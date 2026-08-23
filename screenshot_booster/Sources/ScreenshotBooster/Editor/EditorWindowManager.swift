import AppKit
import Combine

/// Keeps at most one editor window per pinned screenshot alive.
@MainActor
final class EditorWindowManager {

    private var controllers: [UUID: EditorWindowController] = [:]
    private let library: ScreenshotLibrary
    private let settings: SettingsStore
    private var cancellables: Set<AnyCancellable> = []

    init(library: ScreenshotLibrary, settings: SettingsStore) {
        self.library = library
        self.settings = settings

        // Closing a pinned shot should also close the window that edits it.
        library.$screenshots
            .receive(on: RunLoop.main)
            .sink { [weak self] screenshots in
                self?.closeOrphanedWindows(keeping: Set(screenshots.map(\.id)))
            }
            .store(in: &cancellables)
    }

    var hasOpenEditors: Bool { !controllers.isEmpty }

    /// Opens (or re-focuses) the editor for a screenshot.
    func open(_ screenshot: Screenshot) {
        if let existing = controllers[screenshot.id] {
            existing.present()
            return
        }
        do {
            let document = try library.document(for: screenshot)
            let model = EditorViewModel(screenshot: screenshot,
                                        document: document,
                                        library: library,
                                        settings: settings)
            let controller = EditorWindowController(model: model)
            controller.onClose = { [weak self] id in
                self?.controllers.removeValue(forKey: id)
            }
            controllers[screenshot.id] = controller
            controller.present()
        } catch {
            ErrorPresenter.present(error)
        }
    }

    func closeAll() {
        // Take the controllers out of the dictionary first: `close()` calls back
        // into `onClose`, which would otherwise mutate it mid-iteration.
        let all = Array(controllers.values)
        controllers.removeAll()
        for controller in all {
            controller.onClose = nil
            controller.close()
        }
    }

    private func closeOrphanedWindows(keeping ids: Set<UUID>) {
        let orphaned = controllers.filter { !ids.contains($0.key) }
        guard !orphaned.isEmpty else { return }
        for (id, controller) in orphaned {
            controllers.removeValue(forKey: id)
            controller.onClose = nil
            controller.close()
        }
    }
}
