import AppKit

/// Screen Recording (TCC) permission handling.
///
/// The awkward part of this permission is that macOS only applies a fresh grant
/// to a *newly launched* process: the running app keeps being denied, which
/// looks exactly like the grant never happened. Everything here exists to make
/// that state legible and one click away from fixed.
@MainActor
enum ScreenPermission {

    /// Non-prompting check.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system prompt. macOS only shows it once per signature, so a
    /// `false` result afterwards means the user has to go to System Settings.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Starts a fresh copy of the app and quits this one — the only reliable way
    /// to pick up a permission that was granted while the app was running.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                    ErrorPresenter.present(AppError.captureFailed(underlying: "the app could not restart itself"))
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Gate

    /// Ensures permission before a capture. Returns `false` when the caller
    /// should abort.
    static func ensureGranted(settings: SettingsStore) -> Bool {
        if isGranted { return true }

        if !settings.hasRequestedScreenPermission {
            // The system dialog explains itself; stacking our own alert on top
            // of it would only get in the way. Watch for the grant instead.
            settings.hasRequestedScreenPermission = true
            request()
            Log.capture.info("Requested Screen Recording permission for the first time")
            if isGranted { return true }
            beginWatchingForGrant()
            return false
        }

        request()
        if isGranted { return true }

        presentDeniedAlert()
        return false
    }

    // MARK: - Alerts

    /// Shown when the app is not allowed to record the screen.
    static func presentDeniedAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screenshot Booster needs Screen Recording permission"
        alert.informativeText = """
        Enable Screenshot Booster under Privacy & Security › Screen & System Audio Recording.

        macOS only applies the permission to a freshly launched app, so reopen \
        Screenshot Booster once you have enabled it.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit and Reopen")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSystemSettings()
            beginWatchingForGrant()
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    /// Shown when the permission is in place but this process still cannot
    /// capture — the classic "granted while running" case.
    static func presentRelaunchAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Reopen Screenshot Booster to finish setting up"
        alert.informativeText = """
        Screen Recording is allowed, but macOS only hands the permission to an \
        app when it launches. Reopening takes a second and your pinned \
        screenshots are kept.
        """
        alert.addButton(withTitle: "Quit and Reopen")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    // MARK: - Watching for the grant

    private static var watchDeadline: Date?

    /// Polls for the permission after sending the user to System Settings, and
    /// offers to reopen the app the moment it appears.
    static func beginWatchingForGrant(timeout: TimeInterval = 120) {
        // Extend an existing watch instead of stacking a second poller.
        let isWatching = watchDeadline.map { $0 > Date() } ?? false
        watchDeadline = Date().addingTimeInterval(timeout)
        guard !isWatching else { return }
        scheduleWatchTick()
    }

    private static func scheduleWatchTick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                guard let deadline = watchDeadline else { return }
                if isGranted {
                    watchDeadline = nil
                    Log.capture.info("Screen Recording permission appeared; offering a relaunch")
                    presentRelaunchAlert()
                    return
                }
                guard Date() < deadline else {
                    watchDeadline = nil
                    return
                }
                scheduleWatchTick()
            }
        }
    }
}
