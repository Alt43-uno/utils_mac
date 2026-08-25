import AppKit

/// The interactive editing surface.
///
/// AppKit rather than SwiftUI: annotation dragging needs precise, low-latency
/// mouse handling, and drawing goes through the same `AnnotationRenderer` used
/// for export so the preview is pixel-identical to the saved file.
final class CanvasView: NSView, NSTextViewDelegate {

    // Input handling lives in `CanvasView+Input.swift`, so this state is
    // internal rather than private.
    let model: EditorViewModel

    enum Interaction {
        case none
        case drawing(Annotation)
        case moving(original: Annotation, grabPoint: CGPoint)
        case resizing(original: Annotation, handle: ResizeHandle, originalBounds: CGRect)
        case cropping(origin: CGPoint, rect: CGRect)
    }

    var interaction: Interaction = .none
    var textEditor: NSTextView?
    var editingAnnotationID: UUID?
    /// Live preview of the object being moved or resized.
    var interactionPreview: Annotation?
    private var trackingArea: NSTrackingArea?
    /// Base bitmap pre-scaled to the current on-screen size, so redrawing while
    /// dragging is a 1:1 blit instead of a full-resolution resample.
    private var scaledBase: CGImage?
    private var scaledBaseKey: Int = .min
    /// Panning offset, kept local so dragging the view around never pushes
    /// updates through SwiftUI.
    var panOffset: CGSize = .zero

    private let padding: CGFloat = 24
    private let handleSize: CGFloat = 9

    init(model: EditorViewModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // Zoomed-in content is larger than the view; without this it would spill
        // over the toolbar and the status bar.
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Geometry

    /// Region of the base image currently shown. The crop tool always works on
    /// the full image so the crop can be widened again.
    private var displayRect: CGRect {
        model.tool == .crop ? model.document.baseBounds : model.document.visibleRect
    }

    /// Viewport the image is laid out in.
    private var viewport: CGSize {
        CGSize(width: max(bounds.width - padding * 2, 1),
               height: max(bounds.height - padding * 2, 1))
    }

    /// Scale at which the whole document fits the window, never upscaling past
    /// 100% logical size — a Retina shot fits at 1:2.
    var fitZoom: CGFloat {
        let rect = displayRect
        guard rect.width > 0, rect.height > 0 else { return 1 }
        let fit = min(viewport.width / rect.width, viewport.height / rect.height)
        return min(fit, 1 / max(model.document.scale, 1))
    }

    /// Pixels-to-points factor the image is currently drawn at.
    var zoom: CGFloat {
        if case .factor(let factor) = model.zoomMode { return factor }
        return fitZoom
    }

    private var contentRect: CGRect {
        let rect = displayRect
        let size = CGSize(width: rect.width * zoom, height: rect.height * zoom)
        var origin = CGPoint(x: (bounds.width - size.width) / 2,
                             y: (bounds.height - size.height) / 2)
        origin.x += Self.clampedPan(panOffset.width, content: size.width, viewport: viewport.width)
        origin.y += Self.clampedPan(panOffset.height, content: size.height, viewport: viewport.height)
        return CGRect(origin: origin, size: size)
    }

    /// Panning is only possible along an axis where the image overflows the
    /// viewport, and it stops at the image's edges.
    private static func clampedPan(_ value: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
        let slack = max(0, (content - viewport) / 2)
        return min(max(value, -slack), slack)
    }

    /// True when the image is larger than the viewport in either direction.
    var isPannable: Bool {
        let rect = displayRect
        return rect.width * zoom > viewport.width + 1 || rect.height * zoom > viewport.height + 1
    }

    func pan(by delta: CGSize) {
        panOffset.width += delta.width
        panOffset.height += delta.height
        clampPan()
        needsDisplay = true
    }

    func clampPan() {
        let rect = displayRect
        let size = CGSize(width: rect.width * zoom, height: rect.height * zoom)
        panOffset.width = Self.clampedPan(panOffset.width, content: size.width, viewport: viewport.width)
        panOffset.height = Self.clampedPan(panOffset.height, content: size.height, viewport: viewport.height)
    }

    /// Zooms while keeping the image point under `anchor` in place.
    func setVisualScale(_ scale: CGFloat, anchor: CGPoint? = nil) {
        let anchorPoint = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let imageAnchor = imagePoint(fromView: anchorPoint)
        model.setVisualScale(scale)
        let movedAnchor = viewPoint(fromImage: imageAnchor)
        panOffset.width += anchorPoint.x - movedAnchor.x
        panOffset.height += anchorPoint.y - movedAnchor.y
        clampPan()
        needsDisplay = true
    }

    /// Keeps the view model's idea of the fit in sync and resets panning when
    /// the document is fitted to the window again.
    func syncZoomState() {
        let fit = fitZoom
        if abs(model.fitScale - fit) > 0.0001 {
            // Deferred: this runs during layout, and SwiftUI dislikes state
            // changing mid-update.
            DispatchQueue.main.async { [weak model] in model?.updateFitScale(fit) }
        }
        if model.zoomMode == .fit, panOffset != .zero {
            panOffset = .zero
            needsDisplay = true
        }
    }

    func imagePoint(fromView point: CGPoint) -> CGPoint {
        let rect = displayRect
        let content = contentRect
        return CGPoint(x: rect.minX + (point.x - content.minX) / zoom,
                       y: rect.minY + (content.maxY - point.y) / zoom)
    }

    func viewPoint(fromImage point: CGPoint) -> CGPoint {
        let rect = displayRect
        let content = contentRect
        return CGPoint(x: content.minX + (point.x - rect.minX) * zoom,
                       y: content.maxY - (point.y - rect.minY) * zoom)
    }

    func viewRect(fromImage rect: CGRect) -> CGRect {
        let topLeft = viewPoint(fromImage: CGPoint(x: rect.minX, y: rect.minY))
        return CGRect(x: topLeft.x, y: topLeft.y - rect.height * zoom,
                      width: rect.width * zoom, height: rect.height * zoom)
    }

    /// Hit tolerance expressed in image pixels.
    var tolerance: CGFloat { 8 / max(zoom, 0.05) }

    /// Keeps a point inside the region being edited, so a drag that starts in
    /// the window's padding cannot place an object outside the image.
    func clampedToImage(_ point: CGPoint) -> CGPoint {
        let rect = displayRect
        return CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                       y: min(max(point.y, rect.minY), rect.maxY))
    }

