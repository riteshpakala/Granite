//
//  FilePersistence.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/10/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/// Thread-safe registry of per-key serial write queues.
///
/// Each persisted key gets one `OperationQueue` (serial, `.utility` QoS) so that writes to
/// the same file never overlap. The registry is guarded by an internal lock and is
/// `@unchecked Sendable` because `OperationQueue` itself is thread-safe.
final class FilePersistenceJobs: @unchecked Sendable {
    static let shared = FilePersistenceJobs()

    private let lock = NSLock()
    private var map: [String: OperationQueue] = [:]

    func queue(for key: String) -> OperationQueue {
        lock.lock()
        defer { lock.unlock() }
        if let existing = map[key] { return existing }

        let underlying = DispatchQueue(label: "granite.rw.queue.\(key)", qos: .utility)
        let queue = OperationQueue()
        queue.underlyingQueue = underlying
        queue.maxConcurrentOperationCount = 1
        map[key] = queue
        return queue
    }
}

/*
 Allows for @Store'd GraniteStates to persist data. A lightweight
 CoreData alternative.

 Storage guarantees:
  - Writes are **atomic** and use the compact **binary** property-list format.
  - State is wrapped in a versioned ``PersistenceEnvelope`` so schemas can migrate.
  - A file that fails to decode is **backed up** (never silently overwritten).
  - On macOS state lives in Application Support (durable), not Caches (purgeable).
*/
final public class FilePersistence: AnyPersistence, @unchecked Sendable {

    /// One shared encoder/decoder pair, configured once. `PropertyListEncoder` defaults to
    /// verbose XML; `.binary` is smaller and faster and both are thread-safe for encode/decode.
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()
    private static let decoder = PropertyListDecoder()

    /// The folder every store saves under.
    private static let folderName = "granite-db"
    /// Folders earlier releases saved under, **newest first**. Their files are adopted
    /// into ``folderName`` at launch (see ``adoptLegacyFiles(into:from:fileManager:)``).
    ///  - `GranitePersistence`: 1269b5a (2026-07) up to 7a2be5f (2026-08), which renamed
    ///    the folder without migrating it, so apps upgrading across that commit launched
    ///    with every store empty.
    ///  - `granite-file-persistance`: the original, misspelled name.
    static let legacyFolderNames = ["GranitePersistence", "granite-file-persistance"]

    /// Guards the once-per-process legacy migration across concurrent store inits.
    private static let migrationLock = NSLock()
    nonisolated(unsafe) private static var migratedRoots: Set<String> = []

    public var readWriteQueue: OperationQueue? {
        FilePersistenceJobs.shared.queue(for: key)
    }

    public static var initialValue: FilePersistence {
        .init(key: UUID().uuidString, kind: .basic)
    }

    public let key: String

    private let url: URL

    private let flagLock = NSLock()
    private var _isRestoring: Bool = false
    private var _hasRestored: Bool = false

    public var isRestoring: Bool {
        get { flagLock.lock(); defer { flagLock.unlock() }; return _isRestoring }
        set { flagLock.lock(); defer { flagLock.unlock() }; _isRestoring = newValue }
    }

    public var hasRestored: Bool {
        get { flagLock.lock(); defer { flagLock.unlock() }; return _hasRestored }
        set { flagLock.lock(); defer { flagLock.unlock() }; _hasRestored = newValue }
    }

    public required init(key: String, kind: PersistenceKind) {
        let rootPath = Self.rootURL(for: kind)

        self.key = key
        self.url = rootPath.appendingPathComponent(key)

        do {
            try FileManager.default.createDirectory(at: rootPath,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        }
        catch let error {
            GraniteLog(error.localizedDescription, level: .error)
        }
    }

    // MARK: - Locations

    private static func defaultRootURL() -> URL {
        let base: URL
        #if os(macOS)
        // Application Support is durable; Caches can be purged by the OS under disk
        // pressure, which would silently drop "persisted" state. Scope by bundle id so
        // multiple apps don't collide.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleId = Bundle.main.bundleIdentifier ?? "Granite"
        base = support.appendingPathComponent(bundleId, isDirectory: true)
        #else
        base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func rootURL(for kind: PersistenceKind) -> URL {
        switch kind {
        case .basic:
            let root = defaultRootURL()
            migrateLegacyRootIfNeeded(to: root, base: defaultBase())
            return root
        case .group(let id):
            #if os(macOS)
            let root = defaultRootURL()
            migrateLegacyRootIfNeeded(to: root, base: defaultBase())
            return root
            #else
            guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: id) else {
                let root = defaultRootURL()
                migrateLegacyRootIfNeeded(to: root, base: defaultBase())
                return root
            }
            let root = container.appendingPathComponent(folderName, isDirectory: true)
            migrateLegacyRootIfNeeded(to: root, base: container)
            return root
            #endif
        }
    }

    private static func defaultBase() -> URL {
        #if os(macOS)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleId = Bundle.main.bundleIdentifier ?? "Granite"
        return support.appendingPathComponent(bundleId, isDirectory: true)
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
    }

    /// Every legacy folder that may hold this install's saved state, newest first: each
    /// retired name beside the current root, then (macOS) the old Caches location.
    private static func legacyRoots(base: URL) -> [URL] {
        var roots = legacyFolderNames.map { base.appendingPathComponent($0, isDirectory: true) }
        #if os(macOS)
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            roots += legacyFolderNames.map { caches.appendingPathComponent($0, isDirectory: true) }
        }
        #endif
        return roots
    }

