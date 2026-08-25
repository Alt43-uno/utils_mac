import AppKit

/// Builds the application menu.
///
/// The app has no Dock icon, but editor windows still need a real main menu so
/// ⌘Z, ⌘C, ⌘S and ⌘W behave the way people expect.
@MainActor
enum MainMenuBuilder {

    static func build(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem(target: target))
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(captureMenuItem(target: target))
        mainMenu.addItem(windowMenuItem())
        return mainMenu
    }

    // MARK: - Menus

    private static func applicationMenuItem(target: AppDelegate) -> NSMenuItem {
        let appName = "Screenshot Booster"
        let menu = NSMenu(title: appName)
        menu.addItem(withTitle: "About \(appName)",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(AppDelegate.showSettings(_:)),
                                  keyEquivalent: ",")
        settings.target = target
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(appName)",
                     action: #selector(NSApplication.hide(_:)),
                     keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appName)",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Save", action: #selector(EditorWindowController.saveDocument(_:)), keyEquivalent: "s")

        let saveAs = NSMenuItem(title: "Save As…", action: #selector(EditorWindowController.saveDocumentAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAs)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: #selector(EditorWindowController.undo(_:)), keyEquivalent: "z")

        let redo = NSMenuItem(title: "Redo", action: #selector(EditorWindowController.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        let delete = NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "\u{8}")
        delete.keyEquivalentModifierMask = []
        menu.addItem(delete)

        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")
        menu.addItem(withTitle: "Zoom In",
                     action: #selector(EditorWindowController.zoomIn(_:)),
                     keyEquivalent: "+")
        menu.addItem(withTitle: "Zoom Out",
                     action: #selector(EditorWindowController.zoomOut(_:)),
                     keyEquivalent: "-")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Actual Size",
                     action: #selector(EditorWindowController.actualSize(_:)),
                     keyEquivalent: "0")
        menu.addItem(withTitle: "Zoom to Fit",
                     action: #selector(EditorWindowController.zoomToFit(_:)),
                     keyEquivalent: "9")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func captureMenuItem(target: AppDelegate) -> NSMenuItem {
        let menu = NSMenu(title: "Capture")
        for mode in CaptureMode.allCases {
            let item = NSMenuItem(title: mode.title,
                                  action: #selector(AppDelegate.captureFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = target
            item.representedObject = mode.rawValue
            menu.addItem(item)
        }
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front",
                     action: #selector(NSApplication.arrangeInFront(_:)),
                     keyEquivalent: "")

        let item = NSMenuItem()
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }
}
