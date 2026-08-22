import Foundation
import OSLog

/// Central logging facade. Subsystem is derived from the bundle identifier so
/// log messages can be filtered in Console.app.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.screenshotbooster.app"

    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let editor = Logger(subsystem: subsystem, category: "editor")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let app = Logger(subsystem: subsystem, category: "app")
}
