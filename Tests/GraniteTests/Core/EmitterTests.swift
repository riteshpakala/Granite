import XCTest
@testable import Granite

/// The emitter's contract: receivers are held weakly and end with their owners, keys replace,
/// delivery is ordered and re-entrant, and concurrent use stays consistent.
final class EmitterTests: XCTestCase {

    func testReceiversRunInSubscriptionOrder() {
        let emitter = GraniteEmitter<Int>()
        let log = Recorder<String>()
        let first = Probe()
        let second = Probe()

        emitter.on(first) { _, value in log.append("first \(value)") }
        emitter.on(second) { _, value in log.append("second \(value)") }
        emitter.send(1)

        XCTAssertEqual(log.values, ["first 1", "second 1"])
    }

    func testTheHandlerIsHandedItsReceiver() {
        let emitter = GraniteEmitter<Int>()
        let receiver = Probe()
        let expected = ObjectIdentifier(receiver)
        let matched = Recorder<Bool>()

        emitter.on(receiver) { handed, _ in matched.append(ObjectIdentifier(handed) == expected) }
        emitter.send(1)

        XCTAssertEqual(matched.values, [true])
    }

    func testReleasingTheReceiverEndsTheSubscription() {
        let emitter = GraniteEmitter<Int>()
        let log = Recorder<Int>()
        weak var weakReceiver: Probe?

        do {
            let receiver = Probe()
            weakReceiver = receiver
            emitter.on(receiver) { _, value in log.append(value) }
            emitter.send(1)
            XCTAssertEqual(emitter.receiverCount, 1)
        }

        XCTAssertNil(weakReceiver, "the emitter does not keep its receiver alive")
        XCTAssertEqual(emitter.receiverCount, 0)
        emitter.send(2)
        XCTAssertEqual(log.values, [1])
    }

    func testAKeyReplacesItsSubscriptionAndMovesItLast() {
        let emitter = GraniteEmitter<Int>()
        let log = Recorder<String>()
        let first = Probe()
        let middle = Probe()
        let last = Probe()
        let key = GraniteEmitterKey("slot")

        emitter.on(first, key: key) { _, _ in log.append("first") }
        emitter.on(middle) { _, _ in log.append("middle") }
        emitter.on(last, key: key) { _, _ in log.append("last") }
        emitter.send(1)

        XCTAssertEqual(log.values, ["middle", "last"])
        XCTAssertEqual(emitter.receiverCount, 2)
    }

    func testReplacingAKeyTellsTheDisplacedReceiver() {
        let emitter = GraniteEmitter<Int>()
        let first = DisplacedProbe()
        let second = DisplacedProbe()
        let key = GraniteEmitterKey("slot")

        emitter.on(first, key: key) { _, _ in }
        emitter.on(second, key: key) { _, _ in }

        XCTAssertEqual(first.displacedCount, 1)
        XCTAssertEqual(second.displacedCount, 0)
    }

    func testRemovingAllTellsEveryReceiver() {
        let emitter = GraniteEmitter<Int>()
        let first = DisplacedProbe()
        let second = DisplacedProbe()
        emitter.on(first) { _, _ in }
        emitter.on(second) { _, _ in }

        emitter.removeAll()

        XCTAssertEqual(emitter.receiverCount, 0)
        XCTAssertEqual(first.displacedCount, 1)
        XCTAssertEqual(second.displacedCount, 1)
    }

    func testOffMatchesTheReceiverAndTheKey() {
        let emitter = GraniteEmitter<Int>()
        let log = Recorder<String>()
        let receiver = Probe()
        let other = Probe()

        emitter.on(receiver, key: GraniteEmitterKey("a")) { _, _ in log.append("a") }
        emitter.on(receiver, key: GraniteEmitterKey("b")) { _, _ in log.append("b") }
        emitter.on(other, key: GraniteEmitterKey("c")) { _, _ in log.append("c") }

        emitter.off(other, key: GraniteEmitterKey("a"))
        emitter.off(receiver, key: GraniteEmitterKey("a"))
        emitter.send(1)
        XCTAssertEqual(log.values, ["b", "c"], "only the receiver's own subscription under the key went")

        emitter.off(receiver)
        emitter.send(2)
        XCTAssertEqual(log.values, ["b", "c", "c"])
    }

