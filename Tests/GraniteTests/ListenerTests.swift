import XCTest
@testable import Granite

/// `listen`: who owns a handler, how long it lasts, which one wins a slot, and where it runs.
@MainActor
final class ListenerTests: XCTestCase {

    // MARK: Delivery

    func testAMainThreadSendReachesItsListenerInline() {
        let reducer = GraniteReducerExecutable<Announce>()
        let heard = MainLog<Int>()
        let listeners = GraniteListeners()

        listeners.bind {
            reducer.listen(.broadcast("inline")) { heard.append(announced($0)) }
        }
        Announce().broadcast.send(Announce.Meta(value: 1))

        XCTAssertEqual(heard.values, [1], "heard before send returned")
    }

    func testABackgroundSendIsDeliveredOnMainInOrder() {
        let reducer = GraniteReducerExecutable<Announce>()
        let heard = MainLog<Int>()
        let onMain = MainLog<Bool>()
        let delivered = expectation(description: "five deliveries")
        delivered.expectedFulfillmentCount = 5
        let listeners = GraniteListeners()

        listeners.bind {
            reducer.listen(.broadcast("background")) { payload in
                heard.append(announced(payload))
                onMain.append(Thread.isMainThread)
                delivered.fulfill()
            }
        }
        let broadcast = Announce().broadcast
        DispatchQueue.global().async {
            for value in 1...5 {
                broadcast.send(Announce.Meta(value: value))
            }
        }

        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(heard.values, [1, 2, 3, 4, 5])
        XCTAssertEqual(onMain.values, Array(repeating: true, count: 5))
        withExtendedLifetime(listeners) {}
    }

    func testAListenerDroppedBeforeAQueuedDeliveryRunsDoesNotRun() {
        let reducer = GraniteReducerExecutable<Announce>()
        let heard = MainLog<Int>()
        var listeners: GraniteListeners? = GraniteListeners()

        listeners?.bind {
            reducer.listen(.broadcast("dropped")) { heard.append(announced($0)) }
        }
        let broadcast = Announce().broadcast
        let sent = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            broadcast.send(Announce.Meta(value: 1))
            sent.signal()
        }
        // Blocks without running the main queue, so the delivery is queued but has not run.
        sent.wait()
        listeners = nil

