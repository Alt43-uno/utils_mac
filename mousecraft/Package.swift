// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseCraft",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MouseCraft", targets: ["MouseCraft"])],
    targets: [
        .target(name: "MouseCraftCore"),
        .target(name: "MouseCraftNative"),
        .executableTarget(name: "MouseCraft", dependencies: ["MouseCraftCore", "MouseCraftNative"]),
        .testTarget(name: "MouseCraftCoreTests", dependencies: ["MouseCraftCore", "MouseCraftNative"])
    ],
    swiftLanguageVersions: [.v5]
)
