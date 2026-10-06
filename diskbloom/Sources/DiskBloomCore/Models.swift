import Foundation

public enum SourceKind: String, Codable, Sendable { case local, cloud }

public struct ScanSource: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(kind.rawValue):\(path)" }
    public var name: String
    public var path: String
    public var kind: SourceKind
    public var isVolume: Bool
    public init(name: String, path: String, kind: SourceKind = .local, isVolume: Bool = false) {
        self.name = name; self.path = path; self.kind = kind; self.isVolume = isVolume
    }
}

public struct FileIdentity: Codable, Equatable, Sendable {
    public var device: Int32
    public var inode: UInt64
    public var modificationSeconds: Int64
    public var modificationNanos: Int64
    public var logicalSize: Int64
    public var mode: UInt16
    public init(device: Int32, inode: UInt64, modificationSeconds: Int64,
                modificationNanos: Int64, logicalSize: Int64, mode: UInt16) {
        self.device = device; self.inode = inode; self.modificationSeconds = modificationSeconds
        self.modificationNanos = modificationNanos; self.logicalSize = logicalSize; self.mode = mode
    }
}

public struct DiskNode: Identifiable, Codable, Sendable {
    public var id: Int
    public var parent: Int?
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var isSymbolicLink = false
    public var isRestricted = false
    public var isMountBoundary = false
    public var isHardLinkDuplicate = false
    public var isOffline = false
    public var allocatedBytes: Int64 = 0
    public var logicalBytes: Int64 = 0
    public var fileCount: Int = 0
    public var modified: Date?
    public var identity: FileIdentity?
    public var cloudObjectID: String?
    public var children: [Int] = []
    public init(id: Int, parent: Int?, name: String, path: String, isDirectory: Bool) {
        self.id = id; self.parent = parent; self.name = name; self.path = path; self.isDirectory = isDirectory
    }
    public func bytes(_ metric: SizeMetric) -> Int64 { metric == .allocated ? allocatedBytes : logicalBytes }
}

public enum SizeMetric: String, CaseIterable, Codable, Sendable { case allocated, logical }

public struct ScanProgress: Sendable {
    public var files: Int
    public var bytes: Int64
    public var path: String
    public var elapsed: TimeInterval
    public init(files: Int, bytes: Int64, path: String, elapsed: TimeInterval) {
        self.files = files; self.bytes = bytes; self.path = path; self.elapsed = elapsed
    }
}

public struct ScanReport: Codable, Sendable {
    public var source: ScanSource
    public var nodes: [DiskNode]
    public var startedAt: Date
    public var duration: TimeInterval
    public var restrictedCount: Int
    public var skippedMounts: Int
    public var hardLinkDuplicates: Int
    public var isAdministrator: Bool
    public var root: DiskNode { nodes[0] }
    public init(source: ScanSource, nodes: [DiskNode], startedAt: Date = Date(), duration: TimeInterval = 0,
                restrictedCount: Int = 0, skippedMounts: Int = 0, hardLinkDuplicates: Int = 0, isAdministrator: Bool = false) {
        self.source = source; self.nodes = nodes; self.startedAt = startedAt; self.duration = duration
        self.restrictedCount = restrictedCount; self.skippedMounts = skippedMounts
        self.hardLinkDuplicates = hardLinkDuplicates; self.isAdministrator = isAdministrator
    }
    public func ancestors(of id: Int) -> [Int] {
        var result: [Int] = []; var current: Int? = id
        while let index = current, nodes.indices.contains(index) {
            result.append(index); current = nodes[index].parent
        }
        return result.reversed()
    }
    public func contains(_ ancestor: Int, descendant: Int) -> Bool {
        var current: Int? = descendant
        while let index = current, nodes.indices.contains(index) {
            if index == ancestor { return true }; current = nodes[index].parent
        }
        return false
    }
    public func largestFiles(in rootID: Int, metric: SizeMetric, limit: Int = 200) -> [Int] {
        var stack = [rootID]; var ids: [Int] = []
        while let id = stack.popLast() {
            let node = nodes[id]
            if node.isDirectory { stack.append(contentsOf: node.children) }
            else if node.bytes(metric) > 0 { ids.append(id) }
        }
        return Array(ids.sorted { nodes[$0].bytes(metric) > nodes[$1].bytes(metric) }.prefix(limit))
    }
}

public enum BloomError: LocalizedError {
    case cancelled, message(String)
    public var errorDescription: String? {
        switch self { case .cancelled: return "Cancelled"; case .message(let text): return text }
    }
}

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() {
        lock.lock(); cancelled = true; let callbacks = handlers; handlers = []; lock.unlock()
        callbacks.forEach { $0() }
    }
    public func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled { lock.unlock(); handler() } else { handlers.append(handler); lock.unlock() }
    }
    public func check() throws { if isCancelled { throw BloomError.cancelled } }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .decimal)
    }
    public static func parts(_ bytes: Int64) -> (String, String) {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(max(0, bytes)); var unit = 0
        while value >= 1000 && unit < units.count - 1 { value /= 1000; unit += 1 }
        let formatter = NumberFormatter(); formatter.maximumFractionDigits = value >= 100 || unit == 0 ? 0 : 1
        return (formatter.string(from: NSNumber(value: value)) ?? "0", units[unit])
    }
}
