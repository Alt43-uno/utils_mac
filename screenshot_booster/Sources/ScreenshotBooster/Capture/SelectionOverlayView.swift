import AppKit

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
    private var sampler: PixelSampler?

    private var dragOrigin: CGPoint?
    private var selectionRect: CGRect = .zero
    private var isDragging = false
    private var pointerLocation: CGPoint = .zero
    private var hoveredTarget: WindowTarget?
    private var trackingArea: NSTrackingArea?

    private let minimumSelectionSide: CGFloat = 4
    private let loupeRadius: CGFloat = 58
    private let loupeZoom: CGFloat = 8

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

    override var isOpaque: Bool { true }
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
        guard mode == .area else { return }
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

    // MARK: - Hover

    private func updateHoveredTarget() {
        guard mode == .window else {
            hoveredTarget = nil
            return
        }
        let globalPoint = CGPoint(x: pointerLocation.x + snapshot.frame.minX,
                                  y: pointerLocation.y + snapshot.frame.minY)
        // `windowTargets` is front-to-back, so the first hit is the top window.
        hoveredTarget = windowTargets.first { $0.frame.contains(globalPoint) }
    }

    private func localRect(for target: WindowTarget) -> CGRect {
        CGRect(x: target.frame.minX - snapshot.frame.minX,
               y: target.frame.minY - snapshot.frame.minY,
               width: target.frame.width,
               height: target.frame.height)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        context.draw(snapshot.image, in: bounds)

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

        if mode == .area, !isDragging || NSEvent.modifierFlags.contains(.option) {
            drawLoupe(in: context)
        }

        drawHintBar()
    }

    private func currentHighlightRect() -> CGRect? {
        if mode == .window {
            return hoveredTarget.map { localRect(for: $0).clamped(to: bounds) }
        }
        return selectionRect.width > 0 && selectionRect.height > 0 ? selectionRect : nil
    }

    private func drawDimming(excluding rect: CGRect?, in context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(rect == nil ? 0.35 : 0.55).cgColor)
        if let rect {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(rect)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
        } else {
            context.fill(bounds)
        }
        context.restoreGState()
    }

    private func drawSelectionChrome(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))

        if mode == .area && rect.width > 24 && rect.height > 24 {
            let handleSize: CGFloat = 6
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)
            ]
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            for corner in corners {
                let box = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2,
                                 width: handleSize, height: handleSize)
                context.fillEllipse(in: box)
                context.strokeEllipse(in: box)
            }
        }
        context.restoreGState()
    }

    // MARK: - Overlay chrome

    private func drawSizeBadge(for rect: CGRect) {
        let pixels = snapshot.imageRect(fromViewRect: rect, viewHeight: bounds.height)
        let text = "\(Int(pixels.width.rounded())) × \(Int(pixels.height.rounded()))"
        var origin = CGPoint(x: rect.minX, y: rect.minY - 26)
        if origin.y < bounds.minY + 4 { origin.y = rect.maxY + 8 }
        drawBadge(text: text, at: origin, accent: false)
    }

    private func drawWindowLabel(for target: WindowTarget, rect: CGRect) {
        let size = "\(Int(target.frame.width.rounded())) × \(Int(target.frame.height.rounded()))"
        let text = "\(target.displayLabel)  ·  \(size)"
        var origin = CGPoint(x: rect.minX + 8, y: rect.minY - 30)
        if origin.y < bounds.minY + 4 { origin.y = rect.minY + 8 }
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - 240)
        drawBadge(text: text, at: origin, accent: true)
    }

    private func drawHintBar() {
        let hint = mode == .area
            ? "Drag to select  ·  Click a window  ·  Space: window mode  ·  Esc: cancel"
            : "Click a window  ·  Space: area mode  ·  Esc: cancel"
        let attributes = badgeAttributes(fontSize: 12)
        let size = (hint as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2 - 12,
                             y: bounds.maxY - 64)
        drawBadge(text: hint, at: origin, accent: false, fontSize: 12)
    }

    private func badgeAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white
        ]
    }

    private func drawBadge(text: String, at origin: CGPoint, accent: Bool, fontSize: CGFloat = 13) {
        let attributes = badgeAttributes(fontSize: fontSize)
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 10, height: 6)
        let box = CGRect(x: origin.x, y: origin.y,
                         width: textSize.width + padding.width * 2,
                         height: textSize.height + padding.height * 2)
        let path = NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7)
        (accent ? NSColor.controlAccentColor.withAlphaComponent(0.92)
                : NSColor.black.withAlphaComponent(0.72)).setFill()
        path.fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height),
                                withAttributes: attributes)
    }

    // MARK: - Magnifier

    private func drawLoupe(in context: CGContext) {
        let center = pointerLocation
        guard bounds.contains(center) else { return }

        var origin = CGPoint(x: center.x + 20, y: center.y + 20)
        if origin.x + loupeRadius * 2 > bounds.maxX { origin.x = center.x - 20 - loupeRadius * 2 }
        if origin.y + loupeRadius * 2 + 26 > bounds.maxY { origin.y = center.y - 20 - loupeRadius * 2 - 26 }
        let frame = CGRect(x: origin.x, y: origin.y, width: loupeRadius * 2, height: loupeRadius * 2)

        context.saveGState()
        let clip = CGPath(roundedRect: frame, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(clip)
        context.clip()

        // Source rectangle in image pixels, centred on the pointer.
        let sourceSide = (frame.width / loupeZoom) * snapshot.scale
        let centerInImage = snapshot.imagePoint(fromViewPoint: center, viewHeight: bounds.height)
        let sourceRect = CGRect(x: centerInImage.x - sourceSide / 2,
                                y: centerInImage.y - sourceSide / 2,
                                width: sourceSide, height: sourceSide)

        context.setFillColor(NSColor.black.cgColor)
        context.fill(frame)
        if let cropped = snapshot.image.cropping(to: sourceRect.pixelAligned) {
            context.interpolationQuality = .none
            context.draw(cropped, in: frame)
        }

        // Pixel crosshair.
        let pixelSize = frame.width / (sourceSide / snapshot.scale) / snapshot.scale
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        let cross = CGRect(x: frame.midX - pixelSize / 2, y: frame.midY - pixelSize / 2,
                           width: max(pixelSize, 2), height: max(pixelSize, 2))
        context.stroke(cross)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        context.stroke(cross.insetBy(dx: -1, dy: -1))
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
                               cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.strokePath()

        let hex = sampler?.color(at: centerInImage).map(PixelSampler.hexString(for:)) ?? ""
        let caption = hex.isEmpty
            ? "\(Int(centerInImage.x)), \(Int(centerInImage.y))"
            : "\(hex)   \(Int(centerInImage.x)), \(Int(centerInImage.y))"
        drawBadge(text: caption, at: CGPoint(x: frame.minX, y: frame.minY - 26), accent: false, fontSize: 11)
    }
}
