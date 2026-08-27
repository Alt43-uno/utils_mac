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
    /// Screenshot rasterised at exactly the pixel size it is shown at, plus the
    /// region and scale it was made for.
    private var scaledBase: CGImage?
    private var scaledBaseRegion: CGRect?
    private var scaledBaseScale: CGFloat = 0
    private var transparencyCache: Bool?
    private var transparencyKey: ObjectIdentifier?
    /// Panning offset, kept local so dragging the view around never pushes
    /// updates through SwiftUI.
    var panOffset: CGSize = .zero
    /// Zoom held locally for the duration of a pinch. Publishing every gesture
    /// event would re-render the whole editor — glass pills included — at the
    /// trackpad's event rate.
    private var liveZoomFactor: CGFloat?
    private var lastZoomSync: Date = .distantPast

    private let padding: CGFloat = 24
    private let handleSize: CGFloat = 9
    /// The toolbar and status bar float over the canvas, so the image has to be
    /// laid out inside what they leave free.
    var contentInsets = NSEdgeInsets(top: EditorChrome.topInset, left: 0,
                                     bottom: EditorChrome.bottomInset, right: 0)


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

    /// Region left over once the floating bars and padding are accounted for.
    private var layoutRect: CGRect {
        CGRect(x: padding,
               y: padding + contentInsets.bottom,
               width: max(bounds.width - padding * 2, 1),
               height: max(bounds.height - padding * 2 - contentInsets.top - contentInsets.bottom, 1))
    }

    /// Viewport the image is laid out in.
    private var viewport: CGSize { layoutRect.size }

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
        if let liveZoomFactor { return liveZoomFactor }
        if case .factor(let factor) = model.zoomMode { return factor }
        return fitZoom
    }

    private var contentRect: CGRect {
        let rect = displayRect
        let size = CGSize(width: rect.width * zoom, height: rect.height * zoom)
        let area = layoutRect
        var origin = CGPoint(x: area.midX - size.width / 2,
                             y: area.midY - size.height / 2)
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

    /// Zooms during a pinch without pushing every step through SwiftUI.
    func applyLiveVisualScale(_ scale: CGFloat, anchor: CGPoint) {
        let clamped = min(max(scale, EditorViewModel.minVisualScale), EditorViewModel.maxVisualScale)
        let imageAnchor = imagePoint(fromView: anchor)
        liveZoomFactor = clamped / max(model.document.scale, 1)

        let movedAnchor = viewPoint(fromImage: imageAnchor)
        panOffset.width += anchor.x - movedAnchor.x
        panOffset.height += anchor.y - movedAnchor.y
        clampPan()
        needsDisplay = true

        // Let the status pill keep up, but only a few times a second.
        let now = Date()
        if now.timeIntervalSince(lastZoomSync) > 0.1 {
            lastZoomSync = now
            model.setVisualScale(clamped)
        }
    }

    /// Hands the pinch result back to the view model.
    func commitLiveZoom() {
        guard let factor = liveZoomFactor else { return }
        liveZoomFactor = nil
        model.setVisualScale(factor * max(model.document.scale, 1))
        needsDisplay = true
    }

    /// Zooms while keeping the image point under `anchor` in place.
    func setVisualScale(_ scale: CGFloat, anchor: CGPoint? = nil) {
        liveZoomFactor = nil
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
    /// Drops the rasterised copy when the document it was cut from changed.
    func invalidateZoomTileIfNeeded() {
        if transparencyKey != ObjectIdentifier(model.document.base) {
            scaledBase = nil
            scaledBaseRegion = nil
        }
    }

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

        // With the image larger than the window there is no visible edge, so the
        // shadow would only cost a blur over a gigantic rectangle.
        let showsEdge = !content.contains(bounds)
        if showsEdge {
            drawImageShadow(around: content, context: context)
        }
        drawCheckerboard(in: content, context: context)

        context.saveGState()
        context.translateBy(x: content.minX, y: content.maxY)
        context.scaleBy(x: zoom, y: -zoom)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        // Clipping to what is on screen lets Core Graphics reject most geometry
        // before it rasterises anything.
        let visible = visibleImageRect
        context.clip(to: rect.intersection(visible))
        // Magnifying past 1:1 should show real pixels — nearest neighbour is both
        // more honest and far cheaper than a smooth resample.
        context.interpolationQuality = model.visualScale > 1.2 ? .none : .high

        drawBase(in: context)
        // The object being edited, moved or resized is drawn from the live
        // preview instead, so it must be skipped here.
        let hiddenID = editingAnnotationID ?? interactionOriginalID
        for annotation in model.document.annotations where annotation.id != hiddenID {
            guard annotation.displayBounds.intersects(visible) else { continue }
            AnnotationRenderer.draw(annotation: annotation,
                                    base: model.document.base,
                                    in: context,
                                    effects: model.effects,
                                    visibleRect: visible)
        }
        if let live = liveAnnotation {
            drawLive(live, in: context)
        }
        context.restoreGState()

        if showsEdge {
            drawFrame(around: content, context: context)
        }

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
                                    effects: model.effects,
                                    visibleRect: visibleImageRect)
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

    /// Region of image space currently on screen, in image pixels.
    private var visibleImageRect: CGRect {
        let topLeft = imagePoint(fromView: CGPoint(x: bounds.minX, y: bounds.maxY))
        let bottomRight = imagePoint(fromView: CGPoint(x: bounds.maxX, y: bounds.minY))
        return CGRect(corner: topLeft, opposite: bottomRight).insetBy(dx: -2, dy: -2)
    }

    /// Draws the screenshot, touching only the pixels that are actually visible.
    ///
    /// Handing Core Graphics the whole bitmap at 1600% makes it resample every
    /// pixel of the source just to clip almost all of it away; cropping first
    /// keeps the cost proportional to the window instead of the zoom level.
    private func drawBase(in context: CGContext) {
        let fullBounds = model.document.baseBounds
        let visible = visibleImageRect.pixelAligned.intersection(fullBounds)
        guard !visible.isEmpty else { return }

        // Magnified: rasterise a padded window onto the screenshot, so panning
        // reuses it. Otherwise: the whole visible region in one go.
        if model.visualScale > 1,
           visible.width < fullBounds.width || visible.height < fullBounds.height {
            let padded = visible
                .insetBy(dx: -visible.width * 0.3, dy: -visible.height * 0.3)
                .pixelAligned
                .intersection(fullBounds)
            drawRegion(required: visible, build: padded.isEmpty ? visible : padded, in: context)
        } else {
            drawRegion(required: displayRect, build: displayRect, in: context)
        }
    }

    /// Draws a region of the screenshot as a bitmap rasterised at exactly its
    /// on-screen pixel size, blitted 1:1.
    ///
    /// This is the single most important thing for smoothness: Core Graphics
    /// blits a whole-pixel 1:1 bitmap almost for free, but a fractional
    /// destination — which is what the canvas' zoom transform produces at almost
    /// every zoom level — drops it into a general resampler an order of
    /// magnitude slower.
    /// - Parameters:
    ///   - required: the region that must be covered, i.e. what is on screen.
    ///   - build: the region to rasterise if the cache misses — padded, so that
    ///     panning keeps hitting the same bitmap.
    private func drawRegion(required: CGRect, build: CGRect, in context: CGContext) {
        let backingScale = window?.backingScaleFactor ?? 2
        // Device pixels per image pixel.
        let deviceScale = (viewRect(fromImage: build).width * backingScale) / max(build.width, 1)

        guard let raster = rasterised(covering: required, build: build, deviceScale: deviceScale) else {
            AnnotationRenderer.drawImage(model.document.base, in: model.document.baseBounds, context: context)
            return
        }

        let onScreen = viewRect(fromImage: raster.region)
        context.saveGState()
        // Into the backing store's own coordinates. The clip set earlier lives in
        // device space, so cropping still applies.
        context.concatenate(context.ctm.inverted())
        context.interpolationQuality = .none
        // The destination takes the bitmap's own pixel size: a rounding
        // difference of one pixel is invisible, a fractional size is not.
        context.draw(raster.image, in: CGRect(x: (onScreen.minX * backingScale).rounded(),
                                              y: (onScreen.minY * backingScale).rounded(),
                                              width: CGFloat(raster.image.width),
                                              height: CGFloat(raster.image.height)))
        context.restoreGState()
    }

    /// A rasterised copy covering `region` at `deviceScale`, reusing the cached
    /// one whenever it already covers what is being asked for — otherwise
    /// panning would rebuild the bitmap on every frame.
    private func rasterised(covering required: CGRect,
                            build: CGRect,
                            deviceScale: CGFloat) -> (image: CGImage, region: CGRect)? {
        if let scaledBase, let cached = scaledBaseRegion,
           abs(scaledBaseScale - deviceScale) < 0.0001, cached.contains(required) {
            return (scaledBase, cached)
        }

        let base = model.document.base
        let source = build.pixelAligned.intersection(model.document.baseBounds)
        guard !source.isEmpty else { return nil }

        let pixelWidth = Int((source.width * deviceScale).rounded())
        let pixelHeight = Int((source.height * deviceScale).rounded())
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth * pixelHeight < 40_000_000 else { return nil }

        let cropped = source == model.document.baseBounds ? base : base.cropping(to: source)
        // Nearest neighbour is both faster and more honest when magnifying;
        // smooth resampling is faster and better looking when shrinking.
        let magnifying = deviceScale > 1
        guard let cropped,
              let produced = ImageUtilities.resize(cropped,
                                                   pixelWidth: pixelWidth,
                                                   pixelHeight: pixelHeight,
                                                   quality: magnifying ? .none : .high) else {
            return nil
        }
        scaledBase = produced
        scaledBaseRegion = source
        scaledBaseScale = deviceScale
        return (produced, source)
    }

    /// Lifts the screenshot off the blurred window backdrop.
    private func drawImageShadow(around rect: CGRect, context: CGContext) {
        // Only the edges near the window matter; blurring a shadow across a
        // rectangle tens of thousands of points wide is pure waste.
        let area = rect.intersection(bounds.insetBy(dx: -60, dy: -60))
        guard !area.isEmpty else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3),
                          blur: 10,
                          color: NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(area)
        context.restoreGState()
    }

    /// Whether the screenshot actually has transparent pixels.
    ///
    /// Almost every capture is fully opaque, and then the checkerboard is drawn
    /// under an image that hides it completely — pure waste on every frame.
    private var baseHasTransparency: Bool {
        if let cached = transparencyCache, transparencyKey == ObjectIdentifier(model.document.base) {
            return cached
        }
        let result = Self.detectTransparency(in: model.document.base)
        transparencyCache = result
        transparencyKey = ObjectIdentifier(model.document.base)
        return result
    }

    /// Checks a heavily downscaled copy: averaging keeps a fully opaque image at
    /// full alpha, while any transparency anywhere drags a pixel below it.
    private static func detectTransparency(in image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        let probe = ImageUtilities.downscale(image, maxPixelSize: 64)
        guard let sampler = PixelSampler(image: probe) else { return true }
        for y in stride(from: 0, to: probe.height, by: 2) {
            for x in stride(from: 0, to: probe.width, by: 2) {
                if sampler.alpha(at: CGPoint(x: x, y: y)) < 0.99 { return true }
            }
        }
        return false
    }

    private func drawCheckerboard(in rect: CGRect, context: CGContext) {
        guard baseHasTransparency else { return }
        // Only the part on screen is worth drawing: at high zoom `rect` can be
        // tens of thousands of points across, which is millions of squares.
        let area = rect.intersection(bounds)
        guard !area.isEmpty else { return }

        context.saveGState()
        context.clip(to: area)
        context.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
        context.fill(area)
        context.setFillColor(NSColor(white: 0.75, alpha: 1).cgColor)

        let square: CGFloat = 8
        // Start on the pattern's own grid so it does not shift while panning.
        let firstRow = ((area.minY - rect.minY) / square).rounded(.down)
        var row = Int(firstRow)
        var y = rect.minY + firstRow * square
        while y < area.maxY {
            let offset = row.isMultiple(of: 2) ? 0 : square
            let columnStart = ((area.minX - rect.minX - offset) / (square * 2)).rounded(.down)
            var x = rect.minX + offset + columnStart * square * 2
            while x < area.maxX {
                context.fill(CGRect(x: x, y: y, width: square, height: square))
                x += square * 2
            }
            y += square
            row += 1
        }
        context.restoreGState()
    }

    private func drawFrame(around rect: CGRect, context: CGContext) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
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
