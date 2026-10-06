import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DiskBloomCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State<Bool> private var dropTarget = false
    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model).frame(width: 210)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                WorkspaceToolbar(model: model)
                Rectangle().fill(Theme.line).frame(height: 1)
                Group {
                    switch model.page {
                    case .overview: OverviewView(model: model)
                    case .analysis: AnalysisView(model: model)
                    case .snapshots: SnapshotsView(model: model)
                    case .cloud: CloudView(model: model)
                    case .settings: PreferencesView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                CollectorBar(model: model)
            }.background(Theme.background)
        }
        .foregroundStyle(Theme.text).preferredColorScheme(.dark)
        .frame(minWidth: 1040, minHeight: 680)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast).font(.system(size: 12, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Theme.elevated, in: Capsule()).shadow(color: .black.opacity(0.2), radius: 12, y: 5).padding(.top, 68)
                    .allowsHitTesting(false)
            }
        }
        .alert(L.text("Couldn't complete the action", "Не удалось выполнить действие"), isPresented: $model.showError) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.message ?? "") }
        .sheet(isPresented: $model.showCollector) { CollectorSheet(model: model) }
        .sheet(isPresented: $model.showCloudConnect) { CloudConnectView(model: model) }
        .alert(L.text("Review your collection", "Проверьте коллекцию"), isPresented: $model.showDeleteConfirmation) {
            Button(L.cancel, role: .cancel) {}
            Button(model.permanentDeletion ? L.text("Delete permanently", "Удалить навсегда") : L.text("Move to Trash", "В Корзину"), role: .destructive) { model.beginDeletion() }
        } message: {
            Text(deletionMessage)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSURL.self) { url, _ in
                    guard let url = url as? URL else { return }
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
                    Task { @MainActor in model.addFolder(url.path, startScan: true) }
                }
            }; return true
        }
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 3).padding(5).allowsHitTesting(false) } }
    }
    var deletionMessage: String {
        let count = model.collector.count; let size = ByteFormat.string(model.collectedBytes)
        let base = L.text("\(count) items · \(size). You have 5 seconds to cancel.", "Объектов: \(count) · \(size). На отмену будет 5 секунд.")
        let permanent = model.permanentDeletion || model.collector.contains { $0.source.kind == .cloud }
        return base + "\n\n" + (permanent ? L.text("Permanent deletion cannot be undone. Cloud deletions follow the provider's retention policy.", "Безвозвратное удаление нельзя отменить. Для облачных файлов действует политика восстановления провайдера.") : L.text("Files will be moved to the macOS Trash. Space is reclaimed when you empty it.", "Файлы переместятся в Корзину macOS. Место освободится после её очистки."))
    }
}

