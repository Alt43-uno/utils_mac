import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DiskBloomCore

enum WorkspacePage { case overview, analysis, snapshots, cloud, settings }
enum FileListMode: String, CaseIterable { case folders, largest }
struct ScanJob {
    var id: UUID
    var token: CancellationToken
    var progress: ScanProgress
    var administrator: Bool
}

@MainActor
final class AppModel: ObservableObject {
    @Published var page: WorkspacePage = .overview
    @Published var sources: [ScanSource] = []
    @Published var capacities: [String: VolumeCapacity] = [:]
    @Published var reports: [String: ScanReport] = [:]
    @Published var jobs: [String: ScanJob] = [:]
    @Published var selectedSourceID: String?
    @Published var currentID = 0
    @Published var selectedID: Int?
    @Published var hoveredID: Int?
    @Published var groupIDs: [Int]? { didSet { updateRows() } }
    @Published var metric: SizeMetric = .allocated
    @Published var listMode: FileListMode = .folders { didSet { updateRows() } }
    @Published var search = "" { didSet { updateRows() } }
    @Published private(set) var visibleIDs: [Int] = []
    @Published private(set) var totalVisibleCount = 0
    @Published var collector: [CollectorItem] = []
    @Published var showCollector = false
    @Published var showDeleteConfirmation = false
    @Published var deletionCountdown: Int?
    @Published var isDeleting = false
    @Published var permanentDeletion = false
    @Published var message: String?
    @Published var showError = false
    @Published var toast: String?
    @Published var snapshots: [APFSSnapshot] = []
    @Published var otherVolumes: [(String, Int64)] = []
    @Published var snapshotError: String?
    @Published var loadingSnapshots = false
    @Published private(set) var snapshotVolumePath = ""
    @Published var snapshotBusy = false
    @Published var pendingSnapshot: APFSSnapshot?
    @Published var confirmPurge = false
    @Published var cloudRemotes: [String] = []
    @Published var cloudLoading = false
    @Published var showCloudConnect = false
    @Published var languageRevision = 0
    @Published var previewingCloud = false
    private var largestCache: [Int] = []
    private var childColorIndices: [Int: Int] = [:]
    private var deletionTask: Task<Void, Never>?
    private var volumeTimer: Timer?
    private var backStack: [Int] = []
    private var forwardStack: [Int] = []
    private var removedPaths: Set<String> = []
    let demo: Bool

