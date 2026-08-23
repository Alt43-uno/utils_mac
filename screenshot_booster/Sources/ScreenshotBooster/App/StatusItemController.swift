import AppKit

/// Actions the menu bar item can trigger.
@MainActor
struct StatusItemActions {
    var capture: (CaptureMode) -> Void
    var showThumbnails: () -> Void
    var clearThumbnails: () -> Void
    var openSaveFolder: () -> Void
    var openSettings: () -> Void
    var hasPinnedScreenshots: () -> Bool
}

/// The menu bar presence. The app has no Dock icon, so this is its home.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private let settings: SettingsStore
    private let actions: StatusItemActions
    private var statusItem: NSStatusItem?

    init(settings: SettingsStore, actions: StatusItemActions) {
        self.settings = settings
        self.actions = actions
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot Booster")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Screenshot Booster"
        item.menu = buildMenu()
        statusItem = item
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        for mode in [CaptureMode.area, .window, .fullScreen] {
            let item = NSMenuItem(title: mode.title, action: #selector(captureAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil)
            applyShortcut(to: item, mode: mode)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(item(title: "Show Pinned Screenshots", action: #selector(showThumbnailsAction)))
        menu.addItem(item(title: "Clear Pinned Screenshots", action: #selector(clearThumbnailsAction)))
        menu.addItem(item(title: "Open Save Folder", action: #selector(openFolderAction)))

        menu.addItem(.separator())
        let settingsItem = item(title: "Settings…", action: #selector(settingsAction))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        let quitItem = item(title: "Quit Screenshot Booster", action: #selector(quitAction))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        return menu
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Mirrors the configured global shortcut into the menu so it is
    /// discoverable, when the key can be expressed as a menu equivalent.
    private func applyShortcut(to item: NSMenuItem, mode: CaptureMode) {
        guard let combo = settings.hotkeys[mode] else {
            item.keyEquivalent = ""
            return
        }
        let name = KeyCodeNames.name(for: combo.keyCode)
        guard name.count == 1 else {
            item.keyEquivalent = ""
            return
        }
        item.keyEquivalent = name.lowercased()
        item.keyEquivalentModifierMask = combo.modifiers
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        let hasPins = actions.hasPinnedScreenshots()
        for menuItem in menu.items {
            switch menuItem.action {
            case #selector(showThumbnailsAction), #selector(clearThumbnailsAction):
                menuItem.isEnabled = hasPins
            case #selector(captureAction(_:)):
                if let raw = menuItem.representedObject as? String, let mode = CaptureMode(rawValue: raw) {
                    applyShortcut(to: menuItem, mode: mode)
                }
                menuItem.isEnabled = true
            default:
                menuItem.isEnabled = true
            }
        }
    }

    // MARK: - Actions

    @objc private func captureAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = CaptureMode(rawValue: raw) else { return }
        actions.capture(mode)
    }

    @objc private func showThumbnailsAction() { actions.showThumbnails() }
    @objc private func clearThumbnailsAction() { actions.clearThumbnails() }
    @objc private func openFolderAction() { actions.openSaveFolder() }
    @objc private func settingsAction() { actions.openSettings() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
