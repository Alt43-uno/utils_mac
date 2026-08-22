import Foundation

/// Every tool available in the editor. `select` is the manipulation tool; the
/// rest create annotation objects.
enum ToolKind: String, Codable, CaseIterable, Identifiable {
    case select
    case pen
    case arrow
    case line
    case rect
    case ellipse
    case outline
    case highlighter
    case text
    case blur
    case pixelate
    case crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .pen: return "Draw"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rect: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .outline: return "Outline area"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .crop: return "Crop"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "scribble"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .outline: return "lasso"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .crop: return "crop"
        }
    }

    /// Single-key shortcut used while the canvas has focus.
    var shortcutKey: String {
        switch self {
        case .select: return "v"
        case .pen: return "d"
        case .arrow: return "a"
        case .line: return "l"
        case .rect: return "r"
        case .ellipse: return "o"
        case .outline: return "s"
        case .highlighter: return "h"
        case .text: return "t"
        case .blur: return "b"
        case .pixelate: return "p"
        case .crop: return "c"
        }
    }

    /// Tools that are defined by a freehand path rather than two corner points.
    var isPathBased: Bool {
        self == .pen || self == .highlighter || self == .outline
    }

    /// Tools whose geometry is a rectangle defined by two dragged corners.
    var isRectBased: Bool {
        self == .rect || self == .ellipse || self == .blur || self == .pixelate || self == .crop
    }

    var isSegmentBased: Bool {
        self == .arrow || self == .line
    }

    /// Effects sample the underlying bitmap instead of using a stroke color.
    var isEffect: Bool {
        self == .blur || self == .pixelate
    }

    var usesColor: Bool {
        !isEffect && self != .crop && self != .select
    }

    var usesLineWidth: Bool {
        usesColor && self != .text
    }

    /// Tools that create persistent annotation objects.
    var createsAnnotation: Bool {
        self != .select && self != .crop
    }

    /// Tool order shown in the toolbar.
    static let editorOrder: [ToolKind] = [
        .select, .pen, .arrow, .line, .rect, .ellipse, .outline,
        .highlighter, .text, .blur, .pixelate, .crop
    ]
}
