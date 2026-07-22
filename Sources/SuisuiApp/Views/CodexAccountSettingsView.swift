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
                        Task { await model.checkAccount(approvedExecutable: approvedExecutable) }
                    }
                    .accessibilityIdentifier("settings-codex-check-account")
                    Button("Sign in with ChatGPT") {
                        Task { await model.signIn(approvedExecutable: approvedExecutable) }
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
        .onChange(of: approvedExecutable) { _, _ in model.resetForExecutableChange() }
        .confirmationDialog(
            "Sign out of Codex on this Mac?",
            isPresented: $isPresentingCodexSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign out of Codex", role: .destructive) {
                Task { await model.signOut(approvedExecutable: approvedExecutable) }
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

    func checkAccount(approvedExecutable: ApprovedCodexExecutable?) async {
        await withSession(approvedExecutable: approvedExecutable) { account in
            let snapshot = try await account.readAccount(refresh: false)
            self.canSignOutChatGPTAccount = snapshot.account?.isChatGPTAccount == true
            self.present(snapshot.readiness)
        }
    }

    func signIn(approvedExecutable: ApprovedCodexExecutable?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await makeSession(approvedExecutable: approvedExecutable)
            activeTransport = session.transport
            let attempt = try await session.account.startLogin(.chatGPTBrowser)
            guard NSWorkspace.shared.open(attempt.authorizationURL) else {
                throw CodexAccountClientError.unsafeAuthenticationURL
            }
            statusLabel = "Waiting for ChatGPT sign-in"
            let readiness = try await session.account.awaitLogin(id: attempt.id, timeout: 300)
            present(readiness)
            canSignOutChatGPTAccount = readiness.isReady
            await session.transport.shutdown()
            activeTransport = nil
        } catch {
            statusLabel = userFacingFailure(error)
            if let activeTransport { await activeTransport.shutdown() }
            activeTransport = nil
        }
    }

    func signOut(approvedExecutable: ApprovedCodexExecutable?) async {
        await withSession(approvedExecutable: approvedExecutable) { account in
            try await account.logoutChatGPTAccountOnly()
            self.canSignOutChatGPTAccount = false
            self.present(.signedOut)
        }
    }

    func resetForExecutableChange() {
        statusLabel = "Not checked"
        canSignOutChatGPTAccount = false
    }

    private func withSession(
        approvedExecutable: ApprovedCodexExecutable?,
        operation: (CodexAppServerAccountClient) async throws -> Void
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await makeSession(approvedExecutable: approvedExecutable)
            do {
                try await operation(session.account)
                await session.transport.shutdown()
            } catch {
                await session.transport.shutdown()
                throw error
            }
        } catch {
            statusLabel = userFacingFailure(error)
        }
    }

    private func makeSession(approvedExecutable: ApprovedCodexExecutable?) async throws -> (
        transport: CodexAppServerStdioTransport,
        account: CodexAppServerAccountClient
    ) {
        let runtime = try await CodexApprovedRuntimeResolver().resolve(
            approvedExecutable: approvedExecutable
        )
        let process = ProcessCodexAppServerProcess(
            configuration: CodexAppServerLaunchConfiguration(executablePath: runtime.executablePath)
        )
        let transport = CodexAppServerStdioTransport(process: process)
        let account = CodexAppServerAccountClient(transport: transport)
        try await account.initialize(
            clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        )
        return (transport, account)
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
}
