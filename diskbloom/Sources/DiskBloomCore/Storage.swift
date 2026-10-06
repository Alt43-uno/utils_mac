import Foundation

public struct VolumeCapacity: Codable, Sendable {
    public var total: Int64
    public var free: Int64
    public var available: Int64
    public var used: Int64 { max(0, total - free) }
    public var purgeableEstimate: Int64 { max(0, available - free) }
    public init(total: Int64, free: Int64, available: Int64) { self.total = total; self.free = free; self.available = available }
    public static func read(_ path: String) -> VolumeCapacity? {
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys:
            [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity else { return nil }
        return VolumeCapacity(total: Int64(total), free: Int64(free), available: values.volumeAvailableCapacityForImportantUsage ?? Int64(free))
    }
}

public struct APFSSnapshot: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var purgeable: Bool
    public var isTimeMachine: Bool { name.hasPrefix("com.apple.TimeMachine.") }
}

public enum SnapshotService {
    public static func list(volume: String) throws -> [APFSSnapshot] {
        let data = try CommandRunner.checked("/usr/sbin/diskutil", ["apfs", "listSnapshots", "-plist", volume])
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        return (plist["Snapshots"] as? [[String: Any]] ?? []).compactMap {
            guard let uuid = $0["SnapshotUUID"] as? String, let name = $0["Name"] as? String else { return nil }
            return APFSSnapshot(id: uuid, name: name, purgeable: $0["Purgeable"] as? Bool ?? false)
        }
    }
    public static func volumeInfo(_ path: String) throws -> [String: Any] {
        let data = try CommandRunner.checked("/usr/sbin/diskutil", ["info", "-plist", path])
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }
    public static func otherVolumes(_ path: String) throws -> [(String, Int64)] {
        let info = try volumeInfo(path)
        guard let container = info["APFSContainerReference"] as? String, let current = info["DeviceIdentifier"] as? String else { return [] }
        let data = try CommandRunner.checked("/usr/sbin/diskutil", ["apfs", "list", "-plist", container])
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        let containers = plist["Containers"] as? [[String: Any]] ?? []
        return containers.flatMap { $0["Volumes"] as? [[String: Any]] ?? [] }.compactMap {
            guard let device = $0["DeviceIdentifier"] as? String, device != current else { return nil }
            return ($0["Name"] as? String ?? device, ($0["CapacityInUse"] as? NSNumber)?.int64Value ?? 0)
        }
    }
}

public enum ReportExporter {
    public static func csv(_ report: ScanReport) -> String {
        func quote(_ value: String) -> String {
            // Prevent formulas when a filename is opened by Excel or Numbers.
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = ["path,type,allocated_bytes,logical_bytes,files,restricted,modified"]
        let formatter = ISO8601DateFormatter()
        rows += report.nodes.map { node in
            [quote(node.path), node.isDirectory ? "folder" : "file", String(node.allocatedBytes), String(node.logicalBytes),
             String(node.fileCount), String(node.isRestricted), quote(node.modified.map(formatter.string) ?? "")].joined(separator: ",")
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }
}
