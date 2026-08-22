import AppKit
import CoreText

/// Shared text metrics + line building for the text annotation tool.
///
/// The same `CTLine` array is used for measuring, hit testing, on-canvas
/// rendering and export, so what the user sees is exactly what gets written to
/// disk.
enum TextLayout {
    static let padding: CGFloat = 6
    static let placeholder = "Text"

    static func font(ofSize size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: max(6, size), weight: .semibold)
    }

    static func attributes(for annotation: Annotation) -> [NSAttributedString.Key: Any] {
        [
            .font: font(ofSize: annotation.fontSize),
            .foregroundColor: annotation.color.nsColor
        ]
    }

    static func displayString(for annotation: Annotation) -> String {
        annotation.text.isEmpty ? placeholder : annotation.text
    }

    /// Builds one `CTLine` per hard line break.
    static func lines(for annotation: Annotation) -> [CTLine] {
        let attributes = attributes(for: annotation)
        return displayString(for: annotation)
            .components(separatedBy: .newlines)
            .map { line in
                CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            }
    }

    static func lineHeight(for annotation: Annotation) -> CGFloat {
        let font = font(ofSize: annotation.fontSize)
        return (font.ascender - font.descender + font.leading).rounded(.up)
    }

    /// Total size of the laid out text including padding.
    static func size(for annotation: Annotation) -> CGSize {
        let lines = lines(for: annotation)
        let height = lineHeight(for: annotation) * CGFloat(max(lines.count, 1))
        var width: CGFloat = 0
        for line in lines {
            width = max(width, CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        return CGSize(width: width.rounded(.up) + padding * 2, height: height + padding * 2)
    }
}
