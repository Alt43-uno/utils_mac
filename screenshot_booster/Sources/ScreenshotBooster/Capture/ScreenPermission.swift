import AppKit

/// Screen Recording (TCC) permission helpers.
enum ScreenPermission {
    /// Non-prompting check.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system prompt the first time; afterwards macOS only shows it
    /// again once the app is re-signed, so callers must handle a `false` result
    /// by pointing the user at System Settings.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Ensures permission, prompting and offering a shortcut to System Settings.
    /// Returns `false` when the caller should abort the capture.
    @MainActor
    static func ensureGranted() -> Bool {
        if isGranted { return true }
        if request(), isGranted { return true }

        ErrorPresenter.present(AppError.screenRecordingPermissionDenied,
                               extraButton: ("Open System Settings", { openSystemSettings() }))
        return false
    }
}
