// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DiskBloom",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DiskBloom", targets: ["DiskBloom"]),
               .executable(name: "DiskBloomWorker", targets: ["DiskBloomWorker"])],
    targets: [
        .target(name: "DiskBloomCore"),
        .executableTarget(name: "DiskBloom", dependencies: ["DiskBloomCore"]),
        .executableTarget(name: "DiskBloomWorker", dependencies: ["DiskBloomCore"]),
        .testTarget(name: "DiskBloomCoreTests", dependencies: ["DiskBloomCore"])
    ],
    swiftLanguageModes: [.v5]
)
