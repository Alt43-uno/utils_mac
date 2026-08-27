import AppKit
import CoreGraphics
import CoreText

/// Draws documents and annotations.
///
/// Everything is drawn in *image space*: origin top-left, y growing downwards,
/// units are source pixels. The canvas view and the exporter both funnel through
/// this type, which guarantees the exported PNG matches the preview exactly.
enum AnnotationRenderer {

    // MARK: - Public entry points

    /// Flattens a document into a new bitmap, applying the crop rectangle.
    static func flatten(_ document: ScreenshotDocument, effects: EffectCache) -> CGImage? {
        let visible = document.visibleRect.pixelAligned
        guard visible.width >= 1, visible.height >= 1 else { return nil }
        guard let context = ImageUtilities.makeContext(pixelWidth: Int(visible.width),
                                                       pixelHeight: Int(visible.height)) else { return nil }
        context.interpolationQuality = .high
        // Move into image space and shift so the crop origin lands at (0, 0).
        context.translateBy(x: 0, y: visible.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -visible.minX, y: -visible.minY)
        context.clip(to: visible)
        draw(document: document, in: context, effects: effects)
        return context.makeImage()
    }

    /// Draws the base bitmap plus every annotation. The context must already be
    /// in image space.
    static func draw(document: ScreenshotDocument, in context: CGContext, effects: EffectCache) {
        drawImage(document.base, in: document.baseBounds, context: context)
        for annotation in document.annotations {
            draw(annotation: annotation, base: document.base, in: context, effects: effects)
        }
    }

    /// Draws a `CGImage` into image space (handles the extra vertical flip).
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: - Annotations

    /// - Parameter visibleRect: the region actually on screen, in image pixels.
    ///   Effects are cropped to it so a zoomed-in canvas does not blit millions
    ///   of off-screen pixels every frame.
    static func draw(annotation: Annotation,
                     base: CGImage,
                     in context: CGContext,
                     effects: EffectCache,
                     visibleRect: CGRect? = nil) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(max(1, annotation.lineWidth))

