#if canImport(Combine)
import Combine
import XCTest
@testable import Granite

/// The Combine view of Granite's signals, and how the new delivery compares to Combine's.
final class CombineBridgeTests: XCTestCase {

    // MARK: Bridge

    func testPublisherSinkReceivesAndCancelUnsubscribes() {
        let signal = GraniteSignal.Payload<Int>()
        let received = LockedValues<Int>()

        let cancellable = signal.publisher.sink { received.append($0) }
        XCTAssertEqual(signal.observerCount, 1)

        signal.send(1)
        cancellable.cancel()
        signal.send(2)

        XCTAssertEqual(received.values, [1])
        XCTAssertEqual(signal.observerCount, 0)
    }

    func testPublisherHonoursDemand() {
        let signal = GraniteSignal.Payload<Int>()
        let subscriber = OneAtATime()
        signal.publisher.subscribe(subscriber)

        signal.send(1)
        signal.send(2)
        XCTAssertEqual(subscriber.received, [1], "no demand for the second value, so it is dropped")

        subscriber.requestOne()
        signal.send(3)
        XCTAssertEqual(subscriber.received, [1, 3])
    }

    func testPublisherOfADebouncedCopyIsDebounced() {
        let signal = GraniteSignal.Payload<Int>()
        let received = LockedValues<Int>()
        let delivered = expectation(description: "debounced")

        let cancellable = signal.debounced(0.05, on: .main).publisher.sink {
            received.append($0)
            delivered.fulfill()
        }
        signal.send(1)
        signal.send(2)

        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(received.values, [2])
        cancellable.cancel()
    }

    func testTokensStoreIntoACombineBag() {
        let signal = GraniteSignal.Payload<Int>()
        var bag = Set<AnyCancellable>()

        (signal += { _ in }).store(in: &bag)
        XCTAssertEqual(signal.observerCount, 1)

        bag.removeAll()
        XCTAssertEqual(signal.observerCount, 0, "releasing the AnyCancellable cancels the token")
    }

    func testCombineCancellablesStoreIntoAScope() {
        let subject = PassthroughSubject<Int, Never>()
        let received = LockedValues<Int>()
        let scope = Prospect(label: "owner", type: .custom, parent: nil)

        subject.sink { received.append($0) }.store(in: scope)
        subject.send(1)
        scope.cancel()
        subject.send(2)

        XCTAssertEqual(received.values, [1])
    }

    // MARK: Parity with Combine's operators

    func testThrottleMatchesCombine() {
        let script: [Step] = [.burst([1, 2, 3]), .wait(0.25), .burst([4]), .wait(0.02), .burst([5]), .wait(0.3)]

        let combine = run(script) { subject, queue, sink in
            subject.throttle(for: .seconds(0.1), scheduler: queue, latest: true).sink(receiveValue: sink)
        }
        let granite = run(script) { signal, queue, sink in
            signal.throttled(0.1, on: queue) += sink
        }

        XCTAssertEqual(granite, combine)
    }

    func testDebounceMatchesCombine() {
        let script: [Step] = [.burst([1, 2, 3]), .wait(0.25), .burst([4]), .wait(0.25)]

        let combine = run(script) { subject, queue, sink in
            subject.debounce(for: .seconds(0.1), scheduler: queue).sink(receiveValue: sink)
        }
        let granite = run(script) { signal, queue, sink in
            signal.debounced(0.1, on: queue) += sink
        }

        XCTAssertEqual(granite, combine)
        XCTAssertEqual(granite, [3, 4])
    }

    // MARK: Cost against Combine (reported, not asserted)

