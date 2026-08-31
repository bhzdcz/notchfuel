// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "TopNotchAI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TopNotchAI", targets: ["TopNotchAI"])
    ],
    targets: [
        .executableTarget(
            name: "TopNotchAI",
            path: "Sources/TopNotchAI"
        ),
        .testTarget(
            name: "TopNotchAITests",
            dependencies: ["TopNotchAI"],
            path: "Tests/TopNotchAITests"
        )
    ]
)
