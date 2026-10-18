import XCTest
@testable import Granite

final class SignalTests: XCTestCase {

    func testHandlersReceiveValuesInSubscriptionOrder() {
        let signal = GraniteSignal.Payload<Int>()
        let order = Recorder<String>()

        signal += { order.append("a\($0)") }
        signal += { order.append("b\($0)") }
        signal.send(1)
        signal.send(2)

        XCTAssertEqual(order.values, ["a1", "b1", "a2", "b2"])
    }

    func testCancelStopsDeliveryAndIsIdempotent() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()
        let token = signal += { received.append($0) }

        signal.send(1)
        token.cancel()
        token.cancel()
        signal.send(2)

        XCTAssertTrue(token.isCancelled)
        XCTAssertEqual(received.values, [1])
        XCTAssertEqual(signal.observerCount, 0)
    }

    func testAHandlerCancelledMidFanOutDoesNotFire() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<String>()
        var second: GraniteCancellable?

        signal += { _ in
            received.append("first")
            second?.cancel()
        }
        second = signal += { _ in received.append("second") }

        signal.send(1)
        XCTAssertEqual(received.values, ["first"])
    }

    func testHandlersMaySendAndObserveReentrantly() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()
        let late = Recorder<Int>()

        signal += { value in
            received.append(value)
            if value == 1 {
                signal += { late.append($0) }
                signal.send(2)
            }
        }
        signal.send(1)

        XCTAssertEqual(received.values, [1, 2])
        XCTAssertEqual(late.values, [2], "an observer added during delivery sees only later sends")
    }

    func testDroppingATokenDoesNotEndTheSubscription() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()

        do {
            _ = signal += { received.append($0) }
        }
        signal.send(1)

        XCTAssertEqual(received.values, [1])
    }

    func testCopiesShareObserversAndLastValue() {
        let original = GraniteSignal.Payload<Int>(7)
        let copy = original
        let received = Recorder<Int>()

        copy += { received.append($0) }
        XCTAssertEqual(copy.lastValue, 7, "init seeds the last value")

        original.send(1)
        XCTAssertEqual(received.values, [1])
        XCTAssertEqual(copy.lastValue, 1)
        XCTAssertEqual(original.id, copy.id)
    }

    func testRemoveAllObserversCancelsTheirTokens() {
        let signal = GraniteSignal.Payload<Int>()
        let first = signal += { _ in }
        let second = signal += { _ in }

        signal.removeAllObservers()

        XCTAssertTrue(first.isCancelled)
        XCTAssertTrue(second.isCancelled)
        XCTAssertEqual(signal.observerCount, 0)
    }

    func testCancellingReleasesWhatTheHandlerCaptured() {
        let signal = GraniteSignal.Payload<Int>()
        let scope = Prospect(label: "owner", type: .custom, parent: nil)
        weak var weakProbe: Probe?
        var token: GraniteCancellable?

        do {
            let probe = Probe()
            weakProbe = probe
            token = signal.observe(in: scope) { _ in _ = probe }
        }
        XCTAssertNotNil(weakProbe)

        token?.cancel()
        XCTAssertNil(weakProbe, "the scope still holds the token, but not the handler")
        withExtendedLifetime(scope) {}
    }

    func testObserveChangeSkipsTheFirstUnseededSend() {
        let signal = GraniteSignal.Payload<Int>()
        let changes = Recorder<[Int]>()
        signal.observeChange { new, old in changes.append([new, old]) }

        signal.send(1)
        signal.send(2)

        XCTAssertEqual(changes.values, [[2, 1]])
    }

    func testObserveChangeUsesTheSeedAsTheFirstPreviousValue() {
        let signal = GraniteSignal.Payload<Int>(0)
        let changes = Recorder<[Int]>()
        signal.observeChange { new, old in changes.append([new, old]) }

        signal.send(1)

        XCTAssertEqual(changes.values, [[1, 0]])
    }

    func testOptionalPayloadsDeliverNil() {
        let signal = GraniteSignal.Payload<Int?>()
        let received = Recorder<Int?>()
        signal += { received.append($0) }

        signal.send(nil)
        signal.send(3)

        XCTAssertEqual(received.values, [nil, 3])
    }

    func testValuelessSignalDelivers() {
        let signal = GraniteSignal()
        let received = Recorder<Bool>()
        let token = signal += { received.append(true) }

        signal.send()
        token.cancel()
        signal.send()

        XCTAssertEqual(received.count, 1)
    }

    func testConcurrentSendObserveAndCancelStayConsistent() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()
        let steady = signal += { received.append($0) }

        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            let token = signal += { _ in }
            signal.send(index)
            token.cancel()
        }

        XCTAssertEqual(received.count, 2_000)
        XCTAssertEqual(signal.observerCount, 1, "only the steady observer remains")
        steady.cancel()
    }
}
