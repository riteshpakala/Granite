import XCTest
@testable import Granite

/// Pins the memory contract between a command, its reducers and its listeners: whatever a
/// command wires up goes when the command goes, with no `deinit` doing the work, and the wiring
/// behaves as it did when it was built on signals.
final class TeardownTests: XCTestCase {

    func testReducerWiringFires() {
        let command = GraniteCommand<TeardownCenter>.hosted()
        command.center.bump.send()
        XCTAssertEqual(command.center.state.value, 1)
    }

    /// A component's listeners are applied on appear and removed on disappear. After that,
    /// dropping the command must release its reducers: nothing may keep them subscribed.
    func testCommandTeardownReleasesReducersAfterListenersCycle() {
        weak var weakCommand: GraniteCommand<TeardownCenter>?
        weak var weakReducer: Bump.Reducer?

        do {
            let command = GraniteCommand<TeardownCenter>.hosted()
            weakCommand = command
            weakReducer = command.center.bump

            command.listen(command.id) { }
            command.removeListeners(command.id)
        }

        XCTAssertNil(weakCommand, "the command itself is released")
        XCTAssertNil(weakReducer, "the reducer's subscriptions die with its command")
    }

    /// The reducer used to hold its own container's subscription, which held the reducer: a cycle
    /// only the command's `deinit` broke. Now the container is a weak receiver.
    func testDroppingTheCommandReleasesItsContainersEvenWhileTheReducerLives() throws {
        let reducer: Bump.Reducer
        weak var weakContainer: AnyObject?

        do {
            let command = GraniteCommand<TeardownCenter>.hosted()
            reducer = command.center.bump
            weakContainer = try XCTUnwrap(command.reducers.first)
            XCTAssertEqual(reducer.emitter.receiverCount, 1, "the container receives the reducer's sends")
        }

        XCTAssertNil(weakContainer, "the container went with its command")
        XCTAssertEqual(reducer.emitter.receiverCount, 0)
        reducer.send()   // reaches no one, and must not crash
    }

    func testAPendingDebouncedValueIsDroppedWithItsCommand() {
        let commits = Slow.commits
        let before = commits.count

        do {
            let command = GraniteCommand<TeardownCenter>.hosted()
            command.center.slow.send()
        }

        settle(0.2)
        XCTAssertEqual(commits.count, before, "the debounce went with its container, and its value with it")
    }

    func testADebouncedReducerStillCommitsOnce() {
        let command = GraniteCommand<TeardownCenter>.hosted()
        let commits = Slow.commits
        let before = commits.count

        command.center.slow.send()
        command.center.slow.send()
        command.center.slow.send()

        settle(0.2)
        XCTAssertEqual(commits.count, before + 1)
        withExtendedLifetime(command) {}
    }

    func testSettingAContainerUpAgainKeepsOneSubscription() throws {
        let command = GraniteCommand<TeardownCenter>.hosted()
        let container = try XCTUnwrap(command.reducers.first as? ReducerContainer<Bump.Reducer>)

        container.setup(command)
        XCTAssertEqual(command.center.bump.emitter.receiverCount, 1)

        command.center.bump.send()
        XCTAssertEqual(command.center.state.value, 1, "one send, one commit")
    }

    func testANotifyNudgeFiresTheReducerOnceEvenAfterASecondSetup() throws {
        let command = GraniteCommand<TeardownCenter>.hosted()
        let container = try XCTUnwrap(command.reducers.first { $0.reducerType == Nudged.self } as? ReducerContainer<Nudged.Reducer>)

        Nudged().notifyEmitter.send(EmptyGranitePayload())
        XCTAssertEqual(command.center.state.nudges, 1)

        // The commit's notify fan-out reads the container's coordinator on its queue; a real
        // setup runs once, before any send, so let that finish first.
        container.queue.sync {}
        container.setup(command)
        Nudged().notifyEmitter.send(EmptyGranitePayload())
        XCTAssertEqual(command.center.state.nudges, 2, "the second setup replaced the first subscription")
    }

