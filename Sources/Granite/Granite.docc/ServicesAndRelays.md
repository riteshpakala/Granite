# Services & Relays

Share state and logic across components with services, exposed to views through relays.

## Overview

A ``GraniteService`` is like a component's center without a view: it owns state and reducers, but
it is shared. Components reach a service through a ``Relay`` (`@Relay`), a SwiftUI
`DynamicProperty` that resolves the shared service instance and propagates its changes into the
view.

```swift
struct Session: GraniteService {
    @Service var center: Center

    struct Center: GraniteCenter {
        struct State: GraniteState {
            var user: String? = nil
        }
        @Store var state: State
        @Event var signIn: SignIn.Reducer
    }
}

struct Toolbar: GraniteComponent {
    @Command var center: Center
    @Relay var session: Session

    var view: some View {
        Text(session.center.state.user ?? "Signed out")
    }
}
```

## Sharing semantics

A relay resolves a single shared instance per service type, so every view that references the
same service observes the same state. Because a shared service is expected to outlive individual
views, its backing instance is retained for the app's lifetime by design; if you own a genuinely
scoped service you can release it explicitly.

## Observing specific values

Use `observe(_:handler:)` on a relay to react to a specific key path of the service's state
without re-rendering on every change.

## Topics

### Services

- ``GraniteService``
- ``Service``
- ``Relay``
