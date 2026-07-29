import Foundation
import XCTest

final class VoiceTaskConversationWorkspaceSourceTests: XCTestCase {
    func testGivenEmptySessionWhenRenderThenShowsScopeAndComposer() throws {
        let workspace = try source("Sources/SuisuiApp/Views/VoiceTaskConversationWorkspaceView.swift")
        XCTAssertTrue(workspace.contains("voice-conversation-scope"))
        XCTAssertTrue(workspace.contains("voice-conversation-composer"))
        XCTAssertTrue(workspace.contains("VoiceTaskConversationWorkspaceHeader"))
        XCTAssertTrue(workspace.contains("VoiceTaskConversationComposer"))
        let understanding = try source("Sources/SuisuiApp/Views/VoiceTaskConversationUnderstandingView.swift")
        for identifier in [
            "voice-conversation-scope",
            "voice-conversation-turn-list",
            "voice-conversation-clarification",
            "voice-conversation-resolved-target",
            "voice-conversation-proposal",
            "voice-conversation-fact-candidates",
            "voice-conversation-queue-handoff",
            "voice-conversation-composer"
        ] {
            XCTAssertTrue(workspace.contains(identifier) || understanding.contains(identifier))
        }
        XCTAssertFalse(workspace.contains("rawContent"))
        XCTAssertFalse(understanding.contains("rawContent"))
    }

    func testGivenRecordingStateWhenRenderThenAnnouncesStopAction() throws {
        let presentation = try source("Sources/SuisuiCore/Voice/VoiceTaskConversationWorkspacePresentation.swift")
        let workspace = try source("Sources/SuisuiApp/Views/VoiceTaskConversationWorkspaceView.swift")
        XCTAssertTrue(presentation.contains("case recording"))
        XCTAssertTrue(workspace.contains("Stop recording"))
        XCTAssertTrue(workspace.contains("accessibilityLabel"))
    }

    func testGivenClarificationWhenComposeThenSubmitsAnswerToOrchestrator()
        throws
    {
        let workspace = try source(
            "Sources/SuisuiApp/Views/VoiceTaskConversationWorkspaceView.swift"
        )
        XCTAssertTrue(
            workspace.contains(
                "await viewModel.submitClarificationAnswer(answer)"
            )
        )
        XCTAssertTrue(
            workspace.contains(
                "voice-conversation-submit-clarification"
            )
        )
        XCTAssertTrue(
            workspace.contains("voice-conversation-input")
        )
    }

    func testGivenClarificationWhenRenderThenFocusesSingleQuestion() throws {
        let workspace = try source("Sources/SuisuiApp/Views/VoiceTaskConversationWorkspaceView.swift")
        XCTAssertTrue(workspace.contains("voice-conversation-clarification"))
        XCTAssertTrue(workspace.contains("VoiceTaskConversationClarification"))
        XCTAssertTrue(workspace.contains("clarification.prompt"))
    }

    func testGivenResolvedReferenceWhenRenderThenShowsTargetAndReason() throws {
        let understanding = try source("Sources/SuisuiApp/Views/VoiceTaskConversationUnderstandingView.swift")
        XCTAssertTrue(understanding.contains("voice-conversation-resolved-target"))
        XCTAssertTrue(understanding.contains("presentation.resolvedTarget"))
        XCTAssertTrue(understanding.contains("presentation.resolutionReason"))
    }

    func testGivenFactCandidatesWhenRenderThenShowsStateAndSource() throws {
        let understanding = try source("Sources/SuisuiApp/Views/VoiceTaskConversationUnderstandingView.swift")
        let presentation = try source("Sources/SuisuiCore/Voice/VoiceTaskConversationWorkspacePresentation.swift")
        XCTAssertTrue(understanding.contains("voice-conversation-fact-candidates"))
        XCTAssertTrue(understanding.contains("fact.stateLabel"))
        XCTAssertTrue(understanding.contains("fact.sourceLabel"))
        XCTAssertTrue(presentation.contains("redactedPreview"))
    }

    func testGivenWaitingReviewWhenRenderThenShowsQueueHandoffNotRun() throws {
        let workspace = try source("Sources/SuisuiApp/Views/VoiceTaskConversationWorkspaceView.swift")
        let understanding = try source("Sources/SuisuiApp/Views/VoiceTaskConversationUnderstandingView.swift")
        XCTAssertTrue(understanding.contains("voice-conversation-queue-handoff"))
        XCTAssertTrue(understanding.contains("Open Assistant Queue"))
        XCTAssertFalse(workspace.contains("Run Assistant Queue"))
        XCTAssertFalse(understanding.contains("Run Assistant Queue"))
        XCTAssertFalse(workspace.contains("executeAssistantQueue"))
        XCTAssertFalse(understanding.contains("executeAssistantQueue"))
    }

    func testGivenStoreFailureWhenComposeRuntimeThenShowsBlockedState() throws {
        let presentation = try source("Sources/SuisuiCore/Voice/VoiceTaskConversationWorkspacePresentation.swift")
        let workspace = try source("Sources/SuisuiApp/Views/VoiceTaskConversationWorkspaceView.swift")
        XCTAssertTrue(presentation.contains("case blocked"))
        XCTAssertTrue(workspace.contains("voice-conversation-blocked"))
    }

    func testGivenCompactWidthWhenRenderThenKeepsComposerAndProposalReachable() throws {
        let workspace = try source("Sources/SuisuiApp/Views/VoiceTaskConversationWorkspaceView.swift")
        let understanding = try source("Sources/SuisuiApp/Views/VoiceTaskConversationUnderstandingView.swift")
        XCTAssertTrue(workspace.contains("GeometryReader"))
        XCTAssertTrue(workspace.contains("VoiceTaskConversationWorkspaceLayout"))
        XCTAssertTrue(understanding.contains("DisclosureGroup"))
        XCTAssertTrue(understanding.contains("voice-conversation-proposal"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent(relativePath), encoding: .utf8)
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