    /// The notify emitter is shared by every instance of a reducer type, so one command's
    /// container must not displace another's.
    func testANudgeReachesEveryLiveInstanceOfTheReducer() {
        let first = GraniteCommand<TeardownCenter>.hosted()
        let second = GraniteCommand<TeardownCenter>.hosted()

        Nudged().notifyEmitter.send(EmptyGranitePayload())

        XCTAssertEqual(first.center.state.nudges, 1)
        XCTAssertEqual(second.center.state.nudges, 1)
    }

    func testAppearFiresOnAppearReducersWithTheDependencyPayload() {
        let command = GraniteCommand<TeardownCenter>.hosted()
        command.build(.dependency(Boot.Meta(value: 7)))

        command.appear()
        command.thread.sync {}   // the appearance fires on the command's queue

        XCTAssertEqual(command.center.state.booted, 7)
    }

    func testForwardedReducersRunBeforeAndAfterTheirParent() {
        let command = GraniteCommand<TeardownCenter>.hosted()
        let order = Outer.order
        let start = order.count

        command.center.outer.send()

        XCTAssertEqual(Array(order.values.dropFirst(start)), ["before", "outer", "after"])
    }

    func testHostedListenersEndWithRemoveListeners() {
        let command = GraniteCommand<TeardownCenter>.hosted()
        let heard = Recorder<Int>()

        command.listen(command.id) {
            command.center.bump.listen(.bubble("teardown")) { _ in heard.append(1) }
        }
        command.center.bump.send()
        XCTAssertEqual(heard.count, 1, "sent on the main thread, so heard inline")

        command.removeListeners(command.id)
        command.center.bump.send()
        XCTAssertEqual(heard.count, 1)
        XCTAssertEqual(command.center.bump.emitter.receiverCount, 1, "only the container is left")
    }

    /// Waits a fixed span so late, unwanted deliveries would have landed.
    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "settle")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }
}

private struct TeardownCenter: GraniteCenter {
    struct State: GraniteState {
        var value = 0
        var nudges = 0
        var booted = 0
    }

    @Event var bump: Bump.Reducer
    @Event(debounce: 0.05) var slow: Slow.Reducer
    @Event var nudged: Nudged.Reducer
    @Event(.onAppear) var boot: Boot.Reducer
    @Event var outer: Outer.Reducer
    @Store var state: State
}

private struct Bump: GraniteReducer {
    typealias Center = TeardownCenter

    func reduce(state: inout Center.State) {
        state.value += 1
    }
}

private struct Slow: GraniteReducer {
    typealias Center = TeardownCenter

    static let commits = Recorder<Int>()

    func reduce(state: inout Center.State) {
        Self.commits.append(1)
    }
}

private struct Nudged: GraniteReducer {
    typealias Center = TeardownCenter

    var notifiable: Bool { true }

    /// A nudge always arrives with an `EmptyGranitePayload`, which is this reducer's `Metadata`,
    /// so it lands here rather than in `reduce(state:)`.
    func reduce(state: inout Center.State, payload: EmptyGranitePayload) {
        state.nudges += 1
    }
}

private struct Boot: GraniteReducer {
    typealias Center = TeardownCenter
    typealias Metadata = Meta

    struct Meta: GranitePayload {
        let value: Int
    }

    func reduce(state: inout Center.State, payload: Meta) {
        state.booted = payload.value
    }
}

private struct Outer: GraniteReducer {
    typealias Center = TeardownCenter

    static let order = Recorder<String>()

    @Event(.before) var before: Before.Reducer
    @Event(.after) var after: After.Reducer

    func reduce(state: inout Center.State) {
        Self.order.append("outer")
    }
}

private struct Before: GraniteReducer {
    typealias Center = TeardownCenter

    func reduce(state: inout Center.State) {
        Outer.order.append("before")
    }
}

private struct After: GraniteReducer {
    typealias Center = TeardownCenter

    func reduce(state: inout Center.State) {
        Outer.order.append("after")
    }
}
