import Foundation
import Darwin

public struct CommandOutput { public var data: Data; public var error: String; public var status: Int32 }

public enum CommandRunner {
    /// Separate pipe readers avoid deadlock when a provider writes large stderr output.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 120,
                           token: CancellationToken = CancellationToken()) throws -> CommandOutput {
        try token.check()
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        let errorBox = DataBox(); let group = DispatchGroup()
        try process.run()
        func stop() {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        token.onCancel { stop() }
        let deadline = DispatchWorkItem { stop() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        group.enter()
        DispatchQueue.global().async { errorBox.value = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); group.wait(); deadline.cancel()
        try token.check()
        return CommandOutput(data: data, error: String(data: errorBox.value, encoding: .utf8) ?? "", status: process.terminationStatus)
    }
    public static func checked(_ executable: String, _ arguments: [String], timeout: TimeInterval = 120,
                               token: CancellationToken = CancellationToken()) throws -> Data {
        let result = try run(executable, arguments, timeout: timeout, token: token)
        guard result.status == 0 else {
            let message = result.error.isEmpty ? (String(data: result.data, encoding: .utf8) ?? "Command failed") : result.error
            throw BloomError.message(String(message.prefix(1600)))
        }
        return result.data
    }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    private final class DataBox: @unchecked Sendable { var value = Data() }
}
