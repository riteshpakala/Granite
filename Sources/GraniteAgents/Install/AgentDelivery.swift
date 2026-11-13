//  WHAT: A package's code as a store hands it over, and the three places a host plugs into that: who asks the store
//        (`AgentDeliverer`), what undoes an encoding the code arrived in (`AgentPayloadDecoder`), and what runs on the
//        built executable before it goes on the shelf (`AgentBuildFinishing`).
//
//            store → AgentDelivery (an archive at an address that works for minutes, its transforms)
//                  → download → decoders, in the delivery's order → unpack → the install as from a folder
//
//  PIN:  NOTHING KEPT NAMES THE ADDRESS. An installation records `.delivered(id:)`; every install and update asks the
//        store again, so an address that expires is used once, at once.
//  PIN:  ONLY WHAT THIS MACHINE CAN UNDO. The installer tells the store which transforms it has decoders for, and refuses
//        a delivery that names one it hasn't; plain source names none.
//  PIN:  THE SOURCE IS GONE AFTER THE BUILD. It is unpacked inside the install's work folder, which goes whatever
//        happens; only the executable (and its bundles) reach the shelf.

import Foundation

/// One snapshot of a package's code, as a store hands it over.
public struct AgentDelivery: Sendable, Equatable {
    public enum Format: String, Sendable, Equatable, Codable {
        /// A gzipped tarball, one folder inside (GitHub's archive of a repository) or the package's files at its root.
        case tarGz = "tar.gz"
    }

    /// The commit the snapshot is of: what the installation records as its revision.
    public var revision: String
    /// The folder the package is unpacked into, which a Swift package's identity follows (a repository's name, as a
    /// clone would make it).
    public var directory: String
    public var format: Format
    /// Where to fetch it, for a few minutes.
    public var url: URL
    public var expiresAt: Date?
    /// The archive's SHA-256 (hex), checked when the store gives one.
    public var sha256: String?
    /// What was done to the archive on its way, to be undone in this order before it is unpacked; empty for plain source.
    public var transforms: [String]

    public init(revision: String, directory: String, format: Format = .tarGz, url: URL, expiresAt: Date? = nil, sha256: String? = nil,
                transforms: [String] = []) {
        self.revision = revision; self.directory = directory; self.format = format; self.url = url
        self.expiresAt = expiresAt; self.sha256 = sha256; self.transforms = transforms
    }
}

/// Asks a store for a listing's code. A host that installs from a store gives the installer one.
public protocol AgentDeliverer: Sendable {
    /// The listing `id`'s code at what the listing pins now. `accepts` names the transforms this machine can undo.
    func delivery(for id: String, accepts: [String]) async throws -> AgentDelivery
}

/// Undoes one transform a delivery names (an encoding, an obfuscation, a seal), file to file, inside the work folder.
public protocol AgentPayloadDecoder: Sendable {
    /// The transform's name, as the store and the delivery say it.
    var transform: String { get }
    /// Reads `file` and writes what it decodes to, somewhere in `work`; returns that file.
    func decode(_ file: URL, in work: URL) async throws -> URL
}

/// Runs on a built executable, staged for the shelf, before its hash is taken: to strip or harden it.
public protocol AgentBuildFinishing: Sendable {
    func finish(_ executable: URL, name: String) async throws
}
