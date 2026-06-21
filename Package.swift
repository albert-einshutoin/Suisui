// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SoloPM",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SoloPMCore",
            targets: ["SoloPMCore"]
        ),
        .library(
            name: "SoloPMiOS",
            targets: ["SoloPMiOS"]
        ),
        .library(
            name: "SoloPMWeb",
            targets: ["SoloPMWeb"]
        ),
        .executable(
            name: "SoloPM",
            targets: ["SoloPM"]
        ),
        .executable(
            name: "solopm-cli",
            targets: ["SoloPMCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0")
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
        .target(
            name: "SoloPMExternalConnectors",
            dependencies: ["SoloPMCore"]
        ),
        .target(
            name: "SoloPMiOS",
            dependencies: ["SoloPMCore"],
            path: "Sources/SoloPMiOS"
        ),
        .target(
            name: "SoloPMWeb",
            dependencies: ["SoloPMCore"],
            path: "Sources/SoloPMWeb"
        ),
        .executableTarget(
            name: "SoloPM",
            dependencies: [
                "SoloPMCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/SoloPMApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SoloPMCLI",
            dependencies: ["SoloPMCore"]
        ),
        .testTarget(
            name: "SoloPMCoreTests",
            dependencies: ["SoloPMCore", "SoloPMExternalConnectors", "SoloPMWeb"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
