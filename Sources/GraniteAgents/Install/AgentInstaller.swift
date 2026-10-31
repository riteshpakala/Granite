//  WHAT: An agent package made a runner on this machine: fetched, read, wrapped in a package of one executable
//        whose `main` is `AgentServer.main()`, built, asked what it carries, and installed on a shelf with its
//        record. Nothing of the package is imported; its records are found in the runner as an app finds them.
//
//            fetch → read the manifest → write the runner → build (release) → `agent --describe` → install
//
//  PIN:  THE RUNNER IS GENERATED, THE PACKAGE IS UNTOUCHED. Any package with a record installs as it is: the runner
//        depends on every library it makes and on GraniteAgents at the package's own Granite requirement.
//  PIN:  ONE WORD, ONE INSTALLATION. A package that carries a word another installation carries is refused;
//        installing the same package again replaces it whole.

#if os(macOS)
import Foundation

public struct AgentInstaller: Sendable {
    /// A step of an install, with the line the tool just said.
    public struct Progress: Sendable, Equatable {
        public var stage: String
        public var line: String?
        public init(stage: String, line: String? = nil) { self.stage = stage; self.line = line }
    }

    public let shelf: AgentShelf

    public init(folder: URL) { shelf = AgentShelf(folder: folder) }

    /// Installs the package at `source`, replacing an installation of the same name.
    @discardableResult
    public func install(_ source: AgentSource, progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> AgentInstallation {
        let manager = FileManager.default
        let work = shelf.folder.appendingPathComponent(".builds", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: work, withIntermediateDirectories: true)
        // The work folder goes whatever happens; a failed build's log is kept beside it.
        defer { try? manager.removeItem(at: work) }

        // 1. Fetch.
        let package: URL
        var revision: String?
        switch source {
        case .git(let url, let wanted):
            progress(.init(stage: "fetching \(url)"))
            let name = URL(string: url)?.deletingPathExtension().lastPathComponent ?? url.split(separator: "/").last.map(String.init) ?? "package"
            package = work.appendingPathComponent(name.replacingOccurrences(of: ".git", with: ""), isDirectory: true)
            let clone = try await AgentCommand.run(["git", "clone", "--quiet", url, package.path], in: work)
            guard clone.status == 0 else { throw AgentInstallError.fetch(source: url, reason: Self.tail(clone.output)) }
            if let wanted {
                let checkout = try await AgentCommand.run(["git", "checkout", "--quiet", wanted], in: package)
                guard checkout.status == 0 else { throw AgentInstallError.fetch(source: "\(url)@\(wanted)", reason: Self.tail(checkout.output)) }
            }
            revision = try await Self.head(of: package)
        case .path(let path):
            package = URL(fileURLWithPath: path, isDirectory: true)
            guard manager.fileExists(atPath: package.appendingPathComponent("Package.swift").path) else {
                throw AgentInstallError.notAPackage(source: path, reason: "it has no Package.swift")
            }
            revision = try? await Self.head(of: package)
        }

        // 2. Read the manifest.
        progress(.init(stage: "reading the package"))
        let dump = try await AgentCommand.run(["swift", "package", "dump-package", "--package-path", package.path], in: work)
        guard dump.status == 0, let manifest = Self.json(in: dump.output) else {
            if dump.status == 127 { throw AgentInstallError.toolchain("`swift` was not found") }
            throw AgentInstallError.notAPackage(source: source.description, reason: Self.tail(dump.output))
        }
        let read = try PackageManifest(manifest, source: source.description)

        // 3. Write the runner.
        let runner = work.appendingPathComponent("runner", isDirectory: true)
        try manager.createDirectory(at: runner.appendingPathComponent("Sources/agent"), withIntermediateDirectories: true)
        try read.runnerManifest(packagePath: package.path, packageIdentity: package.lastPathComponent)
            .write(to: runner.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try Self.runnerMain.write(to: runner.appendingPathComponent("Sources/agent/Agent.swift"), atomically: true, encoding: .utf8)

        // 4. Build.
        progress(.init(stage: "building \(read.name)"))
        let build = try await AgentCommand.run(["swift", "build", "-c", "release", "--product", "agent", "--package-path", runner.path], in: runner) { line in
            progress(.init(stage: "building \(read.name)", line: line))
        }
        guard build.status == 0 else {
            let log = shelf.folder.appendingPathComponent(".builds/\(read.name).log")
            try? build.output.write(to: log, atomically: true, encoding: .utf8)
            throw AgentInstallError.build(name: read.name, log: Self.tail(build.output, lines: 12), path: log.path)
        }
        let bin = try await AgentCommand.run(["swift", "build", "-c", "release", "--show-bin-path", "--package-path", runner.path], in: runner)
        let products = URL(fileURLWithPath: bin.output.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "",
                           isDirectory: true)
        let built = products.appendingPathComponent("agent")

        // 5. Describe and check.
        progress(.init(stage: "asking \(read.name) what it carries"))
        let entries = try await AgentProcess(executable: built).describe()
        guard !entries.isEmpty else { throw AgentInstallError.noAgent(name: read.name) }
        for other in shelf.installations() where other.name != read.name {
            if let word = entries.map(\.word).first(where: other.words.contains) {
                throw AgentInstallError.clash(word: word, installed: other.source.description)
            }
        }

        // 6. Install, whole or not at all.
        progress(.init(stage: "installing \(read.name)"))
        let staged = shelf.folder.appendingPathComponent(".\(read.name).new", isDirectory: true)
        try? manager.removeItem(at: staged)
        try manager.createDirectory(at: staged, withIntermediateDirectories: true)
        try manager.copyItem(at: built, to: staged.appendingPathComponent("agent"))
        for bundle in (try? manager.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? [] where bundle.pathExtension == "bundle" {
            try manager.copyItem(at: bundle, to: staged.appendingPathComponent(bundle.lastPathComponent))
        }
        let executable = staged.appendingPathComponent("agent")
        let attributes = try manager.attributesOfItem(atPath: executable.path)
        let installation = AgentInstallation(
            name: read.name, source: source, revision: revision, granite: Self.graniteRevision(runner), sha256: try AgentShelf.sha256(of: executable),
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0, modified: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970,
            builtAt: ISO8601DateFormatter().string(from: Date()), entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(installation).write(to: staged.appendingPathComponent(AgentInstallation.file))
        let destination = shelf.folder.appendingPathComponent(read.name, isDirectory: true)
        try? manager.removeItem(at: destination)
        try manager.moveItem(at: staged, to: destination)
        progress(.init(stage: "installed \(read.name): " + entries.map(\.word).joined(separator: ", ")))
        return installation
    }

    /// Installs the installation called `name` again, from its source at its newest.
    @discardableResult
    public func update(_ name: String, progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> AgentInstallation {
        guard let installed = shelf.installation(name) else { throw AgentInstallError.notInstalled(name) }
        return try await install(installed.source.newest, progress: progress)
    }

    /// Removes the installation called `name`, or carrying the agent `name`.
    @discardableResult
    public func remove(_ name: String) throws -> AgentInstallation {
        guard let installed = shelf.installation(name) else { throw AgentInstallError.notInstalled(name) }
        try FileManager.default.removeItem(at: shelf.folder(of: installed))
        return installed
    }

    // MARK: Pieces

    static let runnerMain = """
    // A runner, written by Granite's AgentInstaller: the package is linked and imported nowhere.
    import GraniteAgents

    @main
    enum Agent {
        static func main() async { await AgentServer.main() }
    }

    """

    private static func head(of folder: URL) async throws -> String? {
        let head = try await AgentCommand.run(["git", "rev-parse", "HEAD"], in: folder)
        return head.status == 0 ? head.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    private static func graniteRevision(_ runner: URL) -> String? {
        guard let data = try? Data(contentsOf: runner.appendingPathComponent("Package.resolved")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pins = object["pins"] as? [[String: Any]],
              let granite = pins.first(where: { ($0["identity"] as? String) == "granite" }),
              let state = granite["state"] as? [String: Any] else { return nil }
        return state["revision"] as? String
    }

    /// The JSON object in a tool's output, past any line it printed before it.
    private static func json(in output: String) -> [String: Any]? {
        guard let start = output.firstIndex(of: "{"), let data = String(output[start...]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func tail(_ output: String, lines: Int = 4) -> String {
        output.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }
}
#endif
