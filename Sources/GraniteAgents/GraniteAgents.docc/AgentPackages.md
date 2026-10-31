# Agent packages

Ship an agent as a Swift package of its own, and let any app that links it find it.

## Overview

An agent package is a Swift package that depends on `GraniteAgents` and declares one
``GraniteAgentPackage``: a word, a `Codable` input and output, the compute it makes for itself, and a
run that streams. The package declares no center, state or service. Granite hosts the run on a center
of its own (``AgentPackageCenter``), and an app runs it by its word, JSON in and JSON out.

The package also places a **record** in its binary: two lines that put the address of a function in the
`__DATA_CONST,__granite` section. An app that links the package calls
``GraniteRoster/discovered()`` and finds it there. Nothing in the app names the package: adding one is
adding a dependency, and removing it is removing the dependency.

### Make the package

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MarbleAgent",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MarbleAgent", targets: ["MarbleAgent"])],
    dependencies: [.package(url: "https://github.com/riteshpakala/Granite.git", branch: "main")],
    targets: [
        .target(name: "MarbleAgent", dependencies: [.product(name: "GraniteAgents", package: "Granite")]),
        .testTarget(name: "MarbleAgentTests", dependencies: ["MarbleAgent"]),
    ]
)
```

### Declare the agent

```swift
public struct MarbleAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable {
        public var path: String
        public var filter: MarbleFilter?      // optional: read with decodeIfPresent
        public var intensity: Double?
        public var directory: String?         // the host fills it, and does not show it to a model
    }
    public typealias Event = MarbleFrame
    public typealias Output = MarbleResult
    public typealias Compute = MarbleCompute

    public static let word = "marble"
    public static let summary = "filters a photo on the GPU and writes the result beside it."
    public static let fields = ["path": "the photo, relative to the project", "filter": "the look; sepia when left out"]

    public static func compute() async throws -> MarbleCompute { try MarbleCompute() }   // on the first call
    public static func output(from events: [MarbleFrame]) -> MarbleResult? { events.last?.result }

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<MarbleFrame, Error> { … }
}
```

- `word` is how an app calls it: lowercase, one word, unique among what the app links.
- `fields` are the lines said beside the input's fields when an app shows the schema to a model.
- `compute()` runs once, on the first call, never when the app starts: a package that holds a GPU
  pipeline or a model costs nothing until it is asked for. `Compute == Void` needs none.
- `output(from:)` reads the answer off the events the run streamed. When `Output == Event`, it is the
  last event.
- `lanes` says how many calls run at once (two unless the package says otherwise); every call is a run
  of its own, so two calls never take each other's place.

### Write the record

```swift
@used @section("__DATA_CONST,__granite")
let marbleRecord: GraniteRoster.Record = { GraniteRoster.record(MarbleAgent.self) }
```

`@used` keeps the record through dead stripping; `@section` puts it beside every other record in the
image; ``GraniteRoster/discovered()`` calls each one and keeps one entry per word. It needs a Swift
compiler with the `@used` and `@section` attributes (Swift 6.4 has them).

### What the schema is

An app shows a model what a package takes as JSON Schema, read off the input's own decoding
(``GraniteSchema/of(_:)``): a field read with `decode` is required, one read with `decodeIfPresent` is
not, and an enum of `String` raw values that lists its cases is a choice of those values. So:

- make a field optional when a call may leave it out (a default value in a synthesized `init(from:)`
  still decodes as required);
- make an enum `CaseIterable` for its cases to reach the model;
- a field named `directory` is the host's: it fills it with the folder it works in.

An output that wrote files says where in `path` or `paths`, so a host can tell what changed.

### Test it

The record works in the test binary too, so a test can find the package the way an app will:

```swift
func testTheRecordIsFound() throws {
    XCTAssertNotNil(GraniteRoster.discovered().package("marble"))
}

func testACallFilters() async throws {
    let marble = AnyAgentPackage(MarbleAgent.self)
    let answer = try await marble.perform(Data(#"{"path": "/tmp/photo.png"}"#.utf8))
    let result = try JSONDecoder().decode(MarbleResult.self, from: answer)
    …
}
```

### Run it from an app

Add the package to a target the app links, and import it nowhere. Then:

```swift
let roster = GraniteRoster.discovered()                       // once; the app keeps it
for package in roster.packages {
    tools.append(ToolFor(package.word, schema: package.schema.jsonSchema(notes: package.fields)))
}
let answer = try await roster.package("marble")?.perform(json)   // the run, on its own center
```

``AnyAgentPackage/perform(_:)`` decodes the input, hosts the run on the package's center, waits for it,
and encodes what `output(from:)` read. Cancelling the task awaiting it cancels the run.

### Ship a worker instead

A package can also ship a worker an app spawns beside its own agent: a model given a task, a set of the
app's tools by name, a budget and words of its own. A ``GraniteWorkerSpec`` says those without the app's
types, and its record is ``GraniteRoster/record(worker:)``:

```swift
public enum Scout: GraniteWorkerSpec {
    public static let word = "scout"
    public static let summary = "maps a folder it is pointed at and says what each file is for."
}

@used @section("__DATA_CONST,__granite")
let scoutRecord: GraniteRoster.Record = { GraniteRoster.record(worker: Scout.self) }
```

The app makes it one of its worker kinds; what a worker is, past these words, is the app's.

### Checklist

- The package depends on `GraniteAgents` and declares one ``GraniteAgentPackage``, or a
  ``GraniteWorkerSpec``.
- `Input` is `Codable`; optional fields are optional; enums list their cases.
- Compute is made in `compute()`, on the first call; the run touches no state.
- The record is two lines, and a test finds it with ``GraniteRoster/discovered()``.
- The app links the package from a target, imports it nowhere, and runs it by its word.
