import AppKit
import SwiftUI
import SuisuiCore

@MainActor
struct CodexAccountSettingsView: View {
    let approvedExecutable: ApprovedCodexExecutable?
    let onDisconnect: () -> Void
    @StateObject private var model = CodexAccountSettingsViewModel()
    @State private var isPresentingCodexSignOutConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Codex Account", value: model.statusLabel)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button("Check Account") {
                        Task {
                            await model.checkAccount(
                                approvedExecutable: approvedExecutable,
                                onIntegrityMismatch: onDisconnect
                            )
                        }
                    }
                    .accessibilityIdentifier("settings-codex-check-account")
                    Button("Sign in with ChatGPT") {
                        Task {
                            await model.signIn(
                                approvedExecutable: approvedExecutable,
                                onIntegrityMismatch: onDisconnect
                            )
                        }
                    }
                    .accessibilityIdentifier("settings-codex-sign-in")
                    .accessibilityHint("Opens an allowed OpenAI or ChatGPT authentication page in the default browser.")
                }
                HStack {
                    Button("Disconnect from Suisui") {
                        onDisconnect()
                    }
                    .accessibilityIdentifier("settings-codex-disconnect")
                    .accessibilityHint("Stops Suisui from launching Codex without changing the Codex account on this Mac.")
                    Button("Sign out of Codex on this Mac", role: .destructive) {
                        isPresentingCodexSignOutConfirmation = true
                    }
                    .accessibilityIdentifier("settings-codex-sign-out")
                    .disabled(!model.canSignOutChatGPTAccount)
                }
            }
            .disabled(model.isWorking || approvedExecutable == nil)
            if model.isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityIdentifier("codex-account-settings")
        .onChange(of: approvedExecutable) { _, _ in
            Task { await model.resetForExecutableChange() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .suisuiCodexExecutionApprovalDidChange)) { _ in
            Task { await model.resetForExecutableChange() }
        }
        .onDisappear {
            Task { await model.cancelActiveOperation() }
        }
        .confirmationDialog(
            "Sign out of Codex on this Mac?",
            isPresented: $isPresentingCodexSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign out of Codex", role: .destructive) {
                Task {
                    await model.signOut(
                        approvedExecutable: approvedExecutable,
                        onIntegrityMismatch: onDisconnect
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes the Codex-managed ChatGPT login used by the Codex CLI and other local Codex clients. It is not only a Suisui disconnect.")
        }
    }
}

@MainActor
private final class CodexAccountSettingsViewModel: ObservableObject {
    @Published private(set) var statusLabel = "Not checked"
    @Published private(set) var isWorking = false
    @Published private(set) var canSignOutChatGPTAccount = false
    private var activeTransport: CodexAppServerStdioTransport?
    private var activeAccountClient: CodexAppServerAccountClient?
    private var activeLoginID: String?
    private var activeTask: Task<Void, Never>?
    private var operationGeneration = 0
    private var onIntegrityMismatch: (() -> Void)?

    func checkAccount(
        approvedExecutable: ApprovedCodexExecutable?,
        onIntegrityMismatch: @escaping () -> Void
    ) async {
        self.onIntegrityMismatch = onIntegrityMismatch
        await cancelActiveOperation()
        await withSession(approvedExecutable: approvedExecutable) { account in
            let snapshot = try await account.readAccount(refresh: false)
            self.canSignOutChatGPTAccount = snapshot.account?.isChatGPTAccount == true
            self.present(snapshot.readiness)
        }
    }

