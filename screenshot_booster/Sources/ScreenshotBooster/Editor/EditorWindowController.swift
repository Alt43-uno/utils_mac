import AppKit
import SwiftUI

/// Hosts one editor window and exposes its commands to the main menu through
/// the responder chain.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    let model: EditorViewModel
    /// Called when the window closes so the manager can drop its reference.
    var onClose: ((UUID) -> Void)?

    private var canvasHost: NSHostingView<EditorRootView>?
    private var keyMonitor: Any?

    init(model: EditorViewModel) {
        self.model = model

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // The blurred backdrop lives in the content view, so the window itself
        // must not paint anything.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("")

        super.init(window: window)

        let host = NSHostingView(rootView: EditorRootView(model: model))
        window.contentView = host
        window.delegate = self
        canvasHost = host

        model.onDocumentChanged = { [weak self] in
            self?.updateTitle()
        }
        updateTitle()
        sizeToFit()
        installToolShortcutMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Presentation

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // The SwiftUI hierarchy is built during the first layout pass, so the
        // canvas only exists on the next run loop turn.
        DispatchQueue.main.async { [weak self] in
            self?.focusCanvas()
        }
    }

    private func updateTitle() {
        window?.title = model.titleText
    }

    /// Opens at a comfortable size: the image at 100% logical scale, capped to
    /// most of the screen it appears on.
    private func sizeToFit() {
        guard let window else { return }
        let screen = window.screen ?? NSScreenProvider.screenWithMouse ?? NSScreenProvider.primary
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let chrome = CGSize(width: 0, height: EditorChrome.topInset + EditorChrome.bottomInset)
        let logical = CGSize(width: model.outputSize.width / max(model.document.scale, 1),
                             height: model.outputSize.height / max(model.document.scale, 1))
        let maxContent = CGSize(width: visible.width * 0.82, height: visible.height * 0.82 - chrome.height)
        let scale = min(1, logical.fitScale(in: maxContent))

        let contentSize = CGSize(width: max(900, (logical.width * scale).rounded() + 48),
                                 height: max(480, (logical.height * scale).rounded() + chrome.height + 48))
        window.setContentSize(contentSize)
        window.center()
        // Nudge subsequent windows so several open shots do not stack exactly.
        let offset = CGFloat((EditorWindowController.openCount % 6) * 24)
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + offset, y: window.frame.origin.y - offset))
        EditorWindowController.openCount += 1
    }

    private static var openCount = 0

    /// Single-letter tool switching that keeps working even when a toolbar
    /// control (a slider, the colour well) holds the keyboard focus.
    private func installToolShortcutMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            // Never steal keys from a text field or the inline text editor.
            if window.firstResponder is NSText { return event }
            guard let characters = event.charactersIgnoringModifiers?.lowercased(),
                  let tool = ToolKind.editorOrder.first(where: { $0.shortcutKey == characters }) else {
                return event
            }
            self.model.tool = tool
            return nil
        }
    }

    private func focusCanvas() {
        guard let host = canvasHost else { return }
        if let canvas = Self.findCanvas(in: host) {
            window?.makeFirstResponder(canvas)
        }
    }

    private static func findCanvas(in view: NSView) -> CanvasView? {
        if let canvas = view as? CanvasView { return canvas }
        for subview in view.subviews {
            if let canvas = findCanvas(in: subview) { return canvas }
        }
        return nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Closing the editor keeps the pinned screenshot — it just has to be
        // written back before the window (and the model) go away.
        model.persistNow()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        // Break the retain path model → controller before the window goes away.
        model.onDocumentChanged = nil
        window?.delegate = nil
        window?.contentView = nil
        canvasHost = nil
        onClose?(model.screenshotID)
    }

    // MARK: - Menu commands

    // Standard AppKit selectors, so a focused text field keeps its own
    // behaviour and only the editor window reacts otherwise.
    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    @objc func copy(_ sender: Any?) { model.copyToClipboard() }
    @objc func saveDocument(_ sender: Any?) { model.save() }
    @objc func saveDocumentAs(_ sender: Any?) { model.saveAs() }
    @objc func delete(_ sender: Any?) { model.deleteSelection() }
    @objc func zoomIn(_ sender: Any?) { model.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { model.zoomOut() }
    @objc func actualSize(_ sender: Any?) { model.zoomToActualSize() }
    @objc func zoomToFit(_ sender: Any?) { model.zoomToFit() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return model.canUndo
        case #selector(redo(_:)): return model.canRedo
        case #selector(delete(_:)): return model.selectedID != nil
        case #selector(zoomIn(_:)): return model.canZoomIn
        case #selector(zoomOut(_:)): return model.canZoomOut
        default: return true
        }
    }
}
