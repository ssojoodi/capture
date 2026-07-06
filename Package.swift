// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Capture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CaptureCore", targets: ["CaptureCore"]),
        .executable(name: "Capture", targets: ["CaptureApp"])
    ],
    targets: [
        .target(name: "CaptureCore"),
        .executableTarget(
            name: "CaptureApp",
            dependencies: ["CaptureCore"]
        ),
        .testTarget(
            name: "CaptureCoreTests",
            dependencies: ["CaptureCore"]
        )
    ]
)
