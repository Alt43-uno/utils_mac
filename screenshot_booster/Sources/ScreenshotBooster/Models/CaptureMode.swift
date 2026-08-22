import Foundation

/// The three ways a capture can be started.
enum CaptureMode: String, Codable, CaseIterable, Identifiable {
    case area
    case window
    case fullScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: return "Capture Area"
        case .window: return "Capture Window"
        case .fullScreen: return "Capture Screen"
        }
    }

    var shortTitle: String {
        switch self {
        case .area: return "Area"
        case .window: return "Window"
        case .fullScreen: return "Screen"
        }
    }

    var symbolName: String {
        switch self {
        case .area: return "selection.pin.in.out"
        case .window: return "macwindow"
        case .fullScreen: return "display"
        }
    }
}
