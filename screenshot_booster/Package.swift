// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScreenshotBooster",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "ScreenshotBooster", targets: ["ScreenshotBooster"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotBooster",
            path: "Sources/ScreenshotBooster"
        )
    ],
    // The app is main-actor bound end to end; Swift 5 mode keeps the AppKit
    // interop free of ceremony without giving up safety we actually rely on.
    swiftLanguageModes: [.v5]
)
