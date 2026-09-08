import AppKit

/// Exercise the actual drawing path with backing contexts independent of the
/// attached monitor. The same canvas moves between 1x and 2x and into translated
/// and flipped contexts, as happens with nested views and display caching.
@MainActor
func runCanvasDisplayTests(_ runner: inout TestRunner) {
    runner.section("Canvas across display contexts")
    let settings = TestFixtures.makeSettings(suite: "com.screenshotbooster.tests.display")
    let library = ScreenshotLibrary(settings: settings)
    let base = TestFixtures.quadrantImage(width: 1200, height: 800)

    for sourceScale: CGFloat in [1, 2] {
        let screenshot = Screenshot(fileName: "display-test.png", pixelWidth: base.width,
                                    pixelHeight: base.height, scale: sourceScale, mode: .area)
        let model = EditorViewModel(screenshot: screenshot,
                                    document: ScreenshotDocument(base: base, scale: sourceScale),
                                    library: library, settings: settings)
        let canvas = CanvasView(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)

        let modes: [(String, () -> Void)] = [
            ("fit", { model.zoomToFit() }),
            ("100%", { model.setVisualScale(1) }),
            ("400%", { model.setVisualScale(4) }),
            ("1600%", { model.setVisualScale(16) }),
            ("crop", {
                model.applyCrop(CGRect(x: 240, y: 160, width: 720, height: 480))
                model.zoomToFit()
            })
        ]
        for (mode, apply) in modes {
            apply()
            canvas.syncZoomState()
            canvas.panOffset = .zero
            if canvas.isPannable { canvas.pan(by: CGSize(width: 90, height: -60)) }

            // Repeat 1x after 2x to cover cache reuse when moving back.
            for backingScale: CGFloat in [1, 2, 1] {
                for (origin, flipped) in [(CGPoint.zero, false),
                                          (CGPoint(x: 130, y: 75), false),
                                          (CGPoint(x: -35, y: -20), false),
                                          (CGPoint(x: 90, y: 690), true)] {
                    let context = ImageUtilities.makeContext(pixelWidth: 2000, pixelHeight: 1600)!
                    context.scaleBy(x: backingScale, y: backingScale)
                    context.translateBy(x: origin.x, y: origin.y)
                    if flipped { context.scaleBy(x: 1, y: -1) }
                    let viewTransform = context.ctm
                    context.clip(to: canvas.bounds)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                    canvas.draw(canvas.bounds)
                    NSGraphicsContext.restoreGraphicsState()
                    let rendered = context.makeImage()!

                    var checked = 0
                    var correct = 0
                    for x: CGFloat in [0.2, 0.4, 0.6, 0.8] {
                        for y: CGFloat in [0.3, 0.45, 0.6, 0.7] {
                            let point = CGPoint(x: canvas.bounds.width * x, y: canvas.bounds.height * y)
                            let imagePoint = canvas.imagePoint(fromView: point)
                            guard model.document.visibleRect.insetBy(dx: 4, dy: 4).contains(imagePoint),
                                  abs(imagePoint.x - 600) > 4, abs(imagePoint.y - 400) > 4 else { continue }
                            let devicePoint = point.applying(viewTransform)
                            let sample = CGPoint(x: devicePoint.x,
                                                 y: CGFloat(rendered.height) - devicePoint.y)
                            checked += 1
                            if TestFixtures.colorName(at: sample, in: rendered)
                                == TestFixtures.colorName(at: imagePoint, in: base) { correct += 1 }
                        }
                    }
                    runner.expect(checked > 0 && correct == checked,
                                  "source \(sourceScale)x, \(mode), target \(backingScale)x, origin \(origin), flipped \(flipped): \(correct)/\(checked)")
                }
            }
        }
    }
}
