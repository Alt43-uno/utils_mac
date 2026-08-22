import AppKit

/// Callbacks the thumbnail UI invokes. Injecting them keeps the SwiftUI layer
/// free of any knowledge about windows, files or the pasteboard.
@MainActor
struct ThumbnailActions {
    var open: (Screenshot) -> Void
    var delete: (Screenshot) -> Void
    var copy: (Screenshot) -> Void
    var save: (Screenshot) -> Void
    var saveAs: (Screenshot) -> Void
    var reveal: (Screenshot) -> Void
    var clearAll: () -> Void
    /// Produces the file that gets dragged out of the panel.
    var dragFileURL: (Screenshot) -> URL?
    var thumbnailImage: (Screenshot) -> NSImage?
}
