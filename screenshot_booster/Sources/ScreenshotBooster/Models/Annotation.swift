import CoreGraphics
import Foundation

/// A single editable object drawn on top of a screenshot.
///
/// All coordinates are expressed in *image pixel space* with a top-left origin,
/// which keeps annotations resolution independent from the on-screen zoom level
/// and makes export a straight replay of the same drawing code.
struct Annotation: Identifiable, Codable, Equatable {
    var id: UUID
    var tool: ToolKind
    /// Path-based tools store every sampled point. Rect/segment tools store
    /// exactly two points (start and end).
    var points: [CGPoint]
    var color: RGBAColor
    var lineWidth: CGFloat
    var text: String
    var fontSize: CGFloat
    var isFilled: Bool

    init(id: UUID = UUID(),
         tool: ToolKind,
         points: [CGPoint],
         color: RGBAColor,
         lineWidth: CGFloat,
         text: String = "",
         fontSize: CGFloat = 32,
         isFilled: Bool = false) {
        self.id = id
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
        self.isFilled = isFilled
    }

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? .zero }

    /// Geometric bounds without stroke width or text metrics applied.
    var rawBounds: CGRect {
        switch tool {
        case .text:
            let size = TextLayout.size(for: self)
            return CGRect(origin: start, size: size)
        default:
            guard let first = points.first else { return .zero }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for point in points.dropFirst() {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    /// Bounds including the stroke, used for selection UI and hit testing.
    var displayBounds: CGRect {
        switch tool {
        case .text:
            return rawBounds.insetBy(dx: -4, dy: -4)
        default:
            let inset = -(lineWidth / 2 + 2)
            return rawBounds.insetBy(dx: inset, dy: inset)
        }
    }

    /// Translates every point of the annotation.
    func translated(dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        copy.points = points.map { $0.offsetBy(dx: dx, dy: dy) }
        return copy
    }

    /// Maps the annotation from one bounding box to another. Used by the resize
    /// handles so every tool resizes with a single code path.
    func resized(from oldBounds: CGRect, to newBounds: CGRect) -> Annotation {
        guard oldBounds.width > 0.0001, oldBounds.height > 0.0001 else { return self }
        let sx = newBounds.width / oldBounds.width
        let sy = newBounds.height / oldBounds.height
        var copy = self
        copy.points = points.map { point in
            CGPoint(x: newBounds.minX + (point.x - oldBounds.minX) * sx,
                    y: newBounds.minY + (point.y - oldBounds.minY) * sy)
        }
        if tool == .text {
            copy.fontSize = max(8, fontSize * min(abs(sx), abs(sy)))
        } else {
            copy.lineWidth = max(1, lineWidth * min(abs(sx), abs(sy)))
        }
        return copy
    }

    /// Corner handles are only meaningful for area-like objects; segments expose
    /// their two endpoints instead.
    var usesEndpointHandles: Bool { tool.isSegmentBased }
}
