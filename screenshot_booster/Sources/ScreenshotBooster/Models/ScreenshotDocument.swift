import CoreGraphics
import Foundation

/// An in-memory editable screenshot: the untouched base bitmap plus the
/// non-destructive edits applied on top of it.
struct ScreenshotDocument: Equatable {
    var base: CGImage
    var annotations: [Annotation]
    /// Crop in image pixel space with a top-left origin. `nil` means "full image".
    var cropRect: CGRect?
    var scale: CGFloat

    init(base: CGImage, annotations: [Annotation] = [], cropRect: CGRect? = nil, scale: CGFloat = 2) {
        self.base = base
        self.annotations = annotations
        self.cropRect = cropRect
        self.scale = scale
    }

    var baseSize: CGSize {
        CGSize(width: base.width, height: base.height)
    }

    var baseBounds: CGRect {
        CGRect(origin: .zero, size: baseSize)
    }

    /// The visible region of the base image.
    var visibleRect: CGRect {
        (cropRect ?? baseBounds).clamped(to: baseBounds)
    }

    var outputSize: CGSize { visibleRect.size }

    static func == (lhs: ScreenshotDocument, rhs: ScreenshotDocument) -> Bool {
        lhs.base === rhs.base && lhs.annotations == rhs.annotations && lhs.cropRect == rhs.cropRect
    }

    func annotation(withID id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        annotations.firstIndex { $0.id == id }
    }
}
