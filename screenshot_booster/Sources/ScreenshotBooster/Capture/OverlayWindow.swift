import AppKit

/// Full-screen, shielding-level window used for the capture overlay.
///
/// It sits above everything (including full-screen spaces), accepts key events
/// so Escape works, and never becomes the app's main window.
final class OverlayWindow: NSWindow {

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        isMovable = false
        isReleasedWhenClosed = false
        // The overlay is transient UI; keeping it out of window cycling and
        // restoration avoids odd focus behaviour after a capture.
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}
