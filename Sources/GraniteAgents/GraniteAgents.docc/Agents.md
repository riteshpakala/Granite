# Agents

Declare an agent on a center, compute in its run, and write its frames in its reduce.

## Overview

An agent is one operation that takes time and says things while it runs. Granite owns durable state;
the agent's run owns compute. `run` never touches state and `reduce` never computes: the run streams
events from a task of its own, and the agent's `reduce` folds them into the center's state on main,
one commit per drain, fresh state each time.

### The agent

```swift
struct Summarizer: GraniteAgent {
    struct Input: Sendable { var note: String; var text: String }
    typealias Center = NotesCenter
    typealias Event = String                    // a word, streamed
    typealias Compute = any SummaryModel        // attached by the app; a protocol seam

    init() {}

    /// Which runs are "the same": one run per note.
    static func key(_ input: Input) -> String { input.note }

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await word in context.compute.summarize(input.text) {
                        if Task.isCancelled || context.isCancelled() { break }
                        continuation.yield(word)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }   // a cancel ends the work
        }
    }

    func reduce(state: inout NotesCenter.State, event: String, run: AgentRunID) {
        state.summaries[run.key, default: ""] += event          // on main, keyed by run
    }
}
```

- `Input` is what a send carries; `key(_:)` decides which runs are the same for the policy, and the
  run's id (``AgentRunID``) carries it, so `reduce` knows what a frame belongs to.
- `Compute` is what a run computes with, resolved by the app for each run (``AgentExecutable/attach(_:)``):
  a model session, a Metal pipeline, a speech recognizer. Nothing in the engine names a kind of work.
- `reduce(state:lifecycle:run:)` sees ``AgentLifecycle/started``, `finished`, `cancelled` and
  `failed`, committed after the run's last frames. `coalesce(_:_:)` folds two queued frames into one
  (text deltas), so a fast stream is one commit a drain, not one a token.

### The declaration and the handle

```swift
@Agent var summarizer: Summarizer.Agent                  // the agent's own policy
@Agent(.parallel(max: 4)) var worker: Worker.Agent       // the declaration's policy wins
@Agent(.onTask) var watcher: Watcher.Agent               // started by the host's task, with `lifecycleInput`
```

`center.summarizer` and `center.$summarizer` are the same ``AgentExecutable``:

| Call | Where | What it does |
|---|---|---|
| `attach { input in compute }` | the app, once | resolves `Compute` for each run |
| `send(input)` | main (off main it hops) | starts a run, or applies the policy to a live one |
| `start(input) -> AgentStart` | main | `.started(id)`, `.queued(id)`, `.merged(into: id)` or `.dropped` |
| `perform(input) async throws -> AgentOutcome` | any thread | returns after the lifecycle is committed after the last frames |
| `wait(run:)`, `wait(prefix:)` | any thread | a run someone else started; every run under a key prefix |
| `cancel(key:)`, `cancel(prefix:)` | main | commits `.cancelled` at once; a run still waiting for a lane ends too |
| `isLive(key:)`, `liveKeys()` | main | what runs now |
| `events(key:) -> AsyncStream<Event>` | main | every event of the run, before it is reduced |

### The four policies

| Policy | A second send with the same key while one is live | `perform` of that send |
|---|---|---|
| ``AgentConcurrency/supersede`` (default) | cancels the live run and starts this one | the first waiter fails `.superseded` |
| ``AgentConcurrency/drop`` | ignored | throws `.dropped` at once |
| ``AgentConcurrency/merge`` | handed to the live run's `merge(_:into:context:)` | joins the live run and returns with it |
| ``AgentConcurrency/parallel(max:)`` | runs beside it, up to `max`; more queue, ids already minted | each waits for its own run |

### From a reducer: send or perform

When nothing after the spawn depends on the run, the effect sends and ends; the agent's own `reduce`
writes the frames on later turns:

```swift
func effect(state: Center.State) -> GraniteEffect {
    guard let meta else { return .none }
    let summarizer = Live.service(NotesService.self).center.$summarizer   // captured before .run
    return .run { summarizer.send(.init(note: meta.note, text: meta.text)) }
}
```

When the effect must act on the finished run, it awaits `perform`, then writes through its service's
writer and resolves its ticket, reading complete state:

```swift
return .run {
    do {
        let outcome = try await summarizer.perform(.init(note: meta.note, text: meta.text))
        notes.set(.summarized(meta.note, words: outcome.frames))
        await NotesService.tickets.resolve(meta.ticket, with: .done)
    } catch {
        notes.set(.failed(meta.note, "\(error)"))
        await NotesService.tickets.fail(meta.ticket, error)
    }
}
```

A run never performs its own executable and key: inside its run, that `perform` throws
``AgentRunError/reentrant(_:)`` (``AgentRunScope`` carries the run's id). A child inside a run goes
through ``AgentContext/spawn(_:input:compute:id:kind:prompt:map:)``: its frames are mapped into the
parent's events, in the parent's order, and cancelling the parent cancels it.

### What a service runs on

The engine comes with what a service built around agents needs:

- ``Live/service(_:)`` resolves a service's live instance when it is needed. A stored relay points
  down, never back: a reducer that relays to its own service recurses at construction.
- ``onMain(_:)`` is the one hop: inline on main, hopped from anywhere else. Granite's `send` is
  main-only.
- ``GraniteTickets`` is a typed reply slot: open, send the id in a payload, await the value the
  reducer's effect resolves. A reply that lands before the wait is kept.
- ``GraniteLane`` runs bodies one after another; ``RunRegistry`` cancels work by id, a cancel that
  beats its register leaving a tombstone; ``TransientRegistry`` keeps what a state cannot hold.
- ``TransientState`` is a state that is never persisted: it codes as an empty object.

### Testing

Host the center without SwiftUI, attach a fake, perform, and read the state right after the await:

```swift
@MainActor
func testASummaryLandsBeforePerformReturns() async throws {
    let command = GraniteCommand<NotesCenter>.hosted()
    command.center.$summarizer.attach { _ in FakeSummaryModel(words: ["a", "b"]) }
    _ = try await command.center.$summarizer.perform(.init(note: "n", text: "…"))
    XCTAssertEqual(command.center.state.summaries["n"], "ab")
}
```

### Checklist

- The agent is a ``GraniteAgent``; `run` streams and touches no state; `reduce` folds.
- `key(_:)` names what "the same run" means; the policy is declared where the center declares the agent.
- Compute is a protocol seam attached once by the app; tests attach a fake.
- A reducer spawns with `send`, or with `perform` and then its writer and its ticket.
- Executables and payloads are captured before `.run`; a tap is made before the send it is for.
- No run performs its own executable and key; children go through `context.spawn`.
