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

    /// new folder name
    private static let folderName = "granite-db"
    /// Legacy (misspelled) folder name, migrated on first use if present.
    private static let legacyFolderName = "granite-file-persistance"

    /// Guards the one-time root-folder migration across concurrent store inits.
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

    /// One-time migration of the old, misspelled (`granite-file-persistance`) folder —
    /// and, on macOS, the old Caches location — into the new canonical root, so existing
    /// installs keep their saved state after upgrading.
    private static func migrateLegacyRootIfNeeded(to newRoot: URL, base: URL) {
        migrationLock.lock()
        defer { migrationLock.unlock() }

        let token = newRoot.path
        guard migratedRoots.contains(token) == false else { return }
        migratedRoots.insert(token)

        let fm = FileManager.default
        guard fm.fileExists(atPath: newRoot.path) == false else { return }

        // Candidate legacy locations, in priority order.
        var candidates: [URL] = [base.appendingPathComponent(legacyFolderName, isDirectory: true)]
        #if os(macOS)
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            candidates.append(caches.appendingPathComponent(legacyFolderName, isDirectory: true))
        }
        #endif

        for legacy in candidates where fm.fileExists(atPath: legacy.path) {
            do {
                try fm.createDirectory(at: newRoot.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try fm.moveItem(at: legacy, to: newRoot)
                GraniteLog("migrated persistence \(legacy.path) → \(newRoot.path)", level: .info)
                return
            } catch {
                GraniteLog("persistence migration failed: \(error.localizedDescription)", level: .error)
            }
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
