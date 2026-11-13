# Run a package out of process

Run a package agent in a process of its own, for one call, and release it: installed from source, offered from a
shelf, and called over the `granite-agent/1` wire.

## Overview

An app that links a package runs its agents in its own process. An app can also run an agent it never linked:
the package is built into a *runner*, an executable whose `main` is ``AgentServer``, and each call starts the
runner, makes the one call over its stdin and stdout, and lets it exit. What the call made, a GPU device or a web
page, goes with the process. The messages are set out in the standard, `Schema/GraniteAgent.md`, beside JSON
Schema for each.

```
host                                   runner (one process, one call)
 │  spawn ─────────────────────────────▶ AgentServer.main()
 │  ◀───────────── {"hello": {"wire": "granite-agent/1"}}
 │  {"perform": {"word": "plate", …}} ─▶ the package's run, its host offered across the wire
 │  ◀───────────────────── {"note": …}   context.host.note
 │  ◀──────────────────── {"model": …}   context.host.model, answered by the host's model
 │  {"answer": …} ────────────────────▶
 │  ◀─────────────────── {"output": …}
 │  reaps it: "released · peak 412 MB · 1.8 s CPU in 2.4 s"
```

### Install a package from source

``AgentInstaller`` makes a runner of any package that carries a record, with no change to the package. It
fetches it, reads its manifest, writes a package of one executable that links it, builds it, asks the runner what
it carries, and installs it on a shelf with its record, `installation.json`:

```swift
let installer = AgentInstaller(folder: agents)
let installed = try await installer.install(AgentSource("https://github.com/riteshpakala/PlateAgent.git")) { step in
    print(step.stage)
}
installed.words   // ["plate"]
```

``AgentSource`` reads `url`, `url@revision`, or a folder. Installing a package again replaces it, and
`update(_:)` installs it from its source at its newest. A package whose word another installation carries is
refused.

### Install what a store delivers

A store's listing is ``AgentSource/delivered(id:)``: the installation keeps only the listing, and every install and
update asks the host's ``AgentDeliverer`` for an ``AgentDelivery``, an archive at an address that works for a few
minutes. The installer downloads it, checks its SHA-256 when the store gives one, undoes the transforms it names with
its ``AgentPayloadDecoder``s (telling the store which it has, so plain source names none), unpacks it inside the
install's work folder under the store's ``AgentDelivery/directory``, and builds it as from a folder. The source goes
with the work folder; ``AgentBuildFinishing`` runs on the executable before it is hashed and shelved:

```swift
let installer = AgentInstaller(folder: agents, deliverer: store)
try await installer.install(.delivered(id: listing.id))
```

### Offer a shelf's agents

``AgentShelf`` reads the records and offers each agent as a roster entry, without running a runner. A call
checks the executable's digest against the record first, and refuses one that changed:

```swift
let shelf = AgentShelf(folder: agents)
let roster = GraniteRoster(GraniteRoster.discovered().entries + shelf.entries())
let answer = try await roster.package("plate")?.perform(input, host: AgentHost(directory: project, model: model, note: show))
```

A host reads the shelf again when ``AgentShelf/stamp`` changes. Each call is an ``AgentProcess``, at most the
agent's `lanes` at once. The host hears what the process took as its last note (``AgentProcessCost``), and
failures arrive as ``AgentRemoteError``.

### Write a runner by hand

A runner is one file in an executable that links the packages:

```swift
import GraniteAgents

@main
enum Agent {
    static func main() async { await AgentServer.main() }
}
```

`agent --describe` prints what it carries, one `entries` line, and makes nothing. Anything can drive a runner:

```
echo '{"perform":{"word":"parrot","input":{"text":"hi"},"model":false}}' | agent
```

### Checklist

- The package has its record, and nothing it prints is meant for a host: notes go through `context.host.note`.
- A host fills `directory`, offers its model when it has one, and ends a process that does not answer.
- A host checks the digest before every launch, and installs again rather than running a changed executable.

## Topics

### The wire

- ``AgentWire``
- ``AgentJSON``
- ``AgentChannel``
- ``PipeChannel``
- ``AgentSchemaJSON``

### The runner

- ``AgentServer``

### The host

- ``AgentProcess``
- ``AgentProcessCost``
- ``AgentRemoteError``
- ``RemoteAgent``

### Installing

- ``AgentInstaller``
- ``AgentSource``
- ``AgentInstallation``
- ``AgentInstallError``
- ``AgentShelf``
