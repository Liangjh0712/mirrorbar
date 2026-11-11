// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Mirrorbar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Mirrorbar", path: "Sources/Mirrorbar")
    ],
    swiftLanguageModes: [.v5]
)
