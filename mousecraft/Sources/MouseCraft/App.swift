import AppKit
import SwiftUI
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSToolbarDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private let store = SettingsStore()
    private var engine: MouseEngine!
    private let navigation = SettingsNavigation()
    private var subscriptions = Set<AnyCancellable>()
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSWorkspace.shared.runningApplications.filter({ $0.bundleIdentifier == Bundle.main.bundleIdentifier }).count > 1 {
            NSApp.terminate(nil); return
        }
        engine = MouseEngine(store: store)
        let menu = NSMenu(); let appMenuItem = NSMenuItem(); let appMenu = NSMenu()
        let preferences = NSMenuItem(title: "Настройки MouseCraft…", action: #selector(showSettings), keyEquivalent: ","); preferences.target = self
        appMenu.addItem(preferences); appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Завершить MouseCraft", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu; menu.addItem(appMenuItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; menu.addItem(editItem)
        let viewItem = NSMenuItem(); let viewMenu = NSMenu(title: "Вид")
        for (index, pane) in SettingsPane.allCases.enumerated() {
            let command = NSMenuItem(title: pane.rawValue, action: #selector(selectPaneFromMenu(_:)), keyEquivalent: String(index + 1))
            command.target = self; command.tag = index; viewMenu.addItem(command)
        }
        viewItem.submenu = viewMenu; menu.addItem(viewItem); NSApp.mainMenu = menu
        navigation.$pane.removeDuplicates().sink { [weak self] pane in
            self?.window?.toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
            self?.window?.title = "MouseCraft — \(pane.rawValue)"
        }.store(in: &subscriptions)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseCraft")
        item.button?.image?.isTemplate = true
        item.menu = NSMenu(); item.menu?.delegate = self; statusItem = item
        showSettings()
    }
    @objc private func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MouseCraft — \(navigation.pane.rawValue)"; window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 680, height: 550)
            window.toolbarStyle = .preference
            let toolbar = NSToolbar(identifier: "MouseCraftSettings")
            toolbar.delegate = self; toolbar.allowsUserCustomization = false
            toolbar.displayMode = .iconAndLabel
            window.toolbar = toolbar; toolbar.selectedItemIdentifier = navigation.pane.toolbarIdentifier
            window.contentView = NSHostingView(rootView: SettingsView(store: store, engine: engine, navigation: navigation))
            window.setFrameAutosaveName("MouseCraftSettingsWindow")
            window.center(); self.window = window
        }
        engine.refresh(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarIdentifier)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarIdentifier == identifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.rawValue; item.paletteLabel = pane.rawValue
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.rawValue)
        item.target = self; item.action = #selector(selectPaneFromToolbar(_:))
        return item
    }
    @objc private func selectPaneFromToolbar(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) else { return }
        navigation.pane = pane
    }
    @objc private func selectPaneFromMenu(_ sender: NSMenuItem) {
        guard SettingsPane.allCases.indices.contains(sender.tag) else { return }
        navigation.pane = SettingsPane.allCases[sender.tag]; showSettings()
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems(); menu.autoenablesItems = false
        let status = NSMenuItem(title: engine.status, action: nil, keyEquivalent: ""); status.isEnabled = false; menu.addItem(status)
        add(store.configuration.enabled ? "Приостановить MouseCraft" : "Включить MouseCraft", action: #selector(toggle), menu: menu)
        add("Настройки…", action: #selector(showSettings), menu: menu)
        menu.addItem(.separator()); add("Завершить MouseCraft", action: #selector(quit), menu: menu)
    }
    private func add(_ title: String, action: Selector, menu: NSMenu) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    @objc private func toggle() { store.configuration.enabled.toggle(); engine.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { engine?.stop() }
}
