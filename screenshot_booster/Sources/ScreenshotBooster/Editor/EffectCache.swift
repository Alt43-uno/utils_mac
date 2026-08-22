import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Caches the rendered result of blur / pixelate annotations.
///
/// Re-running a Gaussian blur on every redraw makes dragging feel sluggish, so
/// results are memoised per (annotation, rect, base image) and evicted with a
/// simple LRU once the cache grows past `capacity`.
final class EffectCache {
    private struct Key: Hashable {
        let tool: ToolKind
        let base: ObjectIdentifier
        let x: Int, y: Int, width: Int, height: Int
    }

    private var storage: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let capacity: Int

    init(capacity: Int = 48) {
        self.capacity = capacity
    }

    func removeAll() {
        storage.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    /// Returns the filtered bitmap for `rect` of `base` (rect is in image pixel
    /// space with a top-left origin).
    func image(for annotation: Annotation, rect: CGRect, base: CGImage) -> CGImage? {
        let aligned = rect.pixelAligned
        guard aligned.width >= 1, aligned.height >= 1 else { return nil }
        let key = Key(tool: annotation.tool,
                      base: ObjectIdentifier(base),
                      x: Int(aligned.minX), y: Int(aligned.minY),
                      width: Int(aligned.width), height: Int(aligned.height))

        if let cached = storage[key] {
            touch(key)
            return cached
        }
        guard let produced = render(tool: annotation.tool, rect: aligned, base: base) else { return nil }
        storage[key] = produced
        touch(key)
        evictIfNeeded()
        return produced
    }

    private func touch(_ key: Key) {
        if let existing = order.firstIndex(of: key) {
            order.remove(at: existing)
        }
        order.append(key)
    }

    private func evictIfNeeded() {
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    private func render(tool: ToolKind, rect: CGRect, base: CGImage) -> CGImage? {
        // Core Image works bottom-up; flip the rect into its coordinate space.
        let ciRect = CGRect(x: rect.minX,
                            y: CGFloat(base.height) - rect.maxY,
                            width: rect.width,
                            height: rect.height)
            .clamped(to: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !ciRect.isEmpty else { return nil }

        let source = CIImage(cgImage: base)
        // Clamping first avoids transparent edges bleeding into the result.
        let cropped = source.cropped(to: ciRect).clampedToExtent()
        let shortSide = min(ciRect.width, ciRect.height)

        let output: CIImage
        switch tool {
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = cropped
            filter.radius = Float(max(6, min(shortSide / 4, 40)))
            guard let result = filter.outputImage else { return nil }
            output = result
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = cropped
            filter.scale = Float(max(6, min(shortSide / 10, 48)))
            filter.center = CGPoint(x: ciRect.minX, y: ciRect.minY)
            guard let result = filter.outputImage else { return nil }
            output = result
        default:
            return nil
        }

        return ImageUtilities.ciContext.createCGImage(output, from: ciRect)
    }
}
