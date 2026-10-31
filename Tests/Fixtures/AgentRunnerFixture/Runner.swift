import GraniteAgents

/// A runner, as an installer writes one: the packages linked, none imported, `AgentServer` as its main.
@main
enum Runner {
    static func main() async { await AgentServer.main() }
}
