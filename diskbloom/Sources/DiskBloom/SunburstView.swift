import SwiftUI
import AppKit
import DiskBloomCore

struct SunburstView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> SunburstCanvas { SunburstCanvas(model: model) }
    func updateNSView(_ view: SunburstCanvas, context: Context) { view.update() }
}

@MainActor
final class SunburstCanvas: NSView, NSDraggingSource {
    let model: AppModel
    var segments: [MapSegment] = []
    var shapes: [(MapSegment, CGPath)] = []
    var layoutKey = ""
    var tracking: NSTrackingArea?
    var pressedSegment: MapSegment?
    var pressPoint = NSPoint.zero
    var dragging = false
    var magnification: CGFloat = 0
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
    var outer: CGFloat { min(bounds.width, bounds.height) / 2 - 22 }
    var inner: CGFloat { max(48, outer * 0.23) }
    var ringWidth: CGFloat { (outer - inner) / 7 }
    init(model: AppModel) {
        self.model = model; super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityLabel(L.text("Interactive disk map. Browse the same files in the list on the right.", "Интерактивная карта диска. Эти же файлы доступны в списке справа."))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update() {
        let key = "\(model.report?.startedAt.timeIntervalSince1970 ?? 0)|\(model.currentID)|\(model.metric.rawValue)|\(model.report?.nodes.count ?? 0)"
        if key != layoutKey {
            layoutKey = key
            segments = model.report.map { SunburstLayout.segments(report: $0, rootID: model.currentID, metric: model.metric) } ?? []
        }
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area; super.updateTrackingAreas()
    }
    func path(_ segment: MapSegment) -> CGPath {
        let r0 = inner + CGFloat(segment.depth) * ringWidth + 0.8
        let r1 = r0 + ringWidth - 1.6
        let gap = min(0.0035, (segment.endAngle - segment.startAngle) * 0.1)
        let a = CGFloat(segment.startAngle + gap), b = CGFloat(segment.endAngle - gap)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
        path.addLine(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
        path.addArc(center: center, radius: r1, startAngle: a, endAngle: b, clockwise: false)
        path.addLine(to: CGPoint(x: center.x + cos(b) * r0, y: center.y + sin(b) * r0))
        path.addArc(center: center, radius: r0, startAngle: b, endAngle: a, clockwise: true)
        path.closeSubpath(); return path
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        shapes = []
        // Quiet concentric guides retain orientation without competing with the data.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.035).cgColor); context.setLineWidth(1)
        for i in [1, 3, 5, 7] {
            let r = inner + CGFloat(i) * ringWidth
            context.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        for segment in segments {
            let shape = path(segment); shapes.append((segment, shape))
            var color = Theme.colors[segment.colorIndex % Theme.colors.count]
            let node = segment.nodeID.flatMap { model.report?.nodes[$0] }
            if node?.isRestricted == true { color = NSColor(hex: 0xAB8ADB) }
            let depthBlend = CGFloat(segment.depth) * 0.055
            color = color.blended(withFraction: depthBlend, of: .white) ?? color
            var alpha: CGFloat = segment.isGroup ? 0.35 : 1
            if let node, model.isCollected(node) { alpha = 0.28 }
            if let hovered = model.hoveredID, let id = segment.nodeID, hovered != id,
               !(model.report?.contains(hovered, descendant: id) ?? false) { alpha *= 0.48 }
            context.addPath(shape); context.setFillColor(color.withAlphaComponent(alpha).cgColor); context.fillPath()
            if segment.nodeID != nil && segment.nodeID == (model.hoveredID ?? model.selectedID) {
                context.addPath(shape); context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor); context.setLineWidth(1.5); context.strokePath()
            }
        }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.09).cgColor)
        context.strokeEllipse(in: CGRect(x: center.x - inner + 7, y: center.y - inner + 7, width: (inner - 7) * 2, height: (inner - 7) * 2))
    }
    func hit(_ point: CGPoint) -> MapSegment? { shapes.reversed().first { $0.1.contains(point) }?.0 }
    override func mouseMoved(with event: NSEvent) {
        let hit = hit(convert(event.locationInWindow, from: nil))
        if model.hoveredID != hit?.nodeID { model.hoveredID = hit?.nodeID }
        if hit != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }
    override func mouseExited(with event: NSEvent) { model.hoveredID = nil; NSCursor.arrow.set() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pressPoint = convert(event.locationInWindow, from: nil); pressedSegment = hit(pressPoint); dragging = false
    }
    override func mouseUp(with event: NSEvent) {
        guard !dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - center.x, point.y - center.y) < inner { model.goUp(); return }
        guard let segment = hit(point) else { return }
        if let id = segment.nodeID { model.navigate(id) } else { model.showGroup(segment.groupedIDs) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let segment = pressedSegment, let id = segment.nodeID,
              let node = model.report?.nodes[id], model.canCollect(node), let source = model.source else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - pressPoint.x, point.y - pressPoint.y) > 7 else { return }
        dragging = true
        let pasteboard = NSPasteboardItem(); pasteboard.setString("\(source.id)#\(id)", forType: .string)
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        let image = NSImage(size: NSSize(width: 38, height: 38), flipped: false) { rect in
            Theme.colors[segment.colorIndex % Theme.colors.count].setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill(); return true
        }
        item.setDraggingFrame(NSRect(x: point.x - 19, y: point.y - 19, width: 38, height: 38), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    override func magnify(with event: NSEvent) {
        magnification += event.magnification
        if magnification > 0.3, let id = model.hoveredID { model.navigate(id); magnification = 0 }
        else if magnification < -0.3 { model.goUp(); magnification = 0 }
        if event.phase == .ended { magnification = 0 }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { model.preview() }
        else if event.keyCode == 51 && event.modifierFlags.contains(.command) { model.collect() }
        else if event.keyCode == 53 { model.goUp() }
        else { super.keyDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let id = hit(convert(event.locationInWindow, from: nil))?.nodeID else { return nil }
        model.selectedID = id
        let menu = NSMenu()
        for (title, action) in [(L.preview, #selector(previewItem)), (L.reveal, #selector(revealItem)), (L.collect, #selector(collectItem))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc func previewItem() { model.preview() }
    @objc func revealItem() { model.reveal() }
    @objc func collectItem() { model.collect() }
}
