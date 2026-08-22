import AppKit
import SwiftUI

/// A codable, value-type color used by annotations so documents can be
/// persisted without depending on AppKit archiving.
struct RGBAColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? .red
        self.init(red: Double(converted.redComponent),
                  green: Double(converted.greenComponent),
                  blue: Double(converted.blueComponent),
                  alpha: Double(converted.alphaComponent))
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    func withAlpha(_ value: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: value)
    }

    /// Perceived luminance, used to pick a readable contrast color.
    var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    static let presets: [RGBAColor] = [
        RGBAColor(red: 1.00, green: 0.23, blue: 0.19),  // red
        RGBAColor(red: 1.00, green: 0.58, blue: 0.00),  // orange
        RGBAColor(red: 1.00, green: 0.84, blue: 0.04),  // yellow
        RGBAColor(red: 0.20, green: 0.78, blue: 0.35),  // green
        RGBAColor(red: 0.04, green: 0.52, blue: 1.00),  // blue
        RGBAColor(red: 0.69, green: 0.32, blue: 0.87),  // purple
        RGBAColor(red: 1.00, green: 1.00, blue: 1.00),  // white
        RGBAColor(red: 0.11, green: 0.11, blue: 0.12)   // near black
    ]

    static let defaultAnnotation = presets[0]
    static let defaultHighlighter = RGBAColor(red: 1.00, green: 0.90, blue: 0.10, alpha: 0.40)
}
