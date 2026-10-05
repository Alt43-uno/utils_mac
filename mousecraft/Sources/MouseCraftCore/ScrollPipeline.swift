import Foundation

public struct ScrollVector: Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
    public var magnitude: Double { hypot(x, y) }
}

public enum ScrollDecision: Equatable {
    case passthrough, scroll(ScrollVector), zoom(Int)
}

public enum ScrollTransform {
    /// Continuous input belongs to trackpads (or high-resolution wheels); leave it untouched.
    public static func apply(_ input: ScrollVector, continuous: Bool, flags: UInt64, settings: ScrollSettings) -> ScrollDecision {
        guard settings.enabled, !continuous, input.x.isFinite, input.y.isFinite else { return .passthrough }
        let direction = settings.reverse ? -1.0 : 1.0
        if settings.zoomModifier.matches(flags), input.y != 0 { return .zoom(input.y * direction > 0 ? 1 : -1) }
        var scale = settings.speed * direction
        if settings.fastModifier.matches(flags) { scale *= 3 }
        if settings.preciseModifier.matches(flags) { scale *= 0.25 }
        if settings.precision, input.magnitude <= 12 { scale *= 0.4 }
        var output = ScrollVector(x: input.x * scale, y: input.y * scale)
        if settings.horizontalModifier.matches(flags) { output = ScrollVector(x: output.x + output.y, y: 0) }
        return .scroll(output)
    }
}

/// Time-based exponential interpolation preserves total wheel distance at every refresh rate.
public struct ScrollSmoother {
    public private(set) var remaining = ScrollVector()
    public private(set) var fractional = ScrollVector()
    public var active: Bool { remaining.magnitude > 0.001 }
    public init() {}
    public mutating func add(_ delta: ScrollVector) {
        if delta.x * remaining.x < 0 { remaining.x = 0; fractional.x = 0 }
        if delta.y * remaining.y < 0 { remaining.y = 0; fractional.y = 0 }
        remaining.x += delta.x; remaining.y += delta.y
    }
    public mutating func step(dt: Double, timeConstant: Double) -> ScrollVector {
        guard dt.isFinite, dt > 0 else { return ScrollVector() }
        let alpha = timeConstant <= 0 ? 1 : 1 - exp(-min(dt, 0.1) / timeConstant)
        var step = ScrollVector(x: remaining.x * alpha, y: remaining.y * alpha)
        remaining.x -= step.x; remaining.y -= step.y
        if remaining.magnitude < 0.05 {
            step.x += remaining.x; step.y += remaining.y; remaining = ScrollVector()
        }
        fractional.x += step.x; fractional.y += step.y
        let output = ScrollVector(x: fractional.x.rounded(.towardZero), y: fractional.y.rounded(.towardZero))
        fractional.x -= output.x; fractional.y -= output.y
        return output
    }
    public mutating func reset() { remaining = ScrollVector(); fractional = ScrollVector() }
}
