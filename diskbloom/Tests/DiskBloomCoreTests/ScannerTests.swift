import Testing
import Foundation
import Darwin
@testable import DiskBloomCore

@Suite(.serialized)
final class ScannerTests {
    var directory: URL!
    var source: ScanSource { ScanSource(name: "Test", path: directory.path) }
    init() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        directory = root.appendingPathComponent(".build/test-fixtures/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func write(_ path: String, bytes: Int = 8192) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: bytes).write(to: url)
    }
    func scan() throws -> ScanReport { try LocalScanner().scan(source) }
    func node(_ name: String, _ report: ScanReport) -> DiskNode { report.nodes.first { $0.name == name }! }

    @Test func testNestedAggregationAndUnicode() throws {
        try write("Фото/Лето/фильм.mov", bytes: 17_001); try write("hello.txt", bytes: 201)
        let report = try scan()
        checkEqual(report.root.logicalBytes, 17_202); checkEqual(report.root.fileCount, 2)
        checkEqual(node("Фото", report).logicalBytes, 17_001)
        checkEqual(report.ancestors(of: node("фильм.mov", report).id).map { report.nodes[$0].name }, ["Test", "Фото", "Лето", "фильм.mov"])
        checkTrue(report.nodes.allSatisfy { $0.allocatedBytes >= 0 })
    }
    @Test func testHardLinksCountOnlyOnce() throws {
        try write("original", bytes: 12_345)
        checkEqual(link(directory.appendingPathComponent("original").path, directory.appendingPathComponent("alias").path), 0)
        let report = try scan()
        checkEqual(report.root.fileCount, 2); checkEqual(report.root.logicalBytes, 12_345)
        checkEqual(report.hardLinkDuplicates, 1)
        checkEqual(report.nodes.filter { $0.isHardLinkDuplicate }.count, 1)
    }
    @Test func testSameSizedDistinctFilesAreNotDeduplicated() throws {
        try write("a", bytes: 8192); try write("b", bytes: 8192)
        let report = try scan(); checkEqual(report.root.logicalBytes, 16_384); checkEqual(report.hardLinkDuplicates, 0)
    }
    @Test func testSymbolicLinkCycleAndExternalTargetAreNotTraversed() throws {
        try write("inside/file", bytes: 123)
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("inside/loop").path, withDestinationPath: directory.path)
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("external").path, withDestinationPath: "/Users")
        let report = try scan()
        checkEqual(report.nodes.count, 5); checkEqual(report.nodes.filter { $0.isSymbolicLink }.count, 2)
        checkFalse(node("external", report).isDirectory)
    }
    @Test func testSparseFileUsesAllocatedBlocks() throws {
        let path = directory.appendingPathComponent("sparse").path
        let fd = open(path, O_CREAT | O_WRONLY, 0o600); checkGreaterOrEqual(fd, 0)
        checkEqual(ftruncate(fd, 512_000_000), 0); close(fd)
        let report = try scan(); checkEqual(report.root.logicalBytes, 512_000_000)
        checkLess(report.root.allocatedBytes, 1_000_000)
    }
    @Test func testEmptyFolderIsAValidScan() throws {
        let report = try scan(); checkEqual(report.nodes.count, 1); checkEqual(report.root.logicalBytes, 0)
        checkTrue(SunburstLayout.segments(report: report, rootID: 0, metric: .allocated).isEmpty)
    }
    @Test func testCancellationNeverReturnsAnApparentlyCompleteReport() throws {
        try write("a")
        let token = CancellationToken(); token.cancel()
        checkThrows(try LocalScanner().scan(source, token: token)) { error in
            guard case BloomError.cancelled = error else { return recordFailure("Wrong cancellation error") }
        }
    }
    @Test func testCancellationWhileScanning() throws {
        for index in 0..<20 { try write("\(index)") }
        let token = CancellationToken()
        checkThrows(try LocalScanner().scan(source, token: token) { _ in token.cancel() })
    }
    @Test func testUnreadableDirectoryIsReported() throws {
        guard geteuid() != 0 else { return }
        try write("private/data")
        let path = directory.appendingPathComponent("private").path
        checkEqual(chmod(path, 0), 0); defer { chmod(path, 0o700) }
        let report = try scan(); checkEqual(report.restrictedCount, 1); checkTrue(node("private", report).isRestricted)
        checkEqual(report.root.fileCount, 0)
    }
    @Test func testFileChangesAreRejectedBeforeDeletion() throws {
        try write("safe.txt", bytes: 10)
        let n = node("safe.txt", try scan())
        checkNoThrow(try DeletionSafety.validate(n, source: source))
        try write("safe.txt", bytes: 20)
        checkThrows(try DeletionSafety.validate(n, source: source))
        checkTrue(FileManager.default.fileExists(atPath: n.path))
    }
    @Test func testReplacedFileIsRejectedEvenWhenSizeMatches() throws {
        try write("safe.txt", bytes: 4096); let n = node("safe.txt", try scan())
        try FileManager.default.moveItem(at: directory.appendingPathComponent("safe.txt"), to: directory.appendingPathComponent("old"))
        try write("safe.txt", bytes: 4096)
        checkThrows(try DeletionSafety.validate(n, source: source))
    }
    @Test func testFolderDescendantChangesAreRejected() throws {
        try write("parent/nested/data", bytes: 8192)
        let report = try scan(); let n = node("parent", report)
        let expected = report.nodes.filter { report.contains(n.id, descendant: $0.id) }
        let item = CollectorItem(source: source, node: n, expectedNodes: expected)
        checkNoThrow(try DeletionSafety.validate(item))
        try write("parent/nested/data", bytes: 9000)
        checkThrows(try DeletionSafety.validate(item))
    }
    @Test func testNewDescendantIsRejected() throws {
        try write("parent/nested/data")
        let report = try scan(); let n = node("parent", report)
        let item = CollectorItem(source: source, node: n, expectedNodes: report.nodes.filter { report.contains(n.id, descendant: $0.id) })
        try write("parent/nested/new")
        checkThrows(try DeletionSafety.validate(item))
    }
    @Test func testScannedRootCannotBeRemoved() throws {
        let report = try scan(); checkThrows(try DeletionSafety.validate(report.root, source: source))
    }
    @Test func testSafetyProtectsSystemHomeAndDataFirmlinks() {
        for path in ["/", "/Users", NSHomeDirectory(), "/System/Library", "/Library/Frameworks", "/private/var", "/System/Volumes/Data/Library", "/System/Volumes/Data/usr/bin", NSHomeDirectory() + "/Library"] {
            checkNotNil(DeletionSafety.reason(path: path), path)
        }
        checkNil(DeletionSafety.reason(path: NSHomeDirectory() + "/Downloads/archive.zip"))
        checkFalse(DeletionSafety.isWithin("/scan/Documents2", directory: "/scan/Documents"))
    }
    @Test func testSymlinkParentCannotEscapeSafety() throws {
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("escape").path, withDestinationPath: "/System")
        checkNotNil(DeletionSafety.reason(path: directory.appendingPathComponent("escape/Library").path))
    }
    @Test func testCollectorParentReplacesChildrenWithoutDoubleCounting() throws {
        try write("folder/a"); try write("folder/b")
        let report = try scan(); let a = CollectorItem(source: source, node: node("a", report)); let parent = CollectorItem(source: source, node: node("folder", report))
        var items = CollectorRules.adding(a, to: [])
        items = CollectorRules.adding(parent, to: items); checkEqual(items.count, 1); checkEqual(items[0].node.name, "folder")
        items = CollectorRules.adding(a, to: items); checkEqual(items.count, 1)
    }
    @Test func testLargestFilesStayInsideSelectedSubtree() throws {
        try write("a/small", bytes: 10); try write("b/big", bytes: 100_000)
        let report = try scan(); let a = node("a", report)
        checkEqual(report.largestFiles(in: a.id, metric: .logical).map { report.nodes[$0].name }, ["small"])
    }
    @Test func testJSONRoundTripPreservesFingerprint() throws {
        try write("file"); let report = try scan()
        let decoded = try JSONDecoder().decode(ScanReport.self, from: JSONEncoder().encode(report))
        checkEqual(decoded.root.logicalBytes, report.root.logicalBytes)
        checkEqual(node("file", decoded).identity, node("file", report).identity)
    }
    @Test func testCSVQuotesFilenamesAndPreventsSpreadsheetFormulaExecution() throws {
        try write("=HYPERLINK(\"evil\")", bytes: 1)
        let csv = ReportExporter.csv(try scan())
        checkTrue(csv.contains("\"\"evil\"\"")); checkTrue(csv.contains("allocated_bytes"))
        var report = try scan(); report.nodes[1].path = "=danger"
        checkTrue(ReportExporter.csv(report).contains("\"'=danger\""))
    }
    @Test func testShellQuotesCannotExecuteSubstitutions() throws {
        let text = "a'b $(echo bad) `echo worse` \n end"
        let command = "/usr/bin/printf '%s' " + CommandRunner.shellQuote(text)
        let data = try CommandRunner.checked("/bin/sh", ["-c", command])
        checkEqual(String(data: data, encoding: .utf8), text)
    }
    @Test func testBothProcessPipesAreDrained() throws {
        let data = try CommandRunner.checked("/bin/sh", ["-c", "i=0; while [ $i -lt 2000 ]; do echo output; echo error >&2; i=$((i+1)); done"])
        checkGreater(data.count, 10_000)
    }
    @Test func testSubprocessCancellation() throws {
        let token = CancellationToken()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { token.cancel() }
        let start = Date()
        checkThrows(try CommandRunner.checked("/bin/sleep", ["30"], token: token))
        checkLess(Date().timeIntervalSince(start), 4)
    }
}
