import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class VisualCaptureStabilityTests: XCTestCase {
    func testCaptureRequiresSeedMetadataAndConvergedConsecutiveRasters() throws {
        let source = try readPackageFile("script/capture_ui_evidence.sh")
        let english = try readPackageFile("Sources/SoloPMApp/Resources/en.lproj/Localizable.strings")
        let japanese = try readPackageFile("Sources/SoloPMApp/Resources/ja.lproj/Localizable.strings")

        XCTAssertTrue(source.contains("task-card-open-details-$unscheduled_task_id=>$planned_label, $medium_label, $no_due_date_label"))
        XCTAssertTrue(source.contains("title = 'Unscheduled schedule draft input'"))
        XCTAssertTrue(source.contains("SELECT substr(due_at, 1, 10) FROM tasks"))
        XCTAssertTrue(source.contains("title = 'Capture launch screenshots'"))
        XCTAssertTrue(source.contains("task-card-open-details-$capture_task_id=>Capture launch screenshots"))
        XCTAssertTrue(source.contains("task-card-open-details-$capture_task_id=>$planned_label, $high_label, $capture_due_date"))
        XCTAssertFalse(source.contains("task-card-metadata-strip-$unscheduled_task_id=>"))
        XCTAssertFalse(source.contains("task-card-metadata-strip-$capture_task_id=>"))
        XCTAssertTrue(source.contains("planned_label=\"予定\""))
        XCTAssertTrue(source.contains("medium_label=\"中\""))
        XCTAssertTrue(source.contains("high_label=\"高\""))
        XCTAssertTrue(source.contains("no_due_date_label=\"期限なし\""))
        XCTAssertTrue(english.contains(#""Medium" = "Medium";"#))
        XCTAssertTrue(english.contains(#""High" = "High";"#))
        XCTAssertTrue(english.contains(#""Planned" = "Planned";"#))
        XCTAssertTrue(english.contains(#""No due date" = "No due date";"#))
        XCTAssertTrue(japanese.contains(#""Planned" = "予定";"#))
        XCTAssertTrue(japanese.contains(#""Medium" = "中";"#))
        XCTAssertTrue(japanese.contains(#""High" = "高";"#))
        XCTAssertTrue(japanese.contains(#""No due date" = "期限なし";"#))
        XCTAssertTrue(source.contains("SOLOPM_UI_EVIDENCE_AX_REQUIRE_IDENTIFIER_SUBTREE=1"))
        XCTAssertTrue(source.contains("SOLOPM_UI_EVIDENCE_AX_REQUIRE_EXACT_IDENTIFIER=1"))
        XCTAssertTrue(source.contains("target_marker_present \"$identifier\" \"$text\" \"$marker_mode\""))
        XCTAssertTrue(source.contains("[[ \"$identifier\" =~ ^task-card-open-details-[0-9]+$ ]]"))
        XCTAssertTrue(source.contains("marker_mode=\"strict-task-card\""))
        XCTAssertTrue(source.contains("marker_mode=\"legacy\""))
        XCTAssertTrue(source.contains("invalid task-card UI evidence identifier"))
        XCTAssertTrue(source.contains("inbox-voice-intake-detail=>Voice intake detail for Scheduled manual capture"))
        XCTAssertTrue(source.contains("SOLOPM_UI_EVIDENCE_AX_IDENTITY_FINGERPRINT=1"))
        XCTAssertTrue(source.contains("VISUAL_RASTER_STABILITY_CHECKER"))
        XCTAssertTrue(source.contains("visual_raster_stability_check.swift"))
        XCTAssertTrue(source.contains("local capture_attempts=3"))
        XCTAssertTrue(source.contains("sleep 0.2"))
        XCTAssertTrue(source.contains("second_window_metadata") && source.contains("== \"$window_metadata\""))
        XCTAssertTrue(source.contains("\"$second_target_frame_fingerprint\" == \"$target_frame_fingerprint\""))
        XCTAssertTrue(source.contains("target_frame_fingerprint"))
        XCTAssertTrue(source.contains("second_target_frame_fingerprint"))
        XCTAssertTrue(source.contains("receipt_ax_target_frame_fields"))
        XCTAssertTrue(source.contains("local AX_TARGET_FRAME_AUDIT_MODE=\"fingerprint\""))
        XCTAssertTrue(source.contains("second_target_frame_fingerprint=\"$(wait_for_stable_ax_target_frame \"$target_identifier\" \"$window_name\")\""))
        XCTAssertTrue(source.contains("--manifest \"$VISUAL_BASELINE_MANIFEST\""))
        XCTAssertTrue(source.contains("--first \"$first_raster\""))
        XCTAssertTrue(source.contains("--second \"$second_raster\""))
        XCTAssertTrue(source.contains("raster did not converge"))

        let captureStart = try XCTUnwrap(source.range(of: "capture_visible_window() {"))
        let captureEnd = try XCTUnwrap(
            source.range(of: "\nopen_mcp_settings_tab() {", range: captureStart.upperBound..<source.endIndex)
        )
        let captureFunction = source[captureStart.lowerBound..<captureEnd.lowerBound]
        XCTAssertFalse(captureFunction.contains("screencapture -x -R"))
        XCTAssertTrue(source.contains("rm -f \"$VISUAL_FIRST_RASTER\""))
    }

    func testAXHelpersCompileAndExposeStrictCaptureIdentityModes() throws {
        let root = packageRoot()
        let fixture = root.appendingPathComponent(".build/visual-ax-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        for helper in ["ui_evidence_ax_marker_check.swift", "ui_evidence_ax_target_frame_audit.swift"] {
            let compile = try run([
                "/usr/bin/swiftc",
                root.appendingPathComponent("script/\(helper)").path,
                "-o", fixture.appendingPathComponent(helper).path
            ])
            XCTAssertEqual(compile.status, 0, "\(helper): \(compile.output)")
        }

        let marker = try readPackageFile("script/ui_evidence_ax_marker_check.swift")
        XCTAssertTrue(marker.contains("SOLOPM_UI_EVIDENCE_AX_REQUIRE_EXACT_IDENTIFIER"))
        XCTAssertTrue(marker.contains("identifier == identifierNeedle"))

        let frame = try readPackageFile("script/ui_evidence_ax_target_frame_audit.swift")
        XCTAssertTrue(frame.contains("SOLOPM_UI_EVIDENCE_AX_IDENTITY_FINGERPRINT"))
        XCTAssertTrue(frame.contains("candidateIdentityFingerprint"))
        XCTAssertTrue(frame.contains("Set(candidates.map(candidateIdentityFingerprint))"))
        XCTAssertTrue(frame.contains("candidateFingerprints.count != 1"))
        XCTAssertTrue(frame.contains("candidates.isEmpty"))
        XCTAssertTrue(frame.contains("Identical visible AX duplicates"))
        XCTAssertTrue(frame.contains("distinct visible candidate fingerprint"))
        XCTAssertTrue(frame.contains("visible AX target"))
        XCTAssertFalse(frame.contains("identityFingerprintEnabled && matches.count != 1"))
        XCTAssertFalse(frame.contains("identityFingerprintEnabled && candidates.count != 1"))
        XCTAssertTrue(frame.contains("if !identityFingerprintEnabled"))
        XCTAssertTrue(frame.contains("print(receiptFields)"))
        XCTAssertTrue(frame.contains("targetFrame.minX"))
        XCTAssertTrue(frame.contains("targetFrame.minY"))
        XCTAssertTrue(frame.contains("visibleFrame.minX"))
        XCTAssertTrue(frame.contains("visibleFrame.minY"))
        XCTAssertTrue(frame.contains("kAXRoleAttribute"))
        XCTAssertTrue(frame.contains("kAXValueAttribute"))
        XCTAssertTrue(frame.contains("replacingOccurrences(of: \"\\t\", with: \" \")"))
        XCTAssertTrue(frame.contains("replacingOccurrences(of: \"\\n\", with: \" \")"))
    }

    func testDestinationPositionFailureRelaunchesFreshOwnedProcessAndFailsClosedWhenExhausted() throws {
        let source = try readPackageFile("script/capture_ui_evidence.sh")
        let functionStart = try XCTUnwrap(source.range(of: "capture_project_board_destination() {"))
        let functionEnd = try XCTUnwrap(
            source.range(of: "\ncapture_voice_command_appearance() {", range: functionStart.upperBound..<source.endIndex)
        )
        let functionSource = String(source[functionStart.lowerBound..<functionEnd.lowerBound])

        XCTAssertTrue(functionSource.contains("! position_window_for_capture \"\" \"$marker_diagnostic\""))
        XCTAssertTrue(functionSource.contains("retrying exact production destination after owned window readiness failure"))
        XCTAssertTrue(functionSource.contains("if ! wait_for_window_capture_metadata > /dev/null 2>>\"$marker_diagnostic\""))
        XCTAssertTrue(functionSource.contains("continue"))
        XCTAssertTrue(functionSource.contains("return 1"))
        let position = try XCTUnwrap(functionSource.range(of: "! position_window_for_capture"))
        let markers = try XCTUnwrap(functionSource.range(of: "wait_for_project_board_destination \"$label\" \"$target_markers\""))
        XCTAssertLessThan(position.lowerBound, markers.lowerBound)

        let succeedsOnFreshPID = try runDestinationFixture(functionSource: functionSource, alwaysFailPosition: false)
        XCTAssertEqual(succeedsOnFreshPID.status, 0, succeedsOnFreshPID.output)
        XCTAssertTrue(succeedsOnFreshPID.output.contains("marker:pid2:identity2"), succeedsOnFreshPID.output)
        XCTAssertTrue(succeedsOnFreshPID.output.contains("scroll:pid2:identity2"), succeedsOnFreshPID.output)
        XCTAssertTrue(succeedsOnFreshPID.output.contains("capture:pid2:identity2"), succeedsOnFreshPID.output)
        XCTAssertFalse(succeedsOnFreshPID.output.contains("marker:pid1"), succeedsOnFreshPID.output)
        XCTAssertFalse(succeedsOnFreshPID.output.contains("capture:pid1"), succeedsOnFreshPID.output)

        let metadataRecoversOnFreshPID = try runDestinationFixture(
            functionSource: functionSource,
            alwaysFailPosition: false,
            failFirstPosition: false,
            failFirstMetadataWait: true
        )
        XCTAssertEqual(metadataRecoversOnFreshPID.status, 0, metadataRecoversOnFreshPID.output)
        XCTAssertTrue(metadataRecoversOnFreshPID.output.contains("diagnostic:metadata:pid1:identity1"), metadataRecoversOnFreshPID.output)
        XCTAssertTrue(metadataRecoversOnFreshPID.output.contains("marker:pid2:identity2"), metadataRecoversOnFreshPID.output)
        XCTAssertTrue(metadataRecoversOnFreshPID.output.contains("scroll:pid2:identity2"), metadataRecoversOnFreshPID.output)
        XCTAssertTrue(metadataRecoversOnFreshPID.output.contains("capture:pid2:identity2"), metadataRecoversOnFreshPID.output)
        XCTAssertFalse(metadataRecoversOnFreshPID.output.contains("marker:pid1"), metadataRecoversOnFreshPID.output)
        XCTAssertFalse(metadataRecoversOnFreshPID.output.contains("capture:pid1"), metadataRecoversOnFreshPID.output)

        let exhausted = try runDestinationFixture(functionSource: functionSource, alwaysFailPosition: true)
        XCTAssertNotEqual(exhausted.status, 0, exhausted.output)
        XCTAssertFalse(exhausted.output.contains("marker:"), exhausted.output)
        XCTAssertFalse(exhausted.output.contains("scroll:"), exhausted.output)
        XCTAssertFalse(exhausted.output.contains("capture:"), exhausted.output)
    }

    func testRasterStabilityHelperAcceptsCompositorNoiseAndRejectsMaterialChange() throws {
        let root = packageRoot()
        let fixture = root.appendingPathComponent(".build/visual-stability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let executable = fixture.appendingPathComponent("visual-raster-stability")
        let compile = try run([
            "/usr/bin/swiftc",
            root.appendingPathComponent("script/visual_raster_stability_check.swift").path,
            "-o", executable.path
        ])
        XCTAssertEqual(compile.status, 0, compile.output)

        let manifest = fixture.appendingPathComponent("manifest.json")
        try #"{"rasterComparison":{"perChannelDeltaThreshold":0.10,"maximumChangedPixelRatio":0.005,"maximumMeanAbsoluteError":0.01}}"#
            .write(to: manifest, atomically: true, encoding: .utf8)
        let first = fixture.appendingPathComponent("first.png")
        let compositorNoise = fixture.appendingPathComponent("noise.png")
        let materialChange = fixture.appendingPathComponent("change.png")
        try writePNG(to: first, changedPixels: 0, channelDelta: 0)
        // Four locally antialiased pixels changing below the per-channel
        // threshold models compositor noise without relaxing the manifest.
        try writePNG(to: compositorNoise, changedPixels: 4, channelDelta: 10)
        try writePNG(to: materialChange, changedPixels: 3, channelDelta: 100)

        let accepted = try run([
            executable.path, "--manifest", manifest.path,
            "--first", first.path, "--second", compositorNoise.path
        ])
        XCTAssertEqual(accepted.status, 0, accepted.output)
        XCTAssertTrue(accepted.output.contains("raster converged"), accepted.output)

        let rejected = try run([
            executable.path, "--manifest", manifest.path,
            "--first", first.path, "--second", materialChange.path
        ])
        XCTAssertEqual(rejected.status, 1, rejected.output)
        XCTAssertTrue(rejected.output.contains("raster did not converge"), rejected.output)
    }

    func testRasterStabilityHelperFailsClosedForInvalidInputs() throws {
        let root = packageRoot()
        let fixture = root.appendingPathComponent(".build/visual-stability-invalid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let executable = fixture.appendingPathComponent("visual-raster-stability")
        let compile = try run([
            "/usr/bin/swiftc",
            root.appendingPathComponent("script/visual_raster_stability_check.swift").path,
            "-o", executable.path
        ])
        XCTAssertEqual(compile.status, 0, compile.output)

        let validManifest = fixture.appendingPathComponent("valid-manifest.json")
        try #"{"rasterComparison":{"perChannelDeltaThreshold":0.10,"maximumChangedPixelRatio":0.005,"maximumMeanAbsoluteError":0.01}}"#
            .write(to: validManifest, atomically: true, encoding: .utf8)
        let invalidManifest = fixture.appendingPathComponent("invalid-manifest.json")
        try #"{"rasterComparison":{"perChannelDeltaThreshold":1.1,"maximumChangedPixelRatio":0.005,"maximumMeanAbsoluteError":0.01}}"#
            .write(to: invalidManifest, atomically: true, encoding: .utf8)
        let first = fixture.appendingPathComponent("first.png")
        let differentDimensions = fixture.appendingPathComponent("different-dimensions.png")
        let malformed = fixture.appendingPathComponent("malformed.png")
        try writePNG(to: first, width: 20, height: 20, changedPixels: 0, channelDelta: 0)
        try writePNG(to: differentDimensions, width: 21, height: 20, changedPixels: 0, channelDelta: 0)
        try Data("not a png".utf8).write(to: malformed)

        let invalidThreshold = try run([
            executable.path, "--manifest", invalidManifest.path,
            "--first", first.path, "--second", first.path
        ])
        XCTAssertEqual(invalidThreshold.status, 2, invalidThreshold.output)
        XCTAssertTrue(invalidThreshold.output.contains("must be finite and within 0...1"), invalidThreshold.output)

        let mismatchedDimensions = try run([
            executable.path, "--manifest", validManifest.path,
            "--first", first.path, "--second", differentDimensions.path
        ])
        XCTAssertEqual(mismatchedDimensions.status, 1, mismatchedDimensions.output)
        XCTAssertTrue(mismatchedDimensions.output.contains("dimensions differ"), mismatchedDimensions.output)

        let malformedPNG = try run([
            executable.path, "--manifest", validManifest.path,
            "--first", first.path, "--second", malformed.path
        ])
        XCTAssertEqual(malformedPNG.status, 2, malformedPNG.output)
        XCTAssertTrue(malformedPNG.output.contains("could not decode"), malformedPNG.output)
    }

    private func writePNG(
        to url: URL,
        width: Int = 20,
        height: Int = 20,
        changedPixels: Int,
        channelDelta: UInt8
    ) throws {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            let value: UInt8 = pixel < changedPixels ? 120 &+ channelDelta : 120
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
            pixels[offset + 3] = 255
        }
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private func runDestinationFixture(
        functionSource: String,
        alwaysFailPosition: Bool,
        failFirstPosition: Bool = true,
        failFirstMetadataWait: Bool = false
    ) throws -> (status: Int32, output: String) {
        let positionBody: String
        if alwaysFailPosition {
            positionBody = #"readiness_failure=position; echo "position-failed:$EVIDENCE_APP_PID" >&2; return 1"#
        } else if failFirstPosition {
            positionBody = #"position_attempts=$((position_attempts + 1)); if [[ "$position_attempts" -eq 1 ]]; then readiness_failure=position; echo "position-failed:$EVIDENCE_APP_PID" >&2; return 1; fi"#
        } else {
            positionBody = ":"
        }
        let metadataFailureEnabled = failFirstMetadataWait ? "1" : "0"
        let fixture = """
        set -euo pipefail
        \(functionSource)
        EVIDENCE_ROUTE_ATTEMPTS=2
        EVIDENCE_TMPDIR="${TMPDIR:-/tmp}"
        APPEARANCE_OVERRIDE=""
        PROJECT_BOARD_SELECTION_OVERRIDE=""
        PROJECT_BOARD_SELECTED_TASK_OVERRIDE=""
        SETTINGS_WINDOW_OVERRIDE=""
        SETTINGS_TAB_OVERRIDE=""
        VOICE_COMMAND_WINDOW_OVERRIDE=""
        EVIDENCE_APP_PID=""
        EVIDENCE_APP_IDENTITY=""
        launch_count=0
        position_attempts=0
        metadata_attempts=0
        readiness_failure=none
        stop_evidence_app() { :; }
        write_appearance_preference() { :; }
        write_app_preference() { :; }
        open_evidence_app() { launch_count=$((launch_count + 1)); EVIDENCE_APP_PID="pid$launch_count"; EVIDENCE_APP_IDENTITY="identity$launch_count"; }
        wait_for_process() { :; }
        activate_evidence_app() { :; }
        sleep() { :; }
        wait_for_window_capture_metadata() { metadata_attempts=$((metadata_attempts + 1)); if [[ "\(metadataFailureEnabled)" == "1" && "$metadata_attempts" -eq 1 ]]; then readiness_failure=metadata; echo "metadata-failed:$EVIDENCE_APP_PID:$EVIDENCE_APP_IDENTITY" >&2; return 1; fi; printf '1 0 0 1024 724\\n'; }
        position_window_for_capture() { \(positionBody); }
        wait_for_project_board_destination() { echo "marker:$EVIDENCE_APP_PID:$EVIDENCE_APP_IDENTITY"; }
        emit_evidence_app_diagnostic() { echo "diagnostic:$readiness_failure:$EVIDENCE_APP_PID:$EVIDENCE_APP_IDENTITY"; }
        scroll_ax_target_into_view() { echo "scroll:$EVIDENCE_APP_PID:$EVIDENCE_APP_IDENTITY"; }
        capture_visible_window() { echo "capture:$EVIDENCE_APP_PID:$EVIDENCE_APP_IDENTITY"; }
        capture_project_board_destination light schedule /tmp/output.png fixture 'target=>ready' '' '' target
        """
        return try run(["/bin/bash", "-c", fixture])
    }

    private func readPackageFile(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
