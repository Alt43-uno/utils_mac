import CoreGraphics
import Foundation

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }
}

extension CGRect {
    /// Builds a rect from two arbitrary corners.
    init(corner a: CGPoint, opposite b: CGPoint) {
        self.init(x: min(a.x, b.x),
                  y: min(a.y, b.y),
                  width: abs(a.x - b.x),
                  height: abs(a.y - b.y))
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }

    /// Rounds the rect outward to whole pixels — avoids half-pixel seams when
    /// cropping bitmaps.
    var pixelAligned: CGRect {
        CGRect(x: floor(minX), y: floor(minY), width: ceil(width), height: ceil(height))
    }

    func clamped(to bounds: CGRect) -> CGRect {
        intersection(bounds)
    }

    /// Ensures a minimum size, growing symmetrically around the center.
    func expandedToMinimum(_ minSize: CGFloat) -> CGRect {
        var rect = self
        if rect.width < minSize {
            rect.origin.x -= (minSize - rect.width) / 2
            rect.size.width = minSize
        }
        if rect.height < minSize {
            rect.origin.y -= (minSize - rect.height) / 2
            rect.size.height = minSize
        }
        return rect
    }
}

extension CGSize {
    /// Scale factor that fits `self` into `container` without upscaling beyond `maxScale`.
    func fitScale(in container: CGSize, maxScale: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return min(maxScale, min(container.width / width, container.height / height))
    }

    func scaled(by factor: CGFloat) -> CGSize {
        CGSize(width: width * factor, height: height * factor)
    }
}

enum CoordinateSpaceConverter {
    /// Height of the coordinate space used by Core Graphics global coordinates,
    /// i.e. the primary display's height in points.
    static var primaryScreenHeight: CGFloat {
        NSScreenProvider.primaryHeight
    }

    /// Converts a Core Graphics global rect (top-left origin) into AppKit global
    /// coordinates (bottom-left origin).
    static func appKitRect(fromCoreGraphics rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryScreenHeight - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }
}
