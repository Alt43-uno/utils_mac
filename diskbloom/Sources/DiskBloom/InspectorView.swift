import SwiftUI
import AppKit
import DiskBloomCore

struct InspectorView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let node = model.inspected {
                HStack(spacing: 10) {
                    Circle().fill(Theme.color(model.colorIndex(node.id))).frame(width: 8, height: 8)
                    Text(node.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(ByteFormat.string(node.bytes(model.metric))).font(.system(size: 13, weight: .medium)).monospacedDigit()
                }.padding(.horizontal, 20).padding(.top, 28)
                Text(node.path).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled).padding(.horizontal, 20).padding(.top, 8)
            }
            HStack(spacing: 6) {
                tab(L.text("Contents", "Содержимое"), active: model.listMode == .folders) { model.listMode = .folders; model.groupIDs = nil }
                tab(L.largest, active: model.listMode == .largest) { model.listMode = .largest; model.groupIDs = nil; model.updateLargestCache() }
            }.padding(.horizontal, 17).padding(.top, 22)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.muted)
                TextField(L.text("Find in this folder", "Поиск в этой папке"), text: $model.search).textFieldStyle(.plain).font(.system(size: 11))
                    .accessibilityLabel(L.text("Search files", "Поиск файлов"))
                if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain) }
            }.padding(9).background(Theme.sidebar.opacity(0.5), in: RoundedRectangle(cornerRadius: 7)).padding(.horizontal, 17).padding(.top, 12).padding(.bottom, 13)
            if model.groupIDs != nil {
                HStack {
                    Text(L.text("Smaller items", "Мелкие объекты")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                    Spacer(); Button(L.text("Close", "Закрыть")) { model.groupIDs = nil }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent)
                }.padding(.horizontal, 20).padding(.bottom, 10)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.visibleIDs.prefix(500)), id: \.self) { id in
                        if let node = model.report?.nodes[id] { fileRow(node) }
                    }
                    if model.visibleIDs.isEmpty {
                        Text(L.text("No matching items", "Нет подходящих объектов")).font(.system(size: 11)).foregroundStyle(Theme.muted).padding(30)
                    }
                    if model.totalVisibleCount > 500 { Text(L.text("Showing the largest 500. Search to find other files.", "Показаны 500 самых крупных. Используйте поиск для остальных.")).font(.system(size: 10)).foregroundStyle(Theme.muted).padding(15) }
                }.padding(.horizontal, 10)
            }
            if let node = model.inspected {
                VStack(alignment: .leading, spacing: 11) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack {
                        Text(L.allocated).foregroundStyle(Theme.muted); Spacer(); Text(ByteFormat.string(node.allocatedBytes))
                    }
                    HStack { Text(L.logical).foregroundStyle(Theme.muted); Spacer(); Text(ByteFormat.string(node.logicalBytes)) }
                    if let date = node.modified {
                        HStack { Text(L.text("Modified", "Изменено")).foregroundStyle(Theme.muted); Spacer(); Text(date, style: .date) }
                    }
                    if node.isRestricted { info("lock.fill", L.text("Restricted. Grant Full Disk Access.", "Нет доступа. Разрешите полный доступ к диску.")) }
                    if node.isSymbolicLink { info("arrow.turn.up.right", L.text("Symbolic link · target was not scanned", "Символическая ссылка · цель не сканировалась")) }
                    if node.isOffline { info("icloud", L.text("Cloud placeholder · not downloaded", "Облачный файл · не скачан")) }
                    if node.isHardLinkDuplicate { info("link", L.text("Hard link · counted elsewhere", "Жёсткая ссылка · учтено в другом объекте")) }
                    if model.source?.kind == .local && model.source?.path != "/Demo" {
                        HStack(spacing: 6) {
                            IconButton(symbol: "eye", help: L.preview) { model.preview(node) }
                            IconButton(symbol: "folder", help: L.reveal) { model.reveal(node) }
                            Spacer()
                            Button { model.collect(node.id) } label: { Label(L.collect, systemImage: "plus") }
                                .buttonStyle(BloomButtonStyle()).disabled(!model.canCollect(node) || model.isCollected(node))
                        }.padding(.top, 3)
                    } else if model.source?.kind == .cloud {
                        HStack {
                            Button { model.preview(node) } label: { Image(systemName: "eye") }.buttonStyle(BloomButtonStyle())
                                .help(L.text("Download this file for preview (up to 200 MB)", "Скачать файл для просмотра (до 200 МБ)"))
                                .disabled(node.isDirectory || model.previewingCloud)
                            Spacer()
                            Button(L.collect) { model.collect(node.id) }.buttonStyle(BloomButtonStyle()).disabled(!model.canCollect(node))
                        }
                    }
                }.font(.system(size: 10)).padding(.horizontal, 20).padding(.top, 13).padding(.bottom, 18)
            }
            if model.currentID == 0, let r = model.report, r.restrictedCount > 0 {
                Button { model.openFullDiskAccess() } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield").foregroundStyle(Color(hex: 0xC6A2ED))
                        Text(L.text("\(r.restrictedCount) restricted items. Enable Full Disk Access for a more complete scan.", "Недоступных объектов: \(r.restrictedCount). Разрешите полный доступ к диску для точного сканирования."))
                            .font(.system(size: 10)).lineSpacing(3).multilineTextAlignment(.leading)
                    }.padding(13).background(Color(hex: 0xC6A2ED).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 12)
            }
            if model.currentID == 0, model.unaccounted > 0 {
                Button { model.loadSnapshots() } label: {
                    HStack {
                        Image(systemName: "circle.dashed").foregroundStyle(Theme.muted)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.text("Unaccounted space", "Неучтённое место")).font(.system(size: 11, weight: .medium))
                            Text(L.text("Snapshots, other APFS volumes & metadata", "Снимки, другие тома APFS и метаданные")).font(.system(size: 9)).foregroundStyle(Theme.muted)
                        }
                        Spacer(); Text(ByteFormat.string(model.unaccounted)).font(.system(size: 11)); Image(systemName: "chevron.right").font(.system(size: 8))
                    }.padding(13).background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 18)
            }
        }.background(Theme.sidebar.opacity(0.2))
    }
    func tab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(active ? Theme.text : Theme.muted).background(active ? Theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
    }
    func info(_ icon: String, _ title: String) -> some View { Label(title, systemImage: icon).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
    func fileRow(_ node: DiskNode) -> some View {
        HStack(spacing: 9) {
            Circle().fill(node.isRestricted ? Color(hex: 0xAB8ADB) : Theme.color(model.colorIndex(node.id)))
                .frame(width: 5, height: 5).opacity(node.isDirectory ? 1 : 0.6)
            Button { model.selectedID = node.id; model.hoveredID = nil } label: {
                HStack(spacing: 7) {
                    Text(node.name).lineLimit(1).truncationMode(.middle).strikethrough(model.isRemoved(node))
                    if model.isCollected(node) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 9)) }
                    if node.isRestricted { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Color(hex: 0xAB8ADB)) }
                    Spacer(minLength: 3)
                    Text(ByteFormat.string(node.bytes(model.metric))).monospacedDigit().foregroundStyle(Theme.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).onTapGesture(count: 2) { if node.isDirectory { model.navigate(node.id) } else { model.preview(node) } }
            if node.isDirectory {
                Button { model.navigate(node.id) } label: { Image(systemName: "chevron.right").font(.system(size: 9)).frame(width: 15, height: 20) }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).help(L.text("Open folder", "Открыть папку"))
            } else { Color.clear.frame(width: 15, height: 20) }
        }.font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 8)
            .background(model.selectedID == node.id || model.hoveredID == node.id ? Theme.elevated.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .onHover { hover in if hover { model.hoveredID = node.id } else if model.hoveredID == node.id { model.hoveredID = nil } }
            .contextMenu {
                if node.isDirectory { Button(L.text("Open folder", "Открыть папку")) { model.navigate(node.id) } }
                if model.source?.kind == .local {
                    Button(L.preview) { model.preview(node) }; Button(L.reveal) { model.reveal(node) }
                }
                Button(L.text("Copy path", "Копировать путь")) { model.copyPath(node) }
                Button(L.collect) { model.collect(node.id) }.disabled(!model.canCollect(node))
            }
            .onDrag { NSItemProvider(object: "\(model.source?.id ?? "")#\(node.id)" as NSString) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(node.name + ", " + ByteFormat.string(node.bytes(model.metric)))
    }
}

