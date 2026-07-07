# ``Granite``

A declarative, unidirectional SwiftUI architecture built on components, reducers, events, and typed effects.

## Overview

Granite structures a SwiftUI app as a tree of **components**, each backed by a **center** that
owns **state** and declares **reducers**. Views stay thin and declarative; all logic lives in
reducers that mutate state as a value type. State changes flow back to SwiftUI on the main
thread, and side effects — including chaining one reducer into another — are expressed
declaratively with ``GraniteEffect`` or `@Event(.after)` forwarding.

```swift
struct Counter: GraniteComponent {
    @Command var center: Center

    struct Center: GraniteCenter {
        struct State: GraniteState {
            var value: Int = 0
        }
        @Store var state: State

        @Event var increment: Increment.Reducer
    }

    var view: some View {
        Button("Count: \(center.state.value)") {
            center.increment.send()
        }
    }
}

struct Increment: GraniteReducer {
    typealias Center = Counter.Center
    func reduce(state: inout Center.State) {
        state.value += 1
    }
}
```

### Design principles

- **Unidirectional data flow.** UI dispatches events; reducers mutate value-type state; SwiftUI
  re-renders. There is no hidden two-way binding to fight.
- **State delivered on the main thread.** Reducers may run off the main thread, but state is
  always published to SwiftUI on the main actor, so there are no background-publish warnings.
- **Explicit side effects.** Follow-up work is a value (``GraniteEffect``), not a hidden
  callback, so chaining and async work are easy to read and test.
- **Durable, safe persistence.** ``Store`` persistence writes atomically in a versioned
  envelope, backs up unreadable files instead of clobbering them, and never blocks the main
  thread on disk I/O.

## Topics

### Essentials

- <doc:GettingStarted>
- ``GraniteComponent``
- ``GraniteCenter``
- ``GraniteState``

### Reducers, Events & Effects

- <doc:ReducersAndEvents>
- ``GraniteReducer``
- ``GraniteEffect``
- ``Event``
- ``Notify``

### Services & Relays

- <doc:ServicesAndRelays>
- ``GraniteService``
- ``Relay``

### Persisting state

- <doc:Persistence>
- ``Store``
- ``FilePersistence``
- ``PersistenceKind``
- ``PersistenceError``

### Concurrency model

- <doc:Concurrency>