        switch annotation.tool {
        case .pen:
            guard let path = strokePath(for: annotation) else { break }
            context.addPath(path)
            context.strokePath()

        case .outline:
            guard let path = strokePath(for: annotation, closed: true) else { break }
            context.addPath(path)
            context.strokePath()

        case .highlighter:
            guard let path = strokePath(for: annotation) else { break }
            context.setBlendMode(.multiply)
            context.setLineCap(.butt)
            context.setStrokeColor(annotation.color.withAlpha(min(annotation.color.alpha, 0.45)).cgColor)
            context.setLineWidth(max(6, annotation.lineWidth * 3))
            context.addPath(path)
            context.strokePath()

        case .line:
            context.move(to: annotation.start)
            context.addLine(to: annotation.end)
            context.strokePath()

        case .arrow:
            drawArrow(annotation, in: context)

        case .rect:
            let rect = CGRect(corner: annotation.start, opposite: annotation.end)
            if annotation.isFilled {
                context.fill(rect)
            } else {
                context.stroke(strokeAligned(rect, lineWidth: annotation.lineWidth))
            }

        case .ellipse:
            let rect = CGRect(corner: annotation.start, opposite: annotation.end)
            if annotation.isFilled {
                context.fillEllipse(in: rect)
            } else {
                context.strokeEllipse(in: strokeAligned(rect, lineWidth: annotation.lineWidth))
            }

        case .text:
            drawText(annotation, in: context)

        case .blur, .pixelate:
            let rect = CGRect(corner: annotation.start, opposite: annotation.end)
                .clamped(to: CGRect(x: 0, y: 0, width: base.width, height: base.height))
                .pixelAligned
            guard rect.width >= 1, rect.height >= 1,
                  let effect = effects.image(for: annotation, rect: rect, base: base) else { break }

            guard let visibleRect else {
                drawImage(effect, in: rect, context: context)
                break
            }
            let onScreen = rect.intersection(visibleRect.pixelAligned)
            guard !onScreen.isEmpty else { break }
            if onScreen == rect {
                drawImage(effect, in: rect, context: context)
            } else if let cropped = effect.cropping(to: CGRect(x: onScreen.minX - rect.minX,
                                                               y: onScreen.minY - rect.minY,
                                                               width: onScreen.width,
                                                               height: onScreen.height)) {
                drawImage(cropped, in: onScreen, context: context)
            }

        case .select, .crop:
            break
        }
    }

    // MARK: - Geometry helpers

    /// Insets a rect by half the stroke width so the drawn outline sits inside
    /// the dragged bounds, without collapsing shapes thinner than the stroke.
    private static func strokeAligned(_ rect: CGRect, lineWidth: CGFloat) -> CGRect {
        let inset = min(max(lineWidth, 1) / 2, min(rect.width, rect.height) / 2)
        return rect.insetBy(dx: inset, dy: inset)
    }

    /// Smoothed path through the sampled points of a freehand stroke.
    static func strokePath(for annotation: Annotation, closed: Bool = false) -> CGPath? {
        let points = annotation.points
        guard points.count > 1 else {
            // A single tap still deserves a visible dot.
            guard let point = points.first else { return nil }
            let radius = max(0.5, annotation.lineWidth / 2)
            return CGPath(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                            width: radius * 2, height: radius * 2), transform: nil)
        }
        let path = CGMutablePath()
        path.move(to: points[0])
        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for index in 1..<(points.count - 1) {
                let current = points[index]
                let next = points[index + 1]
                let midpoint = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                path.addQuadCurve(to: midpoint, control: current)
            }
            path.addLine(to: points[points.count - 1])
        }
        if closed { path.closeSubpath() }
        return path
    }

    private static func drawArrow(_ annotation: Annotation, in context: CGContext) {
        let start = annotation.start
        let end = annotation.end
        let width = max(1, annotation.lineWidth)
        let length = start.distance(to: end)
        guard length > 0.5 else { return }

        let headLength = min(max(width * 4.5, 14), length)
        let headWidth = headLength * 0.72
        let angle = atan2(end.y - start.y, end.x - start.x)

        // Shorten the shaft so the stroke does not poke through the head tip.
        let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.72,
                               y: end.y - sin(angle) * headLength * 0.72)
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()

        let base = CGPoint(x: end.x - cos(angle) * headLength,
                           y: end.y - sin(angle) * headLength)
        let normal = CGPoint(x: -sin(angle), y: cos(angle))
        let path = CGMutablePath()
        path.move(to: end)
        path.addLine(to: CGPoint(x: base.x + normal.x * headWidth / 2, y: base.y + normal.y * headWidth / 2))
        path.addLine(to: CGPoint(x: base.x - normal.x * headWidth / 2, y: base.y - normal.y * headWidth / 2))
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }

    private static func drawText(_ annotation: Annotation, in context: CGContext) {
        let lines = TextLayout.lines(for: annotation)
        guard !lines.isEmpty else { return }
        let lineHeight = TextLayout.lineHeight(for: annotation)
        let font = TextLayout.font(ofSize: annotation.fontSize)
        let origin = annotation.start

        context.saveGState()
        // Core Text draws upwards; flip the text matrix so glyphs stay upright in
        // our top-left origin space.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        // A subtle contrast shadow keeps light text readable on light content.
        let shadowAlpha = annotation.color.luminance > 0.6 ? 0.35 : 0.25
        context.setShadow(offset: CGSize(width: 0, height: 1),
                          blur: 2.5,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: shadowAlpha))

        for (index, line) in lines.enumerated() {
            let baseline = origin.y + TextLayout.padding + lineHeight * CGFloat(index) + font.ascender
            context.textPosition = CGPoint(x: origin.x + TextLayout.padding, y: baseline)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
