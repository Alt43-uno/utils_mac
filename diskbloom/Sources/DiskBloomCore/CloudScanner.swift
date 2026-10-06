import Foundation

public struct CloudEntry: Codable, Sendable {
    public var Path: String
    public var Name: String
    public var Size: Int64
    public var IsDir: Bool
    public var ModTime: String?
    public var ID: String?
    public init(path: String, size: Int64, isDirectory: Bool, id: String? = nil) {
        Path = path; Name = (path as NSString).lastPathComponent; Size = size; IsDir = isDirectory; ID = id
    }
}

public struct CloudBridge: Sendable {
    public let executable: String
    public let configPath: String
    public init(executable: String, configPath: String) { self.executable = executable; self.configPath = configPath }
    public func command(_ arguments: [String], token: CancellationToken = CancellationToken(), timeout: TimeInterval = 120) throws -> Data {
        try CommandRunner.checked(executable, ["--config", configPath, "--log-level", "ERROR"] + arguments,
                                  timeout: timeout, token: token)
    }
    public func remotes() throws -> [String] {
        let data = try command(["listremotes"])
        return (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init).filter { $0.hasSuffix(":") }
    }
    public func scan(_ source: ScanSource, token: CancellationToken = CancellationToken(),
                     progress: @escaping (ScanProgress) -> Void = { _ in }) throws -> ScanReport {
        let started = Date()
        progress(ScanProgress(files: 0, bytes: 0, path: source.path, elapsed: 0))
        let data = try command(["lsjson", source.path, "--recursive", "--fast-list", "--no-mimetype"], token: token, timeout: 3600)
        try token.check()
        let entries = try JSONDecoder().decode([CloudEntry].self, from: data)
        var report = try Self.report(source: source, entries: entries, token: token)
        report.startedAt = started; report.duration = Date().timeIntervalSince(started)
        progress(ScanProgress(files: report.root.fileCount, bytes: report.root.logicalBytes, path: source.path, elapsed: report.duration))
        return report
    }
    public static func report(source: ScanSource, entries: [CloudEntry], token: CancellationToken = CancellationToken()) throws -> ScanReport {
        guard source.kind == .cloud, source.path.contains(":"), !source.path.hasPrefix(":") else { throw BloomError.message("Invalid cloud source") }
        var nodes = [DiskNode(id: 0, parent: nil, name: source.name, path: source.path, isDirectory: true)]
        var directories: [String: Int] = ["": 0]; var seen: Set<String> = []; var paths: Set<String> = []; var duplicates = 0
        func directory(_ path: String) -> Int {
            if let id = directories[path] { return id }
            let parentPath = (path as NSString).deletingLastPathComponent
            let parent = directory(parentPath == "." ? "" : parentPath)
            let id = nodes.count
            nodes.append(DiskNode(id: id, parent: parent, name: (path as NSString).lastPathComponent,
                                  path: remotePath(source.path, path), isDirectory: true))
            nodes[parent].children.append(id); directories[path] = id; return id
        }
        for entry in entries {
            try token.check()
            let parts = entry.Path.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.Path.isEmpty, !entry.Path.hasPrefix("/"), !parts.contains(".."), !parts.contains("."),
                  !parts.contains(""), paths.insert(entry.Path).inserted else { continue }
            if entry.IsDir { _ = directory(entry.Path); continue }
            let parentPath = (entry.Path as NSString).deletingLastPathComponent
            let parent = directory(parentPath == "." ? "" : parentPath)
            let id = nodes.count
            var node = DiskNode(id: id, parent: parent, name: entry.Name, path: remotePath(source.path, entry.Path), isDirectory: false)
            node.cloudObjectID = entry.ID
            if let cloudID = entry.ID, !cloudID.isEmpty, !seen.insert(cloudID).inserted {
                node.isHardLinkDuplicate = true; duplicates += 1
            } else { node.logicalBytes = max(0, entry.Size); node.allocatedBytes = node.logicalBytes }
            node.fileCount = 1
            if let date = entry.ModTime {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                node.modified = formatter.date(from: date) ?? ISO8601DateFormatter().date(from: date)
            }
            nodes.append(node); nodes[parent].children.append(id)
        }
        LocalScanner.aggregate(&nodes)
        return ScanReport(source: source, nodes: nodes, hardLinkDuplicates: duplicates)
    }
    public static func remotePath(_ root: String, _ relative: String) -> String {
        root + ((root.hasSuffix(":") || root.hasSuffix("/")) ? "" : "/") + relative
    }
    public func delete(_ node: DiskNode, source: ScanSource, token: CancellationToken = CancellationToken()) throws {
        guard source.kind == .cloud, node.id != 0,
              node.path.hasPrefix(source.path + (source.path.hasSuffix(":") ? "" : "/")),
              node.path != source.path else { throw BloomError.message("Cannot delete cloud root") }
        // Fetch current metadata before deletion; never silently delete a replacement file.
        let data = try command(["lsjson", node.path, "--stat"], token: token)
        let current = try JSONDecoder().decode(CloudEntry.self, from: data)
        guard current.IsDir == node.isDirectory,
              node.isDirectory || current.Size == node.logicalBytes,
              node.cloudObjectID == nil || current.ID == node.cloudObjectID else { throw BloomError.message("Cloud item changed. Rescan first.") }
        if !node.isDirectory, let original = node.modified, let date = current.ModTime {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let currentDate = formatter.date(from: date) ?? ISO8601DateFormatter().date(from: date)
            guard currentDate == original else { throw BloomError.message("Cloud item changed. Rescan first.") }
        }
        _ = try command([node.isDirectory ? "purge" : "deletefile", node.path], token: token, timeout: 3600)
    }
    public func delete(_ item: CollectorItem, token: CancellationToken = CancellationToken()) throws {
        if item.node.isDirectory {
            guard !item.expectedNodes.isEmpty else { throw BloomError.message("Rescan this cloud folder before deleting it") }
            let fresh = try scan(ScanSource(name: item.node.name, path: item.node.path, kind: .cloud), token: token)
            let expected = Dictionary(uniqueKeysWithValues: item.expectedNodes.map { ($0.path, $0) })
            guard fresh.nodes.count == expected.count, fresh.nodes.allSatisfy({ node in
                guard let old = expected[node.path], old.isDirectory == node.isDirectory else { return false }
                return node.isDirectory || (old.logicalBytes == node.logicalBytes && old.modified == node.modified && old.cloudObjectID == node.cloudObjectID)
            }) else { throw BloomError.message("Cloud folder contents changed. Rescan before removing: \(item.node.name)") }
        }
        try delete(item.node, source: item.source, token: token)
    }
    public func capacity(_ source: ScanSource) throws -> VolumeCapacity? {
        let data = try command(["about", source.path, "--json"])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let total = (object["total"] as? NSNumber)?.int64Value,
              let free = (object["free"] as? NSNumber)?.int64Value else { return nil }
        return VolumeCapacity(total: total, free: free, available: free)
    }
}