        spin()
        XCTAssertEqual(heard.values, [])
    }

    // MARK: Ownership

    /// The case that used to leak: a component's listeners outlive its `onDisappear`. Dropping
    /// the set, with no clear, must release the handlers and everything they captured.
    func testDroppingAListenerSetReleasesItsHandlersWithoutAClear() {
        let reducer = GraniteReducerExecutable<Announce>()
        let broadcast = Announce().broadcast
        let before = broadcast.receiverCount
        let heard = MainLog<Int>()
        weak var weakCaptured: Probe?
        weak var weakSet: GraniteListeners?

        do {
            let captured = Probe()
            weakCaptured = captured
            let listeners = GraniteListeners()
            weakSet = listeners
            listeners.bind {
                reducer.listen(.broadcast("owned")) { payload in
                    withExtendedLifetime(captured) {}
                    heard.append(announced(payload))
                }
            }
            XCTAssertEqual(broadcast.receiverCount, before + 1)
        }

        XCTAssertNil(weakSet)
        XCTAssertNil(weakCaptured, "what the handler captured went with the set")
        XCTAssertEqual(broadcast.receiverCount, before)
        broadcast.send(Announce.Meta(value: 1))
        XCTAssertEqual(heard.values, [])
    }

    /// Clearing a set releases its handlers. A handler whose capture broadcasts to the very
    /// listener being cleared, as it is released, must not find that listener's lock held.
    func testAHandlerWhoseCaptureSendsAsItIsReleasedIsClearedSafely() {
        let reducer = GraniteReducerExecutable<Announce>()
        let broadcast = Announce().broadcast
        let heard = MainLog<Int>()
        let listeners = GraniteListeners()

        do {
            let releases = SendsOnRelease<GranitePayload?>(Announce.Meta(value: 4), on: broadcast)
            listeners.bind {
                reducer.listen(.broadcast("release")) { payload in
                    withExtendedLifetime(releases) {}
                    heard.append(announced(payload))
                }
            }
        }
        listeners.clear()

        XCTAssertEqual(heard.values, [], "the listener was already cleared when its capture sent")
        XCTAssertEqual(listeners.count, 0)
    }

    func testATaskStartedInsideListenersDoesNotKeepTheSetAlive() {
        let reducer = GraniteReducerExecutable<Announce>()
        let broadcast = Announce().broadcast
        let before = broadcast.receiverCount
        let release = Holder<CheckedContinuation<Void, Never>?>(nil)
        let late = expectation(description: "the late listen ran")
        weak var weakSet: GraniteListeners?

        do {
            let listeners = GraniteListeners()
            weakSet = listeners
            listeners.bind {
                // Inherits the binding, as a reducer task started from `listeners` would.
                Task {
                    await withCheckedContinuation { release.value = $0 }
                    reducer.listen(.broadcast("late")) { _ in }
                    late.fulfill()
                }
            }
            spin()   // let the task reach its suspension
        }

        XCTAssertNil(weakSet, "the task's inherited binding does not keep the set")
        release.value?.resume()
        wait(for: [late], timeout: 2)
        XCTAssertEqual(broadcast.receiverCount, before, "a listen bound to a gone set registers nowhere")
    }

    func testAListenOutsideListenersLastsAsLongAsItsReducer() {
        let broadcast = Announce().broadcast
        let before = broadcast.receiverCount
        weak var weakReducer: Announce.Reducer?

        do {
            let reducer = GraniteReducerExecutable<Announce>()
            weakReducer = reducer
            reducer.listen(.broadcast("own")) { _ in }
            XCTAssertEqual(broadcast.receiverCount, before + 1)
        }

        XCTAssertNil(weakReducer)
        XCTAssertEqual(broadcast.receiverCount, before)
    }

    // MARK: Slots

    func testTwoOwnersOnOneSlotTheLastWinsAndTheFirstLeavingKeepsTheSecond() {
        let reducer = GraniteReducerExecutable<Announce>()
        let heard = MainLog<String>()
        let first = GraniteListeners()
        let second = GraniteListeners()

        first.bind { reducer.listen(.broadcast("shared")) { _ in heard.append("first") } }
        second.bind { reducer.listen(.broadcast("shared")) { _ in heard.append("second") } }
        Announce().broadcast.send(nil)
        XCTAssertEqual(heard.values, ["second"])

        first.clear()
        Announce().broadcast.send(nil)
        XCTAssertEqual(heard.values, ["second", "second"], "the first owner leaving did not end the second's listener")
    }

    func testADisplacedHandlerIsReleasedAtOnce() {
        let reducer = GraniteReducerExecutable<Announce>()
        let first = GraniteListeners()
        let second = GraniteListeners()
        weak var weakCaptured: Probe?

        do {
            let captured = Probe()
            weakCaptured = captured
            first.bind {
                reducer.listen(.broadcast("displaced")) { _ in withExtendedLifetime(captured) {} }
            }
        }
        second.bind { reducer.listen(.broadcast("displaced")) { _ in } }

        XCTAssertNil(weakCaptured, "released though its set is still alive")
        withExtendedLifetime(first) {}
    }

    func testBindingAgainReplacesTheEarlierListeners() {
        let reducer = GraniteReducerExecutable<Announce>()
        let heard = MainLog<String>()
        let listeners = GraniteListeners()

        listeners.bind { reducer.listen(.broadcast("first")) { _ in heard.append("first") } }
        listeners.bind { reducer.listen(.broadcast("second")) { _ in heard.append("second") } }
        Announce().broadcast.send(nil)

        XCTAssertEqual(heard.values, ["second"])
        XCTAssertEqual(listeners.count, 1)
    }

    func testTheLastBeamListenerWins() {
        let reducer = GraniteReducerExecutable<Announce>()
        let heard = MainLog<String>()
        let first = GraniteListeners()
        let second = GraniteListeners()

        first.bind { reducer.listen { _ in heard.append("first") } }
        second.bind { reducer.listen(.beam) { _ in heard.append("second") } }
        reducer.beamEmitter.send(nil)

        XCTAssertEqual(heard.values, ["second"])
    }

    // MARK: Reducers

    func testABubbleListenerHearsTheReducerAfterItsContainerCommitted() {
        let command = GraniteCommand<ListenCenter>.hosted()
        let seen = MainLog<Int>()

        command.listen {
            command.center.announce.listen(.bubble("after")) { _ in
                seen.append(command.center.state.count)
            }
        }
        command.center.announce.send(Announce.Meta(value: 3))

        XCTAssertEqual(seen.values, [1], "the listener saw the committed state")
    }

    func testAReducerBroadcastReachesAListenerOnAnotherCommand() {
        let service = GraniteCommand<ListenCenter>.hosted()
        let component = GraniteCommand<ListenCenter>.hosted()
        let heard = MainLog<Int>()

        component.listen {
            service.center.announce.listen(.broadcast("service")) { heard.append(announced($0)) }
        }
        service.center.announce.send(Announce.Meta(value: 9))

        XCTAssertEqual(heard.values, [9])
    }

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}

