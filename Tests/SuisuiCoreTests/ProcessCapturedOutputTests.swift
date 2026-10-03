import Foundation
@testable import SuisuiCore
import XCTest

#if !os(iOS) && !targetEnvironment(macCatalyst)
final class ProcessCapturedOutputTests: XCTestCase {
    func testDrainsBothStreamsBeyondPipeCapacityAndPreservesFailureStatus() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", """
        import os
        import sys
        for _ in range(128):
            os.write(1, b'output\\n' * 1024)
            os.write(2, b'error\\n' * 1024)
        sys.exit(23)
        """]
        let finished = expectation(description: "Both streams drained and process exited")
        DispatchQueue.global().async {
            defer { finished.fulfill() }
            do {
                let result = try ProcessCapturedOutput.run(process)
                XCTAssertEqual(result.standardOutput, Data(String(repeating: "output\n", count: 128 * 1024).utf8))
                XCTAssertEqual(result.standardError, Data(String(repeating: "error\n", count: 128 * 1024).utf8))
                XCTAssertEqual(result.exitCode, 23)
            } catch {
                XCTFail("Process capture failed: \(error)")
            }
        }
        await fulfillment(of: [finished], timeout: 10)
        // A broken reader must fail this test without leaving its child running.
        if process.isRunning { process.terminate() }
    }

    func testLaunchFailurePropagates() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/nonexistent-suisui-test-executable")
        XCTAssertThrowsError(try ProcessCapturedOutput.run(process))
    }
}
#endif
