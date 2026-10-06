import Testing
import Foundation
@testable import DiskBloomCore

@Suite(.serialized)
final class CloudIntegrationTests {
    let folder: URL
    let bridge: CloudBridge?
    init() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        folder = root.appendingPathComponent(".build/cloud-fixtures/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executables = [root.appendingPathComponent("build/DiskBloom.app/Contents/Resources/rclone").path,
                           "/opt/homebrew/bin/rclone", "/usr/local/bin/rclone"]
        if let executable = executables.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            bridge = CloudBridge(executable: executable, configPath: folder.appendingPathComponent("rclone.conf").path)
            _ = try bridge!.command(["config", "create", "fixture", "local", "--non-interactive"])
        } else { bridge = nil }
    }
    deinit { try? FileManager.default.removeItem(at: folder) }
    func fixture() throws -> ScanSource {
        let data = folder.appendingPathComponent("data/nested")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data(repeating: 12, count: 64).write(to: data.appendingPathComponent("hello.bin"))
        return ScanSource(name: "Fixture", path: "fixture:" + folder.appendingPathComponent("data").path, kind: .cloud)
    }
    @Test func remoteMetadataScanRunsAgainstRealRcloneWithoutNetwork() throws {
        guard let bridge else { return }
        let source = try fixture(); let report = try bridge.scan(source)
        checkEqual(report.root.logicalBytes, 64); checkEqual(report.root.fileCount, 1)
        checkEqual(try bridge.remotes(), ["fixture:"])
        checkTrue(report.nodes.contains { $0.name == "hello.bin" })
    }
    @Test func remoteFileDeletionRejectsChangedMetadata() throws {
        guard let bridge else { return }
        let source = try fixture(); let report = try bridge.scan(source)
        let node = report.nodes.first { $0.name == "hello.bin" }!
        try Data(repeating: 14, count: 80).write(to: folder.appendingPathComponent("data/nested/hello.bin"))
        checkThrows(try bridge.delete(node, source: source))
        checkTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("data/nested/hello.bin").path))
    }
    @Test func remoteFolderDeletionRejectsNewDescendants() throws {
        guard let bridge else { return }
        let source = try fixture(); let report = try bridge.scan(source)
        let node = report.nodes.first { $0.name == "nested" }!
        let item = CollectorItem(source: source, node: node, expectedNodes: report.nodes.filter { report.contains(node.id, descendant: $0.id) })
        try Data([3, 4]).write(to: folder.appendingPathComponent("data/nested/new.bin"))
        checkThrows(try bridge.delete(item))
        checkTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("data/nested/new.bin").path))
    }
    @Test func remoteDeletionIsLimitedToTheReviewedFixture() throws {
        guard let bridge else { return }
        let source = try fixture(); let report = try bridge.scan(source)
        let node = report.nodes.first { $0.name == "hello.bin" }!
        checkThrows(try bridge.delete(report.root, source: source))
        try bridge.delete(node, source: source)
        checkFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("data/nested/hello.bin").path))
        checkTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("rclone.conf").path))
    }
}
