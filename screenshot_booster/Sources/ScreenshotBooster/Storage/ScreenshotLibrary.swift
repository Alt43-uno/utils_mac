import AppKit
import Combine

/// The single source of truth for pinned screenshots.
///
/// Bitmaps live on disk; the library keeps a small in-memory cache of decoded
/// originals and rendered thumbnails, and persists its index so pins survive a
/// relaunch.
@MainActor
final class ScreenshotLibrary: ObservableObject {

    /// Ordered oldest → newest.
    @Published private(set) var screenshots: [Screenshot] = []

    private let settings: SettingsStore
    private let effects = EffectCache()
    private let baseImageCache = LRUCache<UUID, CGImage>(capacity: 6)
    private var thumbnailCache: [UUID: NSImage] = [:]
    /// Bitmaps whose PNG is still being written in the background. Held strongly
    /// so they can never be evicted before they exist on disk.
    private var pendingWrites: [UUID: CGImage] = [:]
    private var saveWorkItem: DispatchWorkItem?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Loading

    func load() {
        do {
            try AppPaths.prepareDirectories()
        } catch {
            Log.storage.error("Could not create support directories: \(error.localizedDescription, privacy: .public)")
        }

        guard settings.restorePinnedScreenshots else {
            purgeEverything()
            return
        }

        guard let data = try? Data(contentsOf: AppPaths.libraryIndexURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([Screenshot].self, from: data)
            // Drop entries whose bitmap disappeared (manually deleted, disk cleanup…).
            screenshots = decoded.filter { FileManager.default.fileExists(atPath: originalURL(for: $0).path) }
            if screenshots.count != decoded.count { persist() }
            Log.storage.info("Restored \(self.screenshots.count, privacy: .public) pinned screenshots")
        } catch {
            Log.storage.error("Library index unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
        }
        pruneOrphanedFiles()
    }

    // MARK: - Mutations

    /// Pins a freshly captured bitmap.
    ///
    /// Encoding a full-resolution PNG costs 100 ms or more, which would show up
    /// as a stutter right after the shutter, so the write happens in the
    /// background while the bitmap stays available in memory.
    @discardableResult
    func add(image: CGImage, scale: CGFloat, mode: CaptureMode, sourceName: String?) throws -> Screenshot {
        try AppPaths.prepareDirectories()

        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let url = AppPaths.originalsDirectory.appendingPathComponent(fileName)

        let screenshot = Screenshot(id: id,
                                    fileName: fileName,
                                    pixelWidth: image.width,
                                    pixelHeight: image.height,
                                    scale: scale,
                                    mode: mode,
                                    sourceName: sourceName)
        baseImageCache[id] = image
        pendingWrites[id] = image
        screenshots.append(screenshot)
        persist()

        Task.detached(priority: .userInitiated) {
            let failure: AppError? = {
                do {
                    let data = try ImageUtilities.encode(image, format: .png)
                    try data.write(to: url, options: .atomic)
                    return nil
                } catch {
                    return AppError.fileWriteFailed(url: url, underlying: error.localizedDescription)
                }
            }()
            await MainActor.run { [weak self] in
                self?.pendingWrites.removeValue(forKey: id)
                if let failure {
                    Log.storage.error("Could not store the capture: \(failure.localizedDescription, privacy: .public)")
                    ErrorPresenter.present(failure)
                    return
                }
                // The shot may have been dismissed while the write was in
                // flight, in which case `remove` deleted a file that did not
                // exist yet.
                if self?.screenshot(with: id) == nil {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        return screenshot
    }

    func update(_ screenshot: Screenshot) {
        guard let index = screenshots.firstIndex(where: { $0.id == screenshot.id }) else { return }
        screenshots[index] = screenshot
        thumbnailCache[screenshot.id] = nil
        persist()
    }

    func remove(id: UUID) {
        guard let index = screenshots.firstIndex(where: { $0.id == id }) else { return }
        let screenshot = screenshots.remove(at: index)
        thumbnailCache[id] = nil
        baseImageCache[id] = nil
        pendingWrites.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: originalURL(for: screenshot))
        removeDragFiles(for: id, except: AppPaths.dragCacheDirectory)
        persist()
    }

    func removeAll() {
        let all = screenshots
        screenshots.removeAll()
        thumbnailCache.removeAll()
        baseImageCache.removeAll()
        pendingWrites.removeAll()
        for screenshot in all {
            try? FileManager.default.removeItem(at: originalURL(for: screenshot))
        }
        persist()
    }

    func screenshot(with id: UUID) -> Screenshot? {
        screenshots.first { $0.id == id }
    }

    // MARK: - Images

    func originalURL(for screenshot: Screenshot) -> URL {
        AppPaths.originalsDirectory.appendingPathComponent(screenshot.fileName)
    }

    func baseImage(for screenshot: Screenshot) throws -> CGImage {
        if let pending = pendingWrites[screenshot.id] { return pending }
        if let cached = baseImageCache[screenshot.id] { return cached }
        let image = try ImageUtilities.loadImage(at: originalURL(for: screenshot))
        baseImageCache[screenshot.id] = image
        return image
    }

    func document(for screenshot: Screenshot) throws -> ScreenshotDocument {
        ScreenshotDocument(base: try baseImage(for: screenshot),
                           annotations: screenshot.annotations,
                           cropRect: screenshot.cropRect,
                           scale: screenshot.scale)
    }

    /// Flattened output — what Copy, Save and drag & drop all use.
    func flattenedImage(for screenshot: Screenshot) throws -> CGImage {
        let document = try document(for: screenshot)
        guard let image = AnnotationRenderer.flatten(document, effects: effects) else {
            throw AppError.imageEncodingFailed
        }
        return image
    }

    /// Cached thumbnail at the current panel width.
    func thumbnail(for screenshot: Screenshot, maxPixelSize: CGFloat) -> NSImage? {
        if let cached = thumbnailCache[screenshot.id] { return cached }

        let cgImage: CGImage?
        if screenshot.hasEdits {
            cgImage = (try? flattenedImage(for: screenshot)).map { ImageUtilities.downscale($0, maxPixelSize: maxPixelSize) }
        } else if let inMemory = pendingWrites[screenshot.id] ?? baseImageCache[screenshot.id] {
            // Straight after a capture the bitmap is still in memory, so the
            // thumbnail never has to wait for the disk.
            cgImage = ImageUtilities.downscale(inMemory, maxPixelSize: maxPixelSize)
        } else {
            // Otherwise let ImageIO decode a reduced bitmap directly from disk.
            cgImage = ImageUtilities.loadThumbnail(at: originalURL(for: screenshot), maxPixelSize: Int(maxPixelSize))
        }
        guard let cgImage else { return nil }

        let outputSize = screenshot.outputPixelSize
        let scale = outputSize.width > 0 ? CGFloat(cgImage.width) / outputSize.width : 1
        let image = ImageUtilities.nsImage(from: cgImage, scale: max(scale, 0.01))
        thumbnailCache[screenshot.id] = image
        return image
    }

    func invalidateThumbnails() {
        thumbnailCache.removeAll()
    }

    /// Writes a flattened copy into the temp folder for drag & drop, reusing the
    /// file when it is already up to date.
    ///
    /// Each revision gets its own folder so the dropped file keeps a friendly
    /// name (`Screenshot 2025-… .png`) while stale revisions stay easy to purge.
    func dragFileURL(for screenshot: Screenshot) throws -> URL {
        let revisionDirectory = AppPaths.dragCacheDirectory
            .appendingPathComponent("\(screenshot.id.uuidString)-\(revisionToken(for: screenshot))", isDirectory: true)
        let name = AppPaths.suggestedFileName(for: screenshot.createdAt, format: settings.imageFormat)
        let url = revisionDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }

        removeDragFiles(for: screenshot.id, except: revisionDirectory)
        do {
            try FileManager.default.createDirectory(at: revisionDirectory, withIntermediateDirectories: true)
        } catch {
            throw AppError.fileWriteFailed(url: revisionDirectory, underlying: error.localizedDescription)
        }
        let image = try flattenedImage(for: screenshot)
        try ExportService.write(image, to: url, format: settings.imageFormat, quality: settings.exportQuality)
        return url
    }

    /// Short token that changes whenever the rendered result would change.
    private func revisionToken(for screenshot: Screenshot) -> String {
        var hasher = Hasher()
        hasher.combine(settings.imageFormat)
        hasher.combine(screenshot.cropRect?.origin.x ?? -1)
        hasher.combine(screenshot.cropRect?.origin.y ?? -1)
        hasher.combine(screenshot.cropRect?.size.width ?? -1)
        hasher.combine(screenshot.cropRect?.size.height ?? -1)
        for annotation in screenshot.annotations {
            hasher.combine(annotation.id)
            hasher.combine(annotation.points.count)
            hasher.combine(annotation.text)
            hasher.combine(annotation.lineWidth)
            hasher.combine(annotation.points.first?.x ?? 0)
            hasher.combine(annotation.points.last?.y ?? 0)
        }
        return String(UInt(bitPattern: hasher.finalize()), radix: 36)
    }

    private func removeDragFiles(for id: UUID, except keep: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: AppPaths.dragCacheDirectory,
                                                                         includingPropertiesForKeys: nil) else { return }
        for url in contents where url != keep && url.lastPathComponent.hasPrefix(id.uuidString) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Persistence

    /// Debounced so a burst of edits results in a single disk write.
    private func persist() {
        saveWorkItem?.cancel()
        let snapshot = screenshots
        let workItem = DispatchWorkItem {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: AppPaths.libraryIndexURL, options: .atomic)
            } catch {
                Log.storage.error("Could not persist library: \(error.localizedDescription, privacy: .public)")
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    /// Flushes everything immediately — used on termination.
    func persistNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil

        // Finish any background bitmap writes so restored pins are not dangling.
        for (id, image) in pendingWrites {
            guard let screenshot = screenshot(with: id) else { continue }
            do {
                let data = try ImageUtilities.encode(image, format: .png)
                try data.write(to: originalURL(for: screenshot), options: .atomic)
            } catch {
                Log.storage.error("Could not flush a pending capture: \(error.localizedDescription, privacy: .public)")
                screenshots.removeAll { $0.id == id }
            }
        }
        pendingWrites.removeAll()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(screenshots)
            try data.write(to: AppPaths.libraryIndexURL, options: .atomic)
        } catch {
            Log.storage.error("Could not persist library: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes bitmaps that no index entry references any more.
    private func pruneOrphanedFiles() {
        let known = Set(screenshots.map(\.fileName))
        guard let contents = try? FileManager.default.contentsOfDirectory(at: AppPaths.originalsDirectory,
                                                                         includingPropertiesForKeys: nil) else { return }
        for url in contents where !known.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func purgeEverything() {
        try? FileManager.default.removeItem(at: AppPaths.libraryIndexURL)
        if let contents = try? FileManager.default.contentsOfDirectory(at: AppPaths.originalsDirectory,
                                                                      includingPropertiesForKeys: nil) {
            for url in contents { try? FileManager.default.removeItem(at: url) }
        }
        screenshots.removeAll()
    }

    /// Clears the temp folder used for drag & drop.
    static func clearDragCache() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: AppPaths.dragCacheDirectory,
                                                                          includingPropertiesForKeys: nil) else { return }
        for url in contents { try? FileManager.default.removeItem(at: url) }
    }
}
