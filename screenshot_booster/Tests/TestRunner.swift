import AppKit

/// A deliberately small harness.
///
/// The project has no third-party dependencies, and pulling in a test framework
/// for a handful of geometry and drawing checks would be the only one. This
/// prints what it checked and exits non-zero on the first failure it records.
struct TestRunner {
    private(set) var passed = 0
    private(set) var failures: [String] = []
    private var currentSection = ""

    mutating func section(_ name: String) {
        currentSection = name
        print("\n\(name)")
    }

    /// Records a check. `detail` is printed either way, so a passing run doubles
    /// as a description of the behaviour.
    mutating func expect(_ condition: Bool, _ detail: String) {
        if condition {
            passed += 1
            print("  ✓ \(detail)")
        } else {
            failures.append("\(currentSection): \(detail)")
            print("  ✗ \(detail)")
        }
    }

    mutating func expect(_ value: CGFloat,
                         closeTo expected: CGFloat,
                         within tolerance: CGFloat,
                         _ detail: String) {
        expect(abs(value - expected) <= tolerance,
               "\(detail) — got \(String(format: "%.2f", value)), expected \(String(format: "%.2f", expected))")
    }

    func finish() -> Never {
        try? FileManager.default.removeItem(at: AppPaths.testDirectory)
        print("\n" + String(repeating: "—", count: 60))
        if failures.isEmpty {
            print("\(passed) checks passed")
            exit(0)
        }
        print("\(passed) passed, \(failures.count) FAILED:")
        for failure in failures { print("  • \(failure)") }
        exit(1)
    }
}

/// Building blocks shared by the suites.
enum TestFixtures {
    /// A screenshot-like bitmap: four coloured quadrants, so misplacement is
    /// obvious, plus fine detail for the blur and pixelate checks.
    static func quadrantImage(width: Int = 1200, height: Int = 800) -> CGImage {
        let context = ImageUtilities.makeContext(pixelWidth: width, pixelHeight: height)!
        let half = (x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        // Core Graphics is bottom-up, so the top row of the image is drawn last.
        let quadrants: [(CGRect, CGColor)] = [
            (CGRect(x: 0, y: half.y, width: half.x, height: half.y), CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: half.x, y: half.y, width: half.x, height: half.y), CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)),
            (CGRect(x: 0, y: 0, width: half.x, height: half.y), CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)),
            (CGRect(x: half.x, y: 0, width: half.x, height: half.y), CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
        ]
        for (rect, color) in quadrants {
            context.setFillColor(color)
            context.fill(rect)
        }
        return context.makeImage()!
    }

    /// Names the colour at a point in image space (top-left origin).
    static func colorName(at point: CGPoint, in image: CGImage) -> String {
        guard let sampler = PixelSampler(image: image),
              let color = sampler.color(at: point) else { return "unreadable" }
        switch (color.red > 0.6, color.green > 0.6, color.blue > 0.6) {
        case (true, false, false): return "red"
        case (false, true, false): return "green"
        case (false, false, true): return "blue"
        case (true, true, false): return "yellow"
        case (true, true, true): return "white"
        case (false, false, false): return "black"
        default: return String(format: "rgb(%.2f,%.2f,%.2f)", color.red, color.green, color.blue)
        }
    }

    static func makeSettings(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults)
    }
}
