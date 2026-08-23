import AppKit
import SwiftUI

// MARK: - General

struct GeneralSettingsPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("After a capture") {
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboardAfterCapture)
                Toggle("Also save a file automatically", isOn: $settings.autoSaveToDisk)
                Toggle("Play a sound", isOn: $settings.playsCaptureSound)
            }

            Section("Files") {
                LabeledContent("Save folder") {
                    HStack(spacing: 8) {
                        Text(settings.saveDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if settings.imageFormat == .jpeg {
                    LabeledContent("JPEG quality") {
                        HStack {
                            Slider(value: $settings.jpegQuality, in: 0.4...1.0)
                            Text("\(Int(settings.jpegQuality * 100))%")
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in updateLaunchAtLogin(newValue) }
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if LaunchAtLogin.requiresApproval {
                    HStack {
                        Text("macOS is blocking the login item.")
                            .foregroundStyle(.secondary)
                        Button("Open Login Items") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                    .font(.callout)
                }
                Toggle("Include the pointer in captures", isOn: $settings.showsCursorInCaptures)
                Toggle("Hide Screenshot Booster's own windows from captures",
                       isOn: $settings.excludeOwnWindowsFromCapture)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectory
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.saveDirectory = url
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchError = nil
        } catch {
            launchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsPane: View {
    @ObservedObject var settings: SettingsStore
    let onHotkeyChange: () -> Void

    var body: some View {
        Form {
            Section("Global shortcuts") {
                ForEach(CaptureMode.allCases) { mode in
                    LabeledContent(mode.title) {
                        ShortcutRecorder(combo: binding(for: mode))
                            .frame(width: 150, height: 24)
                    }
                }
            }

            Section {
                HStack {
                    Text("Click a field and press the keys you want. ⌫ clears a shortcut.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        settings.resetHotkeysToDefaults()
                        onHotkeyChange()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for mode: CaptureMode) -> Binding<KeyCombo?> {
        Binding(
            get: { settings.hotkeys[mode] },
            set: { newValue in
                settings.setHotkey(newValue, for: mode)
                onHotkeyChange()
            }
        )
    }
}

// MARK: - Thumbnails

struct ThumbnailSettingsPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Placement") {
                Picker("Corner", selection: $settings.panelCorner) {
                    ForEach(PanelCorner.allCases) { corner in
                        Text(corner.title).tag(corner)
                    }
                }
                Picker("Display", selection: $settings.panelScreenPolicy) {
                    ForEach(PanelScreenPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
            }

            Section("Appearance") {
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $settings.thumbnailWidth, in: 110...280, step: 2)
                        Text("\(Int(settings.thumbnailWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Section("Persistence") {
                Toggle("Restore pinned screenshots after a restart", isOn: $settings.restorePinnedScreenshots)
                Text("Pinned screenshots never disappear on their own — close them with the ✕ button or the context menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    @State private var permissionGranted = ScreenPermission.isGranted

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Screen Recording") {
                    HStack(spacing: 8) {
                        Label(permissionGranted ? "Granted" : "Not granted",
                              systemImage: permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(permissionGranted ? Color.green : Color.orange)
                        Button("Open Settings") { ScreenPermission.openSystemSettings() }
                    }
                }
            }

            Section("Shortcuts inside the editor") {
                shortcutRow("V", "Select and move objects")
                shortcutRow("D · A · L · R · O", "Draw, arrow, line, rectangle, ellipse")
                shortcutRow("S · H · T", "Outline, highlighter, text")
                shortcutRow("B · P · C", "Blur, pixelate, crop")
                shortcutRow("⌘Z · ⇧⌘Z", "Undo and redo")
                shortcutRow("⌘C · ⌘S", "Copy and save")
            }
        }
        .formStyle(.grouped)
        .onAppear { permissionGranted = ScreenPermission.isGranted }
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 130, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
