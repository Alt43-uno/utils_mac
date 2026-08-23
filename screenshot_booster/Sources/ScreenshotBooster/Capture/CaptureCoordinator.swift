import AppKit

/// Drives a capture end to end: permission → freeze displays → selection →
/// crop → pin → optional clipboard/disk side effects.
@MainActor
final class CaptureCoordinator {

    /// Called with the newly pinned screenshot and the screen it came from, so
    /// the thumbnail panel can follow the capture when configured to.
    var onCaptured: ((Screenshot, NSScreen?) -> Void)?

    private let settings: SettingsStore
    private let library: ScreenshotLibrary
    private let captureService: CaptureService
    private let overlay = SelectionOverlayController()
    private var isCapturing = false
    /// Guards against the same shortcut arriving twice — once as a global hot
    /// key and once as the menu bar item's key equivalent while the app is
    /// frontmost.
    private var lastRequestAt: Date = .distantPast
    private let repeatThreshold: TimeInterval = 0.35

    init(settings: SettingsStore, library: ScreenshotLibrary, captureService: CaptureService) {
        self.settings = settings
        self.library = library
        self.captureService = captureService
    }

    var isBusy: Bool { isCapturing }

    func cancelActiveSelection() {
        overlay.cancelIfPresenting()
    }

    /// Entry point used by hotkeys and menu items.
    func capture(_ mode: CaptureMode) {
        let now = Date()
        guard now.timeIntervalSince(lastRequestAt) > repeatThreshold else { return }
        lastRequestAt = now
        // While a selection overlay is up, Escape (or a click) is the way out —
        // stacking a second overlay would only confuse things.
        guard !isCapturing else { return }
        Task { await performCapture(mode) }
    }

    // MARK: - Flow

    private func performCapture(_ mode: CaptureMode) async {
        guard ScreenPermission.ensureGranted(settings: settings) else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            switch mode {
            case .fullScreen:
                try await captureFullScreen()
            case .area, .window:
                try await captureInteractively(mode: mode)
            }
        } catch {
            overlay.dismiss()
            report(error)
        }
    }

    /// Permission problems get their own actionable alerts rather than the
    /// generic error sheet.
    private func report(_ error: Error) {
        switch error as? AppError {
        case .screenRecordingNeedsRelaunch:
            ScreenPermission.presentRelaunchAlert()
        case .screenRecordingPermissionDenied:
            ScreenPermission.presentDeniedAlert()
        default:
            ErrorPresenter.present(error)
        }
    }

    private func captureFullScreen() async throws {
        let snapshots = try await captureService.captureAllDisplays()
        let target = preferredSnapshot(in: snapshots)
        try finish(image: target.image,
                   scale: target.scale,
                   mode: .fullScreen,
                   sourceName: displayName(for: target),
                   screen: target.screen)
    }

    private func captureInteractively(mode: CaptureMode) async throws {
        let snapshots = try await captureService.captureAllDisplays()
        // Window targets are best-effort: area selection still works without them.
        let targets = (try? await captureService.windowTargets()) ?? []

        guard let selection = await overlay.present(mode: mode, snapshots: snapshots, targets: targets) else {
            throw AppError.cancelled
        }

        switch selection {
        case .area(let snapshot, let pixelRect):
            guard let cropped = snapshot.image.cropping(to: pixelRect) else {
                throw AppError.captureFailed(underlying: "the selected region could not be cropped")
            }
            try finish(image: cropped,
                       scale: snapshot.scale,
                       mode: .area,
                       sourceName: nil,
                       screen: snapshot.screen)

        case .window(let target):
            let image = try await captureService.captureWindow(target)
            let screen = NSScreen.screens.first { $0.frame.intersects(target.frame) } ?? NSScreenProvider.primary
            try finish(image: image,
                       scale: screen?.backingScaleFactor ?? 2,
                       mode: .window,
                       sourceName: target.applicationName,
                       screen: screen)
        }
    }

    /// Shared tail of every capture path.
    private func finish(image: CGImage,
                        scale: CGFloat,
                        mode: CaptureMode,
                        sourceName: String?,
                        screen: NSScreen?) throws {
        let screenshot = try library.add(image: image, scale: scale, mode: mode, sourceName: sourceName)

        if settings.copyToClipboardAfterCapture {
            PasteboardService.copy(image: image)
        }

        if settings.autoSaveToDisk {
            // Encoding happens off the main actor so the shutter stays snappy.
            let destination = ExportService.Destination(settings: settings)
            let identifier = screenshot.id
            let date = screenshot.createdAt
            let library = self.library
            Task.detached(priority: .utility) {
                do {
                    let url = try ExportService.save(image, date: date, to: destination)
                    await MainActor.run {
                        guard var stored = library.screenshot(with: identifier) else { return }
                        stored.lastSavedPath = url.path
                        library.update(stored)
                    }
                } catch {
                    // The shot is already pinned — surface the problem but keep it.
                    await MainActor.run { ErrorPresenter.present(error) }
                }
            }
        }

        if settings.playsCaptureSound {
            CaptureFeedback.playShutter()
        }

        Log.capture.info("Captured \(mode.rawValue, privacy: .public) \(image.width, privacy: .public)×\(image.height, privacy: .public)")
        onCaptured?(screenshot, screen)
    }

    // MARK: - Helpers

    private func preferredSnapshot(in snapshots: [DisplaySnapshot]) -> DisplaySnapshot {
        let pointerScreen = NSScreenProvider.screenWithMouse
        return snapshots.first { $0.screen == pointerScreen } ?? snapshots[0]
    }

    private func displayName(for snapshot: DisplaySnapshot) -> String? {
        snapshot.screen.localizedName
    }
}
