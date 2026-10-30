import Granite
import XCTest
@testable import GraniteAgents

/// An agent spawned from a reducer, the two ways: a work reducer whose effect performs the run and
/// then writes through `Set` (the run's frames are in the state before `.done` lands), and one whose
/// effect only sends (the reducer's scope ends before the frames arrive). On a relay-hosted service,
/// as the app and the CLI host theirs, so `Live.service` resolves the same instance.

struct JobCounter: GraniteAgent {
    struct Input: Sendable { var key: String; var count: Int; var delay: UInt64 = 0 }
    typealias Center = JobService.Center
    typealias Event = Int
    typealias Compute = Int

    static func key(_ input: Input) -> String { input.key }

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<Int, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for i in 1...max(1, input.count) {
                    if input.delay > 0 { try? await Task.sleep(nanoseconds: input.delay) }
                    if Task.isCancelled || context.isCancelled() { break }
                    continuation.yield(i * context.compute)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func reduce(state: inout JobService.Center.State, event: Int, run: AgentRunID) { state.total += event }

    func reduce(state: inout JobService.Center.State, lifecycle: AgentLifecycle, run: AgentRunID) {
        if lifecycle == .finished, run.key == "spawned" { state.spawnedFinished = true }
    }
}

struct JobService: GraniteService {
    @Service(.online) var center: Center
    init() {}
    static let tickets = GraniteTickets<Int>()

    func set(_ kind: Set.Meta.Kind) {
        let service = self
        onMain { service.center.set.send(Set.Meta(kind: kind)) }
    }

    /// The sync route: answers with the frames the run streamed, once `.done` is on its way.
    func run(key: String, count: Int, delay: UInt64 = 0) async throws -> Int {
        let ticket = await Self.tickets.open()
        let service = self
        onMain { service.center.run.send(Run.Meta(ticket: ticket.id, key: key, count: count, delay: delay)) }
        return try await Self.tickets.wait(ticket.id)
    }

    /// The async route: returns at once.
    func spawn(count: Int, delay: UInt64) {
        let service = self
        onMain { service.center.spawn.send(Spawn.Meta(count: count, delay: delay)) }
    }
}

extension JobService: @unchecked Sendable {}

extension JobService {
    struct Center: GraniteCenter {
        struct State: GraniteState {
            var phase = "idle"
            var total = 0
            var totalAtDone: Int?
            var frames: Int?
            var error: String?
            var spawnedFinished = false
        }
        @Event var set: Set.Reducer
        @Event var run: Run.Reducer
        @Event var spawn: Spawn.Reducer
        @Agent var counter: JobCounter.Agent
        @Store var state: State
    }

    struct Set: GraniteReducer {
        typealias Center = JobService.Center
        struct Meta: GranitePayload {
            enum Kind: Sendable { case reset, done(frames: Int), failed(String) }
            var kind: Kind
        }
        @Payload var meta: Meta?
        func reduce(state: inout Center.State) {
            guard let meta else { return }
            switch meta.kind {
            case .reset: state = .init()
            case .done(let frames): state.phase = "done"; state.totalAtDone = state.total; state.frames = frames
            case .failed(let message): state.phase = "failed"; state.error = message
            }
        }
        var thread: DispatchQueue? { .main }
    }

    /// Marks the start; the effect owns the run's whole scope: it awaits the agent, then writes.
    struct Run: GraniteReducer {
        typealias Center = JobService.Center
        struct Meta: GranitePayload { let ticket: UUID; let key: String; let count: Int; let delay: UInt64 }
        @Payload var meta: Meta?
        func reduce(state: inout Center.State) {
            guard meta != nil else { return }
            state.phase = "running"
            state.total = 0
            state.totalAtDone = nil
        }
        func effect(state: Center.State) -> GraniteEffect {
            guard let meta else { return .none }
            let jobs = Live.service(JobService.self)
            let counter = jobs.center.$counter
            return .run {
                do {
                    let outcome = try await counter.perform(.init(key: meta.key, count: meta.count, delay: meta.delay))
                    jobs.set(.done(frames: outcome.frames))
                    await JobService.tickets.resolve(meta.ticket, with: outcome.frames)
                } catch {
                    jobs.set(.failed("\(error)"))
                    await JobService.tickets.fail(meta.ticket, error)
                }
            }
        }
        var thread: DispatchQueue? { .main }
    }

    /// Marks the start; the effect sends and ends. The agent's own reduce writes the rest.
    struct Spawn: GraniteReducer {
        typealias Center = JobService.Center
        struct Meta: GranitePayload { let count: Int; let delay: UInt64 }
        @Payload var meta: Meta?
        func reduce(state: inout Center.State) {
            guard meta != nil else { return }
            state.phase = "spawned"
        }
        func effect(state: Center.State) -> GraniteEffect {
            guard let meta else { return .none }
            let counter = Live.service(JobService.self).center.$counter
            return .run { counter.send(.init(key: "spawned", count: meta.count, delay: meta.delay)) }
        }
        var thread: DispatchQueue? { .main }
    }
}

@MainActor final class JobRoot {
    static let shared = JobRoot()
    @Relay(.silence) var jobs: JobService
    private init() { jobs.center.$counter.attach { _ in 1 } }
}

@MainActor
final class ReducerSpawnTests: XCTestCase {
    private func jobs() async -> JobService {
        let jobs = JobRoot.shared.jobs
        jobs.set(.reset)
        _ = await until { jobs.center.state.phase == "idle" && jobs.center.state.total == 0 }
        return jobs
    }

    func testAReducerThatPerformsWritesDoneAfterTheRunsFrames() async throws {
        let jobs = await jobs()
        let frames = try await jobs.run(key: "sync", count: 4, delay: 5_000_000)
        XCTAssertEqual(frames, 4)
        let done = await until { jobs.center.state.phase == "done" }
        XCTAssertTrue(done)
        XCTAssertEqual(jobs.center.state.totalAtDone, 10, "every frame was in the state when the reducer's effect wrote .done")
    }

    func testAReducerThatSpawnsEndsBeforeTheFramesLand() async throws {
        let jobs = await jobs()
        jobs.spawn(count: 4, delay: 20_000_000)
        let marked = await until { jobs.center.state.phase == "spawned" }
        XCTAssertTrue(marked)
        XCTAssertLessThan(jobs.center.state.total, 10, "the reducer's scope ended; the run is still streaming")
        let finished = await until { jobs.center.state.spawnedFinished }
        XCTAssertTrue(finished)
        XCTAssertEqual(jobs.center.state.total, 10, "the agent's own reduce wrote every frame")
    }

    func testACancelledRunFailsTheReducersTicket() async throws {
        let jobs = await jobs()
        let call = Task { try await jobs.run(key: "long", count: 100, delay: 20_000_000) }
        _ = await until { jobs.center.$counter.isLive(key: "long") }
        jobs.center.$counter.cancel(key: "long")
        do { _ = try await call.value; XCTFail("a cancelled run answered") } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        let failed = await until { jobs.center.state.phase == "failed" }
        XCTAssertTrue(failed)
    }
}
