import Foundation

/// Owns every on-disk location the app uses and makes sure the folders exist.
enum AppPaths {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.screenshotbooster.app"

    #if SCREENSHOT_BOOSTER_TESTS
    /// Compiled only into the test executable; never shares the user's library.
    static let testDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotBoosterTests-\(UUID().uuidString)", isDirectory: true)
    #endif

    /// `~/Library/Application Support/<bundle id>`
    static var supportDirectory: URL {
        #if SCREENSHOT_BOOSTER_TESTS
        return testDirectory.appendingPathComponent("Support", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
        #endif
    }

    /// Original, unedited bitmaps of pinned screenshots.
    static var originalsDirectory: URL {
        supportDirectory.appendingPathComponent("Originals", isDirectory: true)
    }

    /// Flattened images produced for drag & drop.
    static var dragCacheDirectory: URL {
        #if SCREENSHOT_BOOSTER_TESTS
        return testDirectory.appendingPathComponent("Drags", isDirectory: true)
        #else
        FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotBoosterDrags", isDirectory: true)
        #endif
    }

    static var libraryIndexURL: URL {
        supportDirectory.appendingPathComponent("library.json", conformingTo: .json)
    }

    static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    /// Creates the directories the app writes to. Throws so callers can report a
    /// meaningful error instead of failing silently later.
    static func prepareDirectories() throws {
        for directory in [supportDirectory, originalsDirectory, dragCacheDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// `Screenshot 2025-04-01 at 12.34.56.png`, matching macOS conventions.
    static func suggestedFileName(for date: Date, format: ImageFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// Appends ` 2`, ` 3`, … when a file with the same name already exists.
    static func uniqueURL(for proposed: URL) -> URL {
        let manager = FileManager.default
        guard manager.fileExists(atPath: proposed.path) else { return proposed }
        let directory = proposed.deletingLastPathComponent()
        let ext = proposed.pathExtension
        let stem = proposed.deletingPathExtension().lastPathComponent
        var index = 2
        while index < 10_000 {
            let candidate = directory
                .appendingPathComponent("\(stem) \(index)")
                .appendingPathExtension(ext)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
        return proposed
    }
}
