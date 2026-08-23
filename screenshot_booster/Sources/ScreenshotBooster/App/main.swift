import AppKit

// A plain `main.swift` entry point (instead of `@main`) keeps full control over
// the activation policy: the app is a menu bar accessory with no Dock icon.
//
// Top-level code runs on the main thread but is not statically main-actor
// isolated, hence the explicit `assumeIsolated`.

/// Held for the lifetime of the process — `NSApplication.delegate` is weak.
private let applicationDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = applicationDelegate
    application.setActivationPolicy(.accessory)
    application.run()
}
