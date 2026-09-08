import AppKit

/// The renderer is the one piece both the canvas and the exporter go through,
/// so what it produces is what ends up in the saved file.
@MainActor
func runRendererTests(_ runner: inout TestRunner) {
    runner.section("Renderer")

    let base = TestFixtures.quadrantImage()
    let effects = EffectCache()

    // A plain document renders unchanged.
    let plain = ScreenshotDocument(base: base, scale: 2)
    guard let flat = AnnotationRenderer.flatten(plain, effects: effects) else {
        runner.expect(false, "flattening a plain document produces an image")
        return
    }
    runner.expect(flat.width == 1200 && flat.height == 800, "output keeps the source size")
    runner.expect(TestFixtures.colorName(at: CGPoint(x: 300, y: 200), in: flat) == "red",
                  "the top-left quadrant stays red")
    runner.expect(TestFixtures.colorName(at: CGPoint(x: 900, y: 600), in: flat) == "yellow",
                  "the bottom-right quadrant stays yellow")

    // A filled rectangle lands where it was placed.
    let marker = Annotation(tool: .rect,
                            points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300)],
                            color: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
                            lineWidth: 4,
                            isFilled: true)
    let annotated = ScreenshotDocument(base: base, annotations: [marker], scale: 2)
    if let image = AnnotationRenderer.flatten(annotated, effects: effects) {
        runner.expect(TestFixtures.colorName(at: CGPoint(x: 200, y: 200), in: image) == "white",
                      "a filled rectangle covers the pixels inside it")
        runner.expect(TestFixtures.colorName(at: CGPoint(x: 500, y: 200), in: image) == "red",
                      "and leaves the pixels outside it alone")
    } else {
        runner.expect(false, "flattening an annotated document produces an image")
    }

    // Cropping moves the origin without moving the annotations relative to it.
    var cropped = annotated
    cropped.cropRect = CGRect(x: 100, y: 100, width: 400, height: 300)
    if let image = AnnotationRenderer.flatten(cropped, effects: effects) {
        runner.expect(image.width == 400 && image.height == 300, "a crop resizes the output")
        runner.expect(TestFixtures.colorName(at: CGPoint(x: 50, y: 50), in: image) == "white",
                      "annotations keep their position relative to the crop")
    } else {
        runner.expect(false, "flattening a cropped document produces an image")
    }

    // Blur and pixelate replace the pixels underneath them. They need something
    // to act on: a flat block of colour survives pixelation unchanged, so the
    // region gets fine detail first.
    let detailed = ImageUtilities.makeContext(pixelWidth: 1200, pixelHeight: 800)!
    detailed.draw(base, in: CGRect(x: 0, y: 0, width: 1200, height: 800))
    detailed.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    for row in 0..<28 {
        for column in 0..<28 where (row + column).isMultiple(of: 2) {
            detailed.fill(CGRect(x: 556 + column * 3, y: 356 + row * 3, width: 3, height: 3))
        }
    }
    let detailBase = detailed.makeImage()!

    for tool in [ToolKind.blur, .pixelate] {
        let effect = Annotation(tool: tool,
                                points: [CGPoint(x: 560, y: 360), CGPoint(x: 640, y: 440)],
                                color: .defaultAnnotation,
                                lineWidth: 1)
        let document = ScreenshotDocument(base: detailBase, annotations: [effect], scale: 2)
        guard let image = AnnotationRenderer.flatten(document, effects: EffectCache()) else {
            runner.expect(false, "\(tool.rawValue) renders")
            continue
        }
        // Pixelate can legitimately produce a flat block of one quadrant's
        // colour, so the invariant is that the pixels *changed*, not that they
        // became some blend.
        var probes: [CGPoint] = []
        for index in 0..<12 {
            let x = CGFloat(570 + index * 5)
            let y = CGFloat(380 + (index % 4) * 5)
            probes.append(CGPoint(x: x, y: y))
        }
        let changed = probes.contains { point in
            TestFixtures.colorName(at: point, in: image) != TestFixtures.colorName(at: point, in: detailBase)
        }
        runner.expect(changed, "\(tool.rawValue) changes the pixels it covers")
        runner.expect(TestFixtures.colorName(at: CGPoint(x: 200, y: 200), in: image) == "red",
                      "\(tool.rawValue) leaves the rest of the image untouched")
    }

    // Text has to measure to something drawable.
    let text = Annotation(tool: .text, points: [CGPoint(x: 40, y: 40)],
                          color: .defaultAnnotation, lineWidth: 2,
                          text: "Hello\nSecond line", fontSize: 30)
    let size = TextLayout.size(for: text)
    runner.expect(size.width > 60 && size.height > 60, "multi-line text measures to a sensible box")
    runner.expect(TextLayout.lines(for: text).count == 2, "each hard line break becomes its own line")

    // Encoding round-trips.
    if let png = try? ImageUtilities.encode(flat, format: .png),
       let jpeg = try? ImageUtilities.encode(flat, format: .jpeg, quality: 0.8) {
        runner.expect(png.count > 0 && jpeg.count > 0, "PNG and JPEG both encode")
        runner.expect(jpeg.count < png.count, "JPEG is smaller than PNG for this image")
    } else {
        runner.expect(false, "the flattened image encodes")
    }
}
