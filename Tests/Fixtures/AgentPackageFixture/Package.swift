// swift-tools-version:6.0
// An agent package for the installer's test: one package agent, Granite from this checkout.
import PackageDescription

let package = Package(
    name: "HelloAgent",
    platforms: [.macOS(.v13)],
    products: [.library(name: "HelloAgent", targets: ["HelloAgent"])],
    dependencies: [.package(path: "../../..")],
    targets: [
        .target(name: "HelloAgent", dependencies: [.product(name: "GraniteAgents", package: "Granite")],
                swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
