import AppKit
import SwiftUI

/// Recognition owns its own window, so thumbnail and hotkey actions never need
/// to create an editor or display the captured image.
@MainActor
final class RecognitionWindowManager {
    private var controller: RecognitionWindowController?

    func present(image: CGImage) {
        close()
        let controller = RecognitionWindowController(session: RecognitionSession(image: image))
        controller.onClose = { [weak self] in self?.controller = nil }
        self.controller = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        controller?.onClose = nil
        controller?.close()
        controller = nil
    }
}

@MainActor
final class RecognitionWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(session: RecognitionSession) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 580, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Recognized Text & QR Codes"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = CGSize(width: 520, height: 400)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: RecognitionResultsView(session: session) { [weak self] in
            self?.close()
        })
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        // Removing the SwiftUI hierarchy cancels its recognition task.
        window?.contentView = nil
        window?.delegate = nil
        onClose?()
    }
}
