import SwiftUI

#if canImport(AppKit) && canImport(SwiftTerm)
import AppKit
import SwiftTerm
#endif

struct EmbeddedTerminalPanel: View {
    let workingDirectory: URL
    @Binding var isPresented: Bool

    @State private var isExecutionApproved = false
    @State private var sessionID = UUID()
    @State private var terminalTitle = String(localized: "Local Shell")
    @State private var currentDirectory: String?
    @State private var lastExitLabel: String?

    private var displayDirectory: String {
        currentDirectory?.abbreviatingHomeDirectory ?? workingDirectory.path.abbreviatingHomeDirectory
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if isExecutionApproved {
#if canImport(AppKit) && canImport(SwiftTerm)
                    LocalShellTerminalRepresentable(
                        shellPath: TerminalShellResolver.defaultShellPath(),
                        workingDirectory: workingDirectory,
                        onTitleChange: { terminalTitle = $0.isEmpty ? String(localized: "Local Shell") : $0 },
                        onDirectoryChange: { currentDirectory = $0 },
                        onProcessTerminated: { exitCode in
                            lastExitLabel = TerminalShellResolver.exitLabel(for: exitCode)
                            isExecutionApproved = false
                        }
                    )
                    .id(sessionID)
                    .accessibilityIdentifier("embedded-terminal-view")
#else
                    ContentUnavailableView(
                        "Terminal Unavailable",
                        systemImage: "terminal",
                        description: Text("Embedded terminal requires macOS AppKit support.")
                    )
#endif
                } else {
                    terminalLockedView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 220, idealHeight: 280)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Terminal", systemImage: "terminal")
                .font(.headline)

            VStack(alignment: .leading, spacing: 1) {
                Text(terminalTitle)
                    .font(.caption)
                    .lineLimit(1)
                Text(displayDirectory)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let lastExitLabel, !isExecutionApproved {
                Text(lastExitLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if isExecutionApproved {
                Button {
                    restartSession()
                } label: {
                    Label("Restart Shell", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Restart Shell")
                .accessibilityLabel("Restart Shell")
                .accessibilityIdentifier("embedded-terminal-restart")

                Button {
                    stopSession()
                } label: {
                    Label("Stop Shell", systemImage: "stop.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Stop Shell")
                .accessibilityLabel("Stop Shell")
                .accessibilityIdentifier("embedded-terminal-stop")
            }

            Button {
                closePanel()
            } label: {
                Label("Close Terminal", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [.command])
            .help("Close Terminal")
            .accessibilityLabel("Close Terminal")
            .accessibilityIdentifier("embedded-terminal-close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var terminalLockedView: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Terminal Locked",
                systemImage: "terminal",
                description: Text("Developer Mode is enabled. Local shell execution requires explicit approval and starts in \(displayDirectory).")
            )

            Button { isExecutionApproved = true } label: {
                Label("Approve Local Shell Execution", systemImage: "terminal")
            }
            .buttonStyle(.borderedProminent)
            .help("Approve Local Shell Execution")
            .accessibilityIdentifier("embedded-terminal-approve")
        }
        .padding()
    }

    private func restartSession() {
        lastExitLabel = nil
        sessionID = UUID()
    }

    private func stopSession() {
        lastExitLabel = String(localized: "Stopped")
        isExecutionApproved = false
    }

    private func closePanel() {
        stopSession()
        isPresented = false
    }
}

#if canImport(AppKit) && canImport(SwiftTerm)
private struct LocalShellTerminalRepresentable: NSViewRepresentable {
    let shellPath: String
    let workingDirectory: URL
    let onTitleChange: (String) -> Void
    let onDirectoryChange: (String?) -> Void
    let onProcessTerminated: (Int32?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTitleChange: onTitleChange,
            onDirectoryChange: onDirectoryChange,
            onProcessTerminated: onProcessTerminated
        )
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.autoresizingMask = [.width, .height]
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminal.nativeForegroundColor = .textColor
        terminal.nativeBackgroundColor = .textBackgroundColor
        terminal.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        terminal.caretColor = .controlAccentColor
        terminal.getTerminal().setCursorStyle(.steadyBlock)
        terminal.feed(text: "Suisui Terminal\n")
        terminal.startProcess(
            executable: shellPath,
            args: [],
            environment: TerminalShellResolver.environment(shellPath: shellPath),
            execName: "-\(URL(fileURLWithPath: shellPath).lastPathComponent)",
            currentDirectory: workingDirectory.path
        )
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
    }

    final class Coordinator: LocalProcessTerminalViewDelegate {
        private let onTitleChange: (String) -> Void
        private let onDirectoryChange: (String?) -> Void
        private let onProcessTerminated: (Int32?) -> Void

        init(
            onTitleChange: @escaping (String) -> Void,
            onDirectoryChange: @escaping (String?) -> Void,
            onProcessTerminated: @escaping (Int32?) -> Void
        ) {
            self.onTitleChange = onTitleChange
            self.onDirectoryChange = onDirectoryChange
            self.onProcessTerminated = onProcessTerminated
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            onTitleChange(title)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            guard let directory else {
                onDirectoryChange(nil)
                return
            }

            if let url = URL(string: directory), url.isFileURL {
                onDirectoryChange(url.path)
            } else {
                onDirectoryChange(directory)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            onProcessTerminated(exitCode)
        }
    }
}

private enum TerminalShellResolver {
    static func defaultShellPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let shell = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shell.isEmpty,
           FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }

        if FileManager.default.isExecutableFile(atPath: "/bin/zsh") {
            return "/bin/zsh"
        }

        return "/bin/bash"
    }

    static func environment(shellPath: String) -> [String] {
        var values = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        values.append("PATH=\(inheritedPath)")
        values.append("SHELL=\(shellPath)")
        return values
    }

    static func exitLabel(for exitCode: Int32?) -> String {
        guard let exitCode else {
            return String(localized: "Shell Ended")
        }
        return String(format: String(localized: "Shell Exit %@"), "\(exitCode)")
    }
}
#endif

private extension String {
    var abbreviatingHomeDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard hasPrefix(home) else {
            return self
        }
        return "~" + dropFirst(home.count)
    }
}
