import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build(target: self)
        coordinator.start()
        Log.app.info("Screenshot Booster launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutDown()
    }

    /// The app lives in the menu bar; closing the last editor must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu actions

    @objc func showSettings(_ sender: Any?) {
        coordinator.showSettings()
    }

    @objc func captureFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = CaptureMode(rawValue: raw) else { return }
        coordinator.capture(mode)
    }
}
