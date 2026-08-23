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

/// Draws the frozen screen image behind the selection chrome.
///
/// Using a layer's `contents` instead of `draw(_:)` means moving the pointer
/// re-composites the (potentially 5K) bitmap on the GPU rather than redrawing it
/// on the CPU for every mouse event.
final class OverlayBackdropView: NSView {
    init(image: CGImage, frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.magnificationFilter = .linear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isOpaque: Bool { true }

    /// Hit testing must reach the chrome view layered on top — it is what turns
    /// mouse events into a selection. Returning the subview explicitly (rather
    /// than `self`) guarantees the backdrop never swallows a click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        return subviews.last ?? self
    }
}
