import Granite
import XCTest
@testable import GraniteAgents

/// `@Agent` end to end on a hosted center, without SwiftUI: a run's frames are reduced on main and
/// folded into commits, the concurrency policies hold, a superseded run's late frames are dropped,
/// children are announced through the parent, and `.onTask` starts a run.

protocol CounterPolicy: Sendable { static var concurrency: AgentConcurrency { get } }
enum Supersede: CounterPolicy { static let concurrency = AgentConcurrency.supersede }
enum Drop: CounterPolicy { static let concurrency = AgentConcurrency.drop }
enum Parallel: CounterPolicy { static let concurrency = AgentConcurrency.parallel(max: 2) }
enum Merging: CounterPolicy { static let concurrency = AgentConcurrency.merge }

/// Counts up to `count`, `delay` apart, multiplied by its compute.
struct Counter<Policy: CounterPolicy>: GraniteAgent {
    struct Input: Sendable { var key = AgentRunID.defaultKey; var count: Int; var delay: UInt64 = 0 }
    typealias Center = CounterCenter
    typealias Event = Int
    typealias Compute = Int

    static var concurrency: AgentConcurrency { Policy.concurrency }
    static func key(_ input: Input) -> String { input.key }

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<Int, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for i in 1...max(1, input.count) {
                    if input.delay > 0 { try await Task.sleep(nanoseconds: input.delay) }
                    if Task.isCancelled || context.isCancelled() { break }
                    continuation.yield(i * context.compute)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func reduce(state: inout CounterCenter.State, event: Int, run: AgentRunID) {
        state.total += event
        state.events += 1
        state.commits.append(run.raw)
        if !Thread.isMainThread { state.reducedOffMain += 1 }
    }

    func reduce(state: inout CounterCenter.State, lifecycle: AgentLifecycle, run: AgentRunID) {
        state.lifecycles.append("\(run.raw) \(lifecycle)")
        if !Thread.isMainThread { state.reducedOffMain += 1 }
    }

    static func coalesce(_ a: Int, _ b: Int) -> Int? { a + b }
}

/// A parent that spawns one `Counter` child and reports its frames as text.
struct Parent: GraniteAgent {
    typealias Center = CounterCenter
    typealias Input = Int
    typealias Event = String
    typealias Compute = Int

    func run(_ input: Int, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield("parent begins")
                let child = context.spawn(Counter<Supersede>(), input: .init(count: input), compute: context.compute,
                                          id: "w1", kind: "counter", prompt: "count to \(input)") { frame -> String? in
                    switch frame {
                    case .started(let run, let kind, _): return "spawned \(run.raw) \(kind)"
                    case .event(let run, let value): return "\(run.raw) → \(value)"
                    case .finished(let run, let outcome): return "finished \(run.raw) \(outcome)"
                    }
                }
                for await line in child { continuation.yield(line) }
                continuation.yield("parent ends")
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func reduce(state: inout CounterCenter.State, event: String, run: AgentRunID) { state.log.append(event) }
}

/// Starts on the host's task with a fixed input.
struct Watcher: GraniteAgent {
    typealias Center = CounterCenter
    typealias Input = Int
    typealias Event = Int
    typealias Compute = Int
    static var lifecycleInput: Int? { 3 }
    func run(_ input: Int, context: Context) -> AsyncThrowingStream<Int, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(input * context.compute)
            continuation.finish()
        }
    }
    func reduce(state: inout CounterCenter.State, event: Int, run: AgentRunID) { state.watched += event }
}

/// Computes with a closure, so a test can make a run call back into its own executable.
struct Reentrant: GraniteAgent {
    typealias Center = CounterCenter
    typealias Input = Int
    typealias Event = String
    typealias Compute = @Sendable () async -> String
    func run(_ input: Int, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(await context.compute())
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    func reduce(state: inout CounterCenter.State, event: String, run: AgentRunID) { state.log.append(event) }
}

struct CounterCenter: GraniteCenter {
    struct State: GraniteState {
        var total = 0
        var events = 0
        var commits: [String] = []
        var lifecycles: [String] = []
        var log: [String] = []
        var watched = 0
        var reducedOffMain = 0
    }

    @Agent var supersede: Counter<Supersede>.Agent
    @Agent var drop: Counter<Drop>.Agent
    @Agent var parallel: Counter<Parallel>.Agent
    @Agent var parent: Parent.Agent
    @Agent(.onTask) var watcher: Watcher.Agent
    /// The declaration says drop; the agent's own default is supersede.
    @Agent(.drop) var declaredDrop: Counter<Supersede>.Agent
    @Agent var merging: Counter<Merging>.Agent
    @Agent var reentrant: Reentrant.Agent
    @Store var state: State
}

@MainActor
final class AgentExecutableTests: XCTestCase {
    private func host() async -> GraniteCommand<CounterCenter> {
        let command = GraniteCommand<CounterCenter>.hosted()
        command.center.$supersede.attach { _ in 1 }
        command.center.$drop.attach { _ in 1 }
        command.center.$parallel.attach { _ in 10 }
        command.center.$parent.attach { _ in 2 }
        command.center.$watcher.attach { _ in 5 }
        return command
    }

