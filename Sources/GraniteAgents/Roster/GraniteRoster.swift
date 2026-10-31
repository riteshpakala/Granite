//  WHAT: The agents an app can run that it did not declare itself: the package agents and worker specs of
//        the packages it links, each found by the record it placed in the binary, or listed by hand.
//  PIN:  A RECORD IS TWO LINES IN THE PACKAGE, AND NOTHING IN THE APP. A package writes
//
//            @used @section("__DATA_CONST,__granite")
//            let marbleRecord: GraniteRoster.Record = { GraniteRoster.record(Marble.self) }
//
//        `@used` keeps it through dead stripping, `@section` puts the function's address beside every
//        other record in the image, and `discovered()` calls each one. Adding a package to an app is a
//        dependency; removing it is removing the dependency.
//  PIN:  A WORD IS ONE AGENT. Two entries with one word keep the first, in the order the images loaded.

import Foundation

public struct GraniteRoster: Sendable {
    /// What a package places in `__DATA_CONST,__granite`: a function that makes its entry, boxed and
    /// retained, for the roster to take.
    public typealias Record = @convention(c) () -> UnsafeMutableRawPointer?

    /// Every entry, one per word, in the order found.
    public let entries: [GraniteRosterEntry]

    /// A roster of these entries, the first of any word kept.
    public init(_ entries: [GraniteRosterEntry]) {
        var seen: Set<String> = []
        self.entries = entries.filter { seen.insert($0.word).inserted }
    }

    public static let empty = GraniteRoster([])

    /// The package agents, in order.
    public var packages: [AnyAgentPackage] {
        entries.compactMap { if case .package(let package) = $0 { return package } else { return nil } }
    }

    /// The worker specs, in order.
    public var workers: [AnyWorkerSpec] {
        entries.compactMap { if case .worker(let worker) = $0 { return worker } else { return nil } }
    }

    /// The package agent called `word`.
    public func package(_ word: String) -> AnyAgentPackage? {
        packages.first { $0.word == word }
    }

    /// What a package agent's record calls: its entry, boxed and retained for the roster.
    public static func record<P: GraniteAgentPackage>(_ package: P.Type) -> UnsafeMutableRawPointer? {
        GraniteRosterEntry.Box(.package(AnyAgentPackage(package))).retained()
    }

    /// What a worker spec's record calls: its entry, boxed and retained for the roster.
    public static func record<W: GraniteWorkerSpec>(worker spec: W.Type) -> UnsafeMutableRawPointer? {
        GraniteRosterEntry.Box(.worker(AnyWorkerSpec(spec))).retained()
    }
}
