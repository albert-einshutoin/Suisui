import AppKit
import Foundation

@main
struct MacOSAppLauncher {
    static func main() async {
        guard CommandLine.arguments.count == 8 else {
            fputs(
                "usage: launch_macos_app <bundle> <path> <home> <cfixed-home> <tmpdir> <database> <destination>\n",
                stderr
            )
            exit(2)
        }

        let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["-ApplePersistenceIgnoreState", "YES"]
        configuration.environment = [
            "PATH": CommandLine.arguments[2],
            "HOME": CommandLine.arguments[3],
            "CFFIXED_USER_HOME": CommandLine.arguments[4],
            "TMPDIR": CommandLine.arguments[5],
            "SUISUI_DATABASE_PATH": CommandLine.arguments[6],
            "SUISUI_DISABLE_KEYCHAIN_SECRET_STORE": "1",
            "SUISUI_PROJECT_BOARD_SELECTED_DESTINATION": CommandLine.arguments[7]
        ]

        do {
            // NSWorkspace both honors the app-bundle launch lifecycle and
            // returns the exact new instance, so evidence never attaches to a
            // developer-owned Suisui process with the same bundle identifier.
            let runningApplication = try await NSWorkspace.shared.openApplication(
                at: bundleURL,
                configuration: configuration
            )
            print(runningApplication.processIdentifier)
        } catch {
            fputs("failed to launch \(bundleURL.path): \(error)\n", stderr)
            exit(1)
        }
    }
}
