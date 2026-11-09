# Events and Listeners

How a send reaches a reducer and its listeners, and why nothing has to be torn down.

## Overview

Every reducer sends on a ``GraniteEmitter``. Whoever receives from an emitter is held **weakly**,
so a subscription lasts exactly as long as its receiver. There are no tokens to store, no scopes
to cancel, and no `deinit` doing lifecycle work: releasing a command releases everything it wired
up, and taking a view off screen releases everything it listened with.

The emitter, its debounce and throttle, and the lock behind them live in Granite's
`Architecture/Core` folder, which depends only on Foundation and Dispatch.

## Who owns what

| Wiring | Owned by | Ends when |
| --- | --- | --- |
| A reducer's container receiving its sends | The command | The command is released |
| A component's `listen` handlers | SwiftUI, beside the view | The view goes, or disappears |
| A `listen` outside any `listeners` | The reducer listened to | The reducer is released, or a later `listen` takes its place |
| A hosted command's ``GraniteCommand/listen(_:_:)`` | The command | ``GraniteCommand/removeListeners(_:)``, or the command is released |

Nothing points back up any of these chains. A component's listener set is kept in SwiftUI state
beside the view, not in its command, so a handler that captures the component never keeps the
command alive: if `onDisappear` never runs, the view's release still takes everything with it.

## Listeners

```swift
extension SettingsComponent {
    var listeners: Void {
        account.center.update.listen(.broadcast("settings")) { payload in
            // runs on the main actor
        }
    }
}
```

A component's `listeners` run on appear, after any listeners an earlier appearance registered are
cleared, and before its `.onAppear` events fire. They are cleared on disappear.

- `.broadcast(name)` hears what any instance of the reducer type sends to `broadcast`.
- `.beam` hears what the reducer sends to `beam`; the last `listen(.beam)` made wins.
- `.bubble(name)` hears every send to the reducer itself, after its container has committed.

Listening again under the same reducer, kind and name replaces the earlier handler, whoever
registered it, and releases it at once.

## Threads

Handlers run on the **main actor**, because listeners update views. When the send is made on the
main thread the handler runs before the send returns, as it always has. When it is made from a
reducer's task or queue, the handler runs on the main queue's next turn, in the order the sends
were made. A handler whose listener was cleared before its turn came does not run.

Payloads cross that boundary, so ``GranitePayload`` is `Sendable`.

## Using an emitter directly

```swift
final class Uploader: Sendable {
    init(progress: GraniteEmitter<Double>) {
        progress.on(self) { uploader, value in
            uploader.show(value)
        }
    }
}
```

``GraniteEmitter/on(_:key:_:)`` hands the receiver back to the handler, so the handler need not
capture it. Reach what you need through the receiver: the handler itself is let go when a later
send or subscribe finds its receiver gone. A `key` names a subscription, so subscribing again
under it replaces the first. ``GraniteEmitter/off(_:key:)`` removes one early, and is never needed
for correctness.

## Debounce and throttle

`@Event(debounce:)` and `@Event(throttle:)` shape when a reducer runs. The timing is owned by the
reducer's container, so a value still waiting when the command goes is dropped with it. The
throttle matches Combine's `throttle(for:scheduler:latest:)`.

## Coming from signals

| Before | Now |
| --- | --- |
| `GraniteSignal`, `GraniteSignal.Payload` | ``GraniteEmitter`` |
| `signal += { … }` | `emitter.on(receiver) { receiver, value in … }` |
| `Prospect`, `Prospector`, `withScope` | Not needed: a receiver's lifetime is the subscription's |
| `GraniteCancellable` | Not needed; ``GraniteEmitter/off(_:key:)`` for early removal |
| `scope.cancel()` in `deinit` | Nothing |
| A custom event's `signal` for lifecycle | Granite fires the first container `compile(with:)` returned |
