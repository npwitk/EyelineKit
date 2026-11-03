// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EyelineKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "EyelineKit", targets: ["EyelineKit"]),
        .library(name: "EyelineKitVision", targets: ["EyelineKitVision"]),
    ],
    targets: [
        .target(
            name: "EyelineKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "EyelineKitVision",
            dependencies: ["EyelineKit"]
        ),
        .testTarget(
            name: "EyelineKitTests",
            dependencies: ["EyelineKit", "EyelineKitVision"]
        ),
    ]
)
