import Foundation
import XCTest
@testable import SuisuiCore

final class VoiceTaskContinuityHarnessTests: XCTestCase {
    func testGivenMissingRuntimeScriptWhenValidateHarnessContractThenFails() throws {
        XCTAssertThrowsError(try VoiceTaskContinuityHarnessContract.validate(scriptAt: packageRoot().appendingPathComponent("script/missing-voice-task-continuity.sh"))) { error in
            XCTAssertEqual(error as? VoiceTaskContinuityHarnessContract.Error, .missingRuntimeScript)
        }
    }

    func testGivenScenarioWithoutPreApprovalAssertionWhenValidateThenFails() throws {
        let source = try runtimeScript().replacingFirst(
            "verify_pre_approval_snapshot\n  run_product_stage \"queue_approval_execution\"",
            with: "run_product_stage \"queue_approval_execution\""
        )

        XCTAssertThrowsError(try VoiceTaskContinuityHarnessContract.validate(source: source)) { error in
            XCTAssertEqual(error as? VoiceTaskContinuityHarnessContract.Error, .missingPreApprovalAssertion)
        }
    }

    func testGivenScenarioWithoutRestartResumeWhenValidateThenFails() throws {
        let source = try runtimeScript().replacingFirst(
            "run_product_stage \"restart\" \"restart\"\n  run_product_stage \"resume\" \"resume\"",
            with: ""
        )

        XCTAssertThrowsError(try VoiceTaskContinuityHarnessContract.validate(source: source)) { error in
            XCTAssertEqual(error as? VoiceTaskContinuityHarnessContract.Error, .missingRestartResume)
        }
    }

    func testGivenEvidenceWithWrongSourceCommitWhenValidateThenFails() throws {
        let source = try runtimeScript().replacingFirst(
            "grep -Fxq \"source_commit=$source_commit\" \"$witness\"",
            with: "grep -Fxq \"source_commit=stale\" \"$witness\""
        )

        XCTAssertThrowsError(try VoiceTaskContinuityHarnessContract.validate(source: source)) { error in
            XCTAssertEqual(error as? VoiceTaskContinuityHarnessContract.Error, .missingSourceCommitBinding)
        }
    }

    func testGivenArtifactWithRawPathOrSecretWhenValidateThenFails() throws {
        let source = try runtimeScript().replacingFirst(
            "contains_rejected_evidence \"$artifact_file\" && fail_stage",
            with: "true # unsafe artifact acceptance"
        )

        XCTAssertThrowsError(try VoiceTaskContinuityHarnessContract.validate(source: source)) { error in
            XCTAssertEqual(error as? VoiceTaskContinuityHarnessContract.Error, .missingEvidenceRejection)
        }
    }

    func testGivenAllRequiredStagesWhenValidateThenPasses() throws {
        XCTAssertNoThrow(try VoiceTaskContinuityHarnessContract.validate(source: runtimeScript()))
    }

    func testGivenBundledDriverWhenValidateThenUsesParentFixturesAndScopedProductRoute() throws {
        let source = try driverScript()

        for fixture in [
            "PROJECT_ID=1833801",
            "TASK_ONE_ID=1833811",
            "TASK_TWO_ID=1833812"
        ] {
            XCTAssertTrue(source.contains(fixture), "missing shared fixture: \(fixture)")
        }
        XCTAssertTrue(source.contains("project-board-voice-command"))
        XCTAssertTrue(source.contains("active_project_id=$PROJECT_ID"))
        XCTAssertTrue(source.contains("active_task_id=$TASK_TWO_ID"))
    }

    func testGivenBundledDriverWhenValidateThenBindsReceiptToConversationActionLink() throws {
        let source = try driverScript()

        XCTAssertTrue(source.contains("execution_receipt_id"))
        XCTAssertTrue(source.contains("assistant_queue_item_id='$queue_item_id'"))
        XCTAssertTrue(source.contains("ExecutionReceipts"))
        XCTAssertTrue(source.contains("receipt_filename="))
        XCTAssertTrue(source.contains("receipt_file_id"))
    }

