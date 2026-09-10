// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "swift-carto",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Carto",
            targets: ["Carto"]),
        .executable(
            name: "carto",
            targets: ["CartoCLI"]),
    ],
    traits: [
        .trait(
            name: "EnableYAMLProjectFiles",
            description: "Adds YAML (`.yaml`/`.yml`) support to the MML project file loader."),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.0.1"),
    ],
    targets: [
        .target(
            name: "Carto",
            dependencies: [
                .product(
                    name: "Yams",
                    package: "Yams",
                    condition: .when(traits: ["EnableYAMLProjectFiles"])),
            ]),
        .executableTarget(
            name: "CartoCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Carto",
            ]),
        .testTarget(
            name: "CartoTests",
            dependencies: ["Carto"],
            resources: [
                .copy("Fixtures"),
            ]),
    ])
