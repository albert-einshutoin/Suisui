import AppKit
import SwiftUI
import SuisuiCore

@MainActor
struct CodexAccountSettingsView: View {
    let executablePath: String?
    @StateObject private var model = CodexAccountSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Codex Account", value: model.statusLabel)
            HStack {
                Button("Check Account") {
                    Task { await model.checkAccount(executablePath: executablePath) }
                }
                .accessibilityIdentifier("settings-codex-check-account")
                Button("Sign in with ChatGPT") {
                    Task { await model.signIn(executablePath: executablePath) }
                }
                .accessibilityIdentifier("settings-codex-sign-in")
                .accessibilityHint("Opens an allowed OpenAI or ChatGPT authentication page in the default browser.")
                Button("Sign Out", role: .destructive) {
                    Task { await model.signOut(executablePath: executablePath) }
                }
                .accessibilityIdentifier("settings-codex-sign-out")
            }
            .disabled(model.isWorking || executablePath == nil)
            if model.isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityIdentifier("codex-account-settings")
    }
}

@MainActor
private final class CodexAccountSettingsViewModel: ObservableObject {
    @Published private(set) var statusLabel = "Not checked"
    @Published private(set) var isWorking = false
    private var activeTransport: CodexAppServerStdioTransport?

    func checkAccount(executablePath: String?) async {
        await withSession(executablePath: executablePath) { account in
            let snapshot = try await account.readAccount(refresh: false)
            self.present(snapshot.readiness)
        }
    }

    func signIn(executablePath: String?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await makeSession(executablePath: executablePath)
            activeTransport = session.transport
            let attempt = try await session.account.startLogin(.chatGPTBrowser)
            guard NSWorkspace.shared.open(attempt.authorizationURL) else {
                throw CodexAccountClientError.unsafeAuthenticationURL
            }
            statusLabel = "Waiting for ChatGPT sign-in"
            let readiness = try await session.account.awaitLogin(id: attempt.id, timeout: 300)
            present(readiness)
            await session.transport.shutdown()
            activeTransport = nil
        } catch {
            statusLabel = userFacingFailure(error)
            if let activeTransport { await activeTransport.shutdown() }
            activeTransport = nil
        }
    }

    func signOut(executablePath: String?) async {
        await withSession(executablePath: executablePath) { account in
            try await account.logout()
            self.present(.signedOut)
        }
    }

    private func withSession(
        executablePath: String?,
        operation: (CodexAppServerAccountClient) async throws -> Void
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await makeSession(executablePath: executablePath)
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

    private func makeSession(executablePath: String?) async throws -> (
        transport: CodexAppServerStdioTransport,
        account: CodexAppServerAccountClient
    ) {
        guard let executablePath else {
            throw CodexAppServerRuntimeConfigurationError.absoluteExecutablePathRequired
        }
        let output = try await ProcessCodexVersionReporter().versionOutput(executablePath: executablePath)
        let runtime = try CodexAppServerRuntimeConfiguration.validate(
            executablePath: executablePath,
            reportedVersion: output
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
        if let transportError = error as? CodexAppServerTransportError,
           case let .remote(code, _) = transportError,
           code == 401 {
            return "Signed out"
        }
        return "Could not connect to Codex"
    }
}
