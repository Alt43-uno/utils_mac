import AppKit

/// Annotations are value types with hand-written geometry, which is exactly the
/// kind of code that quietly drifts.
@MainActor
func runAnnotationTests(_ runner: inout TestRunner) {
    runner.section("Annotation geometry")

    let rect = Annotation(tool: .rect,
                          points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200)],
                          color: .defaultAnnotation, lineWidth: 4)

    runner.expect(rect.rawBounds == CGRect(x: 100, y: 100, width: 200, height: 100),
                  "bounds come from the two dragged corners")
    runner.expect(rect.displayBounds.contains(rect.rawBounds),
                  "display bounds allow for the stroke width")

    let moved = rect.translated(dx: 50, dy: -25)
    runner.expect(moved.rawBounds.origin == CGPoint(x: 150, y: 75), "translation moves every point")
    runner.expect(moved.rawBounds.size == rect.rawBounds.size, "translation does not resize")

    let resized = rect.resized(from: rect.rawBounds,
                               to: CGRect(x: 100, y: 100, width: 400, height: 200))
    runner.expect(resized.rawBounds.width == 400 && resized.rawBounds.height == 200,
                  "resizing maps the object onto the new bounds")
    runner.expect(resized.lineWidth > rect.lineWidth, "and scales the stroke with it")

    // Hit testing: a hollow shape is grabbed by its edge, not its middle.
    let tolerance: CGFloat = 6
    runner.expect(AnnotationHitTesting.contains(annotation: rect, point: CGPoint(x: 100, y: 150), tolerance: tolerance),
                  "a hollow rectangle is hit on its edge")
    runner.expect(!AnnotationHitTesting.contains(annotation: rect, point: CGPoint(x: 200, y: 150), tolerance: tolerance),
                  "but not through its empty middle")

    var filled = rect
    filled.isFilled = true
    runner.expect(AnnotationHitTesting.contains(annotation: filled, point: CGPoint(x: 200, y: 150), tolerance: tolerance),
                  "a filled rectangle is hit anywhere inside")

    let arrow = Annotation(tool: .arrow,
                           points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)],
                           color: .defaultAnnotation, lineWidth: 4)
    runner.expect(AnnotationHitTesting.contains(annotation: arrow, point: CGPoint(x: 50, y: 50), tolerance: tolerance),
                  "an arrow is hit along its shaft")
    runner.expect(!AnnotationHitTesting.contains(annotation: arrow, point: CGPoint(x: 90, y: 20), tolerance: tolerance),
                  "but not in the empty corner beside it")

    runner.expect(AnnotationHitTesting.handles(for: arrow) == [.start, .end],
                  "segments expose two endpoint handles")
    runner.expect(AnnotationHitTesting.handles(for: rect).count == 8,
                  "areas expose eight resize handles")
    runner.expect(AnnotationHitTesting.handle(at: CGPoint(x: 0, y: 0), for: arrow, tolerance: tolerance) == .start,
                  "the handle under the pointer is found")

    // Topmost wins when objects overlap.
    let lower = rect
    var upper = rect
    upper.id = UUID()
    upper.isFilled = true
    let hit = AnnotationHitTesting.annotation(at: CGPoint(x: 200, y: 150),
                                              in: [lower, upper],
                                              tolerance: tolerance)
    runner.expect(hit?.id == upper.id, "the topmost object wins where they overlap")

    // Codable, because documents survive relaunches.
    if let data = try? JSONEncoder().encode(rect),
       let decoded = try? JSONDecoder().decode(Annotation.self, from: data) {
        runner.expect(decoded == rect, "annotations round-trip through JSON")
    } else {
        runner.expect(false, "annotations round-trip through JSON")
    }
}