#if os(macOS)
import AppKit
import SwiftUI

/// The end-to-end case: a component on screen listening to an app-lifetime service. Taking the
/// views down must release the component's command, though the service lives on.
@MainActor
final class ComponentListenerTests: XCTestCase {

    func testAComponentListeningToAServiceIsReleasedWithItsViews() throws {
        let probe = WindowProbe()
        let broadcast = Announce().broadcast
        var window: NSWindow? = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                                         styleMask: [.titled],
                                         backing: .buffered,
                                         defer: false)
        window?.isReleasedWhenClosed = false

        autoreleasepool {
            let hosting = NSHostingView(rootView: ListeningComponent(probe: probe))
            window?.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
        }
        spin()

        XCTAssertNotNil(probe.command, "the component rendered")
        broadcast.send(Announce.Meta(value: 1))
        XCTAssertEqual(probe.heard, [1], "its listener is in place while it is on screen")

        autoreleasepool {
            window?.contentView = nil
            window?.close()
            window = nil
        }
        spin()

        XCTAssertNil(probe.command, "the command went with its views")
        broadcast.send(Announce.Meta(value: 2))
        XCTAssertEqual(probe.heard, [1], "and its listener with it")
    }

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
}

@MainActor
private final class WindowProbe {
    weak var command: GraniteCommand<ListenCenter>?
    var heard: [Int] = []
}

private struct ListenService: GraniteService {
    @Service var center: ListenCenter
    init() {}
}

private struct ListeningComponent: GraniteComponent {
    @Command var center: ListenCenter
    @Relay var service: ListenService
    let probe: WindowProbe

    init(probe: WindowProbe) {
        self.probe = probe
    }

    var listeners: Void {
        service.center.announce.listen(.broadcast("window")) { payload in
            // Captures the component, and through it the command, as app listeners do.
            withExtendedLifetime(self) {}
            probe.heard.append(announced(payload))
        }
    }

    var view: some View {
        let _ = MainActor.assumeIsolated { probe.command = locate?.command }
        Text("listening")
    }
}
#endif

// MARK: Fixtures

/// A log a main-actor handler can append to.
@MainActor
private final class MainLog<Value> {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }
}

private func announced(_ payload: GranitePayload?) -> Int {
    (payload as? Announce.Meta)?.value ?? 0
}

private struct ListenCenter: GraniteCenter {
    struct State: GraniteState {
        var count = 0
    }

    @Event var announce: Announce.Reducer
    @Store var state: State
}

private struct Announce: GraniteReducer {
    typealias Center = ListenCenter
    typealias Metadata = Meta

    struct Meta: GranitePayload {
        let value: Int
    }

    func reduce(state: inout Center.State, payload: Meta) {
        state.count += 1
        broadcast.send(payload)
    }
}
