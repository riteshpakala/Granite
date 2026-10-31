#if os(macOS)
import Foundation

/// A command an installer runs (git, the Swift toolchain): its output read line by line as it comes, and kept.
struct AgentCommand {
    struct Result { let status: Int32; let output: String }

    /// Runs `arguments` through `/usr/bin/env` in `directory`, saying each line to `line`.
    static func run(_ arguments: [String], in directory: URL, line: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // A host under a test runner carries its loader's paths; a build must not inherit them.
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let kept = Kept()
        let reading = pipe.fileHandleForReading
        try process.run()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
                Thread {
                    var buffer = Data()
                    while true {
                        let chunk = reading.availableData
                        if chunk.isEmpty { break }
                        buffer.append(chunk)
                        while let end = buffer.firstIndex(of: 0x0A) {
                            let text = String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self)
                            buffer = Data(buffer[buffer.index(after: end)...])
                            kept.add(text)
                            line(text)
                        }
                    }
                    if !buffer.isEmpty { let text = String(decoding: buffer, as: UTF8.self); kept.add(text); line(text) }
                    process.waitUntilExit()
                    continuation.resume(returning: Result(status: process.terminationStatus, output: kept.text))
                }.start()
            }
        } onCancel: {
            process.terminate()
        }
    }

    private final class Kept: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var text: String { lock.withLock { lines.joined(separator: "\n") } }
    }
}
#endif
