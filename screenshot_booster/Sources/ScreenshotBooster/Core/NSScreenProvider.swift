import AppKit

/// Small indirection around `NSScreen` so geometry helpers stay testable and so
/// display lookups live in one place.
enum NSScreenProvider {
    /// The primary screen (the one whose origin is `.zero`).
    static var primary: NSScreen? { NSScreen.screens.first }

    static var primaryHeight: CGFloat { primary?.frame.height ?? 0 }

    static var screenWithMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? primary
    }

    static var activeScreen: NSScreen? {
        NSApp.keyWindow?.screen ?? NSScreen.main ?? primary
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// A stable identifier that survives relaunches better than the display ID.
    var persistentIdentifier: String {
        "\(displayID)-\(Int(frame.width))x\(Int(frame.height))"
    }
}
