import SwiftUI
import AppKit
import ServiceManagement
import MouseCraftCore

enum SettingsPane: String, CaseIterable {
    case overview = "Обзор", scrolling = "Прокрутка", buttons = "Кнопки и жесты", profiles = "Профили", about = "О приложении"
    var symbol: String {
        switch self {
        case .overview: return "gearshape"
        case .scrolling: return "arrow.up.arrow.down"
        case .buttons: return "computermouse"
        case .profiles: return "app.badge"
        case .about: return "info.circle"
        }
    }
    var toolbarIdentifier: NSToolbarItem.Identifier { .init("mousecraft.settings.\(self)") }
}

final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .overview
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var engine: MouseEngine
    @ObservedObject var navigation: SettingsNavigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                connectionNotice
                if let message = store.message {
                    SwiftUI.Section {
                        HStack(alignment: .top, spacing: 12) {
                            Label(message, systemImage: "info.circle")
                            Spacer(minLength: 8)
                            Button { store.message = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless).accessibilityLabel("Закрыть сообщение")
                        }
                    }
                }
                switch navigation.pane {
                case .overview: overview
                case .scrolling:
                    ScrollEditor(settings: $store.configuration.scroll)
                    scrollPreview
                case .buttons: buttons
                case .profiles: ProfilesView(store: store)
                case .about: about
                }
            }
            .formStyle(.grouped)
            .disclosureGroupStyle(SettingsDisclosureStyle())
            .id(navigation.pane)
            Divider()
            if reduceTransparency {
                statusBar.background(Color(nsColor: .windowBackgroundColor))
            } else {
                statusBar.background(.bar)
            }
        }
        .frame(minWidth: 680, minHeight: 550)
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(engine.running ? "Обработка работает" : store.configuration.enabled ? "Не подключено" : "Выключено",
                  systemImage: engine.running ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(engine.running ? Color.green : Color.secondary)
                .font(.callout).help(engine.status)
            Spacer()
            Toggle("Включить MouseCraft", isOn: $store.configuration.enabled)
                .toggleStyle(.switch).controlSize(.small)
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var connectionNotice: some View {
        if store.configuration.enabled && !engine.running {
            SwiftUI.Section {
                Label(engine.status, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.headline)
                if !engine.accessibility {
                    Button("Настроить Универсальный доступ", action: engine.openAccessibility)
                }
                Button("Проверить подключение", action: engine.refresh)
            } footer: {
                detail(engine.conflict
                     ? "Выключите обработку в Mac Mouse Fix, чтобы два приложения не меняли одни и те же события."
                     : "Пока MouseCraft не подключён, настройки не влияют на мышь. Разрешите доступ установленной копии в настройках macOS.")
            }
        }
    }

    private var overview: some View {
        Group {
            card("Подключение", subtitle: "Разрешения выдаются в настройках macOS. После выдачи доступа MouseCraft проверяет подключение автоматически.") {
                permissionRow("Универсальный доступ", granted: engine.accessibility, action: engine.openAccessibility)
                permissionRow("Мониторинг ввода", granted: engine.inputMonitoring, action: engine.openInputMonitoring)
                Button("Проверить разрешения и подключение", action: engine.refresh)
            }
            card("Ваши настройки") {
                summaryRow("Прокрутка", value: store.configuration.scroll.enabled ? "\(store.configuration.scroll.smoothness.title) · ×\(String(format: "%.1f", store.configuration.scroll.speed))" : "Выключена", pane: .scrolling)
                summaryRow("Кнопки и жесты", value: store.configuration.buttonsEnabled ? "\(store.configuration.rules.count) назначений" : "Выключены", pane: .buttons)
                summaryRow("Профили приложений", value: "\(store.configuration.profiles.count)", pane: .profiles)
            }
            card("Запуск") {
                loginToggle
            }
            SwiftUI.Section {
                DisclosureGroup("Диагностика", isExpanded: $showDiagnostics) {
                    LabeledContent("Последнее событие", value: engine.lastInput)
                    LabeledContent("Колесо", value: "Получено \(engine.receivedScrolls) · обработано \(engine.processedScrolls)")
                    LabeledContent("Непрерывных пропущено", value: "\(engine.skippedContinuousScrolls)")
                    LabeledContent("Активное приложение", value: engine.activeApplication)
                    Text(Bundle.main.bundleURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } footer: {
                detail("Настройки и события остаются на вашем Mac. Телеметрии нет.")
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Разрешено", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Открыть настройки", action: action).accessibilityLabel("Настроить \(title)")
            }
        }
    }

    private func summaryRow(_ title: String, value: String, pane: SettingsPane) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Button { navigation.pane = pane } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless).accessibilityLabel("Настроить \(title)")
        }
    }

    private var buttons: some View {
        Group {
            card("Обработка кнопок", subtitle: store.configuration.buttonsEnabled
                 ? "Назначения перехватывают кнопки мыши. Для перемещения по холсту средней кнопкой отключите этот раздел."
                 : "Средняя кнопка, удержание и движение передаются приложениям без перехвата. Плавная прокрутка продолжает работать; назначения сохранены.") {
                Toggle("Включить кнопки и жесты", isOn: $store.configuration.buttonsEnabled).toggleStyle(.switch)
            }
            RulesEditor(rules: $store.configuration.rules, store: store)
                .disabled(!store.configuration.buttonsEnabled)
            card("Распознавание жестов") {
                Toggle("Фиксировать указатель во время жеста", isOn: $store.configuration.lockPointer)
                valueSlider("Удержание", value: $store.configuration.holdDelay, range: 0.15...1.2, unit: "с")
                valueSlider("Порог движения", value: $store.configuration.dragThreshold, range: 8...100, unit: "px")
            }.disabled(!store.configuration.buttonsEnabled)
            SwiftUI.Section {
                DisclosureGroup("Как пользоваться мышью с 3 кнопками") {
                    Text("Нажатие колеса — кнопка 3. В стартовом пресете: щелчок — средняя кнопка, двойной — словарь, удержание — Quick Look.")
                    Text("Удерживайте колесо и двигайте мышь: вверх — Mission Control, вниз — окна приложения, влево и вправо — рабочие столы.")
                    Text("Удержание с вращением колеса меняет масштаб. Option с удержанием и движением включает прокрутку 360°.")
                    Text("Одинарный щелчок ждёт интервал двойного. Shift с нажатием колеса выполняет средний щелчок сразу.")
                }
            } footer: {
                detail("Левая и правая кнопки не переназначаются. Номера остальных кнопок видны в диагностике.")
            }
        }
    }

    private var scrollPreview: some View {
        card("Проверка прокрутки", subtitle: "Прокрутите список колесом. Shift — горизонтально, Option — точнее.") {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(1...24, id: \.self) { i in
                        HStack(spacing: 16) {
                            Text(String(format: "%02d", i)).monospacedDigit().foregroundStyle(.secondary)
                            Text(["Плавное начало. Точная остановка.", "Настройки остаются на вашем Mac.", "Короткое движение — длинная страница."][i % 3])
                        }.frame(width: 680, alignment: .leading)
                    }
                }.padding(12)
            }.frame(height: 150).accessibilityLabel("Список для проверки прокрутки")
        }
    }

    private var loginToggle: some View {
        Toggle("Открывать при входе в macOS", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { enabled in
            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { store.message = "Автозапуск: \(error.localizedDescription)" }
        }))
    }

    private var about: some View {
        Group {
            SwiftUI.Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MouseCraft").font(.title2.weight(.semibold))
                        Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")").foregroundStyle(.secondary)
                        Text("Бесплатно · открытый исходный код · MIT").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            card("Настройки", subtitle: "Экспортируйте настройки для резервной копии или переноса на другой Mac.") {
                HStack {
                    Button("Экспорт настроек…", action: store.exportSettings)
                    Button("Импорт настроек…", action: store.importSettings)
                }
            }
            card("Работа приложения", subtitle: "Закрытие окна оставляет MouseCraft в строке меню. Завершить работу можно через меню приложения.") {
                loginToggle
            }
            SwiftUI.Section {
                DisclosureGroup("Совместимость") {
                    Text("macOS 13 и новее. Колёсные мыши и кнопки 3–32. События трекпада и высокоточных колёс не изменяются.")
                    Text("Нативные Pinch, Smart Zoom и свайпы экспериментальны. Их поведение зависит от приложения. Интерактивные переходы Spaces ещё не реализованы.")
                    Text("На macOS без Launchpad открывается папка «Программы».")
                }
            }
        }
    }
}