    func signIn(
        approvedExecutable: ApprovedCodexExecutable?,
        onIntegrityMismatch: @escaping () -> Void
    ) async {
        self.onIntegrityMismatch = onIntegrityMismatch
        await cancelActiveOperation()
        let generation = operationGeneration
        isWorking = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSignIn(
                approvedExecutable: approvedExecutable,
                generation: generation
            )
        }
        activeTask = task
        await task.value
        if operationGeneration == generation {
            activeTask = nil
            isWorking = false
        }
    }

    private func performSignIn(
        approvedExecutable: ApprovedCodexExecutable?,
        generation: Int
    ) async {
        do {
            let session = try await makeSession(
                approvedExecutable: approvedExecutable,
                generation: generation
            )
            let attempt = try await session.account.startLogin(.chatGPTBrowser)
            try ensureCurrentOperation(generation)
            activeLoginID = attempt.id
            guard NSWorkspace.shared.open(attempt.authorizationURL) else {
                throw CodexAccountClientError.unsafeAuthenticationURL
            }
            statusLabel = "Waiting for ChatGPT sign-in"
            let readiness = try await session.account.awaitLogin(id: attempt.id, timeout: 300)
            try ensureCurrentOperation(generation)
            present(readiness)
            // A successful ChatGPT login remains sign-out eligible even when
            // planning readiness is usage-limited.
            canSignOutChatGPTAccount = true
            await session.transport.shutdown()
            activeTransport = nil
            activeAccountClient = nil
            activeLoginID = nil
        } catch is CancellationError {
            if operationGeneration == generation {
                statusLabel = "Not checked"
            }
        } catch {
            invalidateApprovalIfNeeded(error)
            if operationGeneration == generation {
                statusLabel = userFacingFailure(error)
            }
            if let activeTransport { await activeTransport.shutdown() }
            activeTransport = nil
            activeAccountClient = nil
            activeLoginID = nil
        }
    }

    func signOut(
        approvedExecutable: ApprovedCodexExecutable?,
        onIntegrityMismatch: @escaping () -> Void
    ) async {
        self.onIntegrityMismatch = onIntegrityMismatch
        await cancelActiveOperation()
        await withSession(approvedExecutable: approvedExecutable) { account in
            try await account.logoutChatGPTAccountOnly()
            self.canSignOutChatGPTAccount = false
            self.present(.signedOut)
        }
    }

    func resetForExecutableChange() async {
        await cancelActiveOperation()
        statusLabel = "Not checked"
        canSignOutChatGPTAccount = false
    }

    func cancelActiveOperation() async {
        operationGeneration &+= 1
        let account = activeAccountClient
        let loginID = activeLoginID
        let transport = activeTransport
        let task = activeTask
        activeLoginID = nil
        activeAccountClient = nil
        activeTransport = nil
        activeTask = nil

        // Cancel at the protocol layer before stopping the process, then mark
        // the local task cancelled so a late completion cannot update the UI.
        if let account, let loginID {
            try? await account.cancelLogin(id: loginID)
        }
        if let transport {
            await transport.shutdown()
        }
        task?.cancel()
        isWorking = false
    }

    private func withSession(
        approvedExecutable: ApprovedCodexExecutable?,
        operation: (CodexAppServerAccountClient) async throws -> Void
    ) async {
        let generation = operationGeneration
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await makeSession(
                approvedExecutable: approvedExecutable,
                generation: generation
            )
            do {
                try await operation(session.account)
                try ensureCurrentOperation(generation)
                await session.transport.shutdown()
            } catch {
                await session.transport.shutdown()
                throw error
            }
            activeTransport = nil
            activeAccountClient = nil
        } catch {
            invalidateApprovalIfNeeded(error)
            if operationGeneration == generation {
                statusLabel = userFacingFailure(error)
            }
        }
    }

    private func ensureCurrentOperation(_ generation: Int) throws {
        guard operationGeneration == generation, !Task.isCancelled else {
            throw CancellationError()
        }
    }

    private func makeSession(
        approvedExecutable: ApprovedCodexExecutable?,
        generation: Int
    ) async throws -> (
        transport: CodexAppServerStdioTransport,
        account: CodexAppServerAccountClient
    ) {
        let runtime = try await CodexApprovedRuntimeResolver().resolve(
            approvedExecutable: approvedExecutable
        )
        let process = ProcessCodexAppServerProcess(
            configuration: CodexAppServerLaunchConfiguration(executablePath: runtime.executablePath),
            approvedExecutable: runtime.approvedExecutable
        )
        let transport = CodexAppServerStdioTransport(process: process)
        let account = CodexAppServerAccountClient(transport: transport)
        // Register the process boundary before initialize so an approval
        // change can shut down even a session still waiting for initialization.
        activeTransport = transport
        activeAccountClient = account
        do {
            try ensureCurrentOperation(generation)
            try await account.initialize(
                clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            )
            try ensureCurrentOperation(generation)
            return (transport, account)
        } catch {
            await transport.shutdown()
            if operationGeneration == generation {
                activeTransport = nil
                activeAccountClient = nil
            }
            throw error
        }
    }

    private func present(_ readiness: CodexAccountReadiness) {
        switch readiness {
        case let .ready(plan): statusLabel = "Connected (\(plan.rawValue))"
        case .signedOut: statusLabel = "Signed out"
        case .authenticating: statusLabel = "Signing in"
        case let .usageLimited(resetAt):
            statusLabel = resetAt.map { "Usage limit reached until \($0.formatted())" } ?? "Usage limit reached"
        case .workspaceDisabled: statusLabel = "Disabled by workspace administrator"
        case .notInstalled: statusLabel = "Codex is not installed"
        case .unsupportedVersion: statusLabel = "Codex update required"
        case .unavailable: statusLabel = "Codex account unavailable"
        }
    }

    private func userFacingFailure(_ error: any Error) -> String {
        if let runtimeError = error as? CodexAppServerRuntimeConfigurationError {
            switch runtimeError {
            case .unverifiedVersion:
                return "Codex version is not yet verified for Suisui"
            case .approvedExecutableChanged, .executionApprovalRequired:
                return "Codex executable changed. Review and approve it again"
            default:
                return "The selected Codex executable is not safe to run"
            }
        }
        if let transportError = error as? CodexAppServerTransportError,
           case let .remote(code, _) = transportError,
           code == 401 {
            return "Signed out"
        }
        return "Could not connect to Codex"
    }

    private func invalidateApprovalIfNeeded(_ error: any Error) {
        guard let runtimeError = error as? CodexAppServerRuntimeConfigurationError,
              runtimeError == .approvedExecutableChanged ||
              runtimeError == .executionApprovalRequired else {
            return
        }
        onIntegrityMismatch?()
    }
}
