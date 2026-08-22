import AppKit

/// Everything the app puts on the general pasteboard.
enum PasteboardService {
    /// Writes both PNG data and a TIFF representation so every app — from
    /// Preview to web browsers — finds a flavour it understands.
    @discardableResult
    static func copy(image: CGImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wroteSomething = false
        if let png = try? ImageUtilities.encode(image, format: .png) {
            pasteboard.setData(png, forType: .png)
            wroteSomething = true
        }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
            wroteSomething = true
        }
        if !wroteSomething {
            Log.storage.error("Nothing could be written to the pasteboard")
        }
        return wroteSomething
    }

    @discardableResult
    static func copy(fileURL: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([fileURL as NSURL])
    }
}
