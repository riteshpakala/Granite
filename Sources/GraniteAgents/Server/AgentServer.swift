//  WHAT: The agent's side of `granite-agent/1`: the whole `main` of a process that carries agent packages. With
//        `--describe` it says what it carries and exits; otherwise it answers one call on stdin and stdout,
//        offering the run the host's folder, ask, notes and model over the same pipe, and exits.
//
//            import GraniteAgents
//            @main enum Agent { static func main() async { await AgentServer.main() } }
//
//        That file, in an executable that links the packages, is a runner; no file imports a package, and
//        each is found by its record, as an app finds them.
//  PIN:  STDOUT IS THE WIRE'S ALONE. The real stdout is moved aside before anything runs and the descriptor
//        the process calls stdout is pointed at stderr, so a package's `print` or Granite's own log can never
//        put a line on the wire that is not a message.
//  PIN:  MAIN IS NEVER BLOCKED. Granite reduces on main and WebKit draws on it; the async `main` only awaits,
//        and the channel reads on a thread of its own.

import Foundation
import Granite

public enum AgentServer {
    /// How the process ends.
    public enum Exit: Int32, Sendable {
        /// The call was answered with its output.
        case answered = 0
        /// The call failed, and said why.
        case failed = 1
        /// The host said something that is not a call, or left before making one.
        case unreadable = 2
        /// The host cancelled the call, or asked the process to end (SIGTERM).
        case cancelled = 130
    }

    /// A runner's `main`: never returns.
    public static func main(arguments: [String] = CommandLine.arguments) async -> Never {
        GraniteLogger.currentLevel = .error
        let wire = dup(STDOUT_FILENO)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        let channel = PipeChannel(reading: STDIN_FILENO, writing: wire, owning: true, unreadable: { line in
            FileHandle.standardError.write(Data("granite-agent: an unreadable line from the host: \(line)\n".utf8))
        })
        let roster = GraniteRoster.discovered()
        if arguments.contains("--describe") {
            try? channel.send(.entries(roster.entries.map(AgentWire.Entry.init)))
            channel.close()
            exit(Exit.answered.rawValue)
        }
        let call = AgentServerCall(channel: channel, roster: roster)
        signal(SIGTERM, SIG_IGN)
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        terminate.setEventHandler { call.cancel() }
        terminate.resume()
        let code = await call.serve()
        channel.close()
        exit(code.rawValue)
    }

    /// One call on `channel`, answered from `roster`: what `main` runs, without the process around it.
    public static func serve(_ channel: any AgentChannel, roster: GraniteRoster) async -> Exit {
        await AgentServerCall(channel: channel, roster: roster).serve()
    }
}
