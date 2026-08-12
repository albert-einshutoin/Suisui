import Foundation
import XCTest
@testable import Suisui

final class AVFoundationAudioRecorderTests: XCTestCase {
    @MainActor
    func testProductionTemporaryRecordingNameUsesSweepCompatibleUUID() {
        let temporaryDirectory = URL(filePath: "/tmp/suisui-recorder-contract", directoryHint: .isDirectory)
        let recorder = AVFoundationAudioRecorder(temporaryDirectory: temporaryDirectory)
        let identifier = UUID(uuidString: "203F38F6-2A70-4699-AD49-23DA594857AA")!

        let url = recorder.temporaryRecordingURL(identifier: identifier)

        XCTAssertEqual(url.deletingLastPathComponent(), temporaryDirectory)
        XCTAssertEqual(
            url.lastPathComponent,
            "suisui-recording-203F38F6-2A70-4699-AD49-23DA594857AA.m4a"
        )
        let parsedIdentifier = url.lastPathComponent
            .dropFirst("suisui-recording-".count)
            .dropLast(".m4a".count)
        XCTAssertEqual(UUID(uuidString: String(parsedIdentifier)), identifier)
    }
}
