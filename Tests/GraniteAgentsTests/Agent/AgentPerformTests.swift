import Granite
import XCTest
@testable import GraniteAgents

/// The synchronous route: `perform` starts a run and returns once its lifecycle is committed after
/// its last frames, so the state read next is complete; and every way a run can end reaches the
/// waiter as what it is.
@MainActor
final class AgentPerformTests: XCTestCase {
    private func host() async -> GraniteCommand<CounterCenter> {
        let command = GraniteCommand<CounterCenter>.hosted()
        command.center.$supersede.attach { _ in 1 }
        command.center.$parallel.attach { _ in 10 }
        command.center.$declaredDrop.attach { _ in 1 }
        command.center.$merging.attach { _ in 1 }
        let reentrant = command.center.$reentrant
        reentrant.attach { _ in
            { do { _ = try await reentrant.perform(1); return "performed" } catch { return "\(error)" } }
        }
        return command
    }

    func testPerformReturnsAfterTheRunsLastFramesAreCommitted() async throws {
        let command = await host()
        let outcome = try await command.center.$supersede.perform(.init(count: 4))
        let state = command.center.state
        XCTAssertEqual(state.total, 10, "read right after the await, with no polling: 1 + 2 + 3 + 4")
        XCTAssertEqual(outcome.frames, 4, "frames are counted before they fold into commits")
        XCTAssertEqual(state.lifecycles.last, "\(outcome.run.raw) finished")
    }

    func testEveryWayARunEndsReachesItsWaiter() async throws {
        let command = await host()
        // Cancelled: the waiter fails with CancellationError.
        let cancelled = Task { try await command.center.$supersede.perform(.init(key: "c", count: 100, delay: 20_000_000)) }
        _ = await until { command.center.$supersede.isLive(key: "c") }
        command.center.$supersede.cancel(key: "c")
        do { _ = try await cancelled.value; XCTFail("a cancelled run returned") } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        // Superseded: a later send with the same key takes the run's place.
        let superseded = Task { try await command.center.$supersede.perform(.init(key: "s", count: 100, delay: 20_000_000)) }
        _ = await until { command.center.$supersede.isLive(key: "s") }
        command.center.supersede.send(.init(key: "s", count: 1))
        do { _ = try await superseded.value; XCTFail("a superseded run returned") } catch {
            guard case .superseded = error as? AgentRunError else { return XCTFail("\(error)") }
        }
        // Dropped, by the declaration: the agent's own default would have superseded.
        let first = Task { try await command.center.$declaredDrop.perform(.init(count: 3, delay: 20_000_000)) }
        _ = await until { command.center.$declaredDrop.isLive() }
        do { _ = try await command.center.$declaredDrop.perform(.init(count: 1)); XCTFail("a second perform under .drop ran") } catch {
            guard case .dropped = error as? AgentRunError else { return XCTFail("\(error)") }
        }
        _ = try await first.value
        // Merged: a second perform joins the live run and returns with it.
        let joined = Task { try await command.center.$merging.perform(.init(count: 3, delay: 20_000_000)) }
        _ = await until { command.center.$merging.isLive() }
        let second = try await command.center.$merging.perform(.init(count: 9))
        let firstOutcome = try await joined.value
        XCTAssertEqual(second.run, firstOutcome.run)
        // Ended before anyone opened a wait: unknown.
        do { _ = try await command.center.$merging.wait(run: firstOutcome.run); XCTFail("a wait on an ended run returned") } catch {
            guard case .unknownRun = error as? AgentRunError else { return XCTFail("\(error)") }
        }
        // Inside its own run: refused, never a deadlock.
        _ = try await command.center.$reentrant.perform(1)
        XCTAssertTrue(command.center.state.log.last?.hasPrefix("Reentrant-1 cannot wait on itself") ?? false, "\(command.center.state.log)")
    }

    func testAQueuedRunKeepsItsIdAndAPerformerOwnsWhatItStarted() async throws {
        let command = await host()
        let (a, b, c) = (command.center.$parallel.start(.init(key: "a", count: 2, delay: 30_000_000)),
                         command.center.$parallel.start(.init(key: "b", count: 2, delay: 30_000_000)),
                         command.center.$parallel.start(.init(key: "c", count: 2)))
        guard case .started = a, case .started = b, case .queued(let queued) = c else { return XCTFail("\(a) \(b) \(c)") }
        let outcome = try await command.center.$parallel.wait(run: queued)
        XCTAssertEqual(outcome.run, queued, "the id given when it queued is the id it ran under")
        XCTAssertTrue(command.center.state.lifecycles.contains("\(queued.raw) started"))
        // A cancelled performer cancels the run it started.
        let performer = Task { try await command.center.$supersede.perform(.init(key: "p", count: 100, delay: 20_000_000)) }
        _ = await until { command.center.$supersede.isLive(key: "p") }
        performer.cancel()
        // The commit, not `isLive`: the run leaves `runs` a moment before its `.cancelled` lands on main.
        let stopped = await until { command.center.state.lifecycles.contains { $0.hasSuffix("cancelled") } }
        XCTAssertTrue(stopped, "the run the cancelled performer started was cancelled")
        XCTAssertFalse(command.center.$supersede.isLive(key: "p"))
    }

    func testWaitPrefixReturnsWhenEveryRunUnderItHasEnded() async {
        let command = await host()
        command.center.parallel.send(.init(key: "s/a", count: 2, delay: 20_000_000))
        command.center.parallel.send(.init(key: "s/b", count: 2, delay: 20_000_000))
        command.center.parallel.send(.init(key: "s/c", count: 2))
        _ = await until { command.center.$parallel.isLive(key: "s/a") }
        await command.center.$parallel.wait(prefix: "s/")
        XCTAssertTrue(command.center.$parallel.liveKeys().filter { $0.hasPrefix("s/") }.isEmpty)
        XCTAssertEqual(command.center.state.total, 3 * (10 + 20), "every run under the prefix ran to its end")
    }
}
