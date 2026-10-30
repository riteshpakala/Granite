import XCTest
@testable import GraniteAgents

/// The scaffolding every service builds on: tickets keep a reply that lands early and drop one that
/// lands late, a lane runs in arrival order, registries keep one value a key and forget by prefix,
/// and a cancel that beats its register leaves a tombstone.
final class GraniteScaffoldingTests: XCTestCase {
    func testATicketKeepsAnEarlyReplyAndDropsALateOne() async throws {
        let tickets = GraniteTickets<Int>()
        let early = await tickets.open()
        await tickets.resolve(early.id, with: 7)
        let value = try await tickets.wait(early.id)
        XCTAssertEqual(value, 7, "resolved before the wait, kept")

        let refused = await tickets.open()
        await tickets.fail(refused.id, TicketError.refused("busy"))
        do { _ = try await tickets.wait(refused.id); XCTFail("a failed ticket returned") } catch {
            XCTAssertEqual(error as? TicketError, .refused("busy"))
        }

        let abandoned = await tickets.open()
        let waiter = Task { try await tickets.wait(abandoned.id) }
        try await Task.sleep(nanoseconds: 10_000_000)
        waiter.cancel()
        do { _ = try await waiter.value; XCTFail("a cancelled wait returned") } catch { XCTAssertTrue(error is CancellationError) }
        await tickets.resolve(abandoned.id, with: 1)
        let pending = await tickets.pending
        XCTAssertEqual(pending, 0, "the late reply is dropped, nothing is left open")
    }

    /// An effect writes through `onMain`, then resolves: the waiter wakes to the write, not before it.
    func testASettleWaitsForWhatMainWasSentBeforeIt() async throws {
        let tickets = GraniteTickets<Int>()
        let ticket = await tickets.open()
        let written = Box()
        Task.detached {
            DispatchQueue.main.async { written.value = true }
            await tickets.resolve(ticket.id, with: 1)
        }
        _ = try await tickets.wait(ticket.id)
        XCTAssertTrue(written.value, "the main queue ran the write before the waiter woke")
    }

    private final class Box: @unchecked Sendable { var value = false }

    func testALaneRunsBodiesInArrivalOrder() async throws {
        actor Log { var order: [Int] = []; func add(_ n: Int) { order.append(n) } }
        let lane = GraniteLane(), log = Log()
        let first = Task { try await lane.run { try await Task.sleep(nanoseconds: 30_000_000); await log.add(1) } }
        try await Task.sleep(nanoseconds: 5_000_000)
        let second = Task { try await lane.run { await log.add(2) } }
        _ = try await (first.value, second.value)
        let order = await log.order
        XCTAssertEqual(order, [1, 2], "the second waited for the slower first")
    }

    func testRegistriesKeepOneValueAKeyAndAnEarlyCancelIsATombstone() {
        let registry = TransientRegistry<Int>()
        var made = 0
        XCTAssertEqual(registry.value("a/1") { made += 1; return 1 }, 1)
        XCTAssertEqual(registry.value("a/1") { made += 1; return 2 }, 1, "made once, then found")
        registry.put("a/2", 2)
        registry.put("b/1", 3)
        XCTAssertEqual(Set(registry.removeAll(prefix: "a/")), [1, 2])
        XCTAssertEqual(registry.keys(), ["b/1"])
        XCTAssertEqual(made, 1)

        let runs = RunRegistry()
        runs.cancel("x")
        let task = Task<Void, Never> {}
        XCTAssertFalse(runs.register("x", task), "a cancel that arrived first refuses the register")
        runs.finish("x")
        XCTAssertTrue(runs.register("x", task), "finish clears the tombstone")
        XCTAssertTrue(runs.isRunning("x"))
    }
}
