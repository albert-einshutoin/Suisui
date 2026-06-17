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
        )
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
            dependencies: ["SoloPMCore"]
        ),
        .testTarget(
            name: "SoloPMCoreTests",
            dependencies: ["SoloPMCore"]
        )
    ]
)
