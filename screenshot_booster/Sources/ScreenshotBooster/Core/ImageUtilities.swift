import AppKit
import CoreImage
import UniformTypeIdentifiers

enum ImageFormat: String, Codable, CaseIterable, Identifiable {
    case png
    case jpeg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }
}

enum ImageUtilities {
    /// Shared Core Image context. Creating one per filter run is expensive and
    /// the context itself is thread-safe.
    static let ciContext: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ])
    }()

    static let sRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Creates a premultiplied sRGB bitmap context of the given pixel size.
    static func makeContext(pixelWidth: Int, pixelHeight: Int) -> CGContext? {
        CGContext(data: nil,
                  width: max(1, pixelWidth),
                  height: max(1, pixelHeight),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Encodes a `CGImage`. JPEG output is flattened onto white because JPEG has
    /// no alpha channel.
    static func encode(_ image: CGImage, format: ImageFormat, quality: Double = 0.9) throws -> Data {
        var source = image
        if format == .jpeg {
            source = flattenOnWhite(image) ?? image
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw AppError.imageEncodingFailed
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.imageEncodingFailed
        }
        return data as Data
    }

    static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = makeContext(pixelWidth: image.width, pixelHeight: image.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw AppError.fileReadFailed(url: url)
        }
        return image
    }

    /// Produces a downscaled thumbnail without decoding the full-size bitmap.
    static func loadThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func downscale(_ image: CGImage, maxPixelSize: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxPixelSize, longest > 0 else { return image }
        let factor = maxPixelSize / longest
        let width = Int((CGFloat(image.width) * factor).rounded())
        let height = Int((CGFloat(image.height) * factor).rounded())
        guard let context = makeContext(pixelWidth: width, pixelHeight: height) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Wraps a `CGImage` in an `NSImage` sized in points for the given scale so
    /// Retina bitmaps render at their correct logical size.
    static func nsImage(from image: CGImage, scale: CGFloat) -> NSImage {
        let divisor = max(scale, 1)
        let size = NSSize(width: CGFloat(image.width) / divisor,
                          height: CGFloat(image.height) / divisor)
        return NSImage(cgImage: image, size: size)
    }
}