    func testCostComparedToCombine() {
        let observers = 200
        let sends = 2_000
        let soloSends = 200_000
        let churn = 20_000

        let graniteFanOut = time {
            let signal = GraniteSignal.Payload<Int>()
            let scope = Prospect(label: "bench", type: .custom, parent: nil)
            for _ in 0..<observers { signal.observe(in: scope) { _ in } }
            for value in 0..<sends { signal.send(value) }
            scope.cancel()
        }
        let combineFanOut = time {
            let subject = PassthroughSubject<Int, Never>()
            var bag = Set<AnyCancellable>()
            for _ in 0..<observers { subject.sink { _ in }.store(in: &bag) }
            for value in 0..<sends { subject.send(value) }
            bag.removeAll()
        }
        let graniteSolo = time {
            let signal = GraniteSignal.Payload<Int>()
            let token = signal += { _ in }
            for value in 0..<soloSends { signal.send(value) }
            token.cancel()
        }
        let combineSolo = time {
            let subject = PassthroughSubject<Int, Never>()
            let cancellable = subject.sink { _ in }
            for value in 0..<soloSends { subject.send(value) }
            cancellable.cancel()
        }
        let graniteChurn = time {
            let signal = GraniteSignal.Payload<Int>()
            let scope = Prospect(label: "bench", type: .custom, parent: nil)
            for _ in 0..<churn { signal.observe(in: scope) { _ in }.cancel() }
        }
        let combineChurn = time {
            let subject = PassthroughSubject<Int, Never>()
            for _ in 0..<churn { subject.sink { _ in }.cancel() }
        }

        print("""
        [Granite vs Combine] fan-out \(observers)x\(sends): \(graniteFanOut)ms vs \(combineFanOut)ms; \
        one observer x\(soloSends): \(graniteSolo)ms vs \(combineSolo)ms; \
        observe+cancel x\(churn): \(graniteChurn)ms vs \(combineChurn)ms
        """)
    }

    // MARK: Helpers

    /// A burst is sent from the delivery queue itself, so no scheduled delivery can interleave
    /// with it on either implementation — the comparison is about semantics, not thread races.
    private enum Step {
        case burst([Int])
        case wait(TimeInterval)
    }

    private func run(_ script: [Step],
                     combine attach: (PassthroughSubject<Int, Never>, DispatchQueue, @escaping (Int) -> Void) -> AnyCancellable) -> [Int] {
        let subject = PassthroughSubject<Int, Never>()
        let queue = DispatchQueue(label: "granite.parity.combine")
        let received = LockedValues<Int>()
        let cancellable = attach(subject, queue) { received.append($0) }
        play(script, on: queue) { subject.send($0) }
        cancellable.cancel()
        return received.values
    }

    private func run(_ script: [Step],
                     granite attach: (GraniteSignal.Payload<Int>, DispatchQueue, @escaping (Int) -> Void) -> GraniteCancellable) -> [Int] {
        let signal = GraniteSignal.Payload<Int>()
        let queue = DispatchQueue(label: "granite.parity.granite")
        let received = LockedValues<Int>()
        let token = attach(signal, queue) { received.append($0) }
        play(script, on: queue) { signal.send($0) }
        token.cancel()
        return received.values
    }

    private func play(_ script: [Step], on queue: DispatchQueue, send: (Int) -> Void) {
        for step in script {
            switch step {
            case .burst(let values): queue.sync { values.forEach(send) }
            case .wait(let seconds): Thread.sleep(forTimeInterval: seconds)
            }
        }
    }

    private func time(_ body: () -> Void) -> Int {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }

    var values: [Value] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

/// Requests one value up front, then only when asked.
private final class OneAtATime: Subscriber, @unchecked Sendable {
    typealias Input = Int
    typealias Failure = Never

    private(set) var received: [Int] = []
    private var subscription: Subscription?

    func receive(subscription: Subscription) {
        self.subscription = subscription
        subscription.request(.max(1))
    }

    func receive(_ input: Int) -> Subscribers.Demand {
        received.append(input)
        return .none
    }

    func receive(completion: Subscribers.Completion<Never>) {}

    func requestOne() {
        subscription?.request(.max(1))
    }
}
#endif
