import AppKit

/// Which corner of the screen the thumbnail stack lives in.
enum PanelCorner: String, Codable, CaseIterable, Identifiable {
    case bottomLeft, bottomRight, topLeft, topRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        }
    }

    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
    var isLeading: Bool { self == .bottomLeft || self == .topLeft }

    /// New thumbnails are inserted closest to the corner, so the stack grows
    /// away from it.
    var stackGrowsUpwards: Bool { isBottom }

    /// Origin for a panel of `size` inside `visibleFrame`, in AppKit screen
    /// coordinates.
    func origin(for size: CGSize, in visibleFrame: CGRect, margin: CGFloat) -> CGPoint {
        let x = isLeading ? visibleFrame.minX + margin
                          : visibleFrame.maxX - margin - size.width
        let y = isBottom ? visibleFrame.minY + margin
                         : visibleFrame.maxY - margin - size.height
        return CGPoint(x: x, y: y)
    }
}

/// Which screen the thumbnail stack should follow.
enum PanelScreenPolicy: String, Codable, CaseIterable, Identifiable {
    case screenWithMouse
    case captureScreen
    case primary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenWithMouse: return "Screen with the pointer"
        case .captureScreen: return "Screen the shot came from"
        case .primary: return "Main screen"
        }
    }
}