    func testGivenBundledDriverWhenDrivingAXThenUsesPIDScopedNativeHelpers() throws {
        let source = try driverScript()

        XCTAssertTrue(source.contains("ax_process_matches_identity"))
        XCTAssertTrue(source.contains("ui_evidence_ax_text_input.swift"))
        XCTAssertTrue(source.contains("ui_evidence_ax_press_element.swift"))
        XCTAssertTrue(source.contains("\"$app_pid\""))
        XCTAssertTrue(source.contains("deadline=$((SECONDS + TIMEOUT_SECONDS))"))
        XCTAssertTrue(source.contains("[[ \"$SECONDS\" -lt \"$deadline\" ]] || return 1"))
    }

    private func runtimeScript() throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent("script/check_runtime_voice_task_continuity_smoke.sh"), encoding: .utf8)
    }

    private func driverScript() throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent("script/drive_runtime_voice_task_continuity.sh"), encoding: .utf8)
    }

    private func packageRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        fatalError("Package.swift not found")
    }
}

private enum VoiceTaskContinuityHarnessContract {
    enum Error: Swift.Error, Equatable {
        case missingRuntimeScript
        case missingStage(String)
        case missingPreApprovalAssertion
        case missingRestartResume
        case missingSourceCommitBinding
        case missingEvidenceRejection
        case unsafeFakeProvider
        case nonAtomicArtifact
        case missingFailureLayers
    }

    private static let requiredStages = [
        "isolated_home_sqlite",
        "fixed_fixture_seed",
        "normal_product_route",
        "session_start",
        "task_list",
        "reference_selection",
        "clarification",
        "proposal",
        "pre_approval_snapshot",
        "queue_approval_execution",
        "postcondition_receipt_action_link",
        "restart",
        "resume",
        "redacted_source_bound_artifact"
    ]

    static func validate(scriptAt url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Error.missingRuntimeScript
        }
        try validate(source: String(contentsOf: url, encoding: .utf8))
    }

    static func validate(source: String) throws {
        for stage in requiredStages where !source.contains("\"\(stage)\"") {
            throw Error.missingStage(stage)
        }
        guard source.contains("verify_pre_approval_snapshot\n  run_product_stage \"queue_approval_execution\"") else {
            throw Error.missingPreApprovalAssertion
        }
        guard source.contains("run_product_stage \"restart\" \"restart\"") && source.contains("run_product_stage \"resume\" \"resume\"") else {
            throw Error.missingRestartResume
        }
        guard source.contains("grep -Fxq \"source_commit=$source_commit\" \"$witness\"") && source.contains("artifact_source_commit_mismatch") else {
            throw Error.missingSourceCommitBinding
        }
        guard source.contains("contains_rejected_evidence \"$artifact_file\" && fail_stage") && source.contains("/Users/") && source.contains("sk-") else {
            throw Error.missingEvidenceRejection
        }
        for fact in ["database_mutated", "queue_approved", "receipt_link", "action_link", "session_resumed", "resume_project_scope", "resume_task_scope"] where !source.contains("\"\(fact)\"") {
            throw Error.missingStage("witness fact: \(fact)")
        }
        guard !source.contains("SUISUI_FAKE") && !source.contains("--fake-provider") else {
            throw Error.unsafeFakeProvider
        }
        guard source.contains("mktemp \"$artifact_dir/.voice-task-continuity.XXXXXX\"") && source.contains("mv -f \"$temporary_file\" \"$artifact_file\"") else {
            throw Error.nonAtomicArtifact
        }
        for layer in ["launch", "ax", "plan", "pre-approval", "queue-execution", "postcondition-receipt-action-link", "restart", "resume", "evidence"] where !source.contains("\"\(layer)\"") {
            throw Error.missingFailureLayers
        }
    }
}

private extension String {
    func replacingFirst(_ needle: String, with replacement: String) throws -> String {
        guard let range = range(of: needle) else {
            throw NSError(domain: "VoiceTaskContinuityHarnessTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "fixture anchor missing: \(needle)"])
        }
        return replacingCharacters(in: range, with: replacement)
    }
}
