// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "NotchFuel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchFuel", targets: ["NotchFuel"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "NotchFuel",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/NotchFuel",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "NotchFuelTests",
            dependencies: ["NotchFuel"],
            path: "Tests/NotchFuelTests"
        )
    ]
)
