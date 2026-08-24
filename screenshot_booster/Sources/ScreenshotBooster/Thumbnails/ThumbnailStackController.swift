import AppKit
import Combine
import SwiftUI

/// Owns the floating thumbnail panel: keeps it sized to its content, anchored to
/// the configured corner, and out of the way when there is nothing pinned.
@MainActor
final class ThumbnailStackController {

    private let library: ScreenshotLibrary
    private let settings: SettingsStore
    private let actions: ThumbnailActions

    private var panel: ThumbnailPanel?
    private var hostingView: NSHostingView<ThumbnailStackView>?
    private let interaction = ThumbnailInteractionModel()
    private lazy var swipeRecognizer = ThumbnailSwipeRecognizer(
        model: interaction,
        layout: { [weak self] in
            guard let self else { return ThumbnailGeometry.Layout(size: .zero, cardRects: []) }
            return ThumbnailGeometry.layout(for: self.library.screenshots,
                                            width: CGFloat(self.settings.thumbnailWidth),
                                            corner: self.settings.panelCorner)
        },
        dismiss: { [weak self] id in self?.library.remove(id: id) }
    )
    private var cancellables: Set<AnyCancellable> = []
    /// Screen the most recent capture came from, used by the `captureScreen`
    /// placement policy.
    private var lastCaptureScreen: NSScreen?

    private let margin: CGFloat = 16

    init(library: ScreenshotLibrary, settings: SettingsStore, actions: ThumbnailActions) {
        self.library = library
        self.settings = settings
        self.actions = actions
        observe()
    }

    // MARK: - Public

    func start() {
        refresh()
    }

    /// Explicit teardown at quit: panels are not released when closed, and the
    /// hosting view keeps SwiftUI state alive until it is detached.
    func tearDown() {
        swipeRecognizer.detach()
        cancellables.removeAll()
        hostingView?.removeFromSuperview()
        hostingView = nil
        panel?.contentView = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    func noteCapture(on screen: NSScreen?) {
        lastCaptureScreen = screen
        refresh()
    }

    /// Brings the panel forward without taking focus — used by the menu bar item.
    func revealPanel() {
        refresh()
        panel?.orderFrontRegardless()
    }

    // MARK: - Observation

    private func observe() {
        library.$screenshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Any placement-affecting setting triggers a re-layout.
        Publishers.Merge3(
            settings.$panelCorner.map { _ in () },
            settings.$panelScreenPolicy.map { _ in () },
            settings.$thumbnailWidth.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            self?.library.invalidateThumbnails()
            self?.refresh()
        }
        .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    private func refresh() {
        guard !library.screenshots.isEmpty else {
            hidePanel()
            return
        }
        let panel = ensurePanel()
        guard let screen = targetScreen() else { return }

        let visible = screen.visibleFrame
        let content = ThumbnailGeometry.contentSize(for: library.screenshots,
                                                    width: CGFloat(settings.thumbnailWidth),
                                                    corner: settings.panelCorner)
        let maxHeight = max(120, visible.height - margin * 2)
        let size = CGSize(width: content.width, height: min(content.height, maxHeight))
        let origin = settings.panelCorner.origin(for: size, in: visible, margin: margin)

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> ThumbnailPanel {
        if let panel { return panel }

        let panel = ThumbnailPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))
        let container = PassthroughContainerView(frame: panel.contentLayoutRect)
        container.autoresizingMask = [.width, .height]

        let root = ThumbnailStackView(library: library,
                                      settings: settings,
                                      interaction: interaction,
                                      actions: actions)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        // Let clicks fall through the transparent gaps between cards.
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)
        container.passthroughView = hosting

        panel.contentView = container
        self.panel = panel
        self.hostingView = hosting
        // Two-finger swipe to dismiss a card.
        swipeRecognizer.attach(to: panel)
        return panel
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func targetScreen() -> NSScreen? {
        switch settings.panelScreenPolicy {
        case .screenWithMouse:
            return NSScreenProvider.screenWithMouse ?? NSScreenProvider.primary
        case .captureScreen:
            if let lastCaptureScreen, NSScreen.screens.contains(lastCaptureScreen) {
                return lastCaptureScreen
            }
            return NSScreenProvider.primary
        case .primary:
            return NSScreenProvider.primary
        }
    }
}
