// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Granite",
    // visionOS is supported in source; it is now declared explicitly. macOS 12 (Monterey)
    // is the floor — actors/Sendable back-deploy below it, so no bump was required.
    platforms: [.iOS(.v17), .macOS(.v12), .visionOS(.v1)],
    products: [
        .library(
            name: "Granite",
            targets: ["Granite"]),
        .library(
            name: "GraniteUI",
            targets: ["GraniteUI"]),

    ],
    dependencies: [
        // Swift-DocC plugin: enables `swift package generate-documentation --target Granite`.
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "Granite",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "GraniteTests",
            dependencies: ["Granite"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "GraniteUI",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "GraniteUITests",
            dependencies: ["GraniteUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
