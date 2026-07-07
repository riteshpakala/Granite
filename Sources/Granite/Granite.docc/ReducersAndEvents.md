# Reducers, Events & Effects

Mutate state with reducers, and chain follow-up work with the typed effect DSL or `@Event`
forwarding.

## Overview

A ``GraniteReducer`` is a value type that mutates `inout` state. Reducers can be synchronous,
`async`, or streaming, and they can declare follow-up work — including chaining sibling
reducers — either with the type-safe ``GraniteEffect`` API (recommended) or with
`@Event(.after)` forwarding.

## Synchronous, async, and streaming reducers

```swift
// Synchronous
struct Toggle: GraniteReducer {
    typealias Center = SettingsCenter
    func reduce(state: inout Center.State) { state.enabled.toggle() }
}

// Async: opt in with `behavior`
struct Load: GraniteReducer {
    typealias Center = FeedCenter
    var behavior: GraniteReducerBehavior { .task(.userInitiated) }
    func reduce(state: inout Center.State) async {
        state.items = await api.fetchItems()
    }
}
```

For token-by-token updates (for example, streaming an LLM response), use `.streamingTask` and
the `stream` closure. Each `stream(state)` call is applied to SwiftUI immediately on the main
thread rather than overwriting a single snapshot at the end:

```swift
struct StreamReply: GraniteReducer {
    typealias Center = ChatCenter
    var behavior: GraniteReducerBehavior { .streamingTask(.userInitiated) }

    func reduce(state: inout Center.State,
                stream: @escaping (Center.State) -> Void) async {
        for await token in tokens {
            state.reply += token
            stream(state)
        }
    }
}
```

Streaming frames are dropped once the task is cancelled (for example, when a newer send
supersedes this one), so a stale token can't overwrite fresher state.

## Chaining reducers with the effect DSL

Return a ``GraniteEffect`` from ``GraniteReducer/effect(state:)`` to declare what should happen
*after* the reducer commits. This is the recommended, type-safe way to chain reducers within a
center — no reflection, no nested `@Event`.

```swift
struct Submit: GraniteReducer {
    typealias Center = FormCenter

    func reduce(state: inout Center.State) {
        state.isSubmitting = true
    }

    func effect(state: Center.State) -> GraniteEffect {
        .merge(
            .chain(Validate.self),               // fire a sibling reducer
            .run { await Analytics.track("submit") } // fire-and-forget async work
        )
    }
}
```

- ``GraniteEffect/chain(_:payload:)`` fires a sibling reducer declared as an `@Event` in the
  same center. Chaining a reducer that isn't declared there is a safe no-op.
- ``GraniteEffect/run(_:)`` runs fire-and-forget async work in a cooperative task.
- `merge(_:)` runs several effects in order.

Effects run **after** the state commit. For `async` and `.streamingTask` reducers they run
strictly after the awaited `reduce` completes, giving deterministic ordering.

## Chaining with `@Event(.after)` forwarding

The original forwarding mechanism is still supported. Declare a nested `@Event` inside a reducer
with `.before` or `.after`, and it fires around the reducer's state commit:

```swift
struct Refresh: GraniteReducer {
    typealias Center = FeedCenter
    @Event(.after) var reindex: Reindex.Reducer   // fires after Refresh commits
    func reduce(state: inout Center.State) { /* ... */ }
}
```

Prefer the effect DSL for new code: it is type-safe, avoids the reflection cost of nested-event
discovery, and makes ordering explicit.

## Reacting across commands with `@Notify`

Use ``Notify`` when a component should react to *another* command's (or service's) reducer
completing — for example, a component reducer that responds to a service's network call
finishing.

## Topics

### Reducer types

- ``GraniteReducer``
- ``GraniteReducerBehavior``
- ``GraniteEffect``

### Events

- ``Event``
- ``Notify``
