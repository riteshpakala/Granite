# Persistence

Persist component and service state to disk safely, durably, and without blocking the UI.

## Overview

Any ``GraniteState`` is `Codable`, so a ``Store`` can persist it to disk. Opt in from the
`@Store` property wrapper:

```swift
struct Center: GraniteCenter {
    struct State: GraniteState {
        var draft: String = ""
    }

    // Persisted to disk, auto-saved on change, restored asynchronously on launch.
    @Store(persist: "compose.draft", autoSave: true) var state: State
}
```

## Storage guarantees

Granite's ``FilePersistence`` provides durable, crash-safe storage:

- **Atomic, binary writes.** State is encoded as a compact binary property list and written
  atomically, so a crash or force-quit mid-write can never leave a truncated file.
- **Versioned envelope.** State is wrapped in a versioned envelope (``PersistenceError`` surfaces
  problems), enabling future schema migrations. Files written by earlier, unversioned builds are
  still read transparently and upgraded on the next save.
- **Corrupt files are backed up, never clobbered.** If a file can't be decoded, it is renamed to
  a `.corrupt-<timestamp>` backup instead of being overwritten with defaults, so data is never
  silently destroyed.
- **Durable locations.** On macOS state lives in Application Support (which the OS does not purge)
  rather than Caches. On iOS/visionOS it lives in the documents directory. App Group containers
  are supported via ``PersistenceKind``.
- **Non-blocking.** Reads, decodes, and writes happen off the main thread on a serial queue.
  Restored state is applied back on the main thread; the main thread is never blocked on disk
  I/O, and `@Published` state is never mutated from a background thread.

## Auto-save

When `autoSave` is enabled, state changes are debounced and written automatically. When it is
disabled you can persist explicitly through the store's persistence API.

## Topics

### Persistence

- ``Store``
- ``FilePersistence``
- ``PersistenceKind``
- ``PersistenceError``
