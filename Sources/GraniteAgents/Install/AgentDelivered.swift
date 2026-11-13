//  WHAT: The fetch step for a delivered source: ask the store, download the archive, check it, undo its transforms,
//        unpack it into the install's work folder, and hand back the package folder and the revision it is of.

#if os(macOS)
import Foundation

enum AgentDelivered {
    /// The package a store delivers for `id`, unpacked under `work`, and the commit it is of.
    static func fetch(_ id: String, deliverer: (any AgentDeliverer)?, decoders: [any AgentPayloadDecoder], session: URLSession, work: URL,
                      progress: @escaping @Sendable (AgentInstaller.Progress) -> Void) async throws -> (package: URL, revision: String) {
        let source = AgentSource.delivered(id: id).description
        guard let deliverer else { throw AgentInstallError.delivery(source: source, reason: "nothing here can ask its store for it") }
        progress(.init(stage: "asking for \(id)"))
        let delivery = try await deliverer.delivery(for: id, accepts: decoders.map(\.transform))

        progress(.init(stage: "fetching \(delivery.directory)"))
        var file = work.appendingPathComponent("archive")
        try await download(delivery.url, to: file, session: session, source: source)
        if let expected = delivery.sha256?.lowercased() {
            let actual = try AgentShelf.sha256(of: file)
            guard actual == expected else { throw AgentInstallError.delivery(source: source, reason: "the archive is not the one the store described") }
        }
        for transform in delivery.transforms {
            guard let decoder = decoders.first(where: { $0.transform == transform }) else {
                throw AgentInstallError.delivery(source: source, reason: "it arrives as `\(transform)`, which this version can't read; update the app")
            }
            file = try await decoder.decode(file, in: work)
        }
        let package = try await unpack(file, format: delivery.format, into: work, directory: delivery.directory, source: source)
        return (package, delivery.revision)
    }

    static func download(_ url: URL, to destination: URL, session: URLSession, source: String) async throws {
        let downloaded: URL
        let response: URLResponse
        do {
            (downloaded, response) = try await session.download(from: url)
        } catch {
            throw AgentInstallError.fetch(source: source, reason: error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: downloaded)
            let reason = http.statusCode == 403 || http.statusCode == 404 ? "its address has lapsed; try again" : "the download answered \(http.statusCode)"
            throw AgentInstallError.fetch(source: source, reason: reason)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloaded, to: destination)
    }

    /// Unpacks `archive` into `work/source/<directory>`: the one folder inside it, or its files when they sit at its root.
    static func unpack(_ archive: URL, format: AgentDelivery.Format, into work: URL, directory: String, source: String) async throws -> URL {
        let manager = FileManager.default
        let listing = try await AgentCommand.run(["tar", "-tzf", archive.path], in: work)
        guard listing.status == 0 else { throw AgentInstallError.delivery(source: source, reason: "the archive doesn't open: \(tail(listing.output))") }
        if let bad = listing.output.split(separator: "\n").map(String.init).first(where: unsafe) {
            throw AgentInstallError.delivery(source: source, reason: "the archive reaches outside its folder (\(bad))")
        }
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        try manager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let extract = try await AgentCommand.run(["tar", "-xzf", archive.path, "-C", unpacked.path], in: work)
        guard extract.status == 0 else { throw AgentInstallError.delivery(source: source, reason: "the archive doesn't unpack: \(tail(extract.output))") }
        try? manager.removeItem(at: archive)

        let inside = try manager.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: [.isDirectoryKey]).filter { $0.lastPathComponent != ".DS_Store" }
        let top = inside.count == 1 && ((try? inside[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) ? inside[0] : unpacked
        let parent = work.appendingPathComponent("source", isDirectory: true)
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let package = parent.appendingPathComponent(folderName(directory), isDirectory: true)
        try manager.moveItem(at: top, to: package)
        guard manager.fileExists(atPath: package.appendingPathComponent("Package.swift").path) else {
            throw AgentInstallError.notAPackage(source: source, reason: "it has no Package.swift")
        }
        return package
    }

    /// An entry that would land outside the folder it is unpacked into: an absolute path, or one that climbs.
    static func unsafe(_ entry: String) -> Bool {
        entry.hasPrefix("/") || entry.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }

    /// The folder a package unpacks into: the store's name for it, as one plain path component.
    static func folderName(_ directory: String) -> String {
        let cleaned = String(directory.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "-" })
        return cleaned.isEmpty || cleaned.allSatisfy({ $0 == "." }) ? "package" : cleaned
    }

    private static func tail(_ output: String) -> String { output.split(separator: "\n").suffix(3).joined(separator: "\n") }
}
#endif
