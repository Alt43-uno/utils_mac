import Foundation
import DiskBloomCore

enum DemoReport {
    static func make() -> ScanReport {
        let source = ScanSource(name: "Macintosh HD", path: "/Demo", isVolume: true)
        var nodes = [DiskNode(id: 0, parent: nil, name: source.name, path: source.path, isDirectory: true)]
        func folder(_ name: String, _ parent: Int) -> Int {
            let id = nodes.count; nodes.append(DiskNode(id: id, parent: parent, name: name, path: nodes[parent].path + "/" + name, isDirectory: true)); nodes[parent].children.append(id); return id
        }
        func file(_ name: String, _ bytes: Int64, _ parent: Int) {
            let id = nodes.count; var n = DiskNode(id: id, parent: parent, name: name, path: nodes[parent].path + "/" + name, isDirectory: false)
            n.allocatedBytes = bytes; n.logicalBytes = bytes; n.fileCount = 1; n.modified = Date(timeIntervalSince1970: 1_770_000_000)
            nodes.append(n); nodes[parent].children.append(id)
        }
        let categories: [(String, Int64, [String])] = [
            ("Users", 263_000_000_000, ["Movies", "Pictures", "Projects", "Documents", "Music", "Downloads"]),
            ("Applications", 97_000_000_000, ["Creative Cloud", "Developer Tools", "Games", "Productivity"]),
            ("Library", 74_000_000_000, ["Application Support", "Caches", "Developer", "Containers"]),
            ("System", 41_000_000_000, ["Library", "Frameworks", "Extensions"]),
            ("private", 23_000_000_000, ["var", "tmp"]),
            ("Archives", 18_000_000_000, ["2025", "2024", "Backups"]),
            ("Volumes", 8_000_000_000, ["Disk images", "Shared"])]
        for (category, total, children) in categories {
            let parent = folder(category, 0)
            let sum = Double(children.count * (children.count + 1) / 2)
            for (index, name) in children.enumerated() {
                let f = folder(name, parent); let share = Int64(Double(total) * Double(children.count - index) / sum)
                let deep = folder(index % 2 == 0 ? "Workspace" : "Assets", f)
                file("\(name).archive", share * 4 / 10, f)
                file("Export.mov", share * 3 / 10, deep)
                let deeper = folder("Resources", deep)
                file("Library.data", share * 2 / 10, deeper)
                for small in 0..<12 { file("Item-\(small + 1).bin", share / 120, deeper) }
            }
        }
        LocalScanner.aggregate(&nodes)
        return ScanReport(source: source, nodes: nodes, startedAt: Date(timeIntervalSince1970: 1_790_000_000), duration: 8.4)
    }
}
