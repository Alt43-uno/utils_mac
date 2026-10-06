import Foundation

public enum DeletionSafety {
    public static func isWithin(_ path: String, directory: String) -> Bool {
        path == directory || path.hasPrefix(directory == "/" ? "/" : directory + "/")
    }
    public static func normalizedSystemPath(_ path: String) -> String {
        let prefix = "/System/Volumes/Data"
        if isWithin(path, directory: prefix) { return String(path.dropFirst(prefix.count)).isEmpty ? "/" : String(path.dropFirst(prefix.count)) }
        return path
    }
    public static func reason(path: String, home: String = NSHomeDirectory()) -> String? {
        let lexical = URL(fileURLWithPath: path).standardizedFileURL.path
        // Resolve the parent, not the leaf: deleting a symlink only deletes that link.
        let url = URL(fileURLWithPath: lexical)
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        for candidate in [lexical, resolved] {
            let p = normalizedSystemPath(candidate)
            let h = normalizedSystemPath(URL(fileURLWithPath: home).resolvingSymlinksInPath().path)
            let protected = ["/System", "/Library", "/bin", "/sbin", "/usr", "/private", "/dev", "/etc", "/var", "/.DocumentRevisions-V100"]
            if protected.contains(where: { isWithin(p, directory: $0) }) { return "system" }
            if ["/", "/Users", "/Applications", "/Volumes", h, h + "/Library"].contains(p) { return "root" }
            if isWithin(h, directory: p) { return "home" }
            // A mounted volume itself must never be removed.
            let resource = try? URL(fileURLWithPath: candidate).resourceValues(forKeys: [.isVolumeKey])
            if resource?.isVolume == true { return "volume" }
        }
        return nil
    }
    public static func validate(_ node: DiskNode, source: ScanSource) throws {
        guard node.id != 0, !node.isRestricted, !node.isMountBoundary else { throw BloomError.message("Protected or unreadable item") }
        guard source.kind == .local else { throw BloomError.message("Remote deletion requires its cloud provider") }
        guard isWithin(node.path, directory: source.path) else { throw BloomError.message("Item is outside the scanned folder") }
        guard reason(path: node.path) == nil else { throw BloomError.message("System files and essential folders are protected") }
        let now = try LocalScanner.identity(at: node.path)
        guard let original = node.identity, now == original else {
            throw BloomError.message("This item changed since the scan. Rescan before removing it: \(node.name)")
        }
    }
}

public struct CollectorItem: Identifiable, Sendable {
    public var id: String { source.id + "|" + node.path }
    public var source: ScanSource
    public var node: DiskNode
    public var expectedNodes: [DiskNode]
    public init(source: ScanSource, node: DiskNode, expectedNodes: [DiskNode] = []) {
        self.source = source; self.node = node; self.expectedNodes = expectedNodes
    }
}

public enum CollectorRules {
    /// A parent replaces its children, preventing double counting and duplicate deletion.
    public static func adding(_ item: CollectorItem, to items: [CollectorItem]) -> [CollectorItem] {
        if items.contains(where: { $0.source.id == item.source.id && DeletionSafety.isWithin(item.node.path, directory: $0.node.path) }) { return items }
        return items.filter { !($0.source.id == item.source.id && DeletionSafety.isWithin($0.node.path, directory: item.node.path)) } + [item]
    }
}

extension DeletionSafety {
    public static func validate(_ item: CollectorItem) throws {
        try validate(item.node, source: item.source)
        if item.node.isDirectory {
            guard !item.expectedNodes.isEmpty, !item.expectedNodes.contains(where: { $0.isRestricted || $0.isMountBoundary }) else {
                throw BloomError.message("Folder contains unreadable items or another mounted volume. Review its contents individually.")
            }
            let fresh = try LocalScanner().scan(ScanSource(name: item.node.name, path: item.node.path))
            guard fresh.restrictedCount == 0, fresh.skippedMounts == 0 else { throw BloomError.message("Folder is no longer fully readable") }
            let originals = Dictionary(uniqueKeysWithValues: item.expectedNodes.map { ($0.path, $0.identity) })
            guard fresh.nodes.count == originals.count,
                  fresh.nodes.allSatisfy({ originals[$0.path] == $0.identity }) else {
                throw BloomError.message("Folder contents changed since the scan. Rescan before removing: \(item.node.name)")
            }
        }
    }
}
