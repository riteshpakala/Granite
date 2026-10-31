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
        // Agents on Granite: `@Agent`, `GraniteAgent` and the service scaffolding they run on, and the
        // roster through which an agent shipped as its own package is found by the app that links it.
        .library(
            name: "GraniteAgents",
            targets: ["GraniteAgents"]),
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
        .target(
            name: "GraniteAgents",
            dependencies: ["Granite"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "GraniteAgentsTests",
            dependencies: ["GraniteAgents", "Granite", "AgentRunnerFixture"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        // A runner as an installer writes one, for the tests that run an agent in a process of its own.
        .executableTarget(
            name: "AgentRunnerFixture",
            dependencies: ["GraniteAgents"],
            path: "Tests/Fixtures/AgentRunnerFixture",
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
