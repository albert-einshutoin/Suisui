import Foundation
import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
    func testDomainBoundaryDocumentationDefinesOwnershipAndDependencyDirection() throws {
        let doc = try readPackageFile("docs/architecture/domain-boundaries.md")

        for marker in [
            "# SoloPM Domain Boundaries",
            "| Domain | Owns | Current code area | Boundary rule |",
            "Work Management",
            "Planning & Schedule",
            "Workflow Surfaces",
            "App Shell and Runtime Composition",
            "Automation and Approval",
            "Integrations and Sync",
            "Voice and Assistant Intake",
            "Knowledge & Documents",
            "Settings, Entitlements & Billing",
            "Persistence, Security & Audit",
            "Developer Mode and OSS Operations",
            "UI/platform surfaces -> domain view models/snapshots -> domain services/ports -> infrastructure adapters",
            "Known Exceptions",
            "Core presentation view-model exception",
            "SQLite ownership exception",
            "optional connector targets",
            "No broad file moves before boundary tests",
            "Phase 1: split Work Management",
            "Phase 2: split `ProjectWorkflowViews.swift`",
            "Phase 3: extract app shell/runtime composition"
        ] {
            XCTAssertTrue(doc.contains(marker), "domain boundary documentation must include \(marker)")
        }
    }

    func testCoreAndRuntimeTargetsDoNotImportUIOrPlatformFrameworks() throws {
        let scannedRoots = [
            "Sources/SoloPMCore",
            "Sources/SoloPMExternalConnectors",
            "Sources/SoloPMGoogleCalendarRuntime"
        ]
        let violations = try scannedRoots.flatMap { root in
            try swiftSourceFiles(under: root)
        }.flatMap { file -> [String] in
            let source = try readPackageFile(file)
            return forbiddenCoreImportModules.compactMap { module in
                containsImport(module, in: source) ? "\(file): import \(module)" : nil
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "Core/runtime targets must remain UI-framework-free; move UI/platform concerns to SoloPMApp or adapters."
        )
    }

    func testSwiftUIFeatureViewsDoNotOwnSQLiteStoresOutsideCompositionRoot() throws {
        let allowedOwners: Set<String> = [
            "Sources/SoloPMApp/SoloPMApp.swift"
        ]
        let violations = try swiftSourceFiles(under: "Sources/SoloPMApp")
            .filter { try importsSwiftUI(at: $0) }
            .filter { !allowedOwners.contains($0) }
            .flatMap { file -> [String] in
                let source = try readPackageFile(file)
                return forbiddenPersistenceOwnershipPatterns.compactMap { pattern in
                    source.range(of: pattern, options: .regularExpression) == nil ? nil : "\(file): \(pattern)"
                }
            }

        XCTAssertEqual(
            violations,
            [],
            "SwiftUI feature views must receive stores through composition/runtime factories instead of constructing SQLite stores."
        )
    }

    func testRuntimeAdaptersStayOutOfSwiftUIFeatureViewFiles() throws {
        let violations = try swiftSourceFiles(under: "Sources/SoloPMApp/Views").flatMap { file -> [String] in
            let source = try readPackageFile(file)
            return forbiddenRuntimeAdapterPatterns.compactMap { pattern in
                source.range(of: pattern, options: .regularExpression) == nil ? nil : "\(file): \(pattern)"
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "OAuth, network, Keychain, and EventKit runtime work must stay in app composition or adapters, not SwiftUI feature files."
        )
    }

    func testPassiveAppShellViewsAreSplitFromRuntimeCompositionRoot() throws {
        let appSource = try readPackageFile("Sources/SoloPMApp/SoloPMApp.swift")
        let expectedViewFiles: [String: [String]] = [
            "Sources/SoloPMApp/Views/ProjectBoardLaunchRecoveryViews.swift": [
                "struct ProjectBoardLaunchRecoveryView: View",
                "private struct ProjectBoardLaunchRecoveryTaskInspector: View",
                "private struct ProjectDevelopmentAutomationRecoveryView: View"
            ],
            "Sources/SoloPMApp/Views/MenuBarPanel.swift": [
                "struct MenuBarPanel: View",
                "private struct SummaryRow: View"
            ],
            "Sources/SoloPMApp/Views/VoiceCaptureView.swift": [
                "struct VoiceCaptureView: View",
                "private struct VoiceInboxCaptureSavedPanel: View",
                "private struct AssistantQueuePanel: View",
                "private struct ActionPlanPreview: View"
            ],
            "Sources/SoloPMApp/Views/ActionReviewPanel.swift": [
                "struct ActionReviewPanel: View",
                "private struct ExecutionReceiptSummaryView: View",
                "private struct ReviewActionRow: View"
            ],
            "Sources/SoloPMApp/Views/SettingsView.swift": [
                "struct SettingsView: View",
                "enum SettingsTab: String",
                "private struct SettingsStatusOverview: View"
            ]
        ]

        for (file, markers) in expectedViewFiles {
            let source = try readPackageFile(file)
            for marker in markers {
                XCTAssertTrue(source.contains(marker), "\(file) must own \(marker)")
            }
            XCTAssertFalse(source.contains("SQLiteConnection("), "\(file) must not open persistence directly.")
            XCTAssertFalse(source.contains("GoogleCalendarAppRuntimeFactory."), "\(file) must not own Google Calendar runtime factories.")
            XCTAssertFalse(source.contains("ASWebAuthenticationSession("), "\(file) must not own OAuth sessions.")
            XCTAssertFalse(source.contains("EventKit"), "\(file) must not own EventKit adapters.")
            XCTAssertFalse(source.contains("KeychainSecretStore("), "\(file) must not own Keychain stores.")
            XCTAssertFalse(source.contains("ToolRegistry."), "\(file) must not own tool registries.")
            XCTAssertFalse(source.contains("ActionExecutor("), "\(file) must not own action execution.")
        }

        for movedDeclaration in [
            "struct ProjectBoardLaunchRecoveryView: View",
            "struct ProjectDevelopmentAutomationRecoveryView: View",
            "struct MenuBarPanel: View",
            "struct VoiceCaptureView: View",
            "struct ActionReviewPanel: View",
            "struct SettingsView: View"
        ] {
            XCTAssertFalse(appSource.contains(movedDeclaration), "SoloPMApp.swift must stop owning \(movedDeclaration)")
        }

        for compositionMarker in [
            "WindowGroup(\"SoloPM\", id: \"project-board\")",
            "VoiceCaptureView(viewModel: AppRuntimeFactory.makeVoiceCaptureViewModel())",
            "MenuBarPanel(controller: menuBarController, quickCaptureViewModel: menuBarQuickCaptureViewModel)",
            "SettingsView(",
            "private enum AppRuntimeFactory"
        ] {
            XCTAssertTrue(appSource.contains(compositionMarker), "SoloPMApp.swift must keep runtime composition marker \(compositionMarker)")
        }
    }

    func testAutomationApprovalBoundaryKeepsQueueTranslationSeparateFromExecution() throws {
        let factorySource = try readPackageFile("Sources/SoloPMCore/App/AssistantQueueAutomationPlanFactory.swift")
        let coordinatorSource = try readPackageFile("Sources/SoloPMCore/App/AssistantQueueExecutionCoordinator.swift")
        let shellSource = try readPackageFile("Sources/SoloPMCore/App/AssistantQueueExecution.swift")

        XCTAssertTrue(factorySource.contains("enum AssistantQueueExecutableActionPlanFactory"))
        XCTAssertTrue(factorySource.contains("static func actionPlan(for payload: AssistantQueuePayload) -> ActionPlan?"))
        XCTAssertTrue(factorySource.contains("SyncAutomationRequestPayload"))
        XCTAssertTrue(factorySource.contains("requiresApproval: true"))
        for forbiddenExecutionMarker in [
            "ActionExecutor(",
            "ExecutionReceiptStore",
            "queueStore.transition",
            "ManagedAIUsageLedgerStore",
            "ExecutionReceiptFactory.makeAssistantQueueReceipt"
        ] {
            XCTAssertFalse(
                factorySource.contains(forbiddenExecutionMarker),
                "Automation request translation must stay review-only and must not execute or persist: \(forbiddenExecutionMarker)"
            )
        }

        for executionMarker in [
            "public struct AssistantQueueExecutionCoordinator",
            "AssistantQueueStateMachine.startRunning",
            "ReviewSession(plan: plan",
            "executor.execute(session",
            "ExecutionReceiptFactory.makeAssistantQueueReceipt",
            "ManagedAIUsageLedgerStore"
        ] {
            XCTAssertTrue(coordinatorSource.contains(executionMarker), "Execution coordinator must own \(executionMarker)")
        }
        XCTAssertFalse(
            coordinatorSource.contains("private static func arguments(for mutation"),
            "Execution coordinator must not own automation payload-to-action-plan translation."
        )

        XCTAssertTrue(shellSource.contains("public enum AssistantQueueExecutionError"))
        XCTAssertTrue(shellSource.contains("public struct AssistantQueueExecutionResult"))
        XCTAssertFalse(shellSource.contains("SyncAutomationRequestPayload"))
        XCTAssertFalse(shellSource.contains("public struct AssistantQueueExecutionCoordinator"))
    }

    private let forbiddenPersistenceOwnershipPatterns = [
        #"SQLite[A-Za-z0-9_]*Store\s*\("#,
        #"SQLiteConnection\s*\("#,
        #"CoreMigrations"#,
        #"migratedConnection\s*\("#,
        #"KeychainSecretStore\s*\("#,
        #"UserDefaultsAppSettingsStore\s*\("#
    ]

    private let forbiddenRuntimeAdapterPatterns = [
        #"ActionExecutor\s*\("#,
        #"AssistantQueueExecutionCoordinator\s*\("#,
        #"ASWebAuthenticationSession\s*\("#,
        #"EventKit"#,
        #"EKEventStore"#,
        #"GoogleCalendarAppRuntimeFactory\."#,
        #"GoogleCalendarOAuthAuthorizationService\s*\("#,
        #"GoogleCalendarOAuthCredentialStore\s*\("#,
        #"KeychainSecretStore\s*\("#,
        #"ToolRegistry\s*\("#,
        #"ToolRegistry\."#,
        #"URLSession\b"#,
        #"URLSession[A-Za-z0-9_]*HTTPDataClient\s*\("#,
        #"URLSessionSynchronousHTTPDataClient\s*\("#
    ]

    private let forbiddenCoreImportModules = [
        "SwiftUI",
        "AppKit",
        "EventKit",
        "AVFoundation",
        "AuthenticationServices",
        "Sparkle",
        "SwiftTerm"
    ]

    private func importsSwiftUI(at relativePath: String) throws -> Bool {
        containsImport("SwiftUI", in: try readPackageFile(relativePath))
    }

    private func containsImport(_ module: String, in source: String) -> Bool {
        let escapedModule = NSRegularExpression.escapedPattern(for: module)
        let pattern = #"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*import\s+(?:(?:class|struct|enum|protocol|func|var|typealias)\s+)?"# + escapedModule + #"(\.|\s*$)"#

        return source.split(separator: "\n").contains { line in
            line.trimmingCharacters(in: .whitespaces).range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func swiftSourceFiles(under relativePath: String) throws -> [String] {
        let root = packageRoot().appendingPathComponent(relativePath)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ArchitectureBoundaryTestError.missingSourceRoot(relativePath)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else {
                continue
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            files.append(relativePackagePath(for: url))
        }
        guard !files.isEmpty else {
            throw ArchitectureBoundaryTestError.emptySourceRoot(relativePath)
        }
        return files.sorted()
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func relativePackagePath(for url: URL) -> String {
        let rootPath = packageRoot().standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func packageRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private enum ArchitectureBoundaryTestError: Error, CustomStringConvertible {
    case missingSourceRoot(String)
    case emptySourceRoot(String)

    var description: String {
        switch self {
        case .missingSourceRoot(let path):
            return "Architecture boundary source root is missing: \(path)"
        case .emptySourceRoot(let path):
            return "Architecture boundary source root has no Swift files: \(path)"
        }
    }
}
