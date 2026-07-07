import XCTest
import Combine
@testable import Granite

final class GraniteTests: XCTestCase {

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
