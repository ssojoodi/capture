// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkitchEquivalent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SkitchEquivalentCore", targets: ["SkitchEquivalentCore"]),
        .executable(name: "SkitchEquivalent", targets: ["SkitchEquivalentApp"])
    ],
    targets: [
        .target(name: "SkitchEquivalentCore"),
        .executableTarget(
            name: "SkitchEquivalentApp",
            dependencies: ["SkitchEquivalentCore"]
        ),
        .testTarget(
            name: "SkitchEquivalentCoreTests",
            dependencies: ["SkitchEquivalentCore"]
        )
    ]
)
