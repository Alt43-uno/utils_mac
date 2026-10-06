import SwiftUI
import AppKit
import DiskBloomCore

struct SnapshotsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: model.source?.name ?? "APFS")
                        Text(L.text("Behind the used space.", "Что скрывается за занятым местом."))
                            .font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                        Text(L.text("Snapshots, reclaimable storage and other volumes share your APFS container.", "Снимки, освобождаемое место и другие тома используют общий контейнер APFS."))
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }; Spacer()
                    Button { model.loadSnapshots() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(BloomButtonStyle()).disabled(model.loadingSnapshots || model.snapshotBusy)
                }
                if let c = model.capacity {
                    HStack(spacing: 15) {
                        capacityPanel(L.text("Free now", "Свободно сейчас"), c.free, "externaldrive.badge.checkmark")
                        capacityPanel(L.text("Available for use", "Доступно для записи"), c.available, "arrow.up.right")
                        capacityPanel(L.text("Reclaimable estimate", "Оценка освобождаемого"), c.purgeableEstimate, "arrow.triangle.2.circlepath")
                    }
                }
                Text(L.text("Reclaimable storage is an estimate provided by macOS, not a sum of file sizes. APFS clones and snapshots share blocks; deleting an item may not release its displayed size.", "Освобождаемое место оценивает macOS; это не сумма размеров файлов. Клоны APFS и снимки используют общие блоки: удаление объекта может освободить меньше указанного размера."))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
                if model.loadingSnapshots || model.snapshotBusy { HStack { ProgressView().controlSize(.small); Text(model.snapshotBusy ? L.text("Waiting for macOS…", "Ожидание macOS…") : L.text("Reading APFS metadata…", "Чтение метаданных APFS…")).font(.system(size: 12)) }.padding(20) }
                else if let error = model.snapshotError {
                    Panel { VStack(alignment: .leading, spacing: 10) {
                        Text(L.text("APFS information isn't available for this location.", "Для этого расположения информация APFS недоступна.")).font(.system(size: 13, weight: .medium))
                        Text(error).font(.system(size: 11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                    } }
                } else {
                    Panel {
                        VStack(alignment: .leading, spacing: 17) {
                            HStack { Text(L.snapshots).font(.system(size: 15, weight: .semibold)); Spacer(); Text("\(model.snapshots.count)").foregroundStyle(Theme.muted) }
                            if model.snapshots.isEmpty { Text(L.text("No local snapshots on this volume.", "На этом томе нет локальных снимков.")).font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.vertical, 9) }
                            ForEach(model.snapshots) { snapshot in
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.secondary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(snapshot.name).font(.system(size: 11, weight: .medium)).textSelection(.enabled)
                                        Text(snapshot.purgeable ? L.text("Purgeable · shared blocks, size unavailable", "Освобождаемый · общие блоки, размер неизвестен") : L.text("Protected snapshot", "Защищённый снимок")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                                    }; Spacer()
                                    if snapshot.isTimeMachine && snapshot.purgeable {
                                        IconButton(symbol: "trash", help: L.text("Delete this snapshot…", "Удалить этот снимок…")) { model.pendingSnapshot = snapshot }
                                    } else { Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                                }.padding(.vertical, 7)
                            }
                        }
                    }
                    if !model.otherVolumes.isEmpty {
                        Panel {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(L.text("Other volumes in this container", "Другие тома в этом контейнере")).font(.system(size: 14, weight: .semibold))
                                ForEach(Array(model.otherVolumes.enumerated()), id: \.offset) { _, volume in
                                    HStack { Image(systemName: "externaldrive").foregroundStyle(Theme.muted); Text(volume.0); Spacer(); Text(ByteFormat.string(volume.1)).foregroundStyle(Theme.secondary) }.font(.system(size: 12))
                                }
                            }
                        }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(L.text("Ask macOS to reclaim snapshot space", "Попросить macOS освободить место снимков")).font(.system(size: 13, weight: .medium))
                            Text(L.text("Attempts to reclaim up to 10 GB from local Time Machine snapshots.", "Попытка освободить до 10 ГБ из локальных снимков Time Machine.")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }; Spacer()
                        Button(L.text("Reclaim…", "Освободить…")) { model.confirmPurge = true }.buttonStyle(BloomButtonStyle()).disabled(model.snapshotBusy)
                    }.padding(.top, 8)
                }
            }.padding(35)
        }
        .alert(L.text("Delete this Time Machine snapshot?", "Удалить этот снимок Time Machine?"), isPresented: Binding(get: { model.pendingSnapshot != nil }, set: { if !$0 { model.pendingSnapshot = nil } })) {
            Button(L.cancel, role: .cancel) { model.pendingSnapshot = nil }
            Button(L.text("Delete snapshot", "Удалить снимок"), role: .destructive) {
                if let snapshot = model.pendingSnapshot { model.deleteSnapshot(snapshot) }; model.pendingSnapshot = nil
            }
        } message: { Text(L.text("This backup restore point will be lost permanently. macOS will request administrator authorization.", "Эта точка восстановления будет безвозвратно потеряна. macOS запросит права администратора.")) }
        .alert(L.text("Reclaim Time Machine snapshot space?", "Освободить место снимков Time Machine?"), isPresented: $model.confirmPurge) {
            Button(L.cancel, role: .cancel) {}
            Button(L.text("Reclaim", "Освободить"), role: .destructive) { model.purgeSnapshots() }
        } message: { Text(L.text("macOS may remove local backup restore points. It decides how much can be released; 10 GB is a request, not a guarantee.", "macOS может удалить локальные точки восстановления. Объём выбирает система: 10 ГБ — запрос, а не гарантия.")) }
    }
    func capacityPanel(_ title: String, _ value: Int64, _ icon: String) -> some View {
        Panel { VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.accent)
            Text(ByteFormat.string(value)).font(.system(size: 22, weight: .medium)).monospacedDigit()
            Text(title).font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading) }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @AppStorage("language") private var language = "system"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Eyebrow(text: "DiskBloom")
                Text(L.settings).font(.system(size: 30, weight: .semibold)).tracking(-0.8)
                Panel {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Label(L.text("Language", "Язык"), systemImage: "globe"); Spacer()
                            Picker("", selection: $language) { Text(L.text("System", "Системный")).tag("system"); Text("Русский").tag("ru"); Text("English").tag("en") }.frame(width: 180)
                                .onChange(of: language) { _, _ in model.changeLanguage() }
                        }
                        Divider().overlay(Theme.line)
                        Toggle(L.text("Delete permanently instead of moving to Trash", "Удалять безвозвратно вместо перемещения в Корзину"), isOn: $model.permanentDeletion).toggleStyle(.switch).disabled(model.isDeleting)
                        Text(L.text("The default is recoverable deletion. Permanent deletion requires review and includes a five-second cancellation window.", "По умолчанию файлы можно восстановить из Корзины. Безвозвратное удаление требует проверки и оставляет пять секунд на отмену."))
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }.font(.system(size: 12))
                }
                Panel {
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: "lock.shield").font(.system(size: 26)).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L.access).font(.system(size: 15, weight: .semibold))
                            Text(L.text("Allow DiskBloom in System Settings → Privacy & Security → Full Disk Access, then restart it. Administrator privileges do not bypass this permission.", "Разрешите DiskBloom в Настройках системы → Конфиденциальность и безопасность → Полный доступ к диску, затем перезапустите приложение. Права администратора не заменяют это разрешение."))
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                            Button(L.text("Open System Settings", "Открыть настройки системы"), action: model.openFullDiskAccess).buttonStyle(BloomButtonStyle())
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L.text("Keyboard & gestures", "Клавиатура и жесты")).font(.system(size: 15, weight: .semibold))
                        shortcut("⌘O", L.folder); shortcut("⌘R", L.rescan); shortcut("Space", L.preview)
                        shortcut("⌘⌫", L.collect); shortcut("⌘↑ / Esc", L.text("Parent folder", "Родительская папка"))
                        shortcut("⌘[ / ⌘]", L.text("Back / forward", "Назад / вперёд")); shortcut("⌘E", L.text("Export report", "Экспорт отчёта"))
                        Text(L.text("Pinch the map to enter or leave a folder. Drop a Finder folder onto the window to scan it.", "Сведите или разведите пальцы на карте для навигации. Перетащите папку из Finder в окно для сканирования."))
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
                Text(L.text("DiskBloom 1.0 · Local scans stay on your Mac. No analytics, subscriptions or automatic cleaning. Cloud connections only contact the selected provider.", "DiskBloom 1.0 · Локальные сканы остаются на Mac. Без аналитики, подписок и автоматической очистки. Облачное подключение обращается только к выбранному провайдеру."))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
            }.padding(35).frame(maxWidth: 850)
        }
    }
    func shortcut(_ keys: String, _ title: String) -> some View {
        HStack { Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary); Spacer(); Text(keys).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text) }
    }
}

