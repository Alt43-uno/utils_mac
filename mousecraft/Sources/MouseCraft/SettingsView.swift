import SwiftUI
import AppKit
import ServiceManagement
import MouseCraftCore

enum SettingsPane: String, CaseIterable {
    case overview = "Overview", scrolling = "Scrolling", buttons = "Buttons & Gestures", profiles = "Profiles", about = "About"
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
                                .buttonStyle(.borderless).accessibilityLabel("Dismiss message")
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
            Label(engine.running ? "Processing is active" : store.configuration.enabled ? "Not connected" : "Off",
                  systemImage: engine.running ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(engine.running ? Color.green : Color.secondary)
                .font(.callout).help(engine.status)
            Spacer()
            Toggle("Enable MouseCraft", isOn: $store.configuration.enabled)
                .toggleStyle(.switch).controlSize(.small)
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var connectionNotice: some View {
        if store.configuration.enabled && !engine.running {
            SwiftUI.Section {
                Label(engine.status, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.headline)
                if !engine.accessibility {
                    Button("Set Up Accessibility", action: engine.openAccessibility)
                }
                Button("Check Connection", action: engine.refresh)
            } footer: {
                detail(engine.conflict
                     ? "Turn off mouse processing in Mac Mouse Fix to prevent both apps from modifying the same events."
                     : "Settings take effect once MouseCraft is connected. Grant permissions to the installed copy in macOS System Settings.")
            }
        }
    }

    private var overview: some View {
        Group {
            card("Connection", subtitle: "Grant permissions in macOS System Settings. MouseCraft checks the connection automatically after access is granted.") {
                permissionRow("Accessibility", granted: engine.accessibility, action: engine.openAccessibility)
                permissionRow("Input Monitoring", granted: engine.inputMonitoring, action: engine.openInputMonitoring)
                Button("Check Permissions and Connection", action: engine.refresh)
            }
            card("Your Settings") {
                summaryRow("Scrolling", value: store.configuration.scroll.enabled ? "\(store.configuration.scroll.smoothness.title) · ×\(String(format: "%.1f", store.configuration.scroll.speed))" : "Off", pane: .scrolling)
                summaryRow("Buttons & Gestures", value: store.configuration.buttonsEnabled ? "\(store.configuration.rules.count) assignments" : "Off", pane: .buttons)
                summaryRow("App Profiles", value: "\(store.configuration.profiles.count)", pane: .profiles)
            }
            card("Startup") {
                loginToggle
            }
            SwiftUI.Section {
                DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                    LabeledContent("Last Event", value: engine.lastInput)
                    LabeledContent("Scroll Wheel", value: "Received \(engine.receivedScrolls) · processed \(engine.processedScrolls)")
                    LabeledContent("Continuous Events Skipped", value: "\(engine.skippedContinuousScrolls)")
                    LabeledContent("Active App", value: engine.activeApplication)
                    Text(Bundle.main.bundleURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } footer: {
                detail("Settings and events stay on your Mac. No telemetry.")
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open System Settings", action: action).accessibilityLabel("Configure \(title)")
            }
        }
    }

    private func summaryRow(_ title: String, value: String, pane: SettingsPane) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Button { navigation.pane = pane } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless).accessibilityLabel("Configure \(title)")
        }
    }

    private var buttons: some View {
        Group {
            card("Button Processing", subtitle: store.configuration.buttonsEnabled
                 ? "Assignments intercept mouse buttons. Turn off this section to pan a canvas with the middle button."
                 : "Middle-button clicks, holds, and drags pass through to apps. Smooth scrolling stays active and your assignments are saved.") {
                Toggle("Enable Buttons & Gestures", isOn: $store.configuration.buttonsEnabled).toggleStyle(.switch)
            }
            RulesEditor(rules: $store.configuration.rules, store: store)
                .disabled(!store.configuration.buttonsEnabled)
            card("Gesture Recognition") {
                Toggle("Keep the Pointer Still During Gestures", isOn: $store.configuration.lockPointer)
                valueSlider("Hold", value: $store.configuration.holdDelay, range: 0.15...1.2, unit: "s")
                valueSlider("Drag Threshold", value: $store.configuration.dragThreshold, range: 8...100, unit: "px")
            }.disabled(!store.configuration.buttonsEnabled)
            SwiftUI.Section {
                DisclosureGroup("Using a Three-Button Mouse") {
                    Text("Pressing the scroll wheel is button 3. The default preset uses a click for middle click, a double click for Look Up, and a hold for Quick Look.")
                    Text("Hold the scroll wheel and move the mouse: up for Mission Control, down for App Exposé, and left or right to switch desktops.")
                    Text("Hold and turn the wheel to zoom. Hold Option while holding the wheel and moving the mouse to scroll in any direction.")
                    Text("A single click waits for the double-click interval. Shift-click the wheel for an immediate middle click.")
                }
            } footer: {
                detail("Left and right buttons cannot be reassigned. Other button numbers appear in Diagnostics.")
            }
        }
    }

    private var scrollPreview: some View {
        card("Test Scrolling", subtitle: "Scroll this list with the wheel. Hold Shift to scroll horizontally or Option for precise scrolling.") {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(1...24, id: \.self) { i in
                        HStack(spacing: 16) {
                            Text(String(format: "%02d", i)).monospacedDigit().foregroundStyle(.secondary)
                            Text(["Smooth starts. Precise stops.", "Your settings stay on your Mac.", "A small movement. A long page."][i % 3])
                        }.frame(width: 680, alignment: .leading)
                    }
                }.padding(12)
            }.frame(height: 150).accessibilityLabel("Scrolling test list")
        }
    }

    private var loginToggle: some View {
        Toggle("Open at Login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { enabled in
            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { store.message = "Login item: \(error.localizedDescription)" }
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
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")").foregroundStyle(.secondary)
                        Text("Free · Open Source · MIT").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            card("Settings", subtitle: "Export your settings to make a backup or transfer them to another Mac.") {
                HStack {
                    Button("Export Settings…", action: store.exportSettings)
                    Button("Import Settings…", action: store.importSettings)
                }
            }
            card("App Behavior", subtitle: "MouseCraft stays in the menu bar when you close this window. Quit using the app menu.") {
                loginToggle
            }
            SwiftUI.Section {
                DisclosureGroup("Compatibility") {
                    Text("macOS 13 or later. Supports wheel mice and buttons 3–32. Trackpad and high-resolution wheel events pass through unchanged.")
                    Text("Native pinch, Smart Zoom, and swipe gestures are experimental. Behavior varies by app. Interactive Spaces transitions are not available yet.")
                    Text("On macOS versions without Launchpad, the Applications folder opens instead.")
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
                .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
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
            card("Scrolling", subtitle: "Adjusts discrete scroll-wheel events. Trackpad behavior stays unchanged.") {
                Toggle("Enable Scroll Processing", isOn: $settings.enabled).toggleStyle(.switch)
                Picker("Smoothness", selection: $settings.smoothness) {
                    ForEach(Smoothness.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                valueSlider("Speed", value: $settings.speed, range: 0.1...4, unit: "×")
                Toggle("Reverse Scrolling Direction", isOn: $settings.reverse)
                Toggle("Improve Precision When Scrolling Slowly", isOn: $settings.precision)
            }
            card("Wheel & Keyboard", subtitle: "Choose None to disable a modifier action.") {
                modifierPicker("Horizontal Scrolling", selection: $settings.horizontalModifier)
                modifierPicker("Zoom", selection: $settings.zoomModifier)
                modifierPicker("Fast Scrolling ×3", selection: $settings.fastModifier)
                modifierPicker("Precise Scrolling ×0.25", selection: $settings.preciseModifier)
            }
            SwiftUI.Section {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    Toggle("Simulate a Trackpad", isOn: $settings.simulateTrackpad)
                    Toggle("Native Pinch", isOn: $settings.nativeZoom)
                    Text("Trackpad simulation adds scroll phases. Native Pinch replaces zoom shortcuts with experimental macOS gestures. Test it in the apps you use.")
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
        card("Assignments", subtitle: "Modifier combinations take priority. Holding or dragging cancels the click.") {
            HStack { Button("Add Assignment", systemImage: "plus") { editing = ButtonRule() }; Spacer()
                Menu("Presets") {
                    Button("3 Buttons · Wheel & Gestures") { rules = Configuration.threeButtonRules }
                    Button("5 Buttons · macOS Gestures") { rules = Configuration.defaultRules }
                    Button("3 Buttons · Native Gestures · Experimental") {
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
                    Button("Browser: Back / Forward") { rules = [ButtonRule(button: 4, action: MouseAction(.back)), ButtonRule(button: 5, action: MouseAction(.forward))] }
                    Button("360° Scrolling on Button 5") { rules = [ButtonRule(button: 4, action: MouseAction(.back)), ButtonRule(button: 5, trigger: .pan)] }
                    Button("5 Buttons · Native Gestures · Experimental") {
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
                    Button("Clear Assignments") { rules = [] }
                }
            }
            if rules.isEmpty { Text("All buttons work normally. Add your first assignment.").foregroundStyle(.secondary).padding(.vertical, 14) }
            ForEach(rules) { rule in
                HStack(spacing: 12) {
                    Text("\(rule.button)").font(.system(.headline, design: .rounded)).frame(width: 30, height: 30).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.trigger.title).font(.callout.weight(.medium))
                        Text(modifierTitle(rule.modifiers) + rule.action.kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { editing = rule } label: { Image(systemName: "pencil") }.help("Edit").accessibilityLabel("Edit assignment for button \(rule.button)")
                    Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }.help("Delete").accessibilityLabel("Delete assignment for button \(rule.button)")
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
            Text("Button Assignment").font(.title2.weight(.semibold))
            Form {
                Picker("Button", selection: $rule.button) { ForEach(3...32, id: \.self) { Text($0 == 3 ? "3 · Scroll Wheel" : "\($0)").tag($0) } }
                Picker("Mouse Gesture", selection: $rule.trigger) { ForEach(Trigger.allCases) { Text($0.title).tag($0) } }
                HStack { Text("With Modifiers"); Spacer(); ForEach(Modifier.allCases.filter { $0 != .none }) { modifier in
                    Toggle(modifier.title.components(separatedBy: " ")[0], isOn: Binding(get: { rule.modifiers & modifier.rawValue != 0 }, set: { enabled in
                        if enabled { rule.modifiers |= modifier.rawValue } else { rule.modifiers &= ~modifier.rawValue }
                    })).toggleStyle(.button)
                } }
                if rule.trigger == .pan { Text("Scroll in any direction. The action below is not used.").foregroundStyle(.secondary) }
                else { Picker("Action", selection: $rule.action.kind) { ForEach(ActionKind.allCases) { Text($0.title).tag($0) } } }
                if rule.action.kind == .shortcut && rule.trigger != .pan {
                    ShortcutRecorder(keyCode: $rule.action.keyCode, modifiers: $rule.action.modifiers).frame(height: 42)
                }
                if rule.action.kind == .openApplication && rule.trigger != .pan {
                    HStack { Text(rule.action.applicationPath.isEmpty ? "No App Selected" : URL(fileURLWithPath: rule.action.applicationPath).lastPathComponent).lineLimit(1)
                        Spacer(); Button("Choose…") { let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
                            if panel.runModal() == .OK, let url = panel.url { rule.action.applicationPath = url.path }
                        } }
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { onSave(rule) }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 560, height: 470)
    }
}

struct ProfilesView: View {
    @ObservedObject var store: SettingsStore
    var body: some View {
        Group {
            card("App Profiles", subtitle: "A profile applies to the active app. Other apps use the global settings.") {
                Button("Add App…", systemImage: "plus", action: store.addProfile)
                if store.configuration.profiles.isEmpty {
                    Label("No App Profiles", systemImage: "app.badge").foregroundStyle(.secondary)
                    Text("Add an app to customize its scrolling or exclude it from processing.").foregroundStyle(.secondary)
                }
            }
            ForEach($store.configuration.profiles) { $profile in
                card(profile.name) {
                    Toggle("Leave Mouse Input Unchanged", isOn: $profile.bypass)
                    if !profile.bypass {
                        Toggle("Custom Scrolling", isOn: Binding(get: { profile.scroll != nil }, set: { profile.scroll = $0 ? store.configuration.scroll : nil }))
                        Toggle("Custom Button Assignments", isOn: Binding(get: { profile.rules != nil }, set: { profile.rules = $0 ? store.configuration.rules : nil }))
                    }
                    Button("Delete Profile", role: .destructive) { store.configuration.profiles.removeAll { $0.id == profile.id } }
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
        if !view.recording { view.title = "\(modifierTitle(modifiers))Key \(keyCode) · click to record" }
    }
}

private final class ShortcutField: NSButton {
    var record: (UInt16, UInt64) -> Void = { _, _ in }
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() { super.init(frame: .zero); bezelStyle = .rounded; target = self; action = #selector(beginRecording) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func beginRecording() { recording = true; title = "Press a shortcut · Esc to cancel"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        recording = false
        if event.keyCode != 53 { record(event.keyCode, UInt64(event.modifierFlags.rawValue) & Modifier.mask) }
        title = "Shortcut Recorded"; window?.makeFirstResponder(nil)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }; return super.performKeyEquivalent(with: event)
    }
}
