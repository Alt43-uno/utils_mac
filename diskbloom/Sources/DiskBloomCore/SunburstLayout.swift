import Foundation

public struct MapSegment: Identifiable, Sendable {
    public var id: String { "\(nodeID ?? -1):\(depth):\(startAngle)" }
    public var nodeID: Int?
    public var groupedIDs: [Int]
    public var startAngle: Double
    public var endAngle: Double
    public var depth: Int
    public var colorIndex: Int
    public var bytes: Int64
    public var isGroup: Bool { nodeID == nil }
}

public enum SunburstLayout {
    public static func segments(report: ScanReport, rootID: Int, metric: SizeMetric,
                                maxDepth: Int = 7, minimumAngle: Double = 0.009) -> [MapSegment] {
        guard report.nodes.indices.contains(rootID), report.nodes[rootID].bytes(metric) > 0 else { return [] }
        var output: [MapSegment] = []
        func visit(_ id: Int, start: Double, end: Double, depth: Int, color: Int?) {
            guard depth < maxDepth, output.count < 2400 else { return }
            let node = report.nodes[id]
            let children = node.children.sorted { report.nodes[$0].bytes(metric) > report.nodes[$1].bytes(metric) }
            let total = Double(max(1, node.bytes(metric)))
            var cursor = start; var grouped: [Int] = []; var groupBytes: Int64 = 0
            for (index, child) in children.enumerated() {
                let bytes = report.nodes[child].bytes(metric)
                guard bytes > 0 else { continue }
                let angle = (end - start) * Double(bytes) / total
                if angle < minimumAngle || output.count >= 2300 {
                    grouped.append(child); groupBytes += bytes; continue
                }
                let next = min(end, cursor + angle)
                let hue = color ?? index
                output.append(MapSegment(nodeID: child, groupedIDs: [], startAngle: cursor, endAngle: next,
                                         depth: depth, colorIndex: hue, bytes: bytes))
                if report.nodes[child].isDirectory { visit(child, start: cursor, end: next, depth: depth + 1, color: hue) }
                cursor = next
            }
            if !grouped.isEmpty {
                let next = min(end, cursor + (end - start) * Double(groupBytes) / total)
                output.append(MapSegment(nodeID: nil, groupedIDs: grouped, startAngle: cursor, endAngle: next,
                                         depth: depth, colorIndex: color ?? children.count, bytes: groupBytes))
            }
        }
        visit(rootID, start: -.pi / 2, end: .pi * 1.5, depth: 0, color: nil)
        return output
    }
}