struct Sidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BloomMark().frame(width: 25, height: 25)
                Text("DiskBloom").font(.system(size: 16, weight: .semibold)).tracking(-0.4)
            }.padding(.top, 47).padding(.bottom, 30).padding(.horizontal, 22)
            nav("square.grid.2x2", L.overview, selected: model.page == .overview) { model.page = .overview }
            nav("cloud", L.cloud, selected: model.page == .cloud) { model.page = .cloud; model.refreshCloud() }
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: L.text("Connected disks", "Подключённые диски")).padding(.top, 28).padding(.bottom, 6).padding(.leading, 12)
                    ForEach(model.sources.filter { $0.isVolume }) { source in sourceRow(source) }
                    Eyebrow(text: L.text("Folders & accounts", "Папки и аккаунты")).padding(.top, 23).padding(.bottom, 6).padding(.leading, 12)
                    ForEach(model.sources.filter { !$0.isVolume }) { source in sourceRow(source) }
                    Button { model.chooseFolder() } label: {
                        Label(L.text("Add a folder", "Добавить папку"), systemImage: "plus").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(12)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { Image(systemName: "lock.shield"); Text(L.text("Your files stay yours.", "Ваши файлы — только ваши.")) }
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                nav("slider.horizontal.3", L.settings, selected: model.page == .settings) { model.page = .settings }
            }.padding(.horizontal, 10).padding(.bottom, 18)
        }.background(Theme.sidebar)
    }
    func nav(_ symbol: String, _ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) { Image(systemName: symbol).frame(width: 17); Text(title); Spacer() }
                .font(.system(size: 12, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? Theme.text : Theme.secondary)
                .padding(.horizontal, 12).padding(.vertical, 11).background(selected ? Theme.elevated.opacity(0.65) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).padding(.horizontal, 10)
    }
    func sourceRow(_ source: ScanSource) -> some View {
        let selected = model.selectedSourceID == source.id && model.page == .analysis
        return Button { model.selectSource(source) } label: {
            HStack(spacing: 10) {
                Image(systemName: source.kind == .cloud ? "cloud.fill" : source.isVolume ? "internaldrive" : "folder")
                    .font(.system(size: 15)).foregroundStyle(selected ? Theme.accent : Theme.secondary).frame(width: 19)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if let progress = model.jobs[source.id]?.progress {
                        Text(L.text("Scanning…", "Сканирование…") + " \(progress.files.formatted())").font(.system(size: 10)).foregroundStyle(Theme.accent)
                    } else if let c = model.capacities[source.id] {
                        Text(ByteFormat.string(c.free) + L.text(" free", " свободно")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                    } else { Text(source.kind == .cloud ? L.text("Remote storage", "Удалённое хранилище") : L.text("Folder", "Папка")).font(.system(size: 10)).foregroundStyle(Theme.muted) }
                }
                Spacer(minLength: 0)
                if model.jobs[source.id] != nil { ProgressView().controlSize(.mini) }
                else if model.reports[source.id] != nil { Circle().fill(Theme.accent).frame(width: 4, height: 4) }
            }.padding(.horizontal, 12).padding(.vertical, 11)
                .background(selected ? Theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
        .contextMenu {
            Button(L.scan) { model.scan(source) }
            if source.kind == .local { Button(L.text("Scan as administrator…", "Сканировать от администратора…")) { model.scan(source, administrator: true) } }
            if !source.isVolume { Button(L.text("Remove from sidebar", "Убрать из списка")) { model.forget(source) } }
        }
    }
}

struct BloomMark: View {
    var body: some View {
        ZStack {
            ForEach(0..<8) { i in
                Capsule().fill(Theme.color(i)).frame(width: 5, height: 11).offset(y: -8).rotationEffect(.degrees(Double(i) * 45))
            }
            Circle().fill(Theme.sidebar).frame(width: 7, height: 7)
        }
    }
}

struct WorkspaceToolbar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            if model.page == .analysis {
                IconButton(symbol: "chevron.left", help: L.text("Back", "Назад"), action: model.goBack).disabled(!model.canBack)
                IconButton(symbol: "chevron.right", help: L.text("Forward", "Вперёд"), action: model.goForward).disabled(!model.canForward)
                Button(L.overview) { model.page = .overview }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.leading, 8)
                if let report = model.report {
                    ForEach(Array(report.ancestors(of: model.currentID).suffix(4)), id: \.self) { id in
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.muted)
                        Button(report.nodes[id].name) { model.navigate(id) }.buttonStyle(.plain).font(.system(size: 11, weight: id == model.currentID ? .semibold : .regular)).lineLimit(1)
                    }
                } else if let source = model.source { Text(source.name).font(.system(size: 11, weight: .semibold)) }
            } else {
                Text(model.page == .overview ? L.overview : model.page == .cloud ? L.cloud : model.page == .snapshots ? L.snapshots : L.settings)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 10)
            if model.source?.path == "/Demo" { Text(L.text("DEMO DATA", "ДЕМО-ДАННЫЕ")).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Theme.accent).padding(7).background(Theme.accent.opacity(0.08), in: Capsule()) }
            if model.page == .analysis && model.report != nil {
                Menu {
                    Button(L.text("Export report…", "Экспорт отчёта…"), action: model.exportReport)
                    if model.source?.kind == .local {
                        Button(L.snapshots, action: model.loadSnapshots)
                        Button(L.access, action: model.openFullDiskAccess)
                        Button(L.text("Scan as administrator…", "Сканировать от администратора…")) { if let s = model.source { model.scan(s, administrator: true) } }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }.menuStyle(.borderlessButton).frame(width: 30).help(L.text("More actions", "Другие действия"))
                if let source = model.source, model.activeJob != nil { Button(L.cancel) { model.cancelScan(source) }.buttonStyle(BloomButtonStyle()) }
                else { Button { model.rescan() } label: { Label(L.rescan, systemImage: "arrow.clockwise") }.buttonStyle(BloomButtonStyle()) }
            } else { Button { model.chooseFolder() } label: { Label(L.folder, systemImage: "folder.badge.plus") }.buttonStyle(BloomButtonStyle()) }
        }.padding(.horizontal, 23).frame(height: 61)
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 11) {
                    Eyebrow(text: L.text("A little clarity. A lot of space.", "Больше ясности. Больше места."))
                    Text(L.text("Make room for what matters.", "Место для самого важного."))
                        .font(.system(size: 31, weight: .semibold)).tracking(-1)
                    Text(L.text("See your storage at a glance. Find the big files. Take back your space.", "Посмотрите, чем занят диск. Найдите большие файлы. Освободите место."))
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }.padding(.top, 13).padding(.bottom, 9)
                ForEach(model.sources.filter { $0.kind == .local }) { source in
                    VolumeCard(model: model, source: source)
                }
                HStack(alignment: .top, spacing: 15) {
                    feature("circle.hexagongrid", L.text("Explore, naturally", "Исследуйте наглядно"), L.text("Every ring is a folder level. Bigger petals mean bigger files.", "Каждое кольцо — уровень папок. Чем шире сектор, тем больше файл."))
                    feature("shield.lefthalf.filled", L.text("You're in control", "Всё под вашим контролем"), L.text("Collect first, review, then remove. Essential system files are protected.", "Соберите файлы, проверьте и удалите. Важные системные папки защищены."))
                    feature("cloud", L.text("Beyond your Mac", "За пределами Mac"), L.text("External drives, network shares and your cloud accounts, together.", "Внешние диски, сетевые папки и облачные аккаунты в одном месте."))
                }.padding(.top, 5)
            }.padding(35)
        }
    }
    func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.accent).padding(.bottom, 4)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
    }
}

