# ``GraniteAgents``

Agents on Granite: an operation that computes off main and streams, declared on a center like an
event, with every frame reduced into state by one writer on main.

## Overview

A Granite reducer is the right shape for a change of state, and the wrong one for work that runs for
seconds and says things as it goes: a model's reply, a filter over a photo, a watch over a folder.
`GraniteAgents` adds that shape. An agent is a ``GraniteAgent``: its `run` computes in a task of its
own and streams events; its `reduce` folds each event into the center's state on main, keyed by run,
so a frame of a run that was replaced never lands. A center declares it with ``Agent``, beside its
`@Event`s, and a send reaches a run the way a send reaches a reducer.

```swift
struct NotesCenter: GraniteCenter {
    struct State: GraniteState { var summaries: [String: String] = [:] }

    @Event var open: Open.Reducer
    @Agent(.parallel(max: 2)) var summarizer: Summarizer.Agent
    @Store var state: State
}

center.summarizer.send(.init(note: id, text: text))         // a run begins; frames land on later turns
try await center.$summarizer.perform(.init(note: id, text: text))   // returns once the state is complete
```

An agent can also ship as a Swift package of its own: a word, a `Codable` input and output, and a
run. An app that links the package finds it through the ``GraniteRoster``, with no list to edit:
<doc:AgentPackages>. An app that does not link it can install it from source and run it in a process of
its own, one call each: <doc:RemoteAgents>. The standard both follow is `Schema/GraniteAgent.md`,
`granite-agent/1`.

`GraniteAgents` builds on `Granite` and imports nothing else: Foundation and Granite's own events.

## Topics

### Essentials

- <doc:Agents>
- ``Agent``
- ``GraniteAgent``
- ``AgentExecutable``
- ``AgentContext``

### Runs

- ``AgentRunID``
- ``AgentConcurrency``
- ``AgentLifecycle``
- ``AgentStart``
- ``AgentOutcome``
- ``AgentRunError``
- ``AgentRunScope``
- ``ChildFrame``

### Agent packages

- <doc:AgentPackages>
- ``GraniteAgentPackage``
- ``GraniteWorkerSpec``
- ``WorkerBudget``
- ``GraniteRoster``
- ``GraniteRosterEntry``
- ``AnyAgentPackage``
- ``AnyWorkerSpec``
- ``AgentPackageError``
- ``AgentMake``

### What a call answers

- ``AgentAnswer``
- ``AgentAnswerStandard``
- ``AgentMade``
- ``AgentExpected``
- ``AgentProblem``
- ``AgentPayload``
- ``AgentAnswerCheck``
- ``AgentRefusal``
- ``AgentRefusing``
- ``GraniteSchema``

### Running a package out of process

- <doc:RemoteAgents>

### What a host offers a package

- ``AgentHost``
- ``AgentHostModel``
- ``AgentHostError``

### Hosting a package agent

- ``AgentPackageCenter``
- ``AgentPackageRun``
- ``AgentPackageCall``

### What a service runs on

- ``Live``
- ``onMain(_:)``
- ``GraniteTickets``
- ``TicketError``
- ``GraniteLane``
- ``RunRegistry``
- ``TransientRegistry``
- ``TransientState``
