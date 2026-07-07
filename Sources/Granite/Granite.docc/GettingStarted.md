# Getting Started

Build your first Granite component, wire up a reducer, and render it in SwiftUI.

## Overview

A Granite feature is made of three pieces:

1. A ``GraniteComponent`` — a SwiftUI `View` that hosts a `@Command`.
2. A ``GraniteCenter`` — declares the component's `@Store` state and its `@Event` reducers.
3. One or more ``GraniteReducer`` types — pure functions that mutate state.

### 1. Declare the component and its center

```swift
import Granite
import SwiftUI

struct Counter: GraniteComponent {
    @Command var center: Center

    struct Center: GraniteCenter {
        struct State: GraniteState {
            var value: Int = 0
        }

        @Store var state: State

        @Event var increment: Increment.Reducer
        @Event var reset: Reset.Reducer
    }
}
```

`@Command` owns the component's engine and exposes `center`, through which the view reads state
and dispatches events. `@Store` wraps the state value type; `@Event` primes a reducer.

### 2. Write reducers

A reducer mutates `inout` state. Each reducer's `Center` associated type points back at the
center it belongs to.

```swift
struct Increment: GraniteReducer {
    typealias Center = Counter.Center
    func reduce(state: inout Center.State) {
        state.value += 1
    }
}

struct Reset: GraniteReducer {
    typealias Center = Counter.Center
    func reduce(state: inout Center.State) {
        state.value = 0
    }
}
```

### 3. Render and dispatch

```swift
extension Counter: View {
    var view: some View {
        VStack {
            Text("Count: \(center.state.value)")
            Button("Increment") { center.increment.send() }
            Button("Reset") { center.reset.send() }
        }
    }
}
```

Calling `center.increment.send()` runs the `Increment` reducer, which mutates state; Granite
publishes the change to SwiftUI on the main thread and the view re-renders.

## Where to go next

- Learn how reducers chain and run side effects in <doc:ReducersAndEvents>.
- Share state across components with <doc:ServicesAndRelays>.
- Persist state to disk with <doc:Persistence>.
