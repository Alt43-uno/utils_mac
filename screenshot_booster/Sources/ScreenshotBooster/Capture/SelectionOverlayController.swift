import AppKit

/// Presents the full-screen selection overlay across every display and resolves
/// to the user's choice.
@MainActor
final class SelectionOverlayController: NSObject, SelectionOverlayViewDelegate {

    enum Selection {
        /// Rectangle in image pixel space of the given display snapshot.
        case area(snapshot: DisplaySnapshot, pixelRect: CGRect)
        case window(WindowTarget)
    }

    private var windows: [OverlayWindow] = []
    private var views: [SelectionOverlayView] = []
    private var continuation: CheckedContinuation<Selection?, Never>?
    private var previousApplication: NSRunningApplication?

    var isPresenting: Bool { !windows.isEmpty }

    /// Shows the overlay and waits for a selection. Returns `nil` when cancelled.
    func present(mode: CaptureMode,
                 snapshots: [DisplaySnapshot],
                 targets: [WindowTarget]) async -> Selection? {
        guard !isPresenting else { return nil }
        previousApplication = NSWorkspace.shared.frontmostApplication

        for snapshot in snapshots {
            let window = OverlayWindow(screen: snapshot.screen)
            let view = SelectionOverlayView(snapshot: snapshot, mode: mode)
            view.delegate = self
            view.setWindowTargets(targets)
            view.frame = CGRect(origin: .zero, size: snapshot.frame.size)
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)
        }

        NSApp.activate(ignoringOtherApps: true)
        // Make the display under the pointer key so Escape works immediately.
        if let pointerScreen = NSScreenProvider.screenWithMouse,
           let index = snapshots.firstIndex(where: { $0.screen == pointerScreen }) {
            windows[index].makeKeyAndOrderFront(nil)
            windows[index].makeFirstResponder(views[index])
        } else {
            windows.first?.makeKeyAndOrderFront(nil)
            if let first = views.first { windows.first?.makeFirstResponder(first) }
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Tears the overlay down. Safe to call more than once.
    func dismiss() {
        guard isPresenting else { return }
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
    }

    private func finish(with selection: Selection?) {
        dismiss()
        // Hand focus back to whatever the user was working in; the app is an
        // accessory and should never linger in the foreground.
        if selection == nil, let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil

        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: selection)
    }

    /// Called when the app is about to quit or the screen layout changed.
    func cancelIfPresenting() {
        guard isPresenting else { return }
        finish(with: nil)
    }

    // MARK: - SelectionOverlayViewDelegate

    func overlayView(_ view: SelectionOverlayView, didSelectAreaIn snapshot: DisplaySnapshot, viewRect: CGRect) {
        let pixelRect = snapshot.imageRect(fromViewRect: viewRect, viewHeight: view.bounds.height)
            .pixelAligned
            .clamped(to: CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))
        guard pixelRect.width >= 1, pixelRect.height >= 1 else {
            finish(with: nil)
            return
        }
        finish(with: .area(snapshot: snapshot, pixelRect: pixelRect))
    }

    func overlayView(_ view: SelectionOverlayView, didSelect target: WindowTarget) {
        finish(with: .window(target))
    }

    func overlayViewDidCancel(_ view: SelectionOverlayView) {
        finish(with: nil)
    }

    func overlayView(_ view: SelectionOverlayView, didRequestMode mode: CaptureMode) {
        for overlayView in views {
            overlayView.setMode(mode)
        }
    }
}
