import AppKit

#if !SCREENSHOT_BOOSTER_TESTS
#error("Build tests with Scripts/run_tests.sh to isolate screenshot storage")
#endif

// Runs every suite in one process. A few of them need a real window for the
// backing scale factor, so this has to be an NSApplication rather than a plain
// command line tool.

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

Task { @MainActor in
    var runner = TestRunner()
    runRendererTests(&runner)
    runAnnotationTests(&runner)
    runCanvasTests(&runner)
    runCanvasDisplayTests(&runner)
    if !CommandLine.arguments.contains("--rendering-only") {
        runThumbnailTests(&runner)
        await runLibraryTests(&runner)
    }
    runner.finish()
}

application.run()
