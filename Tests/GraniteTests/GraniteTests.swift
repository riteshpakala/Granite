import XCTest
import Combine
@testable import Granite

final class GraniteTests: XCTestCase {

    private struct PayloadCenter: GraniteCenter {
        struct State: GraniteState {
            var value = 0
        }

        @Store var state: State
    }

    private struct DirectPayloadReducer: GraniteReducer {
        typealias Center = PayloadCenter
        typealias Metadata = Meta

        struct Meta: GranitePayload {
            let value: Int
        }

        func reduce(state: inout Center.State) {
            state.value = -1
        }

        func reduce(state: inout Center.State, payload: Meta) {
            state.value = payload.value
        }
    }

    private struct WrappedPayloadReducer: GraniteReducer {
        typealias Center = PayloadCenter

        struct Meta: GranitePayload {
            let value: Int
        }

        @Payload var meta: Meta?

        func reduce(state: inout Center.State) {
            state.value = meta?.value ?? -1
        }
    }

    /// Polls a condition rather than sleeping a fixed interval — reducer
    /// executions land on the concurrency pool, not this thread.
    private func poll(_ timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

    // MARK: - Persistence (Phase 2: atomic/binary writes, versioned envelope, round-trip)

    private struct Sample: Codable, Equatable {
        var count: Int
        var name: String
    }

    private func makePersistence() -> FilePersistence {
        FilePersistence(key: "granite.test.\(UUID().uuidString)", kind: .basic)
    }

    func testPersistenceRoundTrip() throws {
        let persistence = makePersistence()
        defer { persistence.purge() }

        let value = Sample(count: 42, name: "hello")
        persistence.save(state: value)
        persistence.readWriteQueue?.waitUntilAllOperationsAreFinished()

        let restored: Sample = try persistence.restore()
        XCTAssertEqual(restored, value)
    }

    func testPersistenceMissingFileThrowsNotFound() {
        let persistence = makePersistence()
        defer { persistence.purge() }

        XCTAssertThrowsError(try persistence.restore() as Sample) { error in
            guard case PersistenceError.notFound = error else {
                return XCTFail("expected .notFound, got \(error)")
            }
        }
    }

    func testPersistencePurge() throws {
        let persistence = makePersistence()
        persistence.save(state: Sample(count: 1, name: "x"))
        persistence.readWriteQueue?.waitUntilAllOperationsAreFinished()
        XCTAssertNoThrow(try persistence.restore() as Sample)

        persistence.purge()
        XCTAssertThrowsError(try persistence.restore() as Sample)
    }

    func testPersistenceOverwriteKeepsLatest() throws {
        let persistence = makePersistence()
        defer { persistence.purge() }

        persistence.save(state: Sample(count: 1, name: "first"))
        persistence.save(state: Sample(count: 2, name: "second"))
        persistence.readWriteQueue?.waitUntilAllOperationsAreFinished()

        let restored: Sample = try persistence.restore()
        XCTAssertEqual(restored, Sample(count: 2, name: "second"))
    }

    // MARK: - Signals (Phase 1: core reactive primitive)

    func testSignalPayloadDelivers() {
        let signal = GraniteSignal.Payload<Int>()
        var received: [Int] = []
        let cancellable = signal += { value in received.append(value) }

        signal.send(1)
        signal.send(2)

        XCTAssertEqual(received, [1, 2])
        cancellable.cancel()
    }

    func testDirectReducerPayloadIsReplacedOnEveryUpdate() throws {
        let reducer = DirectPayloadReducer.Reducer()

        reducer.update(DirectPayloadReducer.Meta(value: 1))
        let first = try XCTUnwrap(reducer.execute(PayloadCenter.State()) as? PayloadCenter.State)
        XCTAssertEqual(first.value, 1)

        reducer.update(DirectPayloadReducer.Meta(value: 2))
        let second = try XCTUnwrap(reducer.execute(first) as? PayloadCenter.State)
        XCTAssertEqual(second.value, 2)

        reducer.send()
        let withoutPayload = try XCTUnwrap(reducer.execute(second) as? PayloadCenter.State)
        XCTAssertEqual(withoutPayload.value, -1)
    }

    func testWrappedReducerPayloadStillUpdatesAndClears() throws {
        let reducer = WrappedPayloadReducer.Reducer()

        reducer.update(WrappedPayloadReducer.Meta(value: 1))
        let first = try XCTUnwrap(reducer.execute(PayloadCenter.State()) as? PayloadCenter.State)
        XCTAssertEqual(first.value, 1)

        reducer.update(WrappedPayloadReducer.Meta(value: 2))
        let second = try XCTUnwrap(reducer.execute(first) as? PayloadCenter.State)
        XCTAssertEqual(second.value, 2)

        reducer.send()
        let withoutPayload = try XCTUnwrap(reducer.execute(second) as? PayloadCenter.State)
        XCTAssertEqual(withoutPayload.value, -1)
    }

    // MARK: - persistentStreamingTask (a re-send may not cancel a live stream)

    func testPersistentStreamingTaskDropsSendsWhileRunning() throws {
        let probe = StreamProbe.persistent
        probe.reset()
        let container = ReducerContainer(PersistentStreamReducer.Reducer())

        container.commit(nil)
        XCTAssertTrue(poll { probe.starts == 1 }, "the stream started")

        // Three re-sends land while the loop is running: every one is dropped
        // WHOLE, and none of them cancels the runner.
        container.commit(nil)
        container.commit(nil)
        container.commit(nil)
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertEqual(probe.starts, 1, "re-sends must not start a second execution")
        XCTAssertEqual(probe.cancellations, 0, "re-sends must not cancel the live stream")

        probe.openGate()
        XCTAssertTrue(poll { probe.completions == 1 }, "the loop ended on its own terms")
        XCTAssertEqual(probe.frames, 1, "its streamed frame landed")
    }

    func testPersistentStreamingTaskReopensAfterCompletion() throws {
        let probe = StreamProbe.persistent
        probe.reset()
        let container = ReducerContainer(PersistentStreamReducer.Reducer())

        container.commit(nil)
        XCTAssertTrue(poll { probe.starts == 1 })
        probe.openGate()
        XCTAssertTrue(poll { probe.completions == 1 })

        // The gate reopens: the next send runs normally.
        probe.closeGate()
        container.commit(nil)
        XCTAssertTrue(poll { probe.starts == 2 }, "a send after completion runs")
        probe.openGate()
        XCTAssertTrue(poll { probe.completions == 2 })
    }

    /// The regression pin for every existing app: `.streamingTask` KEEPS its
    /// replace-on-resend semantics. Only the new case opts out.
    func testStreamingTaskStillCancelsOnResend() throws {
        let probe = StreamProbe.replacing
        probe.reset()
        let container = ReducerContainer(ReplacingStreamReducer.Reducer())

        container.commit(nil)
        XCTAssertTrue(poll { probe.starts == 1 })

        container.commit(nil)
        XCTAssertTrue(poll { probe.cancellations == 1 }, "the in-flight execution is cancelled")
        XCTAssertTrue(poll { probe.starts == 2 }, "and replaced by the new send")

        probe.openGate()
    }

    // MARK: - Storage thread-safety (Phase 1: lock-guarded registry)

    func testStorageConcurrentAccessDoesNotCrash() {
        let storage = Storage()
        let iterations = 1_000

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            storage.setValue(i, at: "key.\(i % 16)")
            _ = storage.value(at: "key.\(i % 16)")
        }

        // Reaching here without a data-race trap means the lock is doing its job.
        XCTAssertTrue(storage.hasValue(at: "key.0"))
    }

