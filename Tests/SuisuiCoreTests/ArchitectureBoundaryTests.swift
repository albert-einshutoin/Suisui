import Foundation
import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
    func testDomainBoundaryDocumentationDefinesOwnershipAndDependencyDirection() throws {
        let doc = try readPackageFile("docs/architecture/domain-boundaries.md")

        for marker in [
            "# Suisui Domain Boundaries",
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
            "Phase 2: keep Today, Schedule, Catch Up, Done, Inbox, Assistant Queue",
            "The superseded",
            "`ProjectWorkflowViews.swift` owner has been removed",
            "Phase 3: extract app shell/runtime composition"
        ] {
            XCTAssertTrue(doc.contains(marker), "domain boundary documentation must include \(marker)")
        }
    }

    func testCoreAndRuntimeTargetsDoNotImportUIOrPlatformFrameworks() throws {
        let scannedRoots = [
            "Sources/SuisuiCore",
            "Sources/SuisuiExternalConnectors",
            "Sources/SuisuiGoogleCalendarRuntime"
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
            "Core/runtime targets must remain UI-framework-free; move UI/platform concerns to SuisuiApp or adapters."
        )
    }

    func testSwiftUIFeatureViewsDoNotOwnSQLiteStoresOutsideCompositionRoot() throws {
        let allowedOwners: Set<String> = [
            "Sources/SuisuiApp/SuisuiApp.swift"
        ]
        let violations = try swiftSourceFiles(under: "Sources/SuisuiApp")
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
        let violations = try swiftSourceFiles(under: "Sources/SuisuiApp/Views").flatMap { file -> [String] in
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
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let expectedViewFiles: [String: [String]] = [
            "Sources/SuisuiApp/Views/ProjectBoardLaunchRecoveryViews.swift": [
                "struct ProjectBoardLaunchRecoveryView: View",
                "private struct ProjectBoardLaunchRecoveryTaskInspector: View",
                "private struct ProjectDevelopmentAutomationRecoveryView: View"
            ],
            "Sources/SuisuiApp/Views/MenuBarPanel.swift": [
                "struct MenuBarPanel: View",
                "private struct SummaryRow: View"
            ],
            "Sources/SuisuiApp/Views/VoiceCaptureView.swift": [
                "struct VoiceCaptureView: View",
                "private struct VoiceInboxCaptureSavedPanel: View",
                "private struct AssistantQueuePanel: View",
                "private struct ActionPlanPreview: View"
            ],
            "Sources/SuisuiApp/Views/ActionReviewPanel.swift": [
                "struct ActionReviewPanel: View",
                "private struct ExecutionReceiptSummaryView: View",
                "private struct ReviewActionRow: View"
            ],
            "Sources/SuisuiApp/Views/SettingsView.swift": [
                "struct SettingsView: View",
                "enum SettingsTab: String"
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
            XCTAssertFalse(appSource.contains(movedDeclaration), "SuisuiApp.swift must stop owning \(movedDeclaration)")
        }

        for compositionMarker in [
            "WindowGroup(\"Suisui\", id: \"project-board\")",
            "VoiceCaptureWindowRootView()",
            "quickCaptureController: menuBarQuickCaptureController,",
            "sceneCoordinator: projectBoardSceneCoordinator",
            "SettingsView(",
            "AppRuntimeFactory.prepareProjectBoardRuntimeBundle()"
        ] {
            XCTAssertTrue(appSource.contains(compositionMarker), "SuisuiApp.swift must keep runtime composition marker \(compositionMarker)")
        }
        XCTAssertFalse(appSource.contains("private enum AppRuntimeFactory"))
        XCTAssertFalse(appSource.contains("SQLiteConnection("))
        XCTAssertFalse(appSource.contains("GoogleCalendarAppRuntimeFactory."))
        XCTAssertFalse(appSource.contains("ASWebAuthenticationSession("))
        XCTAssertFalse(appSource.contains("ToolRegistry.phase2MVP"))
        XCTAssertFalse(appSource.contains("KeychainSecretStore("))
    }

    func testRuntimeCompositionFactoriesAreSplitFromSuisuiAppShell() throws {
        let appSource = try readPackageFile("Sources/SuisuiApp/SuisuiApp.swift")
        let expectedCompositionFiles: [String: [String]] = [
            "Sources/SuisuiApp/Composition/AppRuntimeFactory.swift": [
                "enum AppRuntimeFactory",
                "static func migratedConnection() throws -> SQLiteConnection",
                "static func makeSecretStore() -> any SecretStore"
            ],
            "Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift": [
                "static func prepareProjectBoardRuntimeBundle() async -> ProjectBoardRuntimeBundle",
                "static func makeProjectBoardViewModel() -> ProjectBoardViewModel",
                "static func makeProjectBoardViewModel(runtime: ProjectBoardRuntimeBundle) -> ProjectBoardViewModel",
                "static func makeLaunchVisibleProjectBoardViewModel() -> ProjectBoardViewModel",
                "makeSettingsBackedGoogleCalendarSyncController"
            ],
            "Sources/SuisuiApp/Composition/RuntimeToolCompositionFactory.swift": [
                "static func makeRuntimeToolRegistry(",
                "static func makeReviewSessionViewModel(plan: ActionPlan) -> ReviewSessionViewModel"
            ],
            "Sources/SuisuiApp/Composition/SettingsRuntimeFactory.swift": [
                "static func makeAppSettingsViewModel(refreshProviderSecretStatusesOnInit: Bool = true) -> AppSettingsViewModel",
                "static func makeExternalMCPSettingsViewModel() -> ExternalMCPSettingsViewModel",
                "static func makeIntegrationPermissionSnapshot() -> PermissionSnapshot"
            ],
            "Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift": [
                "static func makeGoogleCalendarRuntimeSyncStatus() -> GoogleCalendarRuntimeSyncStatus",
                "static func makeGoogleCalendarOAuthConnector() -> (any GoogleCalendarOAuthConnecting)?",
                "GoogleCalendarOAuthAuthenticationSessionController"
            ],
            "Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift": [
                "static func makeVoiceCaptureViewModel() -> VoiceCaptureViewModel",
                "static func makeLLMProvider(settings: AppSettings, secretStore: any SecretStore) -> any LLMProvider",
                "enum AppTextToSpeechRuntimeFactory"
            ],
            "Sources/SuisuiApp/Composition/MenuBarRuntimeFactory.swift": [
                "static func makeMenuBarSummaryController() -> MenuBarSummaryController",
                "static func makeMenuBarQuickCaptureController() -> MenuBarQuickCaptureController"
            ]
        ]

        for (file, markers) in expectedCompositionFiles {
            let source = try readPackageFile(file)
            for marker in markers {
                XCTAssertTrue(source.contains(marker), "\(file) must own runtime composition marker \(marker)")
            }
        }

        for forbiddenMarker in [
            "GoogleCalendarOAuthAuthenticationSessionController",
            "makeRuntimeToolRegistry(",
            "makeLLMProvider(settings:",
            "makeProjectBoardViewModel() -> ProjectBoardViewModel",
            "static func makeExternalMCPSettingsViewModel()"
        ] {
            XCTAssertFalse(appSource.contains(forbiddenMarker), "SuisuiApp.swift must delegate \(forbiddenMarker) to composition files")
        }
    }

    func testProjectWorkflowSurfacesAreSplitIntoOwnedViewFiles() throws {
        let expectedSurfaceFiles = [
            ("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift", "struct TodayWorkflowView"),
            ("Sources/SuisuiApp/Views/ProjectWorkflowCatchUpView.swift", "struct CatchUpWorkflowView"),
            ("Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift", "struct ScheduleWorkflowView"),
            ("Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift", "struct DoneWorkflowView"),
            ("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift", "struct InboxWorkflowView"),
            ("Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift", "struct AssistantQueueWorkflowView")
        ]
        for (path, marker) in expectedSurfaceFiles {
            let source = try readPackageFile(path)
            XCTAssertTrue(source.contains(marker), "\(path) should own \(marker)")
        }

        let sharedSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowSharedViews.swift")
        XCTAssertTrue(sharedSource.contains("struct WorkflowTaskSurface"))
        XCTAssertTrue(sharedSource.contains("struct WorkflowHeader"))
        XCTAssertTrue(sharedSource.contains("struct WorkflowDoneToggle"))
    }

    func testTodayFeaturePublishesOneAggregateStateWithoutObservingBoardAtTheViewRoot() throws {
        let todayViewSource = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift")
        let featureSource = try readPackageFile("Sources/SuisuiCore/App/TodayFeatureViewModel.swift")

        XCTAssertTrue(todayViewSource.contains("@StateObject private var viewModel: TodayFeatureViewModel"))
        XCTAssertFalse(todayViewSource.contains("@ObservedObject private var viewModel: ProjectBoardViewModel"))
        XCTAssertTrue(featureSource.contains("public struct TodayFeatureState: Equatable"))
        XCTAssertEqual(
            featureSource.components(separatedBy: "@Published public private(set)").count - 1,
            1,
            "Today should invalidate SwiftUI once through one aggregate published state"
        )
        XCTAssertTrue(featureSource.contains("applyStateIfChanged"))
        XCTAssertFalse(featureSource.contains(".combineLatest(board.$snapshot)"))
    }

    func testProjectBoardAndSettingsRetainRootOwnershipWhileLeafViewsAreSplit() throws {
        let boardRoot = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
        let inspectors = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardInspectors.swift")
        let details = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift")
        let settingsRoot = try readPackageFile("Sources/SuisuiApp/Views/SettingsView.swift")
        let settingsFeatures = try readPackageFile("Sources/SuisuiApp/Views/SettingsFeatureViews.swift")

        for ownershipMarker in [
            "@StateObject private var viewModel: ProjectBoardViewModel",
            "NavigationSplitView",
            ".inspector(isPresented:",
            ".sheet("
        ] {
            XCTAssertTrue(boardRoot.contains(ownershipMarker), "ProjectBoardView must retain \(ownershipMarker)")
        }
        for movedDeclaration in [
            "struct TaskInspectorView: View",
            "struct ProjectInspectorView: View"
        ] {
            XCTAssertFalse(boardRoot.contains(movedDeclaration))
            XCTAssertTrue(inspectors.contains(movedDeclaration))
        }
        for movedDeclaration in [
            "struct ProjectsPortfolioOverview: View",
            "struct ProjectBoardDetail: View",
            "struct ProjectKanbanBoard: View"
        ] {
            XCTAssertFalse(boardRoot.contains(movedDeclaration))
            XCTAssertTrue(details.contains(movedDeclaration))
        }

        XCTAssertTrue(settingsRoot.contains("@StateObject private var settingsViewModel"))
        XCTAssertTrue(settingsRoot.contains("@State private var selectedTab: SettingsTab"))
        XCTAssertTrue(settingsRoot.contains("TabView(selection: $selectedTab)"))
        for leafType in [
            "struct SettingsOverviewFeatureView: View",
            "struct SettingsAppearanceFeatureView: View",
            "struct SettingsAIFeatureView: View",
            "struct SettingsSyncFeatureView: View",
            "struct SettingsPrivacyFeatureView: View",
            "struct SettingsMCPFeatureView: View"
        ] {
            XCTAssertTrue(settingsFeatures.contains(leafType), "SettingsFeatureViews must own \(leafType)")
        }
        XCTAssertFalse(settingsFeatures.contains("extension SettingsView"))
        XCTAssertFalse(settingsFeatures.contains("context.overviewSettingsTab"))
        XCTAssertFalse(settingsFeatures.contains("context.appearanceSettingsTab"))
        XCTAssertFalse(settingsFeatures.contains("context.aiSettingsTab"))
        XCTAssertFalse(settingsFeatures.contains("context.syncSettingsTab"))
        XCTAssertFalse(settingsFeatures.contains("context.privacySettingsTab"))
        XCTAssertFalse(settingsFeatures.contains("context.mcpSettingsTab"))
        XCTAssertFalse(settingsFeatures.contains("struct SettingsFeatureContext"))
        for rootOnlyRuntimeDependency in [
            "LazyDependencyLoader",
            "LazyObservableObjectLoader",
            "GoogleCalendarOAuthConnecting",
            "GoogleCalendarOAuthDisconnecting",
            "GoogleCalendarListProviding",
            "AppRuntimeFactory"
        ] {
            XCTAssertFalse(
                settingsFeatures.contains(rootOnlyRuntimeDependency),
                "Settings leaf views must not own runtime orchestration through \(rootOnlyRuntimeDependency)"
            )
        }
        for dependencyType in [
            "SettingsOverviewDependencies",
            "SettingsAppearanceDependencies",
            "SettingsAIDependencies",
            "SettingsSyncDependencies",
            "SettingsPrivacyDependencies",
            "SettingsMCPDependencies"
        ] {
            let suffix = try XCTUnwrap(settingsFeatures.range(of: "struct \(dependencyType)")).upperBound
            let declaration = String(settingsFeatures[suffix...].prefix { $0 != "}" })
            for forbidden in [
                "LazyDependencyLoader",
                "LazyObservableObjectLoader",
                "GoogleCalendarOAuthConnecting",
                "GoogleCalendarOAuthDisconnecting",
                "GoogleCalendarListProviding",
                "some View"
            ] {
                XCTAssertFalse(declaration.contains(forbidden), "\(dependencyType) must not expose \(forbidden)")
            }
        }
        for tabBody in [
            "var overviewSettingsTab:",
            "var appearanceSettingsTab:",
            "var aiSettingsTab:",
            "var syncSettingsTab:",
            "var privacySettingsTab:",
            "var mcpSettingsTab:"
        ] {
            XCTAssertFalse(settingsRoot.contains(tabBody))
            XCTAssertFalse(settingsFeatures.contains(tabBody))
        }
        for movedDeclaration in [
            "struct MCPServerSettingsRow: View",
            "struct SelectedAIProviderStatusRow: View",
            "struct ProValueOverviewRow: View"
        ] {
            XCTAssertFalse(settingsRoot.contains(movedDeclaration))
            XCTAssertTrue(settingsFeatures.contains(movedDeclaration))
        }
    }

    func testAutomationApprovalBoundaryKeepsQueueTranslationSeparateFromExecution() throws {
        let factorySource = try readPackageFile("Sources/SuisuiCore/App/AssistantQueueAutomationPlanFactory.swift")
        let coordinatorSource = try readPackageFile("Sources/SuisuiCore/App/AssistantQueueExecutionCoordinator.swift")
        let shellSource = try readPackageFile("Sources/SuisuiCore/App/AssistantQueueExecution.swift")

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
            "id: \"assistant-queue-item:\\(running.id)\"",
            "executedSession = try executor.execute(",
            "session: session",
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

    func testIntegrationCalendarRuntimeUsesSharedIdentifiersWithoutMovingConcreteAdapters() throws {
        let sharedSource = try readPackageFile("Sources/SuisuiCore/App/ExternalIntegrationIdentifiers.swift")
        let calendarHTTPContractSource = try readPackageFile("Sources/SuisuiCore/App/GoogleCalendarHTTPContracts.swift")
        let coreInteropSource = try readPackageFile("Sources/SuisuiCore/App/ExternalTaskInterop.swift")
        let connectorSource = try readPackageFile("Sources/SuisuiExternalConnectors/SaaSConnectors.swift")
        let googleRuntimeSource = try readPackageFile("Sources/SuisuiGoogleCalendarRuntime/GoogleCalendarAppRuntime.swift")
        let appCompositionSource = try readPackageFile("Sources/SuisuiApp/Composition/GoogleCalendarRuntimeCompositionFactory.swift")
        let eventKitAdapterSource = try readPackageFile("Sources/SuisuiApp/Adapters/EventKitToolClients.swift")

        for marker in [
            "public enum ExternalIntegrationIdentifier",
            "public static let googleCalendar = \"google_calendar\"",
            "public enum ExternalAuthorizationScopeIdentifier",
            "public static let googleCalendarEventsWrite = \"https://www.googleapis.com/auth/calendar.events\"",
            "public static let googleCalendarCalendarListReadOnly = \"https://www.googleapis.com/auth/calendar.calendarlist.readonly\"",
            "public static let offlineAccess = \"offline_access\""
        ] {
            XCTAssertTrue(sharedSource.contains(marker), "shared integration identifiers must own \(marker)")
        }

        XCTAssertTrue(coreInteropSource.contains("ExternalAuthorizationScopeIdentifier.googleCalendarEventsWrite"))
        XCTAssertTrue(connectorSource.contains("ExternalAuthorizationScopeIdentifier.googleCalendarEventsWrite"))
        XCTAssertTrue(connectorSource.contains("ExternalAuthorizationScopeIdentifier.offlineAccess"))
        XCTAssertTrue(googleRuntimeSource.contains("ExternalAuthorizationScopeIdentifier.googleCalendarEventsWrite"))
        XCTAssertTrue(googleRuntimeSource.contains("ExternalAuthorizationScopeIdentifier.googleCalendarCalendarListReadOnly"))
        XCTAssertTrue(googleRuntimeSource.contains("ExternalAuthorizationScopeIdentifier.offlineAccess"))
        XCTAssertTrue(googleRuntimeSource.contains("ExternalIntegrationIdentifier.googleCalendar"))

        for marker in [
            "public struct GoogleCalendarHTTPConfiguration",
            "public protocol SynchronousHTTPDataClient",
            "package struct GoogleCalendarEventRequest",
            "package enum GoogleCalendarEventID",
            "package struct GoogleCalendarEventResponse"
        ] {
            XCTAssertTrue(calendarHTTPContractSource.contains(marker), "Core HTTP contracts must own \(marker)")
        }
        XCTAssertTrue(connectorSource.contains("public typealias GoogleCalendarHTTPConfiguration = SuisuiCore.GoogleCalendarHTTPConfiguration"))
        XCTAssertTrue(connectorSource.contains("public typealias SynchronousHTTPDataClient = SuisuiCore.SynchronousHTTPDataClient"))
        XCTAssertTrue(googleRuntimeSource.contains("public typealias GoogleCalendarHTTPConfiguration = SuisuiCore.GoogleCalendarHTTPConfiguration"))
        XCTAssertTrue(googleRuntimeSource.contains("public typealias SynchronousHTTPDataClient = SuisuiCore.SynchronousHTTPDataClient"))
        XCTAssertFalse(connectorSource.contains("private struct GoogleCalendarEventRequest"))
        XCTAssertFalse(googleRuntimeSource.contains("private struct GoogleCalendarEventRequest"))

        XCTAssertEqual(googleRuntimeSource.components(separatedBy: "private func formURLEncoded").count - 1, 0)
        XCTAssertEqual(googleRuntimeSource.components(separatedBy: "GoogleCalendarFormURLEncoder.encode").count - 1, 2)
        XCTAssertTrue(googleRuntimeSource.contains("private enum GoogleCalendarFormURLEncoder"))

        XCTAssertTrue(appCompositionSource.contains("URLSessionSynchronousHTTPDataClient()"))
        XCTAssertTrue(eventKitAdapterSource.contains("import EventKit"))
        XCTAssertFalse(sharedSource.contains("URLSession"))
        XCTAssertFalse(calendarHTTPContractSource.contains("URLSessionSynchronousHTTPDataClient"))
        XCTAssertFalse(calendarHTTPContractSource.contains("URLSession.shared"))
        XCTAssertFalse(sharedSource.contains("EventKit"))
        XCTAssertFalse(calendarHTTPContractSource.contains("EventKit"))
        XCTAssertFalse(sharedSource.contains("KeychainSecretStore"))
        XCTAssertFalse(calendarHTTPContractSource.contains("KeychainSecretStore"))
        XCTAssertFalse(sharedSource.contains("ASWebAuthenticationSession"))
        XCTAssertFalse(calendarHTTPContractSource.contains("ASWebAuthenticationSession"))
    }

    func testSwiftPMTargetSplitEvaluationDefersPackageGraphChurnUntilMeasuredGatesPass() throws {
        let evaluation = try readPackageFile("docs/architecture/swiftpm-target-split-evaluation.md")
        let packageSource = try readPackageFile("Package.swift")
        let boundaryTestSource = try readPackageFile("Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift")

        for marker in [
            "# SwiftPM Target Split Evaluation",
            "Decision: defer new SwiftPM targets.",
            "No target split happens only for style.",
            "## Current Package Graph",
            "## Measurements",
            "Source file count by target",
            "Core folder concentration",
            "Import distribution",
            "Local verification cost",
            "## Candidate Target Assessment",
            "Work Management",
            "Automation Core",
            "Integration Core",
            "App Shell",
            "## Measurement Commands",
            "## Gates Before Any Target Split",
            "import-boundary tests before the package graph change",
            "Release evidence contracts remain current",
            "Runtime smoke remains green",
            "Accessibility identifiers and VoiceOver/manual gates remain stable",
            "Optional connector targets do not become app dependencies",
            "Candidate import-closure tests prove the extracted domain",
            "## Revisit Triggers"
        ] {
            XCTAssertTrue(evaluation.contains(marker), "target split evaluation must include \(marker)")
        }

        for existingTarget in [
            #"name: "SuisuiCore""#,
            #"name: "SuisuiExternalConnectors""#,
            #"name: "SuisuiGoogleCalendarRuntime""#,
            #"name: "Suisui""#,
            #"name: "SuisuiCLI""#
        ] {
            XCTAssertTrue(packageSource.contains(existingTarget), "Package.swift must keep existing target \(existingTarget)")
        }

        for deferredTarget in [
            "SuisuiWorkManagement",
            "SuisuiAutomationCore",
            "SuisuiIntegrationCore",
            "SuisuiAppShell"
        ] {
            XCTAssertFalse(packageSource.contains(deferredTarget), "Package.swift must not add style-only target \(deferredTarget)")
        }

        XCTAssertTrue(boundaryTestSource.contains("testCoreAndRuntimeTargetsDoNotImportUIOrPlatformFrameworks"))
        XCTAssertTrue(boundaryTestSource.contains("testRuntimeAdaptersStayOutOfSwiftUIFeatureViewFiles"))
        XCTAssertTrue(boundaryTestSource.contains("testSwiftUIFeatureViewsDoNotOwnSQLiteStoresOutsideCompositionRoot"))
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
