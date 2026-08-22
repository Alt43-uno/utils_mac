import AppKit
import UniformTypeIdentifiers

/// Writes flattened screenshots to disk, including the Save As panel.
@MainActor
enum ExportService {

    /// Writes `image` to `url`, creating intermediate folders when needed.
    static func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double) throws {
        let data = try ImageUtilities.encode(image, format: format, quality: quality)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            Log.storage.info("Wrote image to \(url.path, privacy: .public)")
        } catch {
            throw AppError.fileWriteFailed(url: url, underlying: error.localizedDescription)
        }
    }

    /// Saves into the configured folder using an automatic, non-colliding name.
    @discardableResult
    static func saveToConfiguredFolder(_ image: CGImage,
                                       date: Date,
                                       settings: SettingsStore) throws -> URL {
        let name = AppPaths.suggestedFileName(for: date, format: settings.imageFormat)
        let target = AppPaths.uniqueURL(for: settings.saveDirectory.appendingPathComponent(name))
        try write(image, to: target, format: settings.imageFormat, quality: settings.exportQuality)
        return target
    }

    /// Presents the Save As panel. Returns `nil` when the user cancels.
    static func runSavePanel(image: CGImage,
                             suggestedName: String,
                             directory: URL,
                             settings: SettingsStore,
                             accessoryFormat: ImageFormat) throws -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [accessoryFormat.utType]
        panel.isExtensionHidden = false
        panel.level = .modalPanel

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        // Respect the extension the user typed, if it maps to a format we support.
        let format = ImageFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() }
            ?? (url.pathExtension.lowercased() == "jpeg" ? .jpeg : accessoryFormat)
        try write(image, to: url, format: format, quality: settings.exportQuality)
        return url
    }

    /// Reveals a file in Finder, falling back to opening its folder.
    static func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
