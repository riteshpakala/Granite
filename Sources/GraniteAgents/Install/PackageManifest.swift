#if os(macOS)
import Foundation

/// What an installer reads off a package's manifest (`swift package dump-package`): its name, the libraries it
/// makes, the macOS it needs, and how it asks for Granite; and the runner manifest written from them.
struct PackageManifest {
    let name: String
    let libraries: [String]
    let macOS: String?
    /// How the package asks for Granite, as a dependency line of a manifest.
    let granite: String

    init(_ manifest: [String: Any], source: String) throws {
        guard let name = manifest["name"] as? String else { throw AgentInstallError.notAPackage(source: source, reason: "its manifest has no name") }
        self.name = name
        libraries = ((manifest["products"] as? [[String: Any]]) ?? []).compactMap { product in
            guard let type = product["type"] as? [String: Any], type["library"] != nil else { return nil }
            return product["name"] as? String
        }
        macOS = ((manifest["platforms"] as? [[String: Any]]) ?? []).first { ($0["platformName"] as? String) == "macos" }?["version"] as? String
        guard let granite = Self.graniteDependency(manifest["dependencies"] as? [[String: Any]] ?? []) else {
            throw AgentInstallError.notGranite(name: name)
        }
        self.granite = granite
        guard !libraries.isEmpty else { throw AgentInstallError.notAPackage(source: source, reason: "it makes no library") }
    }

    /// The runner's manifest: one executable, `agent`, linking every library of the package and GraniteAgents.
    func runnerManifest(packagePath: String, packageIdentity: String) -> String {
        let products = libraries.map { #".product(name: "\#($0)", package: "\#(packageIdentity)")"# }
            + [#".product(name: "GraniteAgents", package: "Granite")"#]
        let platform = macOS.map { #"platforms: [.macOS("\#($0)")],"# } ?? #"platforms: [.macOS(.v13)],"#
        return """
        // swift-tools-version:6.0
        // A runner for \(name), written by Granite's AgentInstaller.
        import PackageDescription

        let package = Package(
            name: "AgentRunner",
            \(platform)
            dependencies: [
                .package(path: "\(packagePath)"),
                \(granite),
            ],
            targets: [
                .executableTarget(
                    name: "agent",
                    dependencies: [\(products.joined(separator: ", "))],
                    path: "Sources/agent",
                    swiftSettings: [.swiftLanguageMode(.v6)]),
            ]
        )

        """
    }

    /// Granite as the package asks for it: the same repository at the same requirement, or the same folder.
    private static func graniteDependency(_ dependencies: [[String: Any]]) -> String? {
        for dependency in dependencies {
            if let control = (dependency["sourceControl"] as? [[String: Any]])?.first, (control["identity"] as? String) == "granite" {
                let location = ((control["location"] as? [String: Any])?["remote"] as? [[String: Any]])?.first?["urlString"] as? String
                    ?? "https://github.com/riteshpakala/Granite.git"
                let requirement = control["requirement"] as? [String: Any] ?? [:]
                if let branch = (requirement["branch"] as? [String])?.first { return #".package(url: "\#(location)", branch: "\#(branch)")"# }
                if let revision = (requirement["revision"] as? [String])?.first { return #".package(url: "\#(location)", revision: "\#(revision)")"# }
                if let exact = (requirement["exact"] as? [String])?.first { return #".package(url: "\#(location)", exact: "\#(exact)")"# }
                if let range = (requirement["range"] as? [[String: Any]])?.first, let lower = range["lowerBound"] as? String {
                    return #".package(url: "\#(location)", from: "\#(lower)")"#
                }
                return #".package(url: "\#(location)", branch: "main")"#
            }
            if let local = (dependency["fileSystem"] as? [[String: Any]])?.first, (local["identity"] as? String) == "granite",
               let path = local["path"] as? String {
                return #".package(path: "\#(path)")"#
            }
        }
        return nil
    }
}
#endif
