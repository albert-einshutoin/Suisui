// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SoloPM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SoloPMCore",
            targets: ["SoloPMCore"]
        ),
        .executable(
            name: "SoloPM",
            targets: ["SoloPMApp"]
        ),
        .executable(
            name: "solopm",
            targets: ["SoloPMCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        .target(
            name: "SoloPMCore",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "SoloPMApp",
            dependencies: [
                "SoloPMCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "SoloPMCLI",
            dependencies: ["SoloPMCore"]
        ),
        .testTarget(
            name: "SoloPMCoreTests",
            dependencies: ["SoloPMCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
