import Foundation
import Darwin

/// Metadata-only traversal. Does not follow symbolic links, read file contents,
/// cross filesystem boundaries, or hydrate cloud placeholders.
public struct LocalScanner {
    public init() {}
    public static func identity(at path: String) throws -> FileIdentity {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw BloomError.message("\(path): \(String(cString: strerror(errno)))") }
        return identity(info)
    }
    private static func identity(_ info: stat) -> FileIdentity {
        FileIdentity(device: info.st_dev, inode: info.st_ino,
                     modificationSeconds: Int64(info.st_mtimespec.tv_sec),
                     modificationNanos: Int64(info.st_mtimespec.tv_nsec),
                     logicalSize: info.st_size, mode: info.st_mode)
    }
    public func scan(_ source: ScanSource, token: CancellationToken = CancellationToken(),
                     progress: @escaping (ScanProgress) -> Void = { _ in }) throws -> ScanReport {
        guard source.kind == .local else { throw BloomError.message("Local scanner requires a local source") }
        let rootPath = URL(fileURLWithPath: source.path).standardizedFileURL.path
        var rootStat = stat()
        guard lstat(rootPath, &rootStat) == 0, rootStat.st_mode & S_IFMT == S_IFDIR else {
            throw BloomError.message("Cannot open folder: \(rootPath)")
        }
        let started = Date()
        var nodes = [DiskNode(id: 0, parent: nil, name: source.name, path: rootPath, isDirectory: true)]
        nodes[0].identity = Self.identity(rootStat)
        var stack = [0]; var seen: Set<FileKey> = []
        var fileCount = 0; var total: Int64 = 0; var restricted = 0; var mounts = 0; var duplicates = 0
        var lastUpdate = Date.distantPast
        while let parent = stack.popLast() {
            try token.check()
            let path = nodes[parent].path
            // O_NOFOLLOW closes the race between lstat and opening a directory.
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { nodes[parent].isRestricted = true; restricted += 1; continue }
            var opened = stat()
            guard fstat(fd, &opened) == 0, opened.st_dev == rootStat.st_dev,
                  opened.st_ino == nodes[parent].identity?.inode else {
                close(fd); nodes[parent].isRestricted = true; restricted += 1; continue
            }
            guard let directory = fdopendir(fd) else { close(fd); nodes[parent].isRestricted = true; restricted += 1; continue }
            defer { closedir(directory) }
            while true {
                try token.check()
                errno = 0
                guard let entry = readdir(directory) else {
                    if errno != 0 { nodes[parent].isRestricted = true; restricted += 1 }
                    break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                let childPath = path == "/" ? "/\(name)" : "\(path)/\(name)"
                var info = stat()
                let id = nodes.count
                let success = fstatat(dirfd(directory), name, &info, AT_SYMLINK_NOFOLLOW) == 0
                let isDirectory = success && info.st_mode & S_IFMT == S_IFDIR
                var node = DiskNode(id: id, parent: parent, name: name, path: childPath, isDirectory: isDirectory)
                if success {
                    node.identity = Self.identity(info)
                    node.modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                    node.isSymbolicLink = info.st_mode & S_IFMT == S_IFLNK
                    node.isOffline = info.st_flags & UInt32(SF_DATALESS) != 0
                    node.isMountBoundary = info.st_dev != rootStat.st_dev
                    if node.isMountBoundary { mounts += 1 }
                    else if !isDirectory {
                        let key = FileKey(device: info.st_dev, inode: info.st_ino)
                        if info.st_nlink > 1, !seen.insert(key).inserted {
                            node.isHardLinkDuplicate = true; duplicates += 1
                        } else {
                            node.allocatedBytes = max(0, Int64(info.st_blocks) * 512)
                            node.logicalBytes = max(0, info.st_size)
                            total += node.allocatedBytes
                        }
                        node.fileCount = 1; fileCount += 1
                    }
                } else { node.isRestricted = true; restricted += 1 }
                nodes.append(node); nodes[parent].children.append(id)
                if isDirectory && !node.isMountBoundary { stack.append(id) }
                if Date().timeIntervalSince(lastUpdate) > 0.12 {
                    lastUpdate = Date()
                    progress(ScanProgress(files: fileCount, bytes: total, path: childPath, elapsed: Date().timeIntervalSince(started)))
                }
            }
        }
        try token.check()
        Self.aggregate(&nodes)
        let report = ScanReport(source: source, nodes: nodes, startedAt: started, duration: Date().timeIntervalSince(started),
                                restrictedCount: restricted, skippedMounts: mounts, hardLinkDuplicates: duplicates,
                                isAdministrator: geteuid() == 0)
        progress(ScanProgress(files: fileCount, bytes: total, path: rootPath, elapsed: report.duration))
        return report
    }
    public static func aggregate(_ nodes: inout [DiskNode]) {
        // IDs are assigned before their descendants; reverse order is a postorder.
        for id in nodes.indices.reversed() {
            let children = nodes[id].children
            if nodes[id].isDirectory {
                nodes[id].allocatedBytes = children.reduce(0) { $0 + nodes[$1].allocatedBytes }
                nodes[id].logicalBytes = children.reduce(0) { $0 + nodes[$1].logicalBytes }
                nodes[id].fileCount = children.reduce(0) { $0 + nodes[$1].fileCount }
                let sorted = children.sorted {
                    if nodes[$0].allocatedBytes == nodes[$1].allocatedBytes { return nodes[$0].name.localizedStandardCompare(nodes[$1].name) == .orderedAscending }
                    return nodes[$0].allocatedBytes > nodes[$1].allocatedBytes
                }
                nodes[id].children = sorted
            }
        }
    }
    private struct FileKey: Hashable { let device: Int32; let inode: UInt64 }
}