    /// Adopts any legacy folders into `newRoot`, once per process, before the first store
    /// in that root reads anything.
    private static func migrateLegacyRootIfNeeded(to newRoot: URL, base: URL) {
        migrationLock.lock()
        defer { migrationLock.unlock() }

        let token = newRoot.path
        guard migratedRoots.contains(token) == false else { return }
        migratedRoots.insert(token)

        let adopted = adoptLegacyFiles(into: newRoot, from: legacyRoots(base: base))
        if !adopted.isEmpty {
            GraniteLog("adopted legacy persistence into \(newRoot.path): \(adopted.joined(separator: ", "))",
                       level: .info)
        }
    }

    /// Moves every file in `legacyRoots` into `newRoot`, **one file at a time**.
    ///
    /// Per file, not per folder: the old folder move skipped migration whenever `newRoot`
    /// already existed, and a build that shipped the rename without a migration had
    /// already created it — with every store reset to defaults.
    ///
    /// **A legacy file wins over one already in `newRoot`.** A legacy folder only holds
    /// data when this install last saved there: before the rename, or after a downgrade
    /// to a build that still uses it. Either way it is the newest copy, and a `newRoot`
    /// file for the same key came from a launch that could not see it. The file it
    /// replaces is kept as `<name>.superseded-<unix time>`, never deleted.
    ///
    /// Runs every launch rather than once, so a downgrade-then-upgrade is handled too;
    /// with no legacy folders left it costs one existence check per folder. Adopted
    /// folders are removed once empty. When two legacy folders hold the same name, the
    /// newer folder's copy is adopted and the older one is set aside, so it can never be
    /// adopted over current data on a later launch.
    ///
    /// - Returns: The names adopted into `newRoot`, in the order they were moved.
    @discardableResult
    static func adoptLegacyFiles(into newRoot: URL,
                                 from legacyRoots: [URL],
                                 fileManager fm: FileManager = .default) -> [String] {
        let present = legacyRoots.filter { fm.fileExists(atPath: $0.path) }
        guard !present.isEmpty else { return [] }

        do {
            try fm.createDirectory(at: newRoot, withIntermediateDirectories: true)
        } catch {
            GraniteLog("persistence migration failed: \(error.localizedDescription)", level: .error)
            return []
        }

        let stamp = Int(Date().timeIntervalSince1970)
        var claimed: Set<String> = []
        var adopted: [String] = []

        for legacyRoot in present {
            let names = (try? fm.contentsOfDirectory(atPath: legacyRoot.path)) ?? []
            for name in names.sorted() {
                let source = legacyRoot.appendingPathComponent(name)
                let destination = newRoot.appendingPathComponent(name)

                // A newer legacy folder already supplied this name.
                guard claimed.insert(name).inserted else {
                    _ = setAside(source, as: name, in: newRoot, stamp: stamp, fm)
                    continue
                }

                var displaced: URL? = nil
                if fm.fileExists(atPath: destination.path) {
                    guard let aside = setAside(destination, as: name, in: newRoot, stamp: stamp, fm)
                    else { continue }   // can't keep the current file safe: leave both alone
                    displaced = aside
                }

                do {
                    try fm.moveItem(at: source, to: destination)
                    adopted.append(name)
                } catch {
                    GraniteLog("persistence migration of \(name) failed: \(error.localizedDescription)",
                               level: .error)
                    if let displaced { try? fm.moveItem(at: displaced, to: destination) }
                }
            }

            if (try? fm.contentsOfDirectory(atPath: legacyRoot.path))?.isEmpty == true {
                try? fm.removeItem(at: legacyRoot)
            }
        }
        return adopted
    }

    /// Moves `url` to `<name>.superseded-<stamp>` in `root`, never overwriting anything.
    private static func setAside(_ url: URL, as name: String, in root: URL,
                                 stamp: Int, _ fm: FileManager) -> URL? {
        var aside = root.appendingPathComponent("\(name).superseded-\(stamp)")
        var suffix = 1
        while fm.fileExists(atPath: aside.path) {
            aside = root.appendingPathComponent("\(name).superseded-\(stamp)-\(suffix)")
            suffix += 1
        }
        do {
            try fm.moveItem(at: url, to: aside)
            return aside
        } catch {
            GraniteLog("persistence migration could not set aside \(name): \(error.localizedDescription)",
                       level: .error)
            return nil
        }
    }

    // MARK: - Save / Restore

    public func save<State>(state: State) where State: Codable {
        let url = self.url
        let key = self.key
        readWriteQueue?.addOperation {
            do {
                let envelope = PersistenceEnvelope(state)
                let data = try Self.encoder.encode(envelope)
                // Atomic: a crash/kill mid-write can no longer leave a truncated file.
                try data.write(to: url, options: [.atomic])
            }
            catch let error {
                GraniteLog("key: \(key) | error: \(error.localizedDescription)", level: .error)
            }
        }
    }

    public func restore<State>() throws -> State where State: Codable {
        guard let data = try? Data(contentsOf: url) else {
            // Expected on first launch — not an error.
            GraniteLog("no persisted state for key: \(key)", level: .debug)
            throw PersistenceError.notFound
        }

        // Modern (enveloped) format.
        if let envelope = try? Self.decoder.decode(PersistenceEnvelope<State>.self, from: data) {
            hasRestored = true
            return envelope.state
        }

        // Legacy raw-State format (pre-envelope installs): decode transparently; it will be
        // re-written in the enveloped format on the next save.
        if let legacy = try? Self.decoder.decode(State.self, from: data) {
            hasRestored = true
            GraniteLog("restored legacy (unversioned) state for key: \(key)", level: .debug)
            return legacy
        }

        // Genuinely undecodable — back it up rather than clobber it with defaults.
        backupCorruptFile()
        GraniteLog("key: \(key) | corrupt state backed up", level: .error)
        throw PersistenceError.decodingFailed("undecodable state for key \(key)")
    }

    private func backupCorruptFile() {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(key).corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    public func purge() {
        try? FileManager.default.removeItem(at: url)
    }
}
