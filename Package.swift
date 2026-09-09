// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptionPeel",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CaptionPeel", targets: ["CaptionPeel"])
    ],
    targets: [
        .executableTarget(
            name: "CaptionPeel",
            path: "Sources/CaptionPeel"
        ),
        .testTarget(
            name: "CaptionPeelTests",
            dependencies: ["CaptionPeel"],
            path: "Tests/CaptionPeelTests"
        )
    ]
)
