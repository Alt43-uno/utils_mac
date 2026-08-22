import CoreGraphics
import Foundation

/// Layout math shared by the SwiftUI stack and the panel that sizes itself
/// around it, so the window frame always matches what is drawn.
enum ThumbnailGeometry {
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 10

    /// Height of one card for a given screenshot at `width` points.
    static func cardHeight(for screenshot: Screenshot, width: CGFloat) -> CGFloat {
        let size = screenshot.outputPixelSize
        guard size.width > 0, size.height > 0 else { return width * 0.62 }
        let aspect = size.height / size.width
        return (width * aspect).clamped(to: 56...(width * 1.15)).rounded()
    }

    /// Size of the whole stack, before it is capped to the screen.
    static func contentSize(for screenshots: [Screenshot], width: CGFloat) -> CGSize {
        guard !screenshots.isEmpty else { return .zero }
        var height = padding * 2
        if screenshots.count > 1 { height += headerHeight + spacing }
        for (index, screenshot) in screenshots.enumerated() {
            height += cardHeight(for: screenshot, width: width)
            if index < screenshots.count - 1 { height += spacing }
        }
        return CGSize(width: width + padding * 2, height: height)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
