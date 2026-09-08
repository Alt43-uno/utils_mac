import AppKit

/// Zoom, panning and the mapping between screen points and image pixels — the
/// maths every editing gesture depends on.
@MainActor
func runCanvasTests(_ runner: inout TestRunner) {
    runner.section("Canvas zoom and pan")

    let settings = TestFixtures.makeSettings(suite: "com.screenshotbooster.tests.canvas")
    let library = ScreenshotLibrary(settings: settings)

    // A 2x Retina shot: 2400x1600 pixels is 1200x800 points at actual size.
    let base = TestFixtures.quadrantImage(width: 2400, height: 1600)
    let screenshot = Screenshot(fileName: "canvas-test.png", pixelWidth: base.width,
                                pixelHeight: base.height, scale: 2, mode: .area)
    let document = ScreenshotDocument(base: base, scale: 2)

    let model = EditorViewModel(screenshot: screenshot, document: document,
                                library: library, settings: settings)
    let canvas = CanvasView(model: model)
    canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)

    // A real window, so the view reports the display's backing scale factor.
    let window = NSWindow(contentRect: canvas.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = canvas
    window.orderBack(nil)
    canvas.syncZoomState()

    let insets = canvas.contentInsets
    let usableWidth = canvas.bounds.width - 48
    let usableHeight = canvas.bounds.height - 48 - insets.top - insets.bottom
    let expectedFit = min(usableWidth / 2400, usableHeight / 1600)
    runner.expect(canvas.zoom, closeTo: expectedFit, within: 0.001,
                  "fitting uses the space the floating controls leave free")
    runner.expect(!canvas.isPannable, "a fitted image cannot be panned")

    // The image must not sit under the toolbar or status capsules.
    let topEdge = canvas.viewPoint(fromImage: .zero).y
    let bottomEdge = canvas.viewPoint(fromImage: CGPoint(x: 2400, y: 1600)).y
    runner.expect(topEdge <= canvas.bounds.height - insets.top + 0.5,
                  "the toolbar capsules do not cover the top of the image")
    runner.expect(bottomEdge >= insets.bottom - 0.5,
                  "the status capsule does not cover the bottom")

    // The zoom ladder.
    model.zoomToActualSize()
    runner.expect(model.zoomPercent == 100, "actual size is 100%")
    runner.expect(canvas.isPannable, "at 100% a Retina shot is larger than the window")
    model.zoomIn()
    runner.expect(model.zoomPercent == 150, "zooming in steps to the next rung")
    model.zoomOut(); model.zoomOut()
    runner.expect(model.zoomPercent == 66, "and zooming out steps back down")

    for _ in 0..<20 { model.zoomIn() }
    let maximum = model.zoomPercent
    for _ in 0..<40 { model.zoomOut() }
    runner.expect(maximum == 1600 && model.zoomPercent == 10, "the ladder is clamped to 10…1600%")

    // Zooming keeps the point under the pointer in place.
    model.zoomToFit()
    canvas.syncZoomState()
    let anchor = CGPoint(x: 250, y: 180)
    let anchoredImagePoint = canvas.imagePoint(fromView: anchor)
    canvas.setVisualScale(4, anchor: anchor)
    let movedAnchor = canvas.viewPoint(fromImage: anchoredImagePoint)
    runner.expect(movedAnchor.x, closeTo: anchor.x, within: 1, "anchored zoom holds the pointer's x")
    runner.expect(movedAnchor.y, closeTo: anchor.y, within: 1, "anchored zoom holds the pointer's y")

    let probe = CGPoint(x: 613, y: 402)
    let roundTrip = canvas.viewPoint(fromImage: canvas.imagePoint(fromView: probe))
    runner.expect(roundTrip.x, closeTo: probe.x, within: 0.01, "view↔image conversion round-trips at 400%")

    // Panning stops at the edge of the image.
    canvas.panOffset = .zero
    canvas.pan(by: CGSize(width: 100_000, height: 100_000))
    let expectedSlack = (2400 * canvas.zoom - usableWidth) / 2
    runner.expect(canvas.panOffset.width, closeTo: expectedSlack, within: 1,
                  "panning is clamped to the image edge")

    model.zoomToFit()
    canvas.syncZoomState()
    runner.expect(canvas.panOffset == .zero, "fitting recentres the image")

    // The pointer still maps inside the image while zoomed.
    model.setVisualScale(2)
    let center = canvas.imagePoint(fromView: CGPoint(x: 400, y: 300))
    runner.expect(center.x >= 0 && center.x <= 2400 && center.y >= 0 && center.y <= 1600,
                  "the pointer maps inside the image at 200%")

    // What is drawn ends up where the maths says it does.
    runner.section("Canvas drawing")
    let checks: [(String, () -> Void)] = [
        ("fitted", { model.zoomToFit() }),
        ("at 100%", { model.setVisualScale(1) }),
        ("at 400%", { model.setVisualScale(4) }),
        ("at 1600%", { model.setVisualScale(16) }),
        ("cropped", {
            model.applyCrop(CGRect(x: 600, y: 400, width: 1200, height: 800))
            model.zoomToFit()
        })
    ]
    // Expected colour of a point in image space, given the quadrant layout.
    func expectedColor(at point: CGPoint) -> String? {
        let boundary: CGFloat = 24
        guard abs(point.x - 1200) > boundary, abs(point.y - 800) > boundary else { return nil }
        switch (point.x < 1200, point.y < 800) {
        case (true, true): return "red"
        case (false, true): return "green"
        case (true, false): return "blue"
        case (false, false): return "yellow"
        }
    }

    for (label, apply) in checks {
        apply()
        canvas.syncZoomState()
        // Zoomed right in, the centre of the window is the point where all four
        // quadrants meet. Pan into a corner so a single colour fills the view.
        canvas.panOffset = .zero
        if canvas.isPannable {
            canvas.pan(by: CGSize(width: 100_000, height: 100_000))
        }
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { continue }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)

        // Sample points spread across the window, so something is always in
        // view no matter how far in the canvas is zoomed.
        var correct = 0, checked = 0
        for fractionX in [0.3, 0.7] {
            for fractionY in [0.35, 0.65] {
                let viewPoint = CGPoint(x: canvas.bounds.width * fractionX,
                                        y: canvas.bounds.height * fractionY)
                let imagePoint = canvas.imagePoint(fromView: viewPoint)
                // Only where the screenshot is actually drawn, and away from the
                // quadrant boundaries.
                guard model.document.visibleRect.insetBy(dx: 4, dy: 4).contains(imagePoint),
                      let expected = expectedColor(at: imagePoint) else { continue }
                checked += 1
                let x = Int(viewPoint.x * CGFloat(rep.pixelsWide) / canvas.bounds.width)
                let y = Int((canvas.bounds.height - viewPoint.y) * CGFloat(rep.pixelsHigh) / canvas.bounds.height)
                guard let color = rep.colorAt(x: min(max(x, 0), rep.pixelsWide - 1),
                                              y: min(max(y, 0), rep.pixelsHigh - 1))?
                    .usingColorSpace(.sRGB) else { continue }
                let name: String
                switch (color.redComponent > 0.6, color.greenComponent > 0.6, color.blueComponent > 0.6) {
                case (true, false, false): name = "red"
                case (false, true, false): name = "green"
                case (false, false, true): name = "blue"
                case (true, true, false): name = "yellow"
                default: name = "other"
                }
                if name == expected { correct += 1 }
            }
        }
        runner.expect(checked > 0 && correct == checked,
                      "\(label): every visible quadrant lands where the coordinates say (\(correct)/\(checked))")
    }
}
