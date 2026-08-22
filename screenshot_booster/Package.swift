// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotBooster",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScreenshotBooster", targets: ["ScreenshotBooster"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotBooster",
            path: "Sources/ScreenshotBooster"
        )
    ]
)
