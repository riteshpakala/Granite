import XCTest
@testable import Granite

final class DeliveryTests: XCTestCase {
    private let queue = DispatchQueue(label: "granite.tests.delivery")

    func testDebounceDeliversOnlyTheLastValueAfterAQuietPeriod() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()
        let delivered = expectation(description: "debounced delivery")

        signal.debounced(0.05, on: queue) += { value in
            received.append(value)
            delivered.fulfill()
        }
        signal.send(1)
        signal.send(2)
        signal.send(3)

        wait(for: [delivered], timeout: 2)
        settle(0.15)
        XCTAssertEqual(received.values, [3])
    }

    func testCancellingDropsAPendingDebouncedValue() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()
        let token = signal.debounced(0.05, on: queue) += { received.append($0) }

        signal.send(1)
        token.cancel()

        settle(0.15)
        XCTAssertTrue(received.values.isEmpty)
    }

    func testDebounceOnlyShapesItsOwnObservers() {
        let signal = GraniteSignal.Payload<Int>()
        let immediate = Recorder<Int>()
        signal.debounced(10, on: queue) += { _ in }
        signal += { immediate.append($0) }

        signal.send(1)
        XCTAssertEqual(immediate.values, [1])
    }

    func testThrottleDeliversTheLeadingValueThenTheLatestOfTheWindow() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()
        let delivered = expectation(description: "leading and trailing")
        delivered.expectedFulfillmentCount = 2

        signal.throttled(0.1, on: queue) += { value in
            received.append(value)
            delivered.fulfill()
        }
        signal.send(1)
        queue.sync {}            // the leading delivery is scheduled at once
        signal.send(2)
        signal.send(3)

        wait(for: [delivered], timeout: 2)
        settle(0.2)
        XCTAssertEqual(received.values, [1, 3])
    }

    func testThrottleWithoutLatestKeepsTheFirstOfTheWindow() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()
        let delivered = expectation(description: "leading and trailing")
        delivered.expectedFulfillmentCount = 2

        signal.throttled(0.1, on: queue, latest: false) += { value in
            received.append(value)
            delivered.fulfill()
        }
        signal.send(1)
        queue.sync {}
        signal.send(2)
        signal.send(3)

        wait(for: [delivered], timeout: 2)
        settle(0.2)
        XCTAssertEqual(received.values, [1, 2])
    }

    func testDeliveryRunsOnTheGivenQueue() {
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        defer { queue.setSpecific(key: key, value: nil) }

        let signal = GraniteSignal.Payload<Int>()
        let onQueue = Recorder<Bool>()
        let delivered = expectation(description: "delivered")
        signal.debounced(0.01, on: queue) += { _ in
            onQueue.append(DispatchQueue.getSpecific(key: key) == true)
            delivered.fulfill()
        }
        signal.send(1)

        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(onQueue.values, [true])
    }

    /// Waits a fixed span so late, unwanted deliveries would have landed.
    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }
}
