import Foundation

#if !os(iOS) && !targetEnvironment(macCatalyst)
struct ProcessCapturedOutput: Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32

    static func run(_ process: Process) throws -> Self {
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()

        let outputCapture = PipeDataCapture()
        let errorCapture = PipeDataCapture()
        let readers = DispatchGroup()
        // Both streams must drain before exit: either can fill its pipe and
        // prevent the child from reaching the exit that the caller awaits.
        DispatchQueue.global().async(group: readers) {
            outputCapture.data = output.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global().async(group: readers) {
            errorCapture.data = error.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        readers.wait()

        return Self(
            standardOutput: outputCapture.data,
            standardError: errorCapture.data,
            exitCode: process.terminationStatus
        )
    }
}

// Each instance has one writer, and its data is read only after the dispatch
// group joins that writer. The two streams use separate instances.
private final class PipeDataCapture: @unchecked Sendable {
    var data = Data()
}
#endif
