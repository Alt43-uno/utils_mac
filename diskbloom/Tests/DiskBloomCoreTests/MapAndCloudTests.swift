import Testing
@testable import DiskBloomCore

@Suite
final class MapAndCloudTests {
    let source = ScanSource(name: "Cloud", path: "test:", kind: .cloud)
    @Test func testRemoteTreeHandlesMissingDirectoryEntries() throws {
        let report = try CloudBridge.report(source: source, entries: [CloudEntry(path: "a/b/file.mov", size: 100, isDirectory: false), CloudEntry(path: "empty", size: -1, isDirectory: true)])
        checkEqual(report.root.logicalBytes, 100); checkEqual(report.root.fileCount, 1)
        checkEqual(report.nodes.count, 5)
        checkEqual(report.nodes.first { $0.name == "file.mov" }?.path, "test:a/b/file.mov")
    }
    @Test func testRemoteDuplicateIDsCountOnlyOnce() throws {
        let report = try CloudBridge.report(source: source, entries: [CloudEntry(path: "a", size: 500, isDirectory: false, id: "same"), CloudEntry(path: "b", size: 500, isDirectory: false, id: "same"), CloudEntry(path: "c", size: 500, isDirectory: false, id: "different")])
        checkEqual(report.root.logicalBytes, 1000); checkEqual(report.hardLinkDuplicates, 1)
    }
    @Test func testRemotePathTraversalAndDuplicatePathsAreRejected() throws {
        let entries = [CloudEntry(path: "../escape", size: 9000, isDirectory: false), CloudEntry(path: "/absolute", size: 9000, isDirectory: false),
                       CloudEntry(path: "ok", size: 5, isDirectory: false), CloudEntry(path: "ok", size: 5, isDirectory: false)]
        let report = try CloudBridge.report(source: source, entries: entries)
        checkEqual(report.root.logicalBytes, 5); checkEqual(report.nodes.count, 2)
    }
    @Test func testTinySegmentsAreGroupedWithoutLosingBytes() throws {
        var entries = [CloudEntry(path: "big", size: 1_000_000, isDirectory: false)]
        entries += (0..<100).map { CloudEntry(path: "small\($0)", size: 1, isDirectory: false) }
        let report = try CloudBridge.report(source: source, entries: entries)
        let segments = SunburstLayout.segments(report: report, rootID: 0, metric: .logical)
        checkEqual(segments.filter { $0.depth == 0 }.reduce(0) { $0 + $1.bytes }, report.root.logicalBytes)
        checkEqual(segments.first { $0.isGroup }?.groupedIDs.count, 100)
        checkEqual(segments.last!.endAngle, .pi * 1.5, accuracy: 0.00001)
    }
    @Test func testSegmentsRemainWithinParentAngles() throws {
        let report = try CloudBridge.report(source: source, entries: [CloudEntry(path: "a/first", size: 60, isDirectory: false), CloudEntry(path: "a/second", size: 40, isDirectory: false), CloudEntry(path: "b/third", size: 100, isDirectory: false)])
        let segments = SunburstLayout.segments(report: report, rootID: 0, metric: .logical)
        for segment in segments where segment.depth > 0 {
            let id = segment.nodeID!; let parentID = report.nodes[id].parent!
            let parent = segments.first { $0.nodeID == parentID }!
            checkGreaterOrEqual(segment.startAngle, parent.startAngle - 0.00001)
            checkLessOrEqual(segment.endAngle, parent.endAngle + 0.00001)
        }
        checkTrue(segments.allSatisfy { $0.endAngle > $0.startAngle })
    }
    @Test func testSubfolderMapIsFullCircle() throws {
        let report = try CloudBridge.report(source: source, entries: [CloudEntry(path: "a/file", size: 20, isDirectory: false), CloudEntry(path: "b/file", size: 200, isDirectory: false)])
        let a = report.nodes.first { $0.name == "a" }!.id
        let segments = SunburstLayout.segments(report: report, rootID: a, metric: .logical)
        checkEqual(segments.count, 1); checkEqual(segments[0].endAngle - segments[0].startAngle, 2 * .pi, accuracy: 0.000001)
    }
    @Test func testCapacityNeverClaimsNegativePurgeableSpace() {
        let capacity = VolumeCapacity(total: 100, free: 40, available: 30)
        checkEqual(capacity.purgeableEstimate, 0); checkEqual(capacity.used, 60)
    }
}