    func testAReceiverReleasedEarlierInTheSameSendIsNotReached() {
        let emitter = GraniteEmitter<Int>()
        let log = Recorder<String>()
        let first = Probe()
        let holder = Holder<Probe?>(Probe())

        emitter.on(first) { _, _ in
            log.append("first")
            holder.value = nil
        }
        emitter.on(holder.value!) { _, _ in log.append("second") }
        emitter.send(1)

        XCTAssertEqual(log.values, ["first"])
    }

    func testHandlersMaySendAndSubscribeReentrantly() {
        let emitter = GraniteEmitter<Int>()
        let log = Recorder<Int>()
        let receiver = Probe()
        let late = Probe()

        emitter.on(receiver) { _, value in
            log.append(value)
            if value == 1 {
                emitter.on(late) { _, value in log.append(value * 10) }
                emitter.send(2)
            }
        }
        emitter.send(1)

        XCTAssertEqual(log.values, [1, 2, 20], "the nested send reached the receiver added before it")
    }

    func testAValueLessEmitterSends() {
        let emitter = GraniteEmitter<Void>()
        let log = Recorder<Bool>()
        let receiver = Probe()

        emitter.on(receiver) { _, _ in log.append(true) }
        emitter.send()

        XCTAssertEqual(log.count, 1)
    }

    func testConcurrentSendSubscribeAndReleaseStayConsistent() {
        let emitter = GraniteEmitter<Int>()
        let steady = Probe()
        let delivered = Recorder<Int>()
        emitter.on(steady) { _, value in delivered.append(value) }

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            let transient = Probe()
            emitter.on(transient, key: GraniteEmitterKey("transient \(index % 7)")) { _, _ in }
            emitter.send(index)
        }

        emitter.send(-1)
        XCTAssertEqual(delivered.count, 1_001, "the steady receiver heard every send")
        XCTAssertEqual(emitter.receiverCount, 1, "every transient receiver went with its owner")
    }
}

#if canImport(Combine)
import Combine

extension EmitterTests {
    /// Reported, not asserted. The figures to compare with are in the commit that added the emitter.
    func testCostComparedToCombine() {
        let observers = 200
        let sends = 2_000
        let soloSends = 200_000
        let churn = 20_000

        let graniteFanOut = time {
            let emitter = GraniteEmitter<Int>()
            let receivers = (0..<observers).map { _ in Probe() }
            for receiver in receivers { emitter.on(receiver) { _, _ in } }
            for value in 0..<sends { emitter.send(value) }
            withExtendedLifetime(receivers) {}
        }
        let combineFanOut = time {
            let subject = PassthroughSubject<Int, Never>()
            var bag = Set<AnyCancellable>()
            for _ in 0..<observers { subject.sink { _ in }.store(in: &bag) }
            for value in 0..<sends { subject.send(value) }
            bag.removeAll()
        }
        let graniteSolo = time {
            let emitter = GraniteEmitter<Int>()
            let receiver = Probe()
            emitter.on(receiver) { _, _ in }
            for value in 0..<soloSends { emitter.send(value) }
            withExtendedLifetime(receiver) {}
        }
        let combineSolo = time {
            let subject = PassthroughSubject<Int, Never>()
            let cancellable = subject.sink { _ in }
            for value in 0..<soloSends { subject.send(value) }
            cancellable.cancel()
        }
        let graniteChurn = time {
            let emitter = GraniteEmitter<Int>()
            let key = GraniteEmitterKey("churn")
            for _ in 0..<churn {
                let receiver = Probe()
                emitter.on(receiver, key: key) { _, _ in }
            }
        }
        let combineChurn = time {
            let subject = PassthroughSubject<Int, Never>()
            for _ in 0..<churn { subject.sink { _ in }.cancel() }
        }

        print("""
        [Granite vs Combine] fan-out \(observers)x\(sends): \(graniteFanOut)ms vs \(combineFanOut)ms; \
        one observer x\(soloSends): \(graniteSolo)ms vs \(combineSolo)ms; \
        subscribe+release x\(churn): \(graniteChurn)ms vs \(combineChurn)ms
        """)
    }

    private func time(_ body: () -> Void) -> Int {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}
#endif

/// A receiver that counts how often an emitter displaced it.
private final class DisplacedProbe: GraniteEmitterDisplaceable, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func displaced() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }

    var displacedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}