struct CollectorBar: View {
    @ObservedObject var model: AppModel
    @State<Bool> private var dropTarget = false
    var body: some View {
        HStack(spacing: 17) {
            Button { model.showCollector = true } label: {
                ZStack {
                    Circle().stroke(Theme.muted.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: model.collector.isEmpty ? [3, 3] : [])).frame(width: 46, height: 46)
                    Image(systemName: model.collector.isEmpty ? "tray" : "tray.full.fill").font(.system(size: 18, weight: .light)).foregroundStyle(model.collector.isEmpty ? Theme.muted : Theme.accent)
                    if !model.collector.isEmpty {
                        Text("\(model.collector.count)").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.sidebar).padding(4)
                            .background(Theme.accent, in: Circle()).offset(x: 17, y: -17)
                    }
                }
            }.buttonStyle(.plain).help(L.collection)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.collector.isEmpty ? L.text("A fresh start begins here.", "Начните с чистого места.") : ByteFormat.string(model.collectedBytes) + L.text(" collected", " в коллекции"))
                    .font(.system(size: 12, weight: .medium))
                Text(model.deletionCountdown.map { L.text("Removing in \($0) seconds…", "Удаление через \($0) с…") } ?? (model.isDeleting ? L.text("Removing reviewed items…", "Удаление выбранных объектов…") : model.collector.isEmpty ? L.text("Drag files here. Nothing is removed until you decide.", "Перетащите файлы сюда. Удаление — только по вашему решению.") : L.text("Review your files before removing them.", "Проверьте файлы перед удалением.")))
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if model.deletionCountdown != nil { Button(L.cancel) { model.cancelDeletion() }.buttonStyle(BloomButtonStyle(prominent: true)) }
            else if model.isDeleting { ProgressView().controlSize(.small) }
            else {
                if !model.collector.isEmpty { Button(L.text("Review", "Проверить")) { model.showCollector = true }.buttonStyle(BloomButtonStyle()) }
                Button { model.showDeleteConfirmation = true } label: {
                    Label(model.permanentDeletion ? L.text("Delete", "Удалить") : L.text("Move to Trash", "В Корзину"), systemImage: "trash")
                }.buttonStyle(BloomButtonStyle(destructive: !model.collector.isEmpty)).disabled(model.collector.isEmpty)
                    .opacity(model.collector.isEmpty ? 0.35 : 1)
            }
        }.padding(.horizontal, 27).frame(height: 88).background(dropTarget ? Theme.elevated : Theme.sidebar.opacity(0.65))
            .overlay(alignment: .top) { Rectangle().fill(dropTarget ? Theme.accent : Theme.line).frame(height: 1) }
            .onDrop(of: [.plainText], isTargeted: $dropTarget) { providers in
                guard !model.isDeleting else { return false }
                for provider in providers {
                    provider.loadObject(ofClass: NSString.self) { value, _ in
                        guard let text = value as? String, let split = text.lastIndex(of: "#"),
                              let id = Int(text[text.index(after: split)...]) else { return }
                        let sourceID = String(text[..<split])
                        Task { @MainActor in
                            guard let report = model.reports[sourceID], report.nodes.indices.contains(id),
                                  let source = model.sources.first(where: { $0.id == sourceID }) else { return }
                            model.selectSource(source); model.collect(id)
                        }
                    }
                }; return true
            }
    }
}

