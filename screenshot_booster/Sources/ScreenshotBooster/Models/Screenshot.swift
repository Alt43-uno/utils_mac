import CoreGraphics
import Foundation

/// Persisted metadata for a pinned screenshot.
///
/// The bitmap itself lives next to the index as a PNG; annotations and the crop
/// rectangle are stored non-destructively so a shot stays fully re-editable
/// across app launches.
struct Screenshot: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    /// File name (not a full URL) inside the library's originals folder, so the
    /// library keeps working if the container is moved.
    var fileName: String
    var pixelWidth: Int
    var pixelHeight: Int
    /// Backing scale of the display the shot came from (2.0 on Retina).
    var scale: CGFloat
    var mode: CaptureMode
    var sourceName: String?
    var annotations: [Annotation]
    var cropRect: CGRect?
    /// Where the user last exported this shot, used by "Save" to overwrite.
    var lastSavedPath: String?

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         fileName: String,
         pixelWidth: Int,
         pixelHeight: Int,
         scale: CGFloat,
         mode: CaptureMode,
         sourceName: String? = nil,
         annotations: [Annotation] = [],
         cropRect: CGRect? = nil,
         lastSavedPath: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
        self.mode = mode
        self.sourceName = sourceName
        self.annotations = annotations
        self.cropRect = cropRect
        self.lastSavedPath = lastSavedPath
    }

    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }

    /// Output size after cropping, in pixels.
    var outputPixelSize: CGSize {
        (cropRect ?? CGRect(origin: .zero, size: pixelSize)).size
    }

    var lastSavedURL: URL? {
        lastSavedPath.map { URL(fileURLWithPath: $0) }
    }

    var hasEdits: Bool { !annotations.isEmpty || cropRect != nil }

    /// Short human readable label, e.g. `1920 × 1080`.
    var dimensionsLabel: String {
        let size = outputPixelSize
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    var displayTitle: String {
        if let sourceName, !sourceName.isEmpty { return sourceName }
        return mode.shortTitle
    }
}
