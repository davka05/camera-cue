// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CameraCue",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "BelowCamera")
    ]
)
