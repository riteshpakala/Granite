# Components & Centers

How a Granite component renders as a SwiftUI view and where its state lives.

## Overview

A ``GraniteComponent`` is a SwiftUI `View` whose `body` is supplied by Granite. Instead of a
`body`, you implement a `view` property; Granite wraps it with geometry and lifecycle handling.

Each component owns a `@Command`, which holds a ``GraniteCenter``. The center is the single
place that declares the component's `@Store` state and its `@Event` reducers.

```swift
struct Profile: GraniteComponent {
    @Command var center: Center

    struct Center: GraniteCenter {
        struct State: GraniteState {
            var name: String = ""
        }
        @Store var state: State
        @Event var rename: Rename.Reducer
    }

    var view: some View {
        TextField("Name", text: .constant(center.state.name))
    }
}
```

## The command and center

- **`@Command`** creates and retains the component's engine (a `GraniteCommand`). It routes
  events to reducers and delivers state changes back to SwiftUI on the main thread.
- **``GraniteCenter``** is a container. Granite discovers its `@Store`, `@Event`, and `@Notify`
  members once, when the command compiles, and caches that discovery.
- **``GraniteState``** is a `Codable`, `Equatable` value type. Because state is a value, reducers
  can mutate a copy freely; only the final value is published.

## Lifecycle events

Declare lifecycle-scoped reducers with `@Event(.onAppear)`, `@Event(.onDisappear)`, or
`@Event(.onTask)` to run logic when the component appears, disappears, or starts its task.

## Topics

### Building blocks

- ``GraniteComponent``
- ``GraniteCenter``
- ``GraniteState``
- ``Command``
- ``Store``
