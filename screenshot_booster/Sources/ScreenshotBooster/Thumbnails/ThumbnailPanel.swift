import AppKit

/// Borderless, non-activating panel that hosts the thumbnail stack.
///
/// It floats above ordinary windows, follows the user across Spaces and
/// full-screen apps, and never steals focus from the app they are working in.
final class ThumbnailPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false          // each card draws its own shadow
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Panels are not restorable state; without this macOS logs warnings for
        // borderless windows on quit.
        isRestorable = false
    }

    /// The panel must be able to become key for text fields inside menus, but it
    /// should never become the app's main window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Container whose empty areas let clicks through to whatever is underneath.
final class PassthroughContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
