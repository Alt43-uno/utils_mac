import AppKit

/// Errors surfaced to the user. Every case carries a short, human readable
/// message plus an optional recovery hint.
enum AppError: LocalizedError {
    case screenRecordingPermissionDenied
    case noDisplaysAvailable
    case captureFailed(underlying: String)
    case cancelled
    case imageEncodingFailed
    case fileWriteFailed(url: URL, underlying: String)
    case fileReadFailed(url: URL)
    case hotkeyRegistrationFailed(name: String)
    case launchAtLoginFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission is required"
        case .noDisplaysAvailable:
            return "No displays are available for capture"
        case .captureFailed(let underlying):
            return "The screenshot could not be taken: \(underlying)"
        case .cancelled:
            return "Capture cancelled"
        case .imageEncodingFailed:
            return "The image could not be encoded"
        case .fileWriteFailed(let url, let underlying):
            return "Could not write \(url.lastPathComponent): \(underlying)"
        case .fileReadFailed(let url):
            return "Could not read \(url.lastPathComponent)"
        case .hotkeyRegistrationFailed(let name):
            return "The shortcut for “\(name)” could not be registered"
        case .launchAtLoginFailed(let underlying):
            return "Launch at login could not be changed: \(underlying)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return "Open System Settings › Privacy & Security › Screen & System Audio Recording and enable Screenshot Booster."
        case .hotkeyRegistrationFailed:
            return "Another application may already use this shortcut. Pick a different combination in Settings › Shortcuts."
        case .fileWriteFailed:
            return "Check that the destination folder exists and is writable."
        default:
            return nil
        }
    }

    /// Errors that are part of normal flow and should never raise an alert.
    var isSilent: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

enum ErrorPresenter {
    /// Presents a non-blocking alert. Safe to call from any actor context.
    @MainActor
    static func present(_ error: Error, extraButton: (title: String, action: () -> Void)? = nil) {
        if let appError = error as? AppError, appError.isSilent { return }
        Log.app.error("Presenting error: \(String(describing: error), privacy: .public)")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let hint = (error as? LocalizedError)?.recoverySuggestion {
            alert.informativeText = hint
        }
        alert.addButton(withTitle: "OK")
        if let extraButton {
            alert.addButton(withTitle: extraButton.title)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            extraButton?.action()
        }
    }
}
