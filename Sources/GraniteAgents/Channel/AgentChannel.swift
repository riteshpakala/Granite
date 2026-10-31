//  WHAT: How wire messages travel between a host and an agent: one is sent at a time, whole, and the other
//        side's arrive as a stream that ends when it closes. A pipe pair today (`PipeChannel`).
//  PIN:  THE SEAM A MACHINE TAKES. Nothing above a channel knows whether the other side is a child process or
//        another computer; a socket to a runner elsewhere is another channel, and the host and the server
//        stay as they are.

import Foundation

public protocol AgentChannel: Sendable {
    /// Sends one message, whole, before any sent after it.
    func send(_ message: AgentWire) throws
    /// The other side's messages, in order; the stream ends when the other side closes.
    var messages: AsyncStream<AgentWire> { get }
    /// Stops sending; the other side reads to its end.
    func close()
}