struct CloudView: View {
    @ObservedObject var model: AppModel
    @State<String?> private var pendingDisconnect: String? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: L.text("Your space, everywhere", "Ваше место повсюду"))
                HStack { Text(L.cloud).font(.system(size: 30, weight: .semibold)).tracking(-0.8); Spacer(); Button { model.refreshCloud() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(BloomButtonStyle()) }
                Text(L.text("Explore remote files without downloading them. Connect multiple accounts and use the same map and collection.", "Изучайте удалённые файлы без скачивания. Подключайте несколько аккаунтов и используйте привычные карту и коллекцию."))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineSpacing(4)
                HStack(spacing: 12) {
                    ForEach(["Dropbox", "Google Drive", "OneDrive", "Box"], id: \.self) { name in
                        VStack(spacing: 11) { Image(systemName: "cloud.fill").font(.system(size: 25)).foregroundStyle(Theme.accent); Text(name).font(.system(size: 12, weight: .medium)) }
                            .frame(maxWidth: .infinity).padding(.vertical, 26).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(.vertical, 9)
                if model.cloudBridge == nil {
                    Panel { VStack(alignment: .leading, spacing: 12) {
                        Text(L.text("Cloud engine is not bundled in this build.", "В этой сборке нет облачного модуля.")).font(.system(size: 14, weight: .medium))
                        Text(L.text("Build with Scripts/build_app.sh --cloud, or install rclone through Homebrew. Account tokens stay in your private Application Support folder.", "Соберите через Scripts/build_app.sh --cloud или установите rclone через Homebrew. Токены аккаунтов хранятся в вашей закрытой папке Application Support."))
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    } }
                } else {
                    if model.cloudLoading { ProgressView().controlSize(.small) }
                    ForEach(model.cloudRemotes, id: \.self) { remote in
                        Panel {
                            HStack(spacing: 15) {
                                Image(systemName: "cloud").font(.system(size: 24)).foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 6) { Text(String(remote.dropLast())).font(.system(size: 15, weight: .medium)); Text(L.text("Connected account", "Подключённый аккаунт")).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                                Spacer()
                                Button(L.scan) { model.scan(ScanSource(name: String(remote.dropLast()), path: remote, kind: .cloud)) }.buttonStyle(BloomButtonStyle(prominent: true))
                                IconButton(symbol: "xmark", help: L.text("Disconnect account", "Отключить аккаунт")) { pendingDisconnect = remote }
                            }
                        }
                    }
                    Button { model.showCloudConnect = true } label: { Label(L.text("Connect an account", "Подключить аккаунт"), systemImage: "plus") }.buttonStyle(BloomButtonStyle(prominent: true))
                }
                Text(L.text("Cloud sizes reflect provider metadata; shared-file quota rules may differ. For iCloud Drive, scan its local folder. Online-only files are not downloaded during a scan.", "Размеры основаны на метаданных провайдера; учёт квоты общих файлов может отличаться. Для iCloud Drive выберите его локальную папку. При сканировании онлайн-файлы не скачиваются."))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
            }.padding(35)
        }
        .onAppear { model.refreshCloud() }
        .alert(L.text("Disconnect this account?", "Отключить этот аккаунт?"), isPresented: Binding(get: { pendingDisconnect != nil }, set: { if !$0 { pendingDisconnect = nil } })) {
            Button(L.cancel, role: .cancel) { pendingDisconnect = nil }
            Button(L.text("Disconnect", "Отключить"), role: .destructive) {
                if let remote = pendingDisconnect { model.disconnectCloud(remote) }; pendingDisconnect = nil
            }
        } message: { Text(L.text("This removes local authorization. Your cloud files are kept. To revoke access fully, also remove rclone in your provider's account settings.", "Будет удалена локальная авторизация. Облачные файлы сохранятся. Для полного отзыва доступа удалите rclone в настройках аккаунта провайдера.")) }
    }
}
