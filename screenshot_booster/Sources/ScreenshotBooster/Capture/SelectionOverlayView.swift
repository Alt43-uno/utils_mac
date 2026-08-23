import AppKit

@MainActor
protocol SelectionOverlayViewDelegate: AnyObject {
    func overlayView(_ view: SelectionOverlayView, didSelectAreaIn snapshot: DisplaySnapshot, viewRect: CGRect)
    func overlayView(_ view: SelectionOverlayView, didSelect target: WindowTarget)
    func overlayViewDidCancel(_ view: SelectionOverlayView)
    func overlayView(_ view: SelectionOverlayView, didRequestMode mode: CaptureMode)
}

/// The interactive layer of the capture overlay.
///
/// It renders a frozen snapshot of the display, dims everything outside the
/// current selection, and provides a pixel-accurate magnifier. Working against a
/// frozen bitmap (instead of the live screen) means the overlay chrome can never
/// leak into the captured image and the magnifier stays perfectly in sync.
final class SelectionOverlayView: NSView {

    weak var delegate: SelectionOverlayViewDelegate?

    let snapshot: DisplaySnapshot
    private(set) var mode: CaptureMode
    private var windowTargets: [WindowTarget] = []
    /// Drawing lives in `SelectionOverlayView+Drawing.swift`, so the state it
    /// needs is internal rather than private.
    var sampler: PixelSampler?

    private var dragOrigin: CGPoint?
    var selectionRect: CGRect = .zero
    var isDragging = false
    var pointerLocation: CGPoint = .zero
    var hoveredTarget: WindowTarget?
    private var trackingArea: NSTrackingArea?

    let minimumSelectionSide: CGFloat = 4
    let loupeRadius: CGFloat = 58
    let loupeZoom: CGFloat = 8

    init(snapshot: DisplaySnapshot, mode: CaptureMode) {
        self.snapshot = snapshot
        self.mode = mode
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        self.sampler = PixelSampler(image: snapshot.image)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Configuration

    /// Window targets are filtered down to the ones visible on this display and
    /// converted into view coordinates.
    func setWindowTargets(_ targets: [WindowTarget]) {
        windowTargets = targets.filter { $0.frame.intersects(snapshot.frame) }
        needsDisplay = true
    }

    func setMode(_ newMode: CaptureMode) {
        guard newMode != mode else { return }
        mode = newMode
        dragOrigin = nil
        isDragging = false
        selectionRect = .zero
        updateHoveredTarget()
        refreshCursor()
        needsDisplay = true
    }

    // MARK: - View lifecycle

    /// The frozen bitmap lives in `OverlayBackdropView` underneath.
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        pointerLocation = currentPointerLocation()
        updateHoveredTarget()
        refreshCursor()
    }

    private func currentPointerLocation() -> CGPoint {
        let global = NSEvent.mouseLocation
        return CGPoint(x: global.x - snapshot.frame.minX, y: global.y - snapshot.frame.minY)
    }

    private func refreshCursor() {
        if mode == .area {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        refreshCursor()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        pointerLocation = convert(event.locationInWindow, from: nil)
        guard mode == .area else {
            // Refresh the highlight from the click location: the pointer may
            // have entered this display without a tracked mouse-moved event.
            updateHoveredTarget()
            needsDisplay = true
            return
        }
        dragOrigin = pointerLocation
        selectionRect = .zero
        isDragging = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        pointerLocation = convert(event.locationInWindow, from: nil)
        guard mode == .area, let origin = dragOrigin else { return }
        isDragging = true
        var rect = CGRect(corner: origin, opposite: pointerLocation)
        if event.modifierFlags.contains(.shift) {
            // Shift constrains the selection to a square.
            let side = max(rect.width, rect.height)
            rect = CGRect(x: pointerLocation.x < origin.x ? origin.x - side : origin.x,
                          y: pointerLocation.y < origin.y ? origin.y - side : origin.y,
                          width: side, height: side)
        }
        selectionRect = rect.clamped(to: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        pointerLocation = convert(event.locationInWindow, from: nil)

        if mode == .window {
            updateHoveredTarget()
            if let target = hoveredTarget {
                delegate?.overlayView(self, didSelect: target)
            } else {
                delegate?.overlayViewDidCancel(self)
            }
            return
        }

        defer {
            dragOrigin = nil
            isDragging = false
        }

        let rect = selectionRect
        if rect.width >= minimumSelectionSide && rect.height >= minimumSelectionSide {
            delegate?.overlayView(self, didSelectAreaIn: snapshot, viewRect: rect)
        } else if !isDragging {
            // A plain click grabs the window under the pointer, matching the
            // behaviour people expect from macOS' own capture UI.
            updateHoveredTarget()
            if let target = hoveredTarget {
                delegate?.overlayView(self, didSelect: target)
            } else {
                delegate?.overlayViewDidCancel(self)
            }
        } else {
            selectionRect = .zero
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        pointerLocation = convert(event.locationInWindow, from: nil)
        updateHoveredTarget()
        refreshCursor()
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayViewDidCancel(self)
    }

    override func scrollWheel(with event: NSEvent) {
        // Swallow scrolling so the frozen content underneath cannot move.
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Escape
            delegate?.overlayViewDidCancel(self)
        case 49: // Space toggles between area and window mode
            delegate?.overlayView(self, didRequestMode: mode == .area ? .window : .area)
        case 36, 76: // Return / Enter
            if mode == .area, selectionRect.width >= minimumSelectionSide, selectionRect.height >= minimumSelectionSide {
                delegate?.overlayView(self, didSelectAreaIn: snapshot, viewRect: selectionRect)
            } else if mode == .window, let target = hoveredTarget {
                delegate?.overlayView(self, didSelect: target)
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let highlight = currentHighlightRect()
        drawDimming(excluding: highlight, in: context)

        if let highlight {
            drawSelectionChrome(highlight, in: context)
        }

        if mode == .window, let target = hoveredTarget {
            drawWindowLabel(for: target, rect: localRect(for: target))
        } else if let highlight, highlight.width >= minimumSelectionSide {
            drawSizeBadge(for: highlight)
        }

        // The magnifier stays up while dragging too — that is exactly when
        // pixel-accurate edges matter.
        if mode == .area {
            drawLoupe(in: context)
        }

        drawHintBar()
    }

    // MARK: - Hover

    /// Tracks the window under the pointer in *both* modes: window mode draws a
    /// highlight for it, and in area mode a plain click (no drag) captures it.
    private func updateHoveredTarget() {
        let globalPoint = CGPoint(x: pointerLocation.x + snapshot.frame.minX,
                                  y: pointerLocation.y + snapshot.frame.minY)
        // `windowTargets` is front-to-back, so the first hit is the top window.
        hoveredTarget = windowTargets.first { $0.frame.contains(globalPoint) }
    }

    func localRect(for target: WindowTarget) -> CGRect {
        CGRect(x: target.frame.minX - snapshot.frame.minX,
               y: target.frame.minY - snapshot.frame.minY,
               width: target.frame.width,
               height: target.frame.height)
    }
}
