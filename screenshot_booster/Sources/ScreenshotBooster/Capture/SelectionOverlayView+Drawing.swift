import AppKit

/// Everything the capture overlay paints on top of the frozen screen image:
/// the dimming mask, the selection chrome, the window highlight, the size and
/// hint badges, and the pixel magnifier.
extension SelectionOverlayView {

    func currentHighlightRect() -> CGRect? {
        if mode == .window {
            return hoveredTarget.map { localRect(for: $0).clamped(to: bounds) }
        }
        return selectionRect.width > 0 && selectionRect.height > 0 ? selectionRect : nil
    }

    func drawDimming(excluding rect: CGRect?, in context: CGContext) {
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

    func drawSelectionChrome(_ rect: CGRect, in context: CGContext) {
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

    func drawSizeBadge(for rect: CGRect) {
        let pixels = snapshot.imageRect(fromViewRect: rect, viewHeight: bounds.height)
        let text = "\(Int(pixels.width.rounded())) × \(Int(pixels.height.rounded()))"
        var origin = CGPoint(x: rect.minX, y: rect.minY - 26)
        if origin.y < bounds.minY + 4 { origin.y = rect.maxY + 8 }
        drawBadge(text: text, at: origin, accent: false)
    }

    func drawWindowLabel(for target: WindowTarget, rect: CGRect) {
        let size = "\(Int(target.frame.width.rounded())) × \(Int(target.frame.height.rounded()))"
        let text = "\(target.displayLabel)  ·  \(size)"
        var origin = CGPoint(x: rect.minX + 8, y: rect.minY - 30)
        if origin.y < bounds.minY + 4 { origin.y = rect.minY + 8 }
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - 240)
        drawBadge(text: text, at: origin, accent: true)
    }

    func drawHintBar() {
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

    func drawLoupe(in context: CGContext) {
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