struct VolumeCard: View {
    @ObservedObject var model: AppModel
    var source: ScanSource
    var body: some View {
        Panel {
            HStack(spacing: 24) {
                Image(systemName: source.isVolume ? "internaldrive.fill" : "folder.fill").font(.system(size: 32, weight: .light))
                    .foregroundStyle(Theme.secondary).frame(width: 54, height: 65)
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(source.name).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        if let c = model.capacities[source.id] { Text(ByteFormat.string(c.total)).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                    }
                    if let c = model.capacities[source.id] {
                        CapacityBar(used: Double(c.used) / Double(max(1, c.total)))
                        HStack {
                            Text(ByteFormat.string(c.used) + L.text(" used", " занято")).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(ByteFormat.string(c.free) + L.text(" free", " свободно")).foregroundStyle(Theme.accent)
                        }.font(.system(size: 11))
                    } else { Text(source.path).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1) }
                }
                VStack(spacing: 8) {
                    if let job = model.jobs[source.id] {
                        Button(L.cancel) { model.cancelScan(source) }.buttonStyle(BloomButtonStyle())
                        Text(job.progress.files.formatted()).font(.system(size: 10)).foregroundStyle(Theme.muted)
                    } else {
                        Button(model.reports[source.id] != nil ? L.text("Open map", "Открыть карту") : L.scan) {
                            if model.reports[source.id] != nil { model.selectSource(source) } else { model.scan(source) }
                        }.buttonStyle(BloomButtonStyle(prominent: true))
                        Text(source.isVolume ? L.text("Volume", "Том") : L.text("Folder", "Папка")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }.frame(width: 110)
            }
        }
    }
}

