// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "NotchFuel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchFuel", targets: ["NotchFuel"])
    ],
    targets: [
        .executableTarget(
            name: "NotchFuel",
            path: "Sources/NotchFuel"
        ),
        .testTarget(
            name: "NotchFuelTests",
            dependencies: ["NotchFuel"],
            path: "Tests/NotchFuelTests"
        )
    ]
)
