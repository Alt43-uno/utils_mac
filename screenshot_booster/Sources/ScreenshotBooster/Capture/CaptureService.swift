import AppKit
import ScreenCaptureKit

/// Wraps ScreenCaptureKit. All bitmaps come back at native Retina resolution.
///
/// Main-actor bound on purpose: the class reads `NSScreen` geometry and hands
/// `CGImage`s straight to the UI, and the expensive work happens out of process
/// inside ScreenCaptureKit anyway.
@MainActor
final class CaptureService {

    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Content

    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// ScreenCaptureKit reports a missing permission as `userDeclined` (-3801).
    /// If the system says the permission *is* granted, this process simply
    /// started before the grant and has to be relaunched.
    private static func mapped(_ error: Error) -> AppError {
        // -3801 is SCStreamError.userDeclined.
        let looksLikePermission = (error as NSError).code == -3801
        let granted = CGPreflightScreenCaptureAccess()

        guard looksLikePermission || !granted else {
            return .captureFailed(underlying: error.localizedDescription)
        }
        return granted ? .screenRecordingNeedsRelaunch : .screenRecordingPermissionDenied
    }

    /// Windows that make sense as capture targets, front-most first.
    func windowTargets() async throws -> [WindowTarget] {
        let content = try await shareableContent()
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return content.windows.compactMap { window -> WindowTarget? in
            guard window.isOnScreen else { return nil }
            guard window.owningApplication?.processID != ownProcessID else { return nil }
            // Skip the desktop picture and other non-interactive layers.
            guard window.windowLayer == 0 else { return nil }
            return WindowTarget(window: window)
        }
    }

    // MARK: - Capture

    /// Freezes every display. Used both by full-screen capture and to build the
    /// selection overlay's background.
    func captureAllDisplays() async throws -> [DisplaySnapshot] {
        let content = try await shareableContent()
        guard !content.displays.isEmpty else { throw AppError.noDisplaysAvailable }

        let excluded = excludedApplications(in: content)
        var snapshots: [DisplaySnapshot] = []
        for display in content.displays {
            guard let screen = NSScreenProvider.screen(for: display.displayID) else { continue }
            let scale = screen.backingScaleFactor
            let filter = SCContentFilter(display: display,
                                         excludingApplications: excluded,
                                         exceptingWindows: [])
            let image = try await capture(filter: filter,
                                          pixelWidth: Int(CGFloat(display.width) * scale),
                                          pixelHeight: Int(CGFloat(display.height) * scale))
            snapshots.append(DisplaySnapshot(displayID: display.displayID,
                                             screen: screen,
                                             image: image,
                                             scale: scale))
        }
        guard !snapshots.isEmpty else { throw AppError.noDisplaysAvailable }
        return snapshots
    }

    func captureDisplay(withID displayID: CGDirectDisplayID) async throws -> DisplaySnapshot {
        let all = try await captureAllDisplays()
        guard let match = all.first(where: { $0.displayID == displayID }) ?? all.first else {
            throw AppError.noDisplaysAvailable
        }
        return match
    }

    /// Captures a single window with its shadow-free, alpha-preserving content.
    func captureWindow(_ target: WindowTarget) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: target.window)
        let scale = filter.pointPixelScale
        let rect = filter.contentRect
        return try await capture(filter: filter,
                                 pixelWidth: Int(rect.width * CGFloat(scale)),
                                 pixelHeight: Int(rect.height * CGFloat(scale)))
    }

    // MARK: - Internals

    private func capture(filter: SCContentFilter, pixelWidth: Int, pixelHeight: Int) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, pixelWidth)
        configuration.height = max(1, pixelHeight)
        configuration.captureResolution = .best
        configuration.showsCursor = settings.showsCursorInCaptures
        configuration.scalesToFit = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.ignoreGlobalClipDisplay = true
        configuration.ignoreShadowsDisplay = true

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                              configuration: configuration)
        } catch {
            throw Self.mapped(error)
        }
    }

    private func excludedApplications(in content: SCShareableContent) -> [SCRunningApplication] {
        guard settings.excludeOwnWindowsFromCapture else { return [] }
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return content.applications.filter { $0.processID == ownProcessID }
    }
}
