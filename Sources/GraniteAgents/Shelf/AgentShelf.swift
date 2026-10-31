//  WHAT: A folder of installed runners, one folder each with its `installation.json`: what a host reads to offer
//        the agents they carry, without running one. Each agent's call checks the executable before it runs it.
//  PIN:  A CHANGED EXECUTABLE IS NOT RUN. A shelf is a folder anything running as the user can write to; an
//        executable whose digest is not the one recorded at install is refused with a sentence, and installing
//        it again is the way back. The digest is taken only when the size or modification time moved.

#if os(macOS)
import CryptoKit
import Foundation

public struct AgentShelf: Sendable {
    public let folder: URL

    public init(folder: URL) { self.folder = folder.standardizedFileURL }

    /// Every installation on the shelf, by name; one that does not read is left out (`problems` says why).
    public func installations() -> [AgentInstallation] { read().installations }

    /// Sentences for each folder whose installation does not read.
    public func problems() -> [String] { read().problems }

    /// The installation called `name`, or carrying the agent `name`, matched in any case.
    public func installation(_ name: String) -> AgentInstallation? {
        let lower = name.lowercased()
        let all = installations()
        return all.first { $0.name.lowercased() == lower } ?? all.first { $0.words.contains { $0.lowercased() == lower } }
    }

    /// The installation's folder.
    public func folder(of installation: AgentInstallation) -> URL { folder.appendingPathComponent(installation.name, isDirectory: true) }

    /// Its executable.
    public func executable(of installation: AgentInstallation) -> URL {
        folder(of: installation).appendingPathComponent(installation.executable)
    }

    /// Every agent on the shelf, as a roster keeps them: each call one process of its runner, refused when the
    /// executable changed.
    public func entries(environment: [String: String] = ProcessInfo.processInfo.environment) -> [GraniteRosterEntry] {
        installations().flatMap { installation in
            RemoteAgent.entries(installation.entries, executable: executable(of: installation), environment: environment,
                                check: { [self] in try verify(installation) })
        }
    }

    /// What changes when an installation is added, removed or rewritten: a host reads the shelf again when it does.
    public var stamp: String {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name -> String? in
            let manifest = folder.appendingPathComponent(name).appendingPathComponent(AgentInstallation.file)
            guard let modified = (try? FileManager.default.attributesOfItem(atPath: manifest.path))?[.modificationDate] as? Date else { return nil }
            return "\(name)@\(modified.timeIntervalSince1970)"
        }.joined(separator: ",")
    }

    /// Throws `AgentRemoteError.changed` when the executable is not the one installed.
    public func verify(_ installation: AgentInstallation) throws {
        let url = executable(of: installation)
        let word = installation.words.first ?? installation.name
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            throw AgentRemoteError.changed(word: word, path: url.path)
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
        if size == installation.size, let modified, let recorded = installation.modified, abs(modified - recorded) < 0.001 { return }
        guard (try? Self.sha256(of: url)) == installation.sha256 else { throw AgentRemoteError.changed(word: word, path: url.path) }
    }

    /// A file's SHA-256, lowercase hex.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func read() -> (installations: [AgentInstallation], problems: [String]) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        var installations: [AgentInstallation] = [], problems: [String] = []
        for name in names {
            let manifest = folder.appendingPathComponent(name).appendingPathComponent(AgentInstallation.file)
            guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
            do {
                let installation = try JSONDecoder().decode(AgentInstallation.self, from: Data(contentsOf: manifest))
                guard installation.format.hasPrefix("granite-agent-installation/1") else {
                    problems.append("\(name): \(installation.format) is not an installation this host reads")
                    continue
                }
                installations.append(installation)
            } catch {
                problems.append("\(name): its \(AgentInstallation.file) does not read: \(error)")
            }
        }
        return (installations, problems)
    }
}
#endif
