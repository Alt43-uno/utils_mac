import AppKit
import Combine

/// Wires the app together: capture → library → thumbnail panel → editor, plus
/// the menu bar item, global shortcuts and settings window.
@MainActor
final class AppCoordinator {

    let settings: SettingsStore
    let library: ScreenshotLibrary

    private let captureService: CaptureService
    private let captureCoordinator: CaptureCoordinator
    private let editorManager: EditorWindowManager
    private let hotkeyManager = HotkeyManager()
    private var thumbnailController: ThumbnailStackController!
    private var statusItemController: StatusItemController!
    private var settingsWindowController: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        self.library = ScreenshotLibrary(settings: settings)
        self.captureService = CaptureService(settings: settings)
        self.captureCoordinator = CaptureCoordinator(settings: settings,
                                                     library: library,
                                                     captureService: captureService)
        self.editorManager = EditorWindowManager(library: library, settings: settings)

        thumbnailController = ThumbnailStackController(library: library,
                                                       settings: settings,
                                                       actions: makeThumbnailActions())
        statusItemController = StatusItemController(settings: settings, actions: makeMenuActions())
    }

    // MARK: - Lifecycle

    func start() {
        ScreenshotLibrary.clearDragCache()
        library.load()

        captureCoordinator.onCaptured = { [weak self] _, screen in
            self?.thumbnailController.noteCapture(on: screen)
        }

        hotkeyManager.onAction = { [weak self] action in
            self?.captureCoordinator.capture(action.mode)
        }
        settings.$hotkeys
            .receive(on: RunLoop.main)
            .sink { [weak self] combos in self?.applyHotkeys(combos) }
            .store(in: &cancellables)

        statusItemController.install()
        thumbnailController.start()

        if !settings.hasCompletedFirstRun {
            settings.hasCompletedFirstRun = true
            // Deferred: a modal alert inside `applicationDidFinishLaunching`
            // would stall the rest of the launch sequence.
            DispatchQueue.main.async { [weak self] in
                self?.presentFirstRunGuidance()
            }
        }
    }

    func shutDown() {
        captureCoordinator.cancelActiveSelection()
        hotkeyManager.unregisterAll()
        cancellables.removeAll()
        editorManager.closeAll()
        thumbnailController.tearDown()
        library.persistNow()
        ScreenshotLibrary.clearDragCache()
    }

    // MARK: - Commands

    func capture(_ mode: CaptureMode) {
        captureCoordinator.capture(mode)
    }

    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings,
                                                                onHotkeyChange: { [weak self] in
                                                                    guard let self else { return }
                                                                    self.applyHotkeys(self.settings.hotkeys)
                                                                })
            settingsWindowController?.onClose = { [weak self] in
                self?.settingsWindowController = nil
            }
        }
        settingsWindowController?.present()
    }

    // MARK: - Wiring helpers

    private func applyHotkeys(_ combos: [CaptureMode: KeyCombo]) {
        let failures = hotkeyManager.apply(combos)
        guard !failures.isEmpty else { return }
        for failure in failures {
            Log.hotkeys.error("Could not register shortcut for \(failure.mode.rawValue, privacy: .public)")
        }
        let title = failures[0].mode.title
        // Deferred so a conflict detected during launch cannot stall it.
        DispatchQueue.main.async {
            ErrorPresenter.present(AppError.hotkeyRegistrationFailed(name: title),
                                   extraButton: ("Open Settings", { [weak self] in self?.showSettings() }))
        }
    }

    private func makeThumbnailActions() -> ThumbnailActions {
        ThumbnailActions(
            open: { [weak self] screenshot in
                self?.editorManager.open(screenshot)
            },
            delete: { [weak self] screenshot in
                self?.library.remove(id: screenshot.id)
            },
            copy: { [weak self] screenshot in
                self?.copyToClipboard(screenshot)
            },
            save: { [weak self] screenshot in
                self?.save(screenshot, revealing: false)
            },
            saveAs: { [weak self] screenshot in
                self?.saveAs(screenshot)
            },
            reveal: { [weak self] screenshot in
                self?.save(screenshot, revealing: true)
            },
            clearAll: { [weak self] in
                self?.confirmClearAll()
            },
            dragFileURL: { [weak self] screenshot in
                guard let self else { return nil }
                do {
                    return try self.library.dragFileURL(for: screenshot)
                } catch {
                    ErrorPresenter.present(error)
                    return nil
                }
            },
            thumbnailImage: { [weak self] screenshot in
                guard let self else { return nil }
                let maxPixelSize = min(720, CGFloat(self.settings.thumbnailWidth) * 3)
                return self.library.thumbnail(for: screenshot, maxPixelSize: maxPixelSize)
            }
        )
    }

    private func makeMenuActions() -> StatusItemActions {
        StatusItemActions(
            capture: { [weak self] mode in self?.capture(mode) },
            showThumbnails: { [weak self] in self?.thumbnailController.revealPanel() },
            clearThumbnails: { [weak self] in self?.confirmClearAll() },
            openSaveFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.settings.saveDirectory)
            },
            openSettings: { [weak self] in self?.showSettings() },
            hasPinnedScreenshots: { [weak self] in !(self?.library.screenshots.isEmpty ?? true) }
        )
    }

    // MARK: - Screenshot actions

    private func copyToClipboard(_ screenshot: Screenshot) {
        do {
            let image = try library.flattenedImage(for: screenshot)
            PasteboardService.copy(image: image)
        } catch {
            ErrorPresenter.present(error)
        }
    }

    private func save(_ screenshot: Screenshot, revealing: Bool) {
        do {
            if let existing = screenshot.lastSavedURL, FileManager.default.fileExists(atPath: existing.path) {
                if revealing { ExportService.reveal(existing) }
                return
            }
            let image = try library.flattenedImage(for: screenshot)
            let url = try ExportService.saveToConfiguredFolder(image,
                                                               date: screenshot.createdAt,
                                                               settings: settings)
            var updated = screenshot
            updated.lastSavedPath = url.path
            library.update(updated)
            if revealing { ExportService.reveal(url) }
        } catch {
            ErrorPresenter.present(error)
        }
    }

    private func saveAs(_ screenshot: Screenshot) {
        do {
            let image = try library.flattenedImage(for: screenshot)
            let suggested = screenshot.lastSavedURL?.lastPathComponent
                ?? AppPaths.suggestedFileName(for: screenshot.createdAt, format: settings.imageFormat)
            let directory = screenshot.lastSavedURL?.deletingLastPathComponent() ?? settings.saveDirectory
            guard let url = try ExportService.runSavePanel(image: image,
                                                            suggestedName: suggested,
                                                            directory: directory,
                                                            settings: settings,
                                                            accessoryFormat: settings.imageFormat) else { return }
            var updated = screenshot
            updated.lastSavedPath = url.path
            library.update(updated)
        } catch {
            ErrorPresenter.present(error)
        }
    }

    private func confirmClearAll() {
        guard !library.screenshots.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Remove all pinned screenshots?"
        alert.informativeText = "\(library.screenshots.count) screenshots will be unpinned. Files you already saved are not affected."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            library.removeAll()
        }
    }

    // MARK: - First run

    private func presentFirstRunGuidance() {
        let alert = NSAlert()
        alert.messageText = "Screenshot Booster is running in the menu bar"
        let area = settings.hotkeys[.area]?.displayString ?? "—"
        let window = settings.hotkeys[.window]?.displayString ?? "—"
        let screen = settings.hotkeys[.fullScreen]?.displayString ?? "—"
        alert.informativeText = """
        Capture area: \(area)
        Capture window: \(window)
        Capture screen: \(screen)

        Every shot stays pinned in the corner of your screen until you close it.
        macOS will ask for Screen Recording permission the first time you capture.
        """
        alert.addButton(withTitle: "Got it")
        alert.addButton(withTitle: "Open Settings…")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            showSettings()
        }
    }
}
