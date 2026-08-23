import SwiftUI

/// Tabbed settings window content.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onHotkeyChange: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            ShortcutsSettingsPane(settings: settings, onHotkeyChange: onHotkeyChange)
                .tabItem { Label("Shortcuts", systemImage: "command") }

            ThumbnailSettingsPane(settings: settings)
                .tabItem { Label("Thumbnails", systemImage: "rectangle.stack") }

            AboutSettingsPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 520)
    }
}
