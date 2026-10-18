import XCTest
@testable import Granite

/// Pins the memory contract between a command, its listeners and its reducers: whatever a
/// command subscribes is released when the command goes, and listeners can be applied and
/// removed any number of times.
final class ScopeLifecycleTests: XCTestCase {

    func testReducerWiringFires() {
        let command = GraniteCommand<LifecycleCenter>.hosted()
        command.center.bump.send()
        XCTAssertEqual(command.center.state.value, 1)
    }

    /// A component's listeners are applied on appear and removed on disappear. After that,
    /// dropping the command must release its reducers — nothing may keep them subscribed.
    func testCommandTeardownReleasesReducersAfterListenersCycle() {
        weak var weakCommand: GraniteCommand<LifecycleCenter>?
        weak var weakReducer: Bump.Reducer?

        do {
            let command = GraniteCommand<LifecycleCenter>.hosted()
            weakCommand = command
            weakReducer = command.center.bump

            command.listen(command.id) { }
            command.removeListeners(command.id)
        }

        XCTAssertNil(weakCommand, "the command itself is released")
        XCTAssertNil(weakReducer, "the reducer's subscriptions die with its command")
    }

    /// Appearing, disappearing and appearing again must leave the second listener set as
    /// removable as the first. Each step runs in its own autorelease pool, as SwiftUI's
    /// `.onAppear` and `.onDisappear` land on separate run-loop turns.
    func testListenersCanBeReappliedAndRemovedAgain() {
        let command = GraniteCommand<LifecycleCenter>.hosted()
        let signal = GraniteSignal.Payload<Int>()
        var received = 0

        autoreleasepool { command.listen(command.id) { signal += { _ in received += 1 } } }
        autoreleasepool { command.removeListeners(command.id) }

        autoreleasepool { command.listen(command.id) { signal += { _ in received += 1 } } }
        autoreleasepool { command.removeListeners(command.id) }

        signal.send(1)
        XCTAssertEqual(received, 0, "both listener sets were removed")
    }

    func testObserveChangeDeliversNewAndPreviousValue() {
        let signal = GraniteSignal.Payload<Int>()
        var changes: [[Int]] = []
        signal.observeChange { new, old in changes.append([new, old]) }

        signal.send(1)
        signal.send(2)
        signal.send(3)

        XCTAssertEqual(changes, [[2, 1], [3, 2]])
    }
}

private struct LifecycleCenter: GraniteCenter {
    struct State: GraniteState {
        var value = 0
    }

    @Event var bump: Bump.Reducer
    @Store var state: State
}

private struct Bump: GraniteReducer {
    typealias Center = LifecycleCenter

    func reduce(state: inout Center.State) {
        state.value += 1
    }
}
