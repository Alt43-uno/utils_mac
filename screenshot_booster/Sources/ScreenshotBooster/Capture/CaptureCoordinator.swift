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
        guard !isCapturing else {
            // A second trigger while the overlay is up should dismiss it rather
            // than stack another overlay on top.
            overlay.cancelIfPresenting()
            return
        }
        Task { await performCapture(mode) }
    }

    // MARK: - Flow

    private func performCapture(_ mode: CaptureMode) async {
        guard ScreenPermission.ensureGranted() else { return }
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
        var screenshot = try library.add(image: image, scale: scale, mode: mode, sourceName: sourceName)

        if settings.copyToClipboardAfterCapture {
            PasteboardService.copy(image: image)
        }

        if settings.autoSaveToDisk {
            do {
                let url = try ExportService.saveToConfiguredFolder(image,
                                                                   date: screenshot.createdAt,
                                                                   settings: settings)
                screenshot.lastSavedPath = url.path
                library.update(screenshot)
            } catch {
                // The shot is already pinned — surface the problem but keep it.
                ErrorPresenter.present(error)
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