private func card<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    SwiftUI.Section {
        content()
    } header: {
        Text(title)
    } footer: {
        if let subtitle { detail(subtitle) }
    }
}

private func detail(_ text: String) -> some View {
    Text(text).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
}

/// Use the entire row as the disclosure target, including its label. SwiftUI's
/// default macOS triangle otherwise makes this a very small pointer target.
private struct SettingsDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? "Развёрнуто" : "Свёрнуто")
            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 12) { configuration.content }
                    .padding(.leading, 20)
            }
        }
    }
}

private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
    HStack(spacing: 16) {
        Text(title).frame(width: 128, alignment: .leading)
        Slider(value: value, in: range).accessibilityLabel(title)
        Text("\(value.wrappedValue, specifier: "%.2f") \(unit)")
            .monospacedDigit().foregroundStyle(.secondary).frame(width: 76, alignment: .trailing)
    }
}

struct ScrollEditor: View {
    @Binding var settings: ScrollSettings
    @State private var advanced = false
    var body: some View {
        Group {
            card("Прокрутка", subtitle: "Меняет дискретные события колеса. Поведение трекпада сохраняется.") {
                Toggle("Обрабатывать колесо", isOn: $settings.enabled).toggleStyle(.switch)
                Picker("Плавность", selection: $settings.smoothness) {
                    ForEach(Smoothness.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                valueSlider("Скорость", value: $settings.speed, range: 0.1...4, unit: "×")
                Toggle("Обратное направление", isOn: $settings.reverse)
                Toggle("Точнее при медленном вращении", isOn: $settings.precision)
            }
            card("Колесо и клавиатура", subtitle: "Выберите «Нет», чтобы отключить действие модификатора.") {
                modifierPicker("Горизонтальная прокрутка", selection: $settings.horizontalModifier)
                modifierPicker("Масштабирование", selection: $settings.zoomModifier)
                modifierPicker("Быстрая прокрутка ×3", selection: $settings.fastModifier)
                modifierPicker("Точная прокрутка ×0.25", selection: $settings.preciseModifier)
            }
            SwiftUI.Section {
                DisclosureGroup("Дополнительно", isExpanded: $advanced) {
                    Toggle("Симуляция трекпада", isOn: $settings.simulateTrackpad)
                    Toggle("Нативный Pinch", isOn: $settings.nativeZoom)
                    Text("Симуляция добавляет фазы прокрутки. Нативный Pinch заменяет клавиши масштаба экспериментальными жестами macOS; проверьте его в нужных приложениях.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func modifierPicker(_ title: String, selection: Binding<Modifier>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Modifier.allCases) { Text($0.title).tag($0) }
        }
    }
}

struct RulesEditor: View {
    @Binding var rules: [ButtonRule]
    @ObservedObject var store: SettingsStore
    @State private var editing: ButtonRule?
    var body: some View {
        card("Назначения", subtitle: "Комбинация с модификатором имеет приоритет. Удержание и жест отменяют щелчок.") {
            HStack { Button("Добавить назначение", systemImage: "plus") { editing = ButtonRule() }; Spacer()
                Menu("Пресеты") {
                    Button("3 кнопки · колесо и жесты") { rules = Configuration.threeButtonRules }
                    Button("5 кнопок · жесты macOS") { rules = Configuration.defaultRules }
                    Button("3 кнопки · нативные жесты · экспериментально") {
                        var native = Configuration.threeButtonRules
                        for i in native.indices {
                            switch native[i].action.kind {
                            case .resetZoom: native[i].action = MouseAction(.smartZoom)
                            case .zoomIn: native[i].action = MouseAction(.nativeZoomIn)
                            case .zoomOut: native[i].action = MouseAction(.nativeZoomOut)
                            default: break
                            }
                        }
                        rules = native
                    }
                    Button("Браузер: назад / вперёд") { rules = [ButtonRule(button: 4, action: MouseAction(.back)), ButtonRule(button: 5, action: MouseAction(.forward))] }
                    Button("Прокрутка 360° на кнопке 5") { rules = [ButtonRule(button: 4, action: MouseAction(.back)), ButtonRule(button: 5, trigger: .pan)] }
                    Button("5 кнопок · нативные жесты · экспериментально") {
                        var native = Configuration.defaultRules
                        for i in native.indices where native[i].button == 5 {
                            switch native[i].trigger {
                            case .click: native[i].action = MouseAction(.smartZoom)
                            case .dragLeft: native[i].action = MouseAction(.swipeLeft)
                            case .dragRight: native[i].action = MouseAction(.swipeRight)
                            case .scrollUp: native[i].action = MouseAction(.nativeZoomIn)
                            case .scrollDown: native[i].action = MouseAction(.nativeZoomOut)
                            default: break
                            }
                        }
                        rules = native
                    }
                    Button("Очистить назначения") { rules = [] }
                }
            }
            if rules.isEmpty { Text("Все кнопки работают как обычно. Добавьте первое назначение.").foregroundStyle(.secondary).padding(.vertical, 14) }
            ForEach(rules) { rule in
                HStack(spacing: 12) {
                    Text("\(rule.button)").font(.system(.headline, design: .rounded)).frame(width: 30, height: 30).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.trigger.title).font(.callout.weight(.medium))
                        Text(modifierTitle(rule.modifiers) + rule.action.kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { editing = rule } label: { Image(systemName: "pencil") }.help("Изменить").accessibilityLabel("Изменить назначение кнопки \(rule.button)")
                    Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }.help("Удалить").accessibilityLabel("Удалить назначение кнопки \(rule.button)")
                }.padding(.vertical, 5)
            }
        }.sheet(item: $editing) { rule in
            RuleEditor(initial: rule) { newRule in
                var proposed = rules
                if let index = proposed.firstIndex(where: { $0.id == newRule.id }) { proposed[index] = newRule } else { proposed.append(newRule) }
                var check = Configuration(); check.rules = proposed
                do { _ = try check.validated(); rules = proposed; editing = nil }
                catch { store.message = error.localizedDescription; editing = nil }
            }
        }
    }
}

private func modifierTitle(_ flags: UInt64) -> String {
    let symbols = [(Modifier.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")].filter { flags & $0.0.rawValue != 0 }.map { $0.1 }.joined()
    return symbols.isEmpty ? "" : symbols + " · "
}

private struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: ButtonRule
    let onSave: (ButtonRule) -> Void
    init(initial: ButtonRule, onSave: @escaping (ButtonRule) -> Void) { _rule = State(initialValue: initial); self.onSave = onSave }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Назначение кнопки").font(.title2.weight(.semibold))
            Form {
                Picker("Кнопка", selection: $rule.button) { ForEach(3...32, id: \.self) { Text($0 == 3 ? "3 · Колесо" : "\($0)").tag($0) } }
                Picker("Действие мышью", selection: $rule.trigger) { ForEach(Trigger.allCases) { Text($0.title).tag($0) } }
                HStack { Text("С модификаторами"); Spacer(); ForEach(Modifier.allCases.filter { $0 != .none }) { modifier in
                    Toggle(modifier.title.components(separatedBy: " ")[0], isOn: Binding(get: { rule.modifiers & modifier.rawValue != 0 }, set: { enabled in
                        if enabled { rule.modifiers |= modifier.rawValue } else { rule.modifiers &= ~modifier.rawValue }
                    })).toggleStyle(.button)
                } }
                if rule.trigger == .pan { Text("Прокрутка в любом направлении. Действие ниже не используется.").foregroundStyle(.secondary) }
                else { Picker("Выполнить", selection: $rule.action.kind) { ForEach(ActionKind.allCases) { Text($0.title).tag($0) } } }
                if rule.action.kind == .shortcut && rule.trigger != .pan {
                    ShortcutRecorder(keyCode: $rule.action.keyCode, modifiers: $rule.action.modifiers).frame(height: 42)
                }
                if rule.action.kind == .openApplication && rule.trigger != .pan {
                    HStack { Text(rule.action.applicationPath.isEmpty ? "Приложение не выбрано" : URL(fileURLWithPath: rule.action.applicationPath).lastPathComponent).lineLimit(1)
                        Spacer(); Button("Выбрать…") { let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
                            if panel.runModal() == .OK, let url = panel.url { rule.action.applicationPath = url.path }
                        } }
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction); Button("Сохранить") { onSave(rule) }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 560, height: 470)
    }
}

struct ProfilesView: View {
    @ObservedObject var store: SettingsStore
    var body: some View {
        Group {
            card("Профили приложений", subtitle: "Профиль применяется к активному приложению. Остальные приложения используют общие настройки.") {
                Button("Добавить приложение…", systemImage: "plus", action: store.addProfile)
                if store.configuration.profiles.isEmpty {
                    Label("Профилей пока нет", systemImage: "app.badge").foregroundStyle(.secondary)
                    Text("Добавьте приложение, чтобы задать свою прокрутку или исключить его из обработки.").foregroundStyle(.secondary)
                }
            }
            ForEach($store.configuration.profiles) { $profile in
                card(profile.name) {
                    Toggle("Оставлять мышь без изменений", isOn: $profile.bypass)
                    if !profile.bypass {
                        Toggle("Своя прокрутка", isOn: Binding(get: { profile.scroll != nil }, set: { profile.scroll = $0 ? store.configuration.scroll : nil }))
                        Toggle("Свои назначения кнопок", isOn: Binding(get: { profile.rules != nil }, set: { profile.rules = $0 ? store.configuration.rules : nil }))
                    }
                    Button("Удалить профиль", role: .destructive) { store.configuration.profiles.removeAll { $0.id == profile.id } }
                }
                if !profile.bypass, profile.scroll != nil {
                    ScrollEditor(settings: Binding(get: { profile.scroll ?? store.configuration.scroll }, set: { profile.scroll = $0 }))
                }
                if !profile.bypass, profile.rules != nil {
                    RulesEditor(rules: Binding(get: { profile.rules ?? [] }, set: { profile.rules = $0 }), store: store)
                        .disabled(!store.configuration.buttonsEnabled)
                }
            }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt64
    func makeNSView(context: Context) -> ShortcutField { let view = ShortcutField(); updateNSView(view, context: context); return view }
    func updateNSView(_ view: ShortcutField, context: Context) {
        view.record = { code, flags in keyCode = code; modifiers = flags }
        if !view.recording { view.title = "\(modifierTitle(modifiers))Клавиша \(keyCode) · нажмите для записи" }
    }
}

private final class ShortcutField: NSButton {
    var record: (UInt16, UInt64) -> Void = { _, _ in }
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() { super.init(frame: .zero); bezelStyle = .rounded; target = self; action = #selector(beginRecording) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func beginRecording() { recording = true; title = "Нажмите сочетание клавиш · Esc — отмена"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        recording = false
        if event.keyCode != 53 { record(event.keyCode, UInt64(event.modifierFlags.rawValue) & Modifier.mask) }
        title = "Сочетание записано"; window?.makeFirstResponder(nil)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }; return super.performKeyEquivalent(with: event)
    }
}
