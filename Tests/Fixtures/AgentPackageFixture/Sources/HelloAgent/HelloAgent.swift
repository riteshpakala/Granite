import Foundation
import GraniteAgents

/// Says hello to whom it is given.
public struct HelloAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable { public var name: String }
    public typealias Event = String
    public typealias Output = String
    public typealias Compute = Void

    public static let word = "hello"
    public static let summary = "says hello."

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            context.host.note("greeting \(input.name)")
            continuation.yield("hello, \(input.name)")
            continuation.finish()
        }
    }
}

@used @section("__DATA_CONST,__granite")
let helloRecord: GraniteRoster.Record = { GraniteRoster.record(HelloAgent.self) }
