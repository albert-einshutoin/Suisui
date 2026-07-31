// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Suisui",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SuisuiCore",
            targets: ["SuisuiCore"]
        ),
        .library(
            name: "SuisuiiOS",
            targets: ["SuisuiiOS"]
        ),
        .library(
            name: "SuisuiWeb",
            targets: ["SuisuiWeb"]
        ),
        .executable(
            name: "Suisui",
            targets: ["Suisui"]
        ),
        .executable(
            name: "suisui-cli",
            targets: ["SuisuiCLI"]
        ),
        .executable(
            name: "SuisuiVisualFixtureSeeder",
            targets: ["SuisuiVisualFixtureSeeder"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0")
    ],
    targets: [
        .target(
            name: "SuisuiCore",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "SuisuiExternalConnectors",
            dependencies: ["SuisuiCore"]
        ),
        .target(
            name: "SuisuiGoogleCalendarRuntime",
            dependencies: ["SuisuiCore"]
        ),
        .target(
            name: "SuisuiiOS",
            dependencies: ["SuisuiCore"],
            path: "Sources/SuisuiiOS"
        ),
        .target(
            name: "SuisuiWeb",
            dependencies: ["SuisuiCore"],
            path: "Sources/SuisuiWeb"
        ),
        .executableTarget(
            name: "Suisui",
            dependencies: [
                "SuisuiCore",
                "SuisuiGoogleCalendarRuntime",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/SuisuiApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SuisuiCLI",
            dependencies: ["SuisuiCore"]
        ),
        .executableTarget(
            name: "SuisuiVisualFixtureSeeder",
            dependencies: ["SuisuiCore"]
        ),
        .testTarget(
            name: "SuisuiCoreTests",
            dependencies: ["SuisuiCore", "SuisuiExternalConnectors", "SuisuiGoogleCalendarRuntime", "SuisuiWeb"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "SuisuiAppTests",
            dependencies: ["Suisui"]
        )
    ]
)
