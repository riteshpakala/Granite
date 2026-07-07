//
//  Persistence.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/10/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/// Errors surfaced by the persistence layer. Previously every failure was swallowed to a
/// log; callers can now distinguish "no saved state yet" (expected on first launch) from a
/// genuine read/write/decode failure.
public enum PersistenceError: Error, Sendable {
    /// No persisted file exists yet (normal on first launch).
    case notFound
    /// Encoding the state to data failed.
    case encodingFailed(String)
    /// Writing the encoded data to disk failed.
    case writeFailed(String)
    /// The file existed but could not be decoded into `State` (corrupt or incompatible).
    /// The unreadable file is backed up rather than overwritten.
    case decodingFailed(String)
}

/// A versioned envelope wrapping persisted state on disk.
///
/// Storing an explicit `version` alongside the payload enables future schema migrations
/// and lets `restore` distinguish the modern format from Granite's original raw-`State`
/// format (which it still reads transparently for backward compatibility).
struct PersistenceEnvelope<State: Codable>: Codable {
    /// The current on-disk schema version written by this build.
    static var currentVersion: Int { 1 }

    var version: Int
    var state: State

    init(_ state: State, version: Int = PersistenceEnvelope.currentVersion) {
        self.version = version
        self.state = state
    }
}

/*
 Base class for Persistence types.
*/
public protocol AnyPersistence: AnyObject, Sendable {
    var readWriteQueue: OperationQueue? { get }

    var key: String { get }

    var isRestoring: Bool { get set }
    var hasRestored: Bool { get set }

    init(key: String, kind: PersistenceKind)

    func save<State: Codable>(state: State)
    /// Restores persisted state, throwing ``PersistenceError`` on failure so callers can
    /// react to a missing file differently from a corrupt one.
    func restore<State: Codable>() throws -> State
    func purge()
}

public enum PersistenceKind: Sendable {
    case basic
    //App Groups, group ID as string
    case group(String)
}

extension AnyPersistence {
    public var key: String {
        "Empty"
    }

    public func save<State>(state: State) where State: Codable {}

    public func restore<State>() throws -> State where State: Codable {
        throw PersistenceError.notFound
    }

    public func purge() {}
}

/*
 Mostly used for default inits
*/
public final class EmptyPersistence: AnyPersistence, @unchecked Sendable {
    public let readWriteQueue: OperationQueue? = .init()
    public var isRestoring: Bool = false
    public var hasRestored: Bool = false

    public init() {}
    public required init(key: String, kind: PersistenceKind) {}
}
