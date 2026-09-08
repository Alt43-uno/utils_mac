import AppKit

/// Pinned screenshots outlive the process, so the library's storage is worth
/// checking end to end.
@MainActor
func runLibraryTests(_ runner: inout TestRunner) {
    runner.section("Library")

    let settings = TestFixtures.makeSettings(suite: "com.screenshotbooster.tests.library")
    let library = ScreenshotLibrary(settings: settings)
    let before = library.screenshots.count
    let image = TestFixtures.quadrantImage(width: 600, height: 400)

    guard let screenshot = try? library.add(image: image, scale: 2, mode: .window, sourceName: "Safari") else {
        runner.expect(false, "a capture can be pinned")
        return
    }
    runner.expect(library.screenshots.count == before + 1, "pinning adds it to the stack")
    runner.expect(screenshot.displayTitle == "Safari", "a window capture is titled after its app")
    runner.expect(screenshot.dimensionsLabel == "600 × 400", "dimensions are reported in pixels")

    // The bitmap is written in the background; it must still be readable now.
    runner.expect((try? library.baseImage(for: screenshot)) != nil,
                  "the bitmap is available before the background write finishes")

    // Non-destructive edits change the output size but not the original.
    var edited = screenshot
    edited.annotations = [Annotation(tool: .rect,
                                     points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100)],
                                     color: .defaultAnnotation, lineWidth: 4)]
    edited.cropRect = CGRect(x: 100, y: 100, width: 300, height: 200)
    library.update(edited)

    if let stored = library.screenshot(with: screenshot.id) {
        runner.expect(stored.hasEdits, "edits are recorded against the screenshot")
        runner.expect(stored.outputPixelSize == CGSize(width: 300, height: 200),
                      "the crop changes the output size")
        runner.expect(stored.pixelSize == CGSize(width: 600, height: 400),
                      "but not the original bitmap")
    } else {
        runner.expect(false, "the edited screenshot is still in the library")
    }

    if let flattened = try? library.flattenedImage(for: edited) {
        runner.expect(flattened.width == 300 && flattened.height == 200,
                      "flattening applies the crop")
    } else {
        runner.expect(false, "the edited screenshot flattens")
    }

    runner.expect(library.thumbnail(for: edited, maxPixelSize: 320) != nil, "a thumbnail is produced")

    // Drag & drop needs a real file on disk with a readable name.
    if let dragURL = try? library.dragFileURL(for: edited) {
        runner.expect(FileManager.default.fileExists(atPath: dragURL.path),
                      "dragging exports a file that exists")
        runner.expect(dragURL.lastPathComponent.hasPrefix("Screenshot "),
                      "with a name other apps can show (\(dragURL.lastPathComponent))")
    } else {
        runner.expect(false, "a drag file is produced")
    }

    // The index survives a round-trip through JSON.
    if let data = try? JSONEncoder().encode([edited]),
       let decoded = try? JSONDecoder().decode([Screenshot].self, from: data),
       let first = decoded.first {
        runner.expect(first.id == edited.id && first.cropRect == edited.cropRect
                        && first.annotations == edited.annotations,
                      "the library index round-trips through JSON")
    } else {
        runner.expect(false, "the library index round-trips through JSON")
    }

    library.remove(id: screenshot.id)
    runner.expect(library.screenshot(with: screenshot.id) == nil, "removing unpins it")
    runner.expect(!FileManager.default.fileExists(atPath: library.originalURL(for: screenshot).path),
                  "and deletes its bitmap")

    library.removeAll()
    ScreenshotLibrary.clearDragCache()
}
