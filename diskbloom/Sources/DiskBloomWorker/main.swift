import Foundation
import DiskBloomCore

// A one-shot read-only scanner. Privilege is requested by the GUI via macOS;
// the worker never deletes files and accepts no arbitrary shell commands.
do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard [2, 4].contains(arguments.count), arguments[0] == "--scan", arguments[1].hasPrefix("/"),
          arguments.count == 2 || (arguments[2] == "--cancel-marker" && arguments[3].hasPrefix("/")) else {
        throw BloomError.message("Usage: DiskBloomWorker --scan /absolute/folder [--cancel-marker /absolute/marker]")
    }
    let token = CancellationToken()
    var timer: DispatchSourceTimer?
    if arguments.count == 4 {
        let marker = arguments[3]
        guard FileManager.default.fileExists(atPath: marker) else { throw BloomError.cancelled }
        let watcher = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        watcher.schedule(deadline: .now(), repeating: 0.15)
        watcher.setEventHandler { if !FileManager.default.fileExists(atPath: marker) { token.cancel() } }
        watcher.resume(); timer = watcher
    }
    defer { timer?.cancel() }
    let source = ScanSource(name: URL(fileURLWithPath: arguments[1]).lastPathComponent, path: arguments[1])
    let report = try LocalScanner().scan(source, token: token)
    let encoder = JSONEncoder()
    let data = try encoder.encode(report)
    try token.check()
    FileHandle.standardOutput.write(data)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
}
