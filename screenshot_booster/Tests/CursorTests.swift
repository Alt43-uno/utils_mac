import AppKit

@MainActor
func runCursorTests(_ runner: inout TestRunner) {
    runner.section("Editor cursor boundaries")
    let settings = TestFixtures.makeSettings(suite: "com.screenshotbooster.tests.cursor")
    let library = ScreenshotLibrary(settings: settings)
    let image = TestFixtures.quadrantImage()
    let screenshot = Screenshot(fileName: "cursor-test.png", pixelWidth: image.width,
                                pixelHeight: image.height, scale: 2, mode: .area)
    let model = EditorViewModel(screenshot: screenshot, document: ScreenshotDocument(base: image, scale: 2),
                                library: library, settings: settings)
    let canvas = CanvasView(model: model)
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 620),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = canvas
    canvas.frame = CGRect(x: 0, y: 0, width: 900, height: 620)
    let toolbar = CGPoint(x: 450, y: 605)
    let statusBar = CGPoint(x: 450, y: 20)

    for tool in [ToolKind.pen, .text, .crop, .blur] {
        model.tool = tool
        for scale in [CGFloat(1), 16] {
            model.setVisualScale(scale)
            runner.expect(canvas.cursor(at: toolbar) === NSCursor.arrow &&
                          canvas.cursor(at: statusBar) === NSCursor.arrow,
                          "\(tool.title) at \(Int(scale * 100))% uses an arrow over toolbar and status controls")
            let center = CGPoint(x: canvas.toolCursorRect.midX, y: canvas.toolCursorRect.midY)
            let expected = tool == .text ? NSCursor.iBeam : NSCursor.crosshair
            runner.expect(canvas.cursor(at: center) === expected,
                          "\(tool.title) keeps its tool cursor over the image")
        }
    }
    model.tool = .pen
    model.zoomToFit()
    runner.expect(canvas.cursor(at: CGPoint(x: 2, y: 310)) === NSCursor.arrow,
                  "blank space beside a fitted screenshot uses the arrow")
    canvas.updateTrackingAreas()
    runner.expect(canvas.trackingAreas.allSatisfy {
        !$0.rect.contains(toolbar) && !$0.rect.contains(statusBar) && !$0.options.contains(.inVisibleRect)
    }, "canvas tracking excludes floating controls so leaving the image restores their cursor")
    window.contentView = nil
}