    // MARK: - Effect DSL (Phase 4)

    func testEffectNone() {
        guard case .none = GraniteEffect.none.operation else {
            return XCTFail("expected .none")
        }
    }

    func testEffectMergePreservesCount() {
        let merged = GraniteEffect.merge(.none, .run { }, .none)
        guard case .merge(let effects) = merged.operation else {
            return XCTFail("expected .merge")
        }
        XCTAssertEqual(effects.count, 3)
    }

    func testEffectRunWrapsAsyncWork() {
        guard case .run = GraniteEffect.run({ }).operation else {
            return XCTFail("expected .run")
        }
    }
}

// MARK: - Streaming-behavior fixtures

/// What a long-lived streaming reducer reports back. Reducers are value types
/// Granite instantiates itself, so the coordination point is a shared object
/// rather than reducer state. One instance per behavior under test, so the two
/// suites cannot read each other's counts.
private final class StreamProbe: @unchecked Sendable {
    static let persistent = StreamProbe()
    static let replacing = StreamProbe()

    private let lock = NSLock()
    private var _starts = 0
    private var _completions = 0
    private var _frames = 0
    private var _cancellations = 0
    private var _gateOpen = false

    var starts: Int { read { _starts } }
    var completions: Int { read { _completions } }
    var frames: Int { read { _frames } }
    var cancellations: Int { read { _cancellations } }
    var isGateOpen: Bool { read { _gateOpen } }

    func reset() { write { _starts = 0; _completions = 0; _frames = 0; _cancellations = 0; _gateOpen = false } }
    func noteStart() { write { _starts += 1 } }
    func noteCompletion() { write { _completions += 1 } }
    func noteFrame() { write { _frames += 1 } }
    func noteCancellation() { write { _cancellations += 1 } }
    func openGate() { write { _gateOpen = true } }
    func closeGate() { write { _gateOpen = false } }

    private func read<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
    private func write(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        body()
    }
}

private struct StreamCenter: GraniteCenter {
    struct State: GraniteState {
        var value = 0
    }

    @Store var state: State
}

/// A loop that runs until the test lets it out — the shape
/// `persistentStreamingTask` exists for (a voice session, a device watcher).
private struct PersistentStreamReducer: GraniteReducer {
    typealias Center = StreamCenter

    func reduce(state: inout Center.State, stream: @escaping (Center.State) -> Void) async {
        let probe = StreamProbe.persistent
        probe.noteStart()
        while probe.isGateOpen == false {
            if Task.isCancelled {
                probe.noteCancellation()
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        state.value += 1
        stream(state)
        probe.noteFrame()
        probe.noteCompletion()
    }

    var behavior: GraniteReducerBehavior { .persistentStreamingTask(.userInitiated) }
}

/// The same loop under the ORIGINAL streaming behavior, so the replace-on-resend
/// contract every existing app depends on stays pinned.
private struct ReplacingStreamReducer: GraniteReducer {
    typealias Center = StreamCenter

    func reduce(state: inout Center.State, stream: @escaping (Center.State) -> Void) async {
        let probe = StreamProbe.replacing
        probe.noteStart()
        while probe.isGateOpen == false {
            if Task.isCancelled {
                probe.noteCancellation()
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        state.value += 1
        stream(state)
        probe.noteFrame()
        probe.noteCompletion()
    }

    var behavior: GraniteReducerBehavior { .streamingTask(.userInitiated) }
}
