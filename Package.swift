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
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    ],
    targets: [
        .target(
            name: "Carto"),
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