    func testARunsFramesAreReducedOnMainIntoItsCommits() async {
        let command = await host()
        command.center.supersede.send(.init(count: 4))
        let settled1 = await until { command.center.state.lifecycles.contains { $0.hasSuffix("finished") } }
        XCTAssertTrue(settled1)
        let state = command.center.state
        XCTAssertEqual(state.total, 10, "1 + 2 + 3 + 4")
        XCTAssertEqual(state.lifecycles.first, "Counter<Supersede>-1 started")
        XCTAssertGreaterThanOrEqual(state.events, 1, "frames fold into commits; at least one commit carried them")
        XCTAssertEqual(state.reducedOffMain, 0, "every frame and lifecycle is reduced on main")
    }

    func testASupersededRunsLateFramesAreDropped() async {
        let command = await host()
        command.center.supersede.send(.init(count: 50, delay: 20_000_000))
        try? await Task.sleep(nanoseconds: 50_000_000)
        command.center.supersede.send(.init(count: 2))
        let settled2 = await until { command.center.state.lifecycles.contains("Counter<Supersede>-2 finished") }
        XCTAssertTrue(settled2)
        let state = command.center.state
        XCTAssertTrue(state.lifecycles.contains("Counter<Supersede>-1 cancelled"))
        XCTAssertFalse(state.commits.contains("Counter<Supersede>-1") && state.commits.last == "Counter<Supersede>-1",
                       "nothing of the first run lands after the second began")
        XCTAssertEqual(state.commits.filter { $0 == "Counter<Supersede>-2" }.isEmpty, false)
    }

    func testDropIgnoresASendWhileLive() async {
        let command = await host()
        command.center.drop.send(.init(count: 3, delay: 20_000_000))
        try? await Task.sleep(nanoseconds: 10_000_000)
        command.center.drop.send(.init(count: 100))
        let settled3 = await until { command.center.state.lifecycles.contains("Counter<Drop>-1 finished") }
        XCTAssertTrue(settled3)
        XCTAssertEqual(command.center.state.total, 6, "only the first run counted")
        XCTAssertFalse(command.center.state.lifecycles.contains { $0.hasPrefix("Counter<Drop>-2") })
    }

    func testParallelRunsBesideEachOtherUpToMaxThenQueues() async {
        let command = await host()
        command.center.parallel.send(.init(key: "a", count: 2, delay: 30_000_000))
        command.center.parallel.send(.init(key: "b", count: 2, delay: 30_000_000))
        command.center.parallel.send(.init(key: "c", count: 2))
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(command.center.$parallel.isLive(key: "a"))
        XCTAssertTrue(command.center.$parallel.isLive(key: "b"))
        XCTAssertFalse(command.center.$parallel.isLive(key: "c"), "the third waits for a lane")
        let settled4 = await until { command.center.state.lifecycles.filter { $0.hasSuffix("finished") }.count == 3 }
        XCTAssertTrue(settled4)
        XCTAssertEqual(command.center.state.total, 3 * (10 + 20))
    }

    func testCancelCommitsCancelledAtOnce() async {
        let command = await host()
        command.center.supersede.send(.init(count: 100, delay: 20_000_000))
        try? await Task.sleep(nanoseconds: 30_000_000)
        command.center.$supersede.cancel()
        XCTAssertTrue(command.center.state.lifecycles.contains("Counter<Supersede>-1 cancelled"))
        XCTAssertFalse(command.center.$supersede.isLive())
    }

    func testTapsSeeEveryEventBeforeTheReduceAndEndWithTheRun() async {
        let command = await host()
        let tap = command.center.$supersede.events()
        command.center.supersede.send(.init(count: 3))
        var seen: [Int] = []
        for await event in tap { seen.append(event) }
        XCTAssertEqual(seen.reduce(0, +), 6, "every frame reached the tap, folded or not")
        let settled5 = await until { command.center.state.total == 6 }
        XCTAssertTrue(settled5)
    }

    func testAChildIsAnnouncedThroughItsParent() async {
        let command = await host()
        command.center.parent.send(3)
        let settled6 = await until { command.center.state.log.last == "parent ends" }
        XCTAssertTrue(settled6)
        let log = command.center.state.log
        XCTAssertEqual(log.first, "parent begins")
        XCTAssertEqual(log[1], "spawned w1 counter", "announced before anything else of it")
        XCTAssertTrue(log.contains("w1 → 2") && log.contains("w1 → 6"), "\(log)")
        XCTAssertTrue(log.contains("finished w1 finished"))
    }

    func testOnTaskStartsARunWithTheLifecycleInput() async {
        let command = await host()
        command.performTasks()
        let settled7 = await until { command.center.state.watched == 15 }
        XCTAssertTrue(settled7)
    }

    func testASendWithoutComputeFails() async {
        let command = GraniteCommand<CounterCenter>.hosted()
        command.center.supersede.send(.init(count: 1))
        let settled8 = await until { command.center.state.lifecycles.contains { $0.contains("failed") } }
        XCTAssertTrue(settled8)
        XCTAssertTrue(command.center.state.lifecycles.last?.contains("no compute attached") ?? false)
    }
}
