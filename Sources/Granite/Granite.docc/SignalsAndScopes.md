# Signals and Scopes

Send events with signals, and let scopes decide how long each subscription lives.

## Overview

A signal (`GraniteSignal`, or `GraniteSignal.Payload<Value>` when it carries a value) delivers
each `send` to its observers synchronously, on the sending thread. Every subscription belongs to
a **scope** (`Prospect`). When a scope ends, every subscription stored in it ends, and so does
every scope beneath it, in the manner of a responder chain.

Granite creates the scopes for you: one per command, one per reducer container, one per listener
set, one per relay and one per pushed navigation destination. Most code never names a scope. It
observes a signal, and the subscription lands in whichever scope is current.

Signals, cancellation and scopes live in Granite's `Architecture/Core` folder, which depends
only on Foundation and Dispatch. It imports neither Combine nor SwiftUI, as a first step toward
an event backbone that also builds on Linux.

## Observing a signal

```swift
let saved = GraniteSignal.Payload<Document>()

saved += { document in
    print("saved", document.title)
}

saved.send(document)
```

`+=` and `observe(handler:)` return a `GraniteCancellable`. Cancel it to stop early. Dropping
it does **not** end the subscription: the current scope owns it. That is what makes the
discarded `+=` results in a component's listeners safe.

To observe into a particular scope, pass it explicitly:

```swift
let token = saved.observe(in: scope) { document in … }
```

With no current scope and no explicit one, a subscription lasts until it is cancelled or the
signal is released.

## Listeners

A component's `listeners` run in a fresh scope each time it appears, and that scope ends when it
disappears. Anything observed there is torn down with it, however many times the component
appears and disappears.

```swift
extension SettingsComponent {
    var listeners: Void {
        config.center.$setAppearance.listen(.broadcast("settings")) { _ in
            // react to the service
        }
    }
}
```

## The view tree is the chain

A component's command is created lazily by SwiftUI, outside any Granite call. To place it in the
tree, each component publishes its command's scope in the SwiftUI environment, and `@Command`
attaches its own command beneath whatever scope it finds there. A child component's command
therefore sits under its parent's. A pushed navigation destination gets a scope of its own, and
popping the screen ends every command built under it.

Relays are app-lifetime singletons, so their scopes are always top-level: a relay never ends
because the view that first touched it went away.

## Your own scopes

```swift
final class Uploader {
    private let scope = Prospect(label: "uploader", type: .custom, parent: nil)

    init(progress: GraniteSignal.Payload<Double>) {
        scope.withScope {
            progress += { value in print(value) }
        }
    }

    deinit { scope.cancel() }
}
```

- **Keep the scope.** Whoever creates a scope holds it. A parent holds its children weakly, so a
  child scope nobody keeps ends straight away.
- **`withScope` binds the current scope** for the duration of its closure. Signals observed and
  scopes created inside it land beneath it.
- **`cancel()` is final.** A token stored into an ended scope is cancelled immediately.
- **Releasing a scope ends it**, but owners should still call `cancel()` in `deinit` so the
  teardown happens at a known point.

## Threads and tasks

The current scope is a task-local value. Each task (or, outside any task, each thread) sees only
the binding made by its own enclosing `withScope`. Views built concurrently never contend for it
or attach to one another's scopes.

`Task { }` inherits the current scope. `Task.detached` and `DispatchQueue.async` do not: capture
the scope and bind it again on the other side, or observe with `observe(in:)`.

## Debounce and throttle

```swift
query.debounced(0.3, on: .main) += { text in search(text) }
taps.throttled(0.5, on: .main) += { _ in refresh() }
```

`debounced(_:on:)` and `throttled(_:on:latest:)` return a copy of the signal whose observers
receive values with that timing, on the given queue. Sending is unaffected, and other observers
still receive every value. The throttle matches Combine's `throttle(for:scheduler:latest:)`.

## Combine

On Apple platforms, `publisher` exposes any signal as a Combine publisher, honouring demand and
the copy's debounce or throttle. `GraniteCancellable` conforms to `Cancellable`, so a token can go
into a `Set<AnyCancellable>`. In the other direction, `AnyCancellable.store(in:)` hands a Combine
subscription to a scope.

## Diagnostics

`Prospector.dump()` prints the live scope tree, and `Prospector.nodeCount` counts it. Both walk
the tree from the top-level scopes, and are meant for debugging rather than hot paths.
