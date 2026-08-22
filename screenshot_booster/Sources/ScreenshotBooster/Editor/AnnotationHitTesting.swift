import CoreGraphics
import Foundation

/// The eight resize handles of a bounding box plus the two endpoint handles used
/// by lines and arrows.
enum ResizeHandle: Int, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case start, end

    var isEndpoint: Bool { self == .start || self == .end }

    func position(in rect: CGRect, annotation: Annotation) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .start: return annotation.start
        case .end: return annotation.end
        }
    }

    /// Applies a drag to a bounding box. Endpoint handles are handled separately.
    func resize(_ rect: CGRect, to point: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch self {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        case .start, .end: break
        }
        return CGRect(corner: CGPoint(x: minX, y: minY), opposite: CGPoint(x: maxX, y: maxY))
    }

    var cursorKind: CursorKind {
        switch self {
        case .topLeft, .bottomRight: return .diagonalDown
        case .topRight, .bottomLeft: return .diagonalUp
        case .top, .bottom: return .vertical
        case .left, .right: return .horizontal
        case .start, .end: return .crosshair
        }
    }

    enum CursorKind { case diagonalDown, diagonalUp, vertical, horizontal, crosshair }
}

enum AnnotationHitTesting {

    /// Handles the given annotation exposes when selected.
    static func handles(for annotation: Annotation) -> [ResizeHandle] {
        annotation.usesEndpointHandles ? [.start, .end]
                                       : [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]
    }

    /// Returns the handle under `point`, if any. `tolerance` is in image pixels.
    static func handle(at point: CGPoint, for annotation: Annotation, tolerance: CGFloat) -> ResizeHandle? {
        let bounds = annotation.displayBounds
        return handles(for: annotation).first { handle in
            handle.position(in: bounds, annotation: annotation).distance(to: point) <= tolerance
        }
    }

    /// Topmost annotation containing `point`, searched front-to-back.
    static func annotation(at point: CGPoint, in annotations: [Annotation], tolerance: CGFloat) -> Annotation? {
        annotations.last { contains(annotation: $0, point: point, tolerance: tolerance) }
    }

    static func contains(annotation: Annotation, point: CGPoint, tolerance: CGFloat) -> Bool {
        // Cheap rejection first.
        guard annotation.displayBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }

        switch annotation.tool {
        case .text, .blur, .pixelate:
            return annotation.displayBounds.contains(point)

        case .rect where annotation.isFilled, .ellipse where annotation.isFilled:
            let rect = CGRect(corner: annotation.start, opposite: annotation.end)
            if annotation.tool == .rect { return rect.contains(point) }
            return CGPath(ellipseIn: rect, transform: nil).contains(point)

        case .rect:
            let rect = CGRect(corner: annotation.start, opposite: annotation.end)
            return strokeContains(CGPath(rect: rect, transform: nil), annotation: annotation, point: point, tolerance: tolerance)

        case .ellipse:
            let rect = CGRect(corner: annotation.start, opposite: annotation.end)
            return strokeContains(CGPath(ellipseIn: rect, transform: nil), annotation: annotation, point: point, tolerance: tolerance)

        case .line, .arrow:
            let path = CGMutablePath()
            path.move(to: annotation.start)
            path.addLine(to: annotation.end)
            return strokeContains(path, annotation: annotation, point: point, tolerance: tolerance)

        case .pen, .highlighter, .outline:
            guard let path = AnnotationRenderer.strokePath(for: annotation, closed: annotation.tool == .outline) else { return false }
            return strokeContains(path, annotation: annotation, point: point, tolerance: tolerance)

        case .select, .crop:
            return false
        }
    }

    private static func strokeContains(_ path: CGPath, annotation: Annotation, point: CGPoint, tolerance: CGFloat) -> Bool {
        let baseWidth = annotation.tool == .highlighter ? annotation.lineWidth * 3 : annotation.lineWidth
        let width = max(baseWidth, tolerance * 2)
        let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
        return stroked.contains(point)
    }
}
