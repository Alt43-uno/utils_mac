import Testing
import Foundation
@testable import DiskBloomCore

@Suite
struct WorkerTests {
    var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    var executable: String { root.appendingPathComponent("build/DiskBloom.app/Contents/MacOS/DiskBloomWorker").path }
    @Test func workerRejectsDeletionCommands() throws {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return }
        let result = try CommandRunner.run(executable, ["--delete", root.path])
        checkEqual(result.status, 1); checkTrue(result.error.contains("Usage:")); checkTrue(result.data.isEmpty)
        checkTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path))
    }
    @Test func cancelledMarkerPreventsWorkerFromScanning() throws {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return }
        let absent = root.appendingPathComponent(".build/absent-marker-" + UUID().uuidString).path
        let result = try CommandRunner.run(executable, ["--scan", root.path, "--cancel-marker", absent])
        checkEqual(result.status, 1); checkTrue(result.error.contains("Cancelled")); checkTrue(result.data.isEmpty)
    }
}
