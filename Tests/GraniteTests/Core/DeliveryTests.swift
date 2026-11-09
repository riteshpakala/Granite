import XCTest
@testable import Granite

/// Debounce and throttle: their timing, their queue, and what happens to a pending value when
/// their owner lets them go.
final class DeliveryTests: XCTestCase {
    private let queue = DispatchQueue(label: "granite.tests.delivery")

    func testDebounceDeliversOnlyTheLastValueAfterAQuietPeriod() {
        let received = Recorder<Int>()
        let delivered = expectation(description: "debounced delivery")

        let debounce = GraniteDebounce<Int>(interval: 0.05, queue: queue) { value in
            received.append(value)
            delivered.fulfill()
        }
        debounce.receive(1)
        debounce.receive(2)
        debounce.receive(3)

        wait(for: [delivered], timeout: 2)
        settle(0.15)
        XCTAssertEqual(received.values, [3])
        withExtendedLifetime(debounce) {}
    }

    func testReleasingTheDebounceDropsAPendingValue() {
        let received = Recorder<Int>()
        weak var weakDebounce: GraniteDebounce<Int>?

        do {
            let debounce = GraniteDebounce<Int>(interval: 0.05, queue: queue) { received.append($0) }
            weakDebounce = debounce
            debounce.receive(1)
        }

        XCTAssertNil(weakDebounce, "scheduled work does not keep it alive")
        settle(0.15)
        XCTAssertTrue(received.values.isEmpty)
    }

    func testThrottleDeliversTheLeadingValueThenTheLatestOfTheWindow() {
        let received = Recorder<Int>()
        let delivered = expectation(description: "leading and trailing")
        delivered.expectedFulfillmentCount = 2

        let throttle = GraniteThrottle<Int>(interval: 0.1, queue: queue) { value in
            received.append(value)
            delivered.fulfill()
        }
        throttle.receive(1)
        queue.sync {}            // the leading delivery is scheduled at once
        throttle.receive(2)
        throttle.receive(3)

        wait(for: [delivered], timeout: 2)
        settle(0.2)
        XCTAssertEqual(received.values, [1, 3])
        withExtendedLifetime(throttle) {}
    }

    func testThrottleWithoutLatestKeepsTheFirstOfTheWindow() {
        let received = Recorder<Int>()
        let delivered = expectation(description: "leading and trailing")
        delivered.expectedFulfillmentCount = 2

        let throttle = GraniteThrottle<Int>(interval: 0.1, queue: queue, latest: false) { value in
            received.append(value)
            delivered.fulfill()
        }
        throttle.receive(1)
        queue.sync {}
        throttle.receive(2)
        throttle.receive(3)

        wait(for: [delivered], timeout: 2)
        settle(0.2)
        XCTAssertEqual(received.values, [1, 2])
        withExtendedLifetime(throttle) {}
    }

    func testANilPayloadIsDeliveredAsAValue() {
        let received = Recorder<Int?>()
        let delivered = expectation(description: "delivered")

        let debounce = GraniteDebounce<Int?>(interval: 0.01, queue: queue) { value in
            received.append(value)
            delivered.fulfill()
        }
        debounce.receive(nil)

        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(received.values, [nil])
        withExtendedLifetime(debounce) {}
    }

    func testDeliveryRunsOnTheGivenQueue() {
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        defer { queue.setSpecific(key: key, value: nil) }

        let onQueue = Recorder<Bool>()
        let delivered = expectation(description: "delivered")
        let debounce = GraniteDebounce<Int>(interval: 0.01, queue: queue) { _ in
            onQueue.append(DispatchQueue.getSpecific(key: key) == true)
            delivered.fulfill()
        }
        debounce.receive(1)

        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(onQueue.values, [true])
        withExtendedLifetime(debounce) {}
    }

    /// Waits a fixed span so late, unwanted deliveries would have landed.
    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }
}

#if canImport(Combine)
import Combine

/// The same scripts through Combine's operators and through Granite's: the delivered values must
/// match.
extension DeliveryTests {
    func testThrottleMatchesCombine() {
        let script: [Step] = [.burst([1, 2, 3]), .wait(0.25), .burst([4]), .wait(0.02), .burst([5]), .wait(0.3)]

        let combine = run(script) { subject, queue, sink in
            subject.throttle(for: .seconds(0.1), scheduler: queue, latest: true).sink(receiveValue: sink)
        }
        let granite = run(script) { queue, sink -> (Int) -> Void in
            let throttle = GraniteThrottle<Int>(interval: 0.1, queue: queue, handler: sink)
            return { throttle.receive($0) }
        }

        XCTAssertEqual(granite, combine)
    }

    func testDebounceMatchesCombine() {
        let script: [Step] = [.burst([1, 2, 3]), .wait(0.25), .burst([4]), .wait(0.25)]

        let combine = run(script) { subject, queue, sink in
            subject.debounce(for: .seconds(0.1), scheduler: queue).sink(receiveValue: sink)
        }
        let granite = run(script) { queue, sink -> (Int) -> Void in
            let debounce = GraniteDebounce<Int>(interval: 0.1, queue: queue, handler: sink)
            return { debounce.receive($0) }
        }

        XCTAssertEqual(granite, combine)
        XCTAssertEqual(granite, [3, 4])
    }

    /// A burst is sent from the delivery queue itself, so no scheduled delivery can interleave
    /// with it on either implementation: the comparison is about semantics, not thread races.
    private enum Step {
        case burst([Int])
        case wait(TimeInterval)
    }

    private func run(_ script: [Step],
                     combine attach: (PassthroughSubject<Int, Never>, DispatchQueue, @escaping (Int) -> Void) -> AnyCancellable) -> [Int] {
        let subject = PassthroughSubject<Int, Never>()
        let queue = DispatchQueue(label: "granite.parity.combine")
        let received = Recorder<Int>()
        let cancellable = attach(subject, queue) { received.append($0) }
        play(script, on: queue) { subject.send($0) }
        cancellable.cancel()
        return received.values
    }

    private func run(_ script: [Step],
                     granite attach: (DispatchQueue, @escaping @Sendable (Int) -> Void) -> (Int) -> Void) -> [Int] {
        let queue = DispatchQueue(label: "granite.parity.granite")
        let received = Recorder<Int>()
        let send = attach(queue) { received.append($0) }
        play(script, on: queue, send: send)
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
}
#endif
