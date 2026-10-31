// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Capture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CaptureCore", targets: ["CaptureCore"]),
        .executable(name: "Capture", targets: ["CaptureApp"]),
        .executable(name: "capture-mcp", targets: ["CaptureMCP"])
    ],
    dependencies: [.package(path: "Vendor/swift-sdk"), .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")],
    targets: [
        .target(name: "CaptureAutomation"),
        .executableTarget(name: "CaptureMCP", dependencies: ["CaptureAutomation", .product(name: "MCP", package: "swift-sdk"), .product(name: "Logging", package: "swift-log")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CaptureCore"),
        .executableTarget(
            name: "CaptureApp",
            dependencies: ["CaptureCore", "CaptureAutomation"],
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "CaptureCoreTests",
            dependencies: ["CaptureCore"]
        )
    ]
)