    // MARK: - View lifecycle

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endTextEditing(commit: true) }
        syncZoomState()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncZoomState()
        clampPan()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let content = contentRect
        let rect = displayRect

        drawCheckerboard(in: content, context: context)

        context.saveGState()
        context.translateBy(x: content.minX, y: content.maxY)
        context.scaleBy(x: zoom, y: -zoom)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.clip(to: rect)
        context.interpolationQuality = .high

        AnnotationRenderer.drawImage(displayBase(), in: model.document.baseBounds, context: context)
        // The object being edited, moved or resized is drawn from the live
        // preview instead, so it must be skipped here.
        let hiddenID = editingAnnotationID ?? interactionOriginalID
        for annotation in model.document.annotations where annotation.id != hiddenID {
            AnnotationRenderer.draw(annotation: annotation,
                                    base: model.document.base,
                                    in: context,
                                    effects: model.effects)
        }
        if let live = liveAnnotation {
            drawLive(live, in: context)
        }
        context.restoreGState()

        drawFrame(around: content, context: context)

        if model.tool == .crop {
            drawCropOverlay(context: context)
        } else {
            drawSelectionOverlay(context: context)
        }
    }

    /// The object the current interaction is previewing, if any.
    private var liveAnnotation: Annotation? {
        switch interaction {
        case .drawing(let draft): return draft
        case .moving(let original, _), .resizing(let original, _, _): return interactionPreview ?? original
        case .cropping, .none: return nil
        }
    }

    /// Blur and pixelate are far too expensive to re-filter on every mouse move,
    /// so an in-flight effect is previewed as a translucent placeholder and only
    /// rendered for real once the drag ends.
    private func drawLive(_ annotation: Annotation, in context: CGContext) {
        guard annotation.tool.isEffect else {
            AnnotationRenderer.draw(annotation: annotation,
                                    base: model.document.base,
                                    in: context,
                                    effects: model.effects)
            return
        }
        let rect = CGRect(corner: annotation.start, opposite: annotation.end)
        context.saveGState()
        context.setFillColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1 / max(zoom, 0.05))
        context.setLineDash(phase: 0, lengths: [6 / max(zoom, 0.05), 4 / max(zoom, 0.05)])
        context.stroke(rect)
        context.restoreGState()
    }

    /// Identifier of the object currently being dragged, if any.
    private var interactionOriginalID: UUID? {
        switch interaction {
        case .moving(let original, _), .resizing(let original, _, _): return original.id
        case .drawing, .cropping, .none: return nil
        }
    }

    /// Returns the base bitmap at (roughly) the size it is displayed.
    private func displayBase() -> CGImage {
        let base = model.document.base
        let factor = zoom * (window?.backingScaleFactor ?? 2)
        guard factor < 0.9 else { return base }

        let longest = CGFloat(max(base.width, base.height))
        // Quantised so a window resize does not rebuild the bitmap continuously.
        let target = max(256, ((longest * factor) / 128).rounded(.up) * 128)
        let key = Int(target)
        if let scaledBase, scaledBaseKey == key { return scaledBase }

        let produced = ImageUtilities.downscale(base, maxPixelSize: target)
        scaledBase = produced
        scaledBaseKey = key
        return produced
    }

    private func drawCheckerboard(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        context.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
        context.fill(rect)
        context.setFillColor(NSColor(white: 0.75, alpha: 1).cgColor)
        let square: CGFloat = 8
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : square)
            while x < rect.maxX {
                context.fill(CGRect(x: x, y: y, width: square, height: square))
                x += square * 2
            }
            y += square
            row += 1
        }
        context.restoreGState()
    }

    private func drawFrame(around rect: CGRect, context: CGContext) {
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
    }

    private func drawSelectionOverlay(context: CGContext) {
        guard model.tool == .select,
              let annotation = model.selectedAnnotation,
              annotation.id != editingAnnotationID else { return }

        let box = viewRect(fromImage: annotation.displayBounds)
        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(box.insetBy(dx: -1.5, dy: -1.5))
        context.setLineDash(phase: 0, lengths: [])

        for handle in AnnotationHitTesting.handles(for: annotation) {
            let point = viewPoint(fromImage: handle.position(in: annotation.displayBounds, annotation: annotation))
            let dot = CGRect(x: point.x - handleSize / 2, y: point.y - handleSize / 2,
                             width: handleSize, height: handleSize)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: dot)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: dot)
        }
        context.restoreGState()
    }

    private func drawCropOverlay(context: CGContext) {
        let cropImageRect: CGRect?
        if case .cropping(_, let rect) = interaction {
            cropImageRect = rect
        } else {
            cropImageRect = model.document.cropRect
        }

        let content = contentRect
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        if let cropImageRect {
            let box = viewRect(fromImage: cropImageRect)
            let path = CGMutablePath()
            path.addRect(content)
            path.addRect(box)
            context.addPath(path)
            context.fillPath(using: .evenOdd)

            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(box.insetBy(dx: 0.5, dy: 0.5))
            drawThirds(in: box, context: context)
            drawBadge(text: "\(Int(cropImageRect.width)) × \(Int(cropImageRect.height))",
                      at: CGPoint(x: box.minX, y: box.minY - 24))
        } else {
            drawBadge(text: "Drag to crop", at: CGPoint(x: content.minX, y: content.minY - 24))
        }
        context.restoreGState()
    }

    private func drawThirds(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.5)
        for index in 1...2 {
            let fraction = CGFloat(index) / 3
            context.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawBadge(text: String, at origin: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: origin.x, y: max(origin.y, bounds.minY + 2),
                         width: size.width + 14, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 7, y: box.minY + 4), withAttributes: attributes)
    }
}
