import AppKit
import ScreenCaptureKit

/// A frozen image of one display plus the geometry needed to map between screen
/// points and image pixels.
struct DisplaySnapshot {
    let displayID: CGDirectDisplayID
    let screen: NSScreen
    let image: CGImage
    /// Backing scale factor of the display (2 on Retina).
    let scale: CGFloat

    var frame: CGRect { screen.frame }

    /// Converts a point in the overlay view (bottom-left origin, points) into
    /// image pixel space (top-left origin).
    func imagePoint(fromViewPoint point: CGPoint, viewHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: (viewHeight - point.y) * scale)
    }

    func imageRect(fromViewRect rect: CGRect, viewHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale,
               y: (viewHeight - rect.maxY) * scale,
               width: rect.width * scale,
               height: rect.height * scale)
    }
}

/// A capturable window with its frame already converted to AppKit coordinates.
struct WindowTarget: Identifiable {
    let window: SCWindow
    /// Frame in AppKit global coordinates (bottom-left origin).
    let frame: CGRect
    let title: String
    let applicationName: String

    var id: CGWindowID { window.windowID }

    var displayLabel: String {
        title.isEmpty ? applicationName : "\(applicationName) — \(title)"
    }

    init?(window: SCWindow) {
        guard window.frame.width > 24, window.frame.height > 24 else { return nil }
        self.window = window
        self.frame = CoordinateSpaceConverter.appKitRect(fromCoreGraphics: window.frame)
        self.title = window.title ?? ""
        self.applicationName = window.owningApplication?.applicationName ?? "Window"
    }
}
