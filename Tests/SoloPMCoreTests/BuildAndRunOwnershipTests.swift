import Foundation
import XCTest

final class BuildAndRunOwnershipTests: XCTestCase {
    func testOnlyInteractiveModesStopExistingDistAppProcesses() throws {
        let script = try readBuildAndRunScript()

        XCTAssertFalse(script.contains("pkill -x \"$APP_NAME\""))
        XCTAssertTrue(script.contains("stop_existing_dist_apps_for_mode()"))
        let modeGate = try functionSource(named: "stop_existing_dist_apps_for_mode", in: script)
        XCTAssertTrue(modeGate.contains("run|--debug|debug|--logs|logs|--telemetry|telemetry)"))
        XCTAssertFalse(modeGate.contains("--build-only"))
        XCTAssertFalse(modeGate.contains("build)"))
        XCTAssertFalse(modeGate.contains("--verify"))
        XCTAssertFalse(modeGate.contains("verify)"))
        XCTAssertEqual(script.components(separatedBy: "stop_existing_dist_apps_for_mode").count - 1, 2)
        XCTAssertTrue(script.contains("terminate_verify_app()"))
        XCTAssertTrue(script.contains("terminate_owned_verify_process"))
    }

    func testInteractiveTerminationRequiresExactBinaryAndStableProcessIdentity() throws {
        let helpers = try ownershipHelpers(from: readBuildAndRunScript())
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-build-ownership-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let harnessURL = fixtureRoot.appendingPathComponent("ownership-harness.sh")
        try ownershipHarness(helpers: helpers).write(to: harnessURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: harnessURL.path)

        let wrongBinarySignals = try runHarness(harnessURL, scenario: "wrong-binary", fixtureRoot: fixtureRoot)
        XCTAssertEqual(wrongBinarySignals, "", "a same-name process with a different executable must not receive a signal")

        let reusedPIDSignals = try runHarness(harnessURL, scenario: "pid-reused", fixtureRoot: fixtureRoot)
        XCTAssertEqual(
            reusedPIDSignals,
            "-TERM 41001\n",
            "a PID reused by a new process must not receive the force-kill intended for the old process"
        )

        let ownedSignals = try runHarness(harnessURL, scenario: "owned", fixtureRoot: fixtureRoot)
        XCTAssertEqual(ownedSignals, "-TERM 41001\n")

        let stubbornOwnedSignals = try runHarness(harnessURL, scenario: "stubborn-owned", fixtureRoot: fixtureRoot)
        XCTAssertEqual(stubbornOwnedSignals, "-TERM 41001\n-KILL 41001\n")
    }

    private func readBuildAndRunScript() throws -> String {
        try String(
            contentsOf: packageRoot().appendingPathComponent("script/build_and_run.sh"),
            encoding: .utf8
        )
    }

    private func ownershipHelpers(from script: String) throws -> String {
        let startMarker = "# BEGIN INTERACTIVE DIST APP OWNERSHIP HELPERS"
        let endMarker = "# END INTERACTIVE DIST APP OWNERSHIP HELPERS"
        let start = try XCTUnwrap(script.range(of: startMarker))
        let end = try XCTUnwrap(script.range(of: endMarker))
        XCTAssertLessThan(start.upperBound, end.lowerBound)
        return String(script[start.upperBound..<end.lowerBound])
    }

    private func functionSource(named name: String, in script: String) throws -> String {
        let start = try XCTUnwrap(script.range(of: "\(name)() {"))
        let tail = script[start.upperBound...]
        let end = try XCTUnwrap(tail.range(of: "\n}"))
        return String(script[start.lowerBound..<end.upperBound])
    }

    private func ownershipHarness(helpers: String) -> String {
        """
        #!/usr/bin/env bash
        set -euo pipefail

        APP_NAME="SoloPM"
        APP_BINARY="/fixture/dist/SoloPM.app/Contents/MacOS/SoloPM"
        scenario="$1"
        signal_log="$2"
        fixture_state="initial"

        \(helpers)

        pgrep() {
          if [[ "$1" == "-x" && "$2" == "$APP_NAME" ]]; then
            printf '%s\n' '41001'
            return 0
          fi
          return 1
        }

        ps() {
          local requested_column="$4"
          case "$scenario:$requested_column:$fixture_state" in
            wrong-binary:command=:*) printf '%s\n' '/usr/bin/OtherApp --fixture' ;;
            wrong-binary:lstart=:*) printf '%s\n' 'Fri Jul 10 12:00:00 2026' ;;
            owned:command=:initial|pid-reused:command=:initial|stubborn-owned:command=:*) printf '%s\n' "$APP_BINARY --fixture" ;;
            owned:lstart=:initial|pid-reused:lstart=:initial|stubborn-owned:lstart=:*) printf '%s\n' 'Fri Jul 10 12:00:00 2026' ;;
            pid-reused:command=:reused) printf '%s\n' "$APP_BINARY --fixture" ;;
            pid-reused:lstart=:reused) printf '%s\n' 'Fri Jul 10 12:00:01 2026' ;;
            owned:*:terminated|stubborn-owned:*:terminated) return 1 ;;
            *) return 1 ;;
          esac
        }

        kill() {
          local signal="$1"
          local pid="$2"
          printf '%s %s\n' "$signal" "$pid" >>"$signal_log"
          case "$scenario:$signal" in
            owned:-TERM) fixture_state="terminated" ;;
            pid-reused:-TERM) fixture_state="reused" ;;
            stubborn-owned:-KILL) fixture_state="terminated" ;;
          esac
        }

        sleep() {
          SECONDS=$((SECONDS + 1))
        }

        terminate_existing_dist_app_for_interactive_mode
        """
    }

    private func runHarness(_ harnessURL: URL, scenario: String, fixtureRoot: URL) throws -> String {
        let signalLogURL = fixtureRoot.appendingPathComponent("\(scenario)-signals.txt")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [harnessURL.path, scenario, signalLogURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let diagnostic = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, diagnostic)
        guard FileManager.default.fileExists(atPath: signalLogURL.path) else {
            return ""
        }
        return try String(contentsOf: signalLogURL, encoding: .utf8)
    }

    private func packageRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