    var source: ScanSource? { sources.first { $0.id == selectedSourceID } }
    var report: ScanReport? { selectedSourceID.flatMap { reports[$0] } }
    var current: DiskNode? { guard let r = report, r.nodes.indices.contains(currentID) else { return nil }; return r.nodes[currentID] }
    var inspected: DiskNode? {
        guard let r = report else { return nil }
        let id = hoveredID ?? selectedID ?? currentID
        return r.nodes.indices.contains(id) ? r.nodes[id] : nil
    }
    var activeJob: ScanJob? { selectedSourceID.flatMap { jobs[$0] } }
    var collectedBytes: Int64 { collector.reduce(0) { $0 + $1.node.bytes(metric) } }
    var canBack: Bool { !backStack.isEmpty }
    var canForward: Bool { !forwardStack.isEmpty }
    var capacity: VolumeCapacity? { selectedSourceID.flatMap { capacities[$0] } }
    var unaccounted: Int64 { guard let r = report, r.source.isVolume, let c = capacity else { return 0 }; return max(0, c.used - r.root.allocatedBytes) }
    var cloudBridge: CloudBridge? {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("rclone").path,
                          "/opt/homebrew/bin/rclone", "/usr/local/bin/rclone"].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DiskBloom", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return CloudBridge(executable: path, configPath: directory.appendingPathComponent("rclone.conf").path)
    }

    init() {
        demo = CommandLine.arguments.contains("--demo")
        Self.clearPreviewCache()
        refreshVolumes()
        if demo {
            let r = DemoReport.make(); sources.insert(r.source, at: 0); reports[r.source.id] = r
            capacities[r.source.id] = VolumeCapacity(total: 1_000_000_000_000, free: 312_000_000_000, available: 340_000_000_000)
            selectedSourceID = r.source.id; page = .analysis; updateRows()
        }
        if let argument = CommandLine.arguments.firstIndex(of: "--scan"), CommandLine.arguments.indices.contains(argument + 1) {
            addFolder(CommandLine.arguments[argument + 1], startScan: true)
        }
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshVolumes() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshVolumes() }
            }
        }
    }
    func refreshVolumes() {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsInternalKey, .volumeIsBrowsableKey, .volumeIsLocalKey]
        let mounted = fm.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        var volumes: [ScanSource] = []
        for url in mounted {
            let values = try? url.resourceValues(forKeys: keys)
            if url.path.hasPrefix("/System/Volumes/") { continue }
            let path = url.path == "/" && fm.fileExists(atPath: "/System/Volumes/Data") ? "/System/Volumes/Data" : url.path
            let s = ScanSource(name: values?.volumeName ?? url.lastPathComponent, path: path, isVolume: true)
            volumes.append(s)
        }
        let saved = UserDefaults.standard.stringArray(forKey: "folders") ?? []
        let folders = saved.filter { fm.fileExists(atPath: $0) }.map { ScanSource(name: URL(fileURLWithPath: $0).lastPathComponent, path: $0) }
        let existing = sources.filter { $0.path == "/Demo" || (!$0.isVolume && ($0.kind == .cloud || !saved.contains($0.path))) }
        sources = deduplicated(existing + volumes + folders)
        for s in sources where s.kind == .local && s.path != "/Demo" { capacities[s.id] = VolumeCapacity.read(s.path) }
        if selectedSourceID == nil { selectedSourceID = volumes.first?.id }
    }
    private func deduplicated(_ list: [ScanSource]) -> [ScanSource] {
        var seen: Set<String> = []; return list.filter { seen.insert($0.id).inserted }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = L.scan
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addFolder(url.path, startScan: true) }
    }
    func addFolder(_ path: String, startScan: Bool) {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let s = sources.first { $0.path == url.path && $0.kind == .local } ?? ScanSource(name: url.lastPathComponent, path: url.path)
        if !sources.contains(s) { sources.append(s) }
        var saved = UserDefaults.standard.stringArray(forKey: "folders") ?? []
        if !saved.contains(s.path), !s.isVolume { saved.append(s.path); UserDefaults.standard.set(saved, forKey: "folders") }
        capacities[s.id] = VolumeCapacity.read(s.path)
        if startScan { scan(s) } else { selectSource(s) }
    }
    func forget(_ s: ScanSource) {
        guard !s.isVolume, jobs[s.id] == nil else { return }
        sources.removeAll { $0.id == s.id }; reports.removeValue(forKey: s.id)
        var saved = UserDefaults.standard.stringArray(forKey: "folders") ?? []; saved.removeAll { $0 == s.path }
        UserDefaults.standard.set(saved, forKey: "folders")
        if s.id == selectedSourceID { selectedSourceID = sources.first?.id; page = .overview }
    }
    func selectSource(_ s: ScanSource) {
        selectedSourceID = s.id; currentID = 0; selectedID = nil; hoveredID = nil; groupIDs = nil; search = ""
        backStack = []; forwardStack = []; listMode = .folders; updateLargestCache()
        page = reports[s.id] == nil && jobs[s.id] == nil ? .overview : .analysis
    }
    func scan(_ s: ScanSource, administrator: Bool = false) {
        guard s.path != "/Demo", jobs[s.id] == nil, !isDeleting else { return }
        selectSource(s); page = .analysis
        let id = UUID(); let token = CancellationToken()
        jobs[s.id] = ScanJob(id: id, token: token, progress: ScanProgress(files: 0, bytes: 0, path: s.path, elapsed: 0), administrator: administrator)
        let bridge = cloudBridge
        let worker = Bundle.main.url(forAuxiliaryExecutable: "DiskBloomWorker")?.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let progress: (ScanProgress) -> Void = { p in
                    DispatchQueue.main.async { [weak self] in
                        guard self?.jobs[s.id]?.id == id else { return }; self?.jobs[s.id]?.progress = p
                    }
                }
                var result: ScanReport
                if administrator {
                    guard let worker else { throw BloomError.message(L.text("Build the app bundle to use administrator scanning.", "Для сканирования от администратора запустите собранный .app.")) }
                    // No redirects or privileged writes: the report is returned over stdout.
                    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("DiskBloom-" + UUID().uuidString + ".scan")
                    try Data().write(to: marker, options: .withoutOverwriting)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
                    defer { try? FileManager.default.removeItem(at: marker) }
                    token.onCancel { try? FileManager.default.removeItem(at: marker) }
                    let command = [worker, "--scan", s.path, "--cancel-marker", marker.path].map(CommandRunner.shellQuote).joined(separator: " ")
                    let script = "do shell script \(CommandRunner.appleScriptQuote(command)) with administrator privileges"
                    let data = try CommandRunner.checked("/usr/bin/osascript", ["-e", script], timeout: 3600, token: token)
                    result = try JSONDecoder().decode(ScanReport.self, from: data); result.source = s
                } else if s.kind == .cloud {
                    guard let bridge else { throw BloomError.message("rclone is not installed") }
                    result = try bridge.scan(s, token: token, progress: progress)
                } else { result = try LocalScanner().scan(s, token: token, progress: progress) }
                DispatchQueue.main.async {
                    guard let self, self.jobs[s.id]?.id == id else { return }
                    self.jobs[s.id] = nil; self.reports[s.id] = result
                    if self.selectedSourceID == s.id { self.currentID = 0; self.selectedID = nil; self.groupIDs = nil; self.updateLargestCache() }
                    self.removedPaths = self.removedPaths.filter { !$0.hasPrefix(s.id + "|") }
                    self.refreshVolumes()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.jobs[s.id]?.id == id else { return }; self.jobs[s.id] = nil
                    if !token.isCancelled { self.fail(error) }
                }
            }
        }
    }
    func cancelScan(_ s: ScanSource) { jobs[s.id]?.token.cancel(); jobs[s.id] = nil }
    func rescan() { if let s = source { scan(s) } }
    func navigate(_ id: Int, record: Bool = true) {
        guard let r = report, r.nodes.indices.contains(id) else { return }
        if !r.nodes[id].isDirectory { selectedID = id; return }
        if record && currentID != id { backStack.append(currentID); forwardStack = [] }
        currentID = id; selectedID = nil; hoveredID = nil; groupIDs = nil; search = ""; updateLargestCache()
    }
    func goUp() { if let parent = current?.parent { navigate(parent) } }
    func goBack() { guard let id = backStack.popLast() else { return }; forwardStack.append(currentID); navigate(id, record: false) }
    func goForward() { guard let id = forwardStack.popLast() else { return }; backStack.append(currentID); navigate(id, record: false) }
    func showGroup(_ ids: [Int]) { groupIDs = ids; selectedID = nil; hoveredID = nil }
    func updateLargestCache() {
        largestCache = listMode == .largest ? report?.largestFiles(in: currentID, metric: metric) ?? [] : []
        updateRows()
    }
    func updateRows() {
        guard let r = report, r.nodes.indices.contains(currentID) else { visibleIDs = []; return }
        if search.isEmpty {
            let base = groupIDs ?? (listMode == .largest ? largestCache : r.nodes[currentID].children)
            let sorted = base.sorted { r.nodes[$0].bytes(metric) > r.nodes[$1].bytes(metric) }
            let children = r.nodes[currentID].children.sorted { r.nodes[$0].bytes(metric) > r.nodes[$1].bytes(metric) }
            childColorIndices = Dictionary(uniqueKeysWithValues: children.enumerated().map { ($0.element, $0.offset) })
            totalVisibleCount = sorted.count; visibleIDs = Array(sorted.prefix(500)); return
        }
        // Search the entire current subtree; keep expensive work out of ring drawing.
        var stack = [currentID]; var matches: [Int] = []
        while let id = stack.popLast() {
            let n = r.nodes[id]; stack.append(contentsOf: n.children)
            if id != currentID && n.name.localizedCaseInsensitiveContains(search) { matches.append(id) }
        }
        totalVisibleCount = matches.count
        visibleIDs = Array(matches.sorted { r.nodes[$0].bytes(metric) > r.nodes[$1].bytes(metric) }.prefix(500))
    }
    func colorIndex(_ id: Int) -> Int {
        guard let r = report else { return 0 }
        var child = id
        while let parent = r.nodes[child].parent, parent != currentID { child = parent }
        return childColorIndices[child] ?? 0
    }
    func isRemoved(_ node: DiskNode) -> Bool { guard let s = source else { return false }; return removedPaths.contains(s.id + "|" + node.path) }
    func isCollected(_ node: DiskNode) -> Bool {
        guard let s = source else { return false }
        return collector.contains { $0.source.id == s.id && DeletionSafety.isWithin(node.path, directory: $0.node.path) }
    }
    func canCollect(_ node: DiskNode) -> Bool {
        guard let s = source, s.path != "/Demo", node.id != 0, !node.isRestricted, !node.isMountBoundary, !isRemoved(node), !isDeleting else { return false }
        return s.kind == .cloud || DeletionSafety.reason(path: node.path) == nil
    }
    func collect(_ id: Int? = nil) {
        guard let s = source, let r = report, let n = id.map({ r.nodes[$0] }) ?? inspected else { return }
        guard canCollect(n) else { notify(L.text("This item is protected.", "Этот объект защищён.")); return }
        var stack = [n.id]; var expected: [DiskNode] = []
        while let id = stack.popLast() { expected.append(r.nodes[id]); stack.append(contentsOf: r.nodes[id].children) }
        if expected.contains(where: { $0.isRestricted || $0.isMountBoundary }) {
            notify(L.text("This folder contains unreadable items or another volume. Review its files individually.", "В папке есть недоступные объекты или другой том. Выбирайте файлы отдельно.")); return
        }
        collector = CollectorRules.adding(CollectorItem(source: s, node: n, expectedNodes: expected), to: collector)
        notify(L.text("Added to collection", "Добавлено в коллекцию"))
    }
    func removeCollected(_ item: CollectorItem) { if !isDeleting { collector.removeAll { $0.id == item.id } } }
    func preview(_ node: DiskNode? = nil, from explicitSource: ScanSource? = nil) {
        guard let n = node ?? inspected, !isRemoved(n), (explicitSource ?? source)?.path != "/Demo" else { return }
        if (explicitSource ?? source)?.kind == .cloud { previewCloud(n); return }
        if n.isOffline { notify(L.text("Preview may download this cloud file.", "Просмотр может скачать этот облачный файл.")) }
        QuickLookController.shared.show(URL(fileURLWithPath: n.path))
    }
    func reveal(_ node: DiskNode? = nil) {
        guard let n = node ?? inspected, source?.kind == .local else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: n.path)])
    }
    func copyPath(_ node: DiskNode) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(node.path, forType: .string) }
    func fail(_ error: Error) { message = error.localizedDescription; showError = true }
    func notify(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in if self?.toast == text { self?.toast = nil } }
    }
    func changeLanguage() { languageRevision += 1 }
    func openFullDiskAccess() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
    func exportReport() {
        guard let r = report else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText, .json]
        panel.nameFieldStringValue = "DiskBloom-\(r.source.name).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            if url.pathExtension.lowercased() == "json" { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; data = try encoder.encode(r) }
            else { data = Data(ReportExporter.csv(r).utf8) }
            try data.write(to: url, options: .atomic); notify(L.text("Report exported", "Отчёт сохранён"))
        } catch { fail(error) }
    }
    func beginDeletion() {
        guard !collector.isEmpty, !isDeleting else { return }
        let items = collector; let permanent = permanentDeletion; let bridge = cloudBridge
        isDeleting = true; deletionCountdown = 5
        deletionTask = Task {
            for value in stride(from: 5, through: 1, by: -1) {
                deletionCountdown = value
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            deletionCountdown = nil
            var failures: [String] = []; var succeeded: [CollectorItem] = []
            for item in items {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        if item.source.kind == .cloud {
                            guard let bridge else { throw BloomError.message("rclone is unavailable") }
                            try bridge.delete(item)
                        } else {
                            try DeletionSafety.validate(item)
                            if permanent { try FileManager.default.removeItem(at: URL(fileURLWithPath: item.node.path)) }
                            else { try FileManager.default.trashItem(at: URL(fileURLWithPath: item.node.path), resultingItemURL: nil) }
                        }
                    }.value
                    succeeded.append(item)
                } catch { failures.append("\(item.node.name): \(error.localizedDescription)") }
            }
            for item in succeeded { collector.removeAll { $0.id == item.id }; removedPaths.insert(item.id) }
            isDeleting = false; refreshVolumes()
            if !failures.isEmpty { fail(BloomError.message(failures.joined(separator: "\n\n"))) }
            else { notify(permanent ? L.text("Deleted. Rescan to update the map.", "Удалено. Повторите сканирование для обновления карты.") : L.text("Moved to Trash. Empty Trash to reclaim space.", "Перемещено в Корзину. Очистите её, чтобы освободить место.")) }
            // Invalidate the affected scans: displayed accounting must not claim freed space.
            for s in Set(succeeded.map(\.source)) where reports[s.id] != nil { scan(s) }
        }
    }
    func cancelDeletion() {
        guard deletionCountdown != nil else { return }; deletionTask?.cancel(); deletionTask = nil; deletionCountdown = nil; isDeleting = false
    }
    func loadSnapshots() {
        guard let s = source, s.kind == .local else { return }
        page = .snapshots; loadingSnapshots = true; snapshots = []; otherVolumes = []; snapshotError = nil
        let volume = (try? URL(fileURLWithPath: s.path).resourceValues(forKeys: [.volumeURLKey]))?.volume?.path ?? s.path
        snapshotVolumePath = volume
        DispatchQueue.global().async { [weak self] in
            do {
                let list = try SnapshotService.list(volume: volume)
                let volumes = try SnapshotService.otherVolumes(volume)
                DispatchQueue.main.async {
                    guard let self, self.source?.id == s.id else { return }
                    self.snapshots = list; self.otherVolumes = volumes; self.loadingSnapshots = false
                }
            } catch {
                DispatchQueue.main.async { self?.snapshotError = error.localizedDescription; self?.loadingSnapshots = false }
            }
        }
    }
    func deleteSnapshot(_ snapshot: APFSSnapshot) {
        guard snapshot.isTimeMachine, snapshot.purgeable, !snapshotVolumePath.isEmpty else { return }
        let command = ["/usr/sbin/diskutil", "apfs", "deleteSnapshot", snapshotVolumePath, "-uuid", snapshot.id, "-wait"]
        elevated(command)
    }
    func purgeSnapshots() {
        guard !snapshotVolumePath.isEmpty else { return }
        elevated(["/usr/bin/tmutil", "thinlocalsnapshots", snapshotVolumePath, "10000000000", "2"])
    }
    private func elevated(_ command: [String]) {
        snapshotBusy = true
        DispatchQueue.global().async { [weak self] in
            do {
                let script = "do shell script \(CommandRunner.appleScriptQuote(command.map(CommandRunner.shellQuote).joined(separator: " "))) with administrator privileges"
                _ = try CommandRunner.checked("/usr/bin/osascript", ["-e", script], timeout: 600)
                DispatchQueue.main.async { self?.snapshotBusy = false; self?.loadSnapshots(); self?.refreshVolumes() }
            } catch { DispatchQueue.main.async { self?.snapshotBusy = false; self?.fail(error) } }
        }
    }
    func refreshCloud() {
        guard let bridge = cloudBridge else { cloudRemotes = []; return }
        cloudLoading = true
        DispatchQueue.global().async { [weak self] in
            do {
                let remotes = try bridge.remotes()
                DispatchQueue.main.async {
                    guard let self else { return }; self.cloudRemotes = remotes; self.cloudLoading = false
                    for remote in remotes {
                        let s = ScanSource(name: String(remote.dropLast()), path: remote, kind: .cloud)
                        if !self.sources.contains(s) { self.sources.append(s) }
                        Task {
                            let capacity = try? await Task.detached { try bridge.capacity(s) }.value
                            if let capacity { self.capacities[s.id] = capacity }
                        }
                    }
                }
            } catch { DispatchQueue.main.async { self?.cloudLoading = false; self?.fail(error) } }
        }
    }
    func disconnectCloud(_ remote: String) {
        guard let bridge = cloudBridge else { return }
        let id = "cloud:" + remote
        guard jobs[id] == nil, !isDeleting else { notify(L.text("Finish the current operation first.", "Сначала завершите текущую операцию.")); return }
        Task {
            do {
                _ = try await Task.detached { try bridge.command(["config", "delete", String(remote.dropLast())]) }.value
                sources.removeAll { $0.id == id }; reports[id] = nil; collector.removeAll { $0.source.id == id }; refreshCloud()
                if selectedSourceID == id { selectedSourceID = sources.first?.id }
            } catch { fail(error) }
        }
    }
    func previewCloud(_ node: DiskNode) {
        guard let bridge = cloudBridge, !node.isDirectory, !previewingCloud else { return }
        guard node.logicalBytes <= 200_000_000 else {
            notify(L.text("Cloud previews are limited to 200 MB. Open larger files in your provider's app.", "Облачный просмотр ограничен 200 МБ. Большие файлы откройте в приложении провайдера.")); return
        }
        previewingCloud = true
        Task {
            do {
                let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DiskBloom/Previews/" + UUID().uuidString)
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let url = cache.appendingPathComponent(URL(fileURLWithPath: node.name).lastPathComponent)
                notify(L.text("Downloading this file for preview…", "Скачиваем выбранный файл для просмотра…"))
                _ = try await Task.detached { try bridge.command(["copyto", node.path, url.path, "--max-size", "200M"], timeout: 300) }.value
                guard FileManager.default.fileExists(atPath: url.path) else { throw BloomError.message("Preview file was not downloaded") }
                QuickLookController.shared.show(url); previewingCloud = false
            } catch { previewingCloud = false; fail(error) }
        }
    }
    static func clearPreviewCache() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DiskBloom/Previews")
        try? FileManager.default.removeItem(at: root)
    }
}