struct CollectorSheet: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text(L.collection).font(.system(size: 23, weight: .semibold)); Spacer(); IconButton(symbol: "xmark", help: L.text("Close", "Закрыть")) { model.showCollector = false } }
            Text(L.text("These files are still in their original locations. Take a moment to review them.", "Эти файлы всё ещё на своих местах. Проверьте список перед удалением."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.collector) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.node.isDirectory ? "folder" : "doc").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.node.name).font(.system(size: 12, weight: .medium))
                                Text(item.node.path).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                            }; Spacer()
                            Text(ByteFormat.string(item.node.bytes(model.metric))).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            if item.source.kind == .local {
                                IconButton(symbol: "eye", help: L.preview) { model.preview(item.node, from: item.source) }
                            }
                            IconButton(symbol: "xmark", help: L.text("Remove from collection", "Убрать из коллекции")) { model.removeCollected(item) }.disabled(model.isDeleting)
                        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                    }
                    if model.collector.isEmpty { Text(L.text("Your collection is empty.", "Коллекция пуста.")).foregroundStyle(Theme.muted).padding(50) }
                }
            }.frame(minHeight: 180, maxHeight: 330)
            Toggle(L.text("Delete local files permanently", "Удалять локальные файлы безвозвратно"), isOn: $model.permanentDeletion).toggleStyle(.switch).font(.system(size: 12)).disabled(model.isDeleting)
            Text(L.text("Cloud items use the provider's deletion policy. Moving local files to Trash does not immediately free space.", "Облачные файлы удаляются по правилам провайдера. Перемещение в Корзину не освобождает место сразу."))
                .font(.system(size: 10)).foregroundStyle(Theme.muted)
            HStack {
                Text(ByteFormat.string(model.collectedBytes)).font(.system(size: 20, weight: .medium)); Spacer()
                Button(L.cancel) { model.showCollector = false }.buttonStyle(BloomButtonStyle())
                Button(L.text("Continue…", "Продолжить…")) { model.showCollector = false; model.showDeleteConfirmation = true }
                    .buttonStyle(BloomButtonStyle(destructive: true)).disabled(model.collector.isEmpty || model.isDeleting)
            }
        }.padding(28).frame(width: 650).background(Theme.background).foregroundStyle(Theme.text)
    }
}
