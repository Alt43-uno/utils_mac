import CoreGraphics

/// Reads individual pixels out of a `CGImage` for the magnifier's colour
/// readout. Falls back to `nil` for exotic pixel formats rather than guessing.
struct PixelSampler {
    private let data: CFData
    private let pointer: UnsafePointer<UInt8>
    private let bytesPerRow: Int
    private let bytesPerPixel: Int
    private let width: Int
    private let height: Int
    private let isLittleEndian: Bool
    private let alphaFirst: Bool

    init?(image: CGImage) {
        guard image.bitsPerComponent == 8,
              image.bitsPerPixel == 32,
              let provider = image.dataProvider,
              let data = provider.data,
              let pointer = CFDataGetBytePtr(data) else { return nil }

        self.data = data
        self.pointer = pointer
        self.bytesPerRow = image.bytesPerRow
        self.bytesPerPixel = 4
        self.width = image.width
        self.height = image.height

        let byteOrder = image.bitmapInfo.intersection(.byteOrderMask)
        self.isLittleEndian = byteOrder == .byteOrder32Little
        switch image.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            self.alphaFirst = true
        default:
            self.alphaFirst = false
        }
    }

    /// `point` is in image pixel space with a top-left origin.
    func color(at point: CGPoint) -> RGBAColor? {
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = y * bytesPerRow + x * bytesPerPixel
        let bytes = (0..<4).map { Double(pointer[offset + $0]) / 255.0 }

        // Normalise the four channels into RGBA regardless of layout.
        let ordered = isLittleEndian ? bytes.reversed().map { $0 } : bytes
        let rgb: [Double] = alphaFirst ? Array(ordered.dropFirst()) : Array(ordered.dropLast())
        guard rgb.count == 3 else { return nil }
        return RGBAColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }

    static func hexString(for color: RGBAColor) -> String {
        String(format: "#%02X%02X%02X",
               Int((color.red * 255).rounded()),
               Int((color.green * 255).rounded()),
               Int((color.blue * 255).rounded()))
    }
}
