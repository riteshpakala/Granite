# Concurrency

How Granite delivers state safely under Swift 6 strict concurrency.

## Overview

Granite builds under **Swift 6 language mode** with complete strict-concurrency checking. The
architecture separates *where work runs* from *where state is observed*:

- **Reducers may run off the main thread** — synchronous reducers run inline, while `.task` and
  `.streamingTask` reducers run on structured-concurrency `Task`s at a chosen priority.
- **State is always delivered to SwiftUI on the main thread.** UI-facing `objectWillChange`
  notifications are throttled and scheduled on the main dispatch queue, so SwiftUI never receives
  a background publish — and delivery is no longer stalled during touch tracking.

## Serial execution

Each command and each reducer container owns a single serial dispatch queue, created once, so
state commits and cross-reducer notifications are serialized. (Earlier versions allocated a fresh
queue on every access, which provided no ordering guarantee.)

## Thread-safe registries

The process-wide registries that back signals, shared objects, and persistence queues are
lock-guarded and `Sendable`, so they can be touched safely from reducer queues and the main
thread alike.

## Cancellation

`.task` and `.streamingTask` reducers are cancelled when a newer send supersedes them. Streaming
reducers drop frames once cancelled, so a stale update can't overwrite fresher state. Reducer
bodies that do long-running async work should check `Task.isCancelled` to cooperate.

## Guidance

- Keep ``GraniteState`` a value type of `Sendable` fields.
- Prefer ``GraniteEffect/run(_:)`` for async side effects; its closure is `@Sendable`.
- Do UI work (navigation, windowing) on the main actor — those subsystems are `@MainActor`
  isolated.
