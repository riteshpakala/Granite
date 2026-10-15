import Combine
import XCTest
@testable import Granite

/// A property wrapper declared outside Granite's own `@Event`: the center's pass compiles it
/// through `GraniteCustomEvent`, it commits fresh state through its host, and it fires on the
/// lifecycle it names — the contract Craft's `@Agent` is built on.
final class CustomEventTests: XCTestCase {
    /// Counts its sends into the center's state.
    @propertyWrapper
    struct Counter: GraniteCustomEvent {
        final class Handle {
            let signal = GraniteSignal.Payload<GranitePayload?>()
            func send() { signal.send(nil) }
        }

        final class Container: GraniteEventContainer {
            let id = UUID()
            let label = "counter"
            let reducerType: AnyGraniteReducer.Type? = nil
            private let host: GraniteEventHost
            private var subscription: AnyCancellable?
            private(set) var fired = 0

            init(host: GraniteEventHost, signal: GraniteSignal.Payload<GranitePayload?>) {
                self.host = host
                subscription = signal.publisher.sink { [weak self] payload in self?.fire(payload) }
            }

            func fire(_ payload: GranitePayload?) {
                fired += 1
                guard var state = host.state() as? CounterCenter.State else { return }
                state.count += 1
                host.commit(state)
            }
        }

        private let handle = Handle()
        let forwarding: Forwarding = .none
        let lifecycle: Lifecycle
        let intermediateSignal = GraniteSignal.Payload<GranitePayload?>()
        var signal: GraniteSignal.Payload<GranitePayload?> { handle.signal }
        var wrappedValue: Handle { handle }

        init(_ lifecycle: Lifecycle = .none) { self.lifecycle = lifecycle }

        func compile(with host: GraniteEventHost) -> [any GraniteEventContainer] {
            [Container(host: host, signal: handle.signal)]
        }
    }

    struct CounterCenter: GraniteCenter {
        struct State: GraniteState {
            var count = 0
        }

        @Counter var tick: Counter.Handle
        @Counter(.onTask) var boot: Counter.Handle
        @Store var state: State
    }

    func testACustomEventIsCompiledAndCommitsFreshState() {
        let command = GraniteCommand<CounterCenter>.hosted()
        XCTAssertEqual(command.reducers.count, 2, "both wrappers compiled beside the store")
        command.center.tick.send()
        XCTAssertEqual(command.center.state.count, 1)
        command.center.tick.send()
        XCTAssertEqual(command.center.state.count, 2, "each commit read fresh state")
    }

    func testACustomEventOnTaskFiresWhenTheHostRunsItsTasks() {
        let command = GraniteCommand<CounterCenter>.hosted()
        XCTAssertEqual(command.center.state.count, 0)
        command.performTasks()
        XCTAssertEqual(command.center.state.count, 1)
    }

    func testTheHostIsANoOpOnceTheCommandIsGone() {
        var host: GraniteEventHost?
        do {
            let command = GraniteCommand<CounterCenter>.hosted()
            host = GraniteEventHost(director: command, isOnline: false)
            XCTAssertNotNil(host?.state())
        }
        XCTAssertNil(host?.state(), "the host holds its command weakly")
        host?.commit(CounterCenter.State())   // nothing to commit to; must not crash
    }
}
