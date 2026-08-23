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
    /// The hosted SwiftUI view. Hits that land on it but not on any of its
    /// content count as misses, so the transparent gaps between thumbnail cards
    /// stay click-through for the app underneath.
    weak var passthroughView: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === self || hit === passthroughView { return nil }
        // A hit on pure scaffolding — the hosting view itself or the scroll
        // view's clipping machinery — means the click landed in the empty space
        // between cards, so it belongs to whatever is underneath the panel.
        if hit is NSClipView || hit is NSScrollView || hit is NSVisualEffectView { return nil }
        return hit
    }
}
