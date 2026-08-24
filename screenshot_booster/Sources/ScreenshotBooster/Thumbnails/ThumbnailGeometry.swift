import CoreGraphics
import Foundation

/// Layout math for the thumbnail stack.
///
/// This is the single source of truth: the panel sizes itself from it, and the
/// swipe recogniser uses the very same rectangles to decide which card is under
/// the pointer — so the two can never disagree about where a card is.
enum ThumbnailGeometry {
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 10

    /// Where every card ends up, in the stack's own space (top-left origin).
    struct Layout {
        var size: CGSize
        var cardRects: [(id: UUID, rect: CGRect)]

        func card(at point: CGPoint) -> UUID? {
            cardRects.first { $0.rect.contains(point) }?.id
        }
    }

    /// Height of one card for a given screenshot at `width` points.
    static func cardHeight(for screenshot: Screenshot, width: CGFloat) -> CGFloat {
        let size = screenshot.outputPixelSize
        guard size.width > 0, size.height > 0 else { return width * 0.62 }
        let aspect = size.height / size.width
        return (width * aspect).clamped(to: 56...(width * 1.15)).rounded()
    }

    /// Mirrors the order `ThumbnailStackView` renders in: the newest card always
    /// sits closest to the anchored corner.
    static func orderedScreenshots(_ screenshots: [Screenshot], corner: PanelCorner) -> [Screenshot] {
        corner.stackGrowsUpwards ? screenshots : screenshots.reversed()
    }

    static func layout(for screenshots: [Screenshot], width: CGFloat, corner: PanelCorner) -> Layout {
        guard !screenshots.isEmpty else { return Layout(size: .zero, cardRects: []) }

        let showsHeader = screenshots.count > 1
        var y = padding
        var rects: [(id: UUID, rect: CGRect)] = []

        // The header sits at the far end from the anchored corner.
        if showsHeader, corner.stackGrowsUpwards {
            y += headerHeight + spacing
        }

        let ordered = orderedScreenshots(screenshots, corner: corner)
        for (index, screenshot) in ordered.enumerated() {
            let height = cardHeight(for: screenshot, width: width)
            rects.append((screenshot.id, CGRect(x: padding, y: y, width: width, height: height)))
            y += height
            if index < ordered.count - 1 { y += spacing }
        }

        if showsHeader, !corner.stackGrowsUpwards {
            y += spacing + headerHeight
        }

        return Layout(size: CGSize(width: width + padding * 2, height: y + padding),
                      cardRects: rects)
    }

    /// Size of the whole stack, before it is capped to the screen.
    static func contentSize(for screenshots: [Screenshot], width: CGFloat, corner: PanelCorner) -> CGSize {
        layout(for: screenshots, width: width, corner: corner).size
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
