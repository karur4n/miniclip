// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MiniClip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MiniClip"),
        .testTarget(name: "MiniClipTests", dependencies: ["MiniClip"]),
    ],
    swiftLanguageModes: [.v5]
)