struct AnalysisView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let report = model.report, let current = model.current {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Eyebrow(text: L.text("Storage map", "Карта диска"))
                            Text(current.name).font(.system(size: 25, weight: .semibold)).tracking(-0.7).lineLimit(1)
                            Text("\(current.fileCount.formatted()) " + L.text("files", "файлов") + " · " + String(format: "%.1f", report.duration) + L.text(" sec scan", " с сканирование"))
                                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Menu {
                            Button(L.allocated) { model.metric = .allocated; model.updateLargestCache() }
                            Button(L.logical) { model.metric = .logical; model.updateLargestCache() }
                        } label: { Text(model.metric == .allocated ? L.allocated : L.logical).font(.system(size: 10)) }
                            .menuStyle(.borderlessButton).frame(width: 120).foregroundStyle(Theme.secondary)
                    }.padding(.horizontal, 30).padding(.top, 26)
                    GeometryReader { proxy in
                        let size = min(proxy.size.width, proxy.size.height)
                        ZStack {
                            SunburstView(model: model)
                            let centerNode = model.inspected ?? current
                            let parts = ByteFormat.parts(centerNode.bytes(model.metric))
                            Button { model.goUp() } label: {
                                VStack(spacing: 3) {
                                    Text(parts.0).font(.system(size: min(31, size * 0.061), weight: .medium)).tracking(-0.8).monospacedDigit()
                                    Text(parts.1).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                                    if model.currentID != 0 { Image(systemName: "arrow.turn.up.left").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.top, 3) }
                                }.frame(width: size * 0.19, height: size * 0.19).contentShape(Circle())
                            }.buttonStyle(.plain).help(L.text("Click to go up one level", "Нажмите, чтобы вернуться на уровень выше"))
                        }.frame(width: size, height: size).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.padding(.horizontal, 13)
                    HStack(spacing: 7) {
                        Image(systemName: "cursorarrow.motionlines").font(.system(size: 11))
                        Text(L.text("Click to explore · Drag to collect · Space to preview", "Клик — открыть · Перетаскивание — в коллекцию · Пробел — просмотр"))
                            .font(.system(size: 10))
                        Spacer()
                    }.foregroundStyle(Theme.muted).padding(.horizontal, 30).padding(.bottom, 22)
                    if let job = model.activeJob { scanStrip(job) }
                }
                Rectangle().fill(Theme.line).frame(width: 1)
                InspectorView(model: model).frame(width: 300)
            }
        } else if let job = model.activeJob {
            VStack(spacing: 20) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text(L.text("Getting the full picture…", "Собираем полную картину…")).font(.system(size: 26, weight: .medium)).tracking(-0.6)
                Text(model.source?.name ?? "").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                HStack(spacing: 30) {
                    stat(job.progress.files.formatted(), L.text("files found", "файлов найдено"))
                    stat(ByteFormat.string(job.progress.bytes), L.text("measured", "измерено"))
                }.padding(.top, 10)
                Text(job.administrator ? L.text("macOS will ask for administrator authorization. Full Disk Access is still required.", "macOS запросит права администратора. Полный доступ к диску всё равно необходим.") : job.progress.path)
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 500)
                if let s = model.source { Button(L.cancel) { model.cancelScan(s) }.buttonStyle(BloomButtonStyle()) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 15) {
                Image(systemName: "circle.hexagongrid").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(Theme.accent)
                Text(L.text("Ready when you are.", "Готово к сканированию.")).font(.system(size: 24, weight: .medium))
                if let s = model.source { Button(L.scan) { model.scan(s) }.buttonStyle(BloomButtonStyle(prominent: true)) }
                else { Button(L.folder, action: model.chooseFolder).buttonStyle(BloomButtonStyle(prominent: true)) }
            }
        }
    }
    func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 7) { Text(value).font(.system(size: 22, weight: .medium)).monospacedDigit(); Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted) }
    }
    func scanStrip(_ job: ScanJob) -> some View {
        HStack(spacing: 10) { ProgressView().controlSize(.small); Text(L.text("Updating map…", "Обновление карты…") + " \(job.progress.files.formatted())").font(.system(size: 11)); Spacer() }
            .padding(12).background(Theme.surface)
    }
}
