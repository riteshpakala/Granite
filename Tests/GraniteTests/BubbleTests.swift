#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import Granite

/// Hosts real view trees in a window to check bubbling end to end: which route takes an
/// action, what a reducer route sends, and that nothing the routes capture outlives the views
/// that installed them.
@MainActor
final class BubbleTests: XCTestCase {

    // MARK: Resolution

    func testTheNearestRouteTakesAnAction() throws {
        let probe = BubbleProbe()
        var window: NSWindow? = host(
            Leaf(probe: probe)
                .onBubble { On(.ping) { probe.log.append("inner") } }
                .onBubble { On(.ping) { probe.log.append("outer") } }
        )

        XCTAssertTrue(probe.handle(.ping))
        XCTAssertEqual(probe.log, ["inner"], "only the nearest route ran")
        close(&window)
    }

    func testAnActionTheNearestInstallerDoesNotRoutePassesUp() throws {
        let probe = BubbleProbe()
        var window: NSWindow? = host(
            Leaf(probe: probe)
                .onBubble { On(.ping) { probe.log.append("inner ping") } }
                .onBubble { On(.pong) { probe.log.append("outer pong") } }
        )

        XCTAssertTrue(probe.handle(.pong))
        XCTAssertEqual(probe.log, ["outer pong"])
        close(&window)
    }

    func testNamesAndTypesKeepRoutesApart() throws {
        let probe = BubbleProbe()
        var window: NSWindow? = host(
            Leaf(probe: probe)
                .onBubble {
                    On(.ping) { probe.log.append("ping") }
                    On(.pong) { probe.log.append("pong") }
                    On { (value: Int) in probe.log.append("int \(value)") }
                    On(.ping) { (value: Int) in probe.log.append("ping int \(value)") }
                }
        )

        probe.handle(.pong)
        probe.handle(5)
        probe.handle(.ping, 6)
        probe.handle(.ping)
        XCTAssertFalse(probe.handle("seven"), "no route takes an unnamed String")
        XCTAssertFalse(probe.handle(.pong, 8), "nor .pong with an Int")
        XCTAssertEqual(probe.log, ["pong", "int 5", "ping int 6", "ping"])
        close(&window)
    }

    func testNothingTakesAnActionWithoutAnInstaller() {
        let probe = BubbleProbe()
        var window: NSWindow? = host(Leaf(probe: probe))

        XCTAssertFalse(probe.handle(.ping))
        XCTAssertFalse(GraniteBubble()(.ping), "the environment default routes nowhere")
        close(&window)
    }

    func testAViewThatDeclaresBubbleCallsTheHandleNotTheModifier() {
        let probe = BubbleProbe()
        var window: NSWindow? = host(
            Shadowing(probe: probe)
                .onBubble { On(.ping) { probe.log.append("ping") } }
        )

        probe.fire?()
        XCTAssertEqual(probe.log, ["ping"], "`bubble(.ping)` in a method reached the route")
        close(&window)
    }

    // MARK: Reducers

    func testAReducerRouteSendsTheBubbledPayload() {
        let probe = BubbleProbe()
        let vote = GraniteReducerExecutable<VoteReducer>()
        vote.listen(.bubble("test")) { probe.log.append("vote \(($0 as? Meta)?.value ?? 0)") }

        var window: NSWindow? = host(
            Leaf(probe: probe).onBubble { vote.on() }
        )

        XCTAssertTrue(probe.handle(Meta(value: 3)))
        XCTAssertEqual(probe.log, ["vote 3"])
        close(&window)
    }

    func testMappersLetReducersShareAnInputUnderTheirOwnNames() {
        let probe = BubbleProbe()
        let up = GraniteReducerExecutable<UpReducer>()
        let down = GraniteReducerExecutable<DownReducer>()
        up.listen(.bubble("test")) { probe.log.append("up \(($0 as? Meta)?.value ?? 0)") }
        down.listen(.bubble("test")) { probe.log.append("down \(($0 as? Meta)?.value ?? 0)") }

        var window: NSWindow? = host(
            Leaf(probe: probe).onBubble {
                up.on(.upvote) { (post: Post) in Meta(value: post.score + 1) }
                down.on(.downvote) { (post: Post) in Meta(value: post.score - 1) }
            }
        )

        probe.handle(.upvote, Post(score: 10))
        probe.handle(.downvote, Post(score: 10))
        XCTAssertEqual(probe.log, ["up 11", "down 9"])
        close(&window)
    }

    func testSideEffectsRunBeforeTheReducerIsSent() {
        let probe = BubbleProbe()
        let vote = GraniteReducerExecutable<VoteReducer>()
        let refresh = GraniteReducerExecutable<RefreshReducer>()
        vote.listen(.bubble("test")) { probe.log.append("vote \(($0 as? Meta)?.value ?? 0)") }
        refresh.listen(.bubble("test")) { probe.log.append("refresh \($0 == nil ? "bare" : "payload")") }

        var window: NSWindow? = host(
            Leaf(probe: probe).onBubble {
                vote.on(.reply) { (meta: Meta) in probe.log.append("effect \(meta.value)") }
                refresh.on(.refresh) { probe.log.append("effect") }
            }
        )

        probe.handle(.reply, Meta(value: 4))
        probe.handle(.refresh)
        XCTAssertEqual(probe.log, ["effect 4", "vote 4", "effect", "refresh bare"])
        close(&window)
    }

    func testAClosureReturningThePayloadIsAMapperNotASideEffect() {
        let probe = BubbleProbe()
        let vote = GraniteReducerExecutable<VoteReducer>()
        let up = GraniteReducerExecutable<UpReducer>()
        vote.listen(.bubble("test")) { probe.log.append("vote \(($0 as? Meta)?.value ?? 0)") }
        up.listen(.bubble("test")) { probe.log.append("up \(($0 as? Meta)?.value ?? 0)") }

        var window: NSWindow? = host(
            Leaf(probe: probe).onBubble {
                vote.on(.reply) { (meta: Meta) in Meta(value: meta.value * 2) }
                up.on(.upvote) { Meta(value: 7) }
            }
        )

        probe.handle(.reply, Meta(value: 3))
        probe.handle(.upvote)
        XCTAssertEqual(probe.log, ["vote 6", "up 7"],
                       "Meta -> Meta maps, and a payload built from nothing is sent on the bare name")
        close(&window)
    }

    func testAPayloadlessReducerIsReachedByName() {
        let probe = BubbleProbe()
        let refresh = GraniteReducerExecutable<RefreshReducer>()
        refresh.listen(.bubble("test")) { probe.log.append("refresh \($0 == nil ? "bare" : "payload")") }

        var window: NSWindow? = host(
            Leaf(probe: probe).onBubble { refresh.on(.refresh) }
        )

        XCTAssertTrue(probe.handle(.refresh))
        XCTAssertEqual(probe.log, ["refresh bare"])
        close(&window)
    }

    // MARK: Validation

    func testProblemsFlagDuplicateKeysAndUnreachableRoutes() {
        let refresh = GraniteReducerExecutable<RefreshReducer>()
        let vote = GraniteReducerExecutable<VoteReducer>()

        XCTAssertEqual(GraniteBubbleNode.problems(in: [
            On(.ping) {},
            On(.pong) {},
            On { (_: Int) in },
            On(.ping) { (_: Int) in },
            vote.on(),
            refresh.on(.refresh),
        ]), [], "a valid set has no problems")

        XCTAssertEqual(GraniteBubbleNode.problems(in: [On(.ping) {}, On(.ping) {}]).count, 1,
                       "two routes keyed (.ping, Void)")
        XCTAssertEqual(GraniteBubbleNode.problems(in: [vote.on(), On { (_: Meta) in }]).count, 1,
                       "a reducer route and a closure route keyed (unnamed, Meta)")
        XCTAssertEqual(GraniteBubbleNode.problems(in: [refresh.on()]).count, 1,
                       "an unnamed payload-less reducer route is unreachable")
        XCTAssertEqual(GraniteBubbleNode.problems(in: [refresh.on { }]).count, 1,
                       "with a side effect too")
        XCTAssertEqual(GraniteBubbleNode.problems(in: [On { (_: Void) in }]).count, 1,
                       "so is an unnamed route for Void")
    }

    // MARK: Memory

    func testARedrawKeepsTheHandleAndRunsTheLatestRoute() {
        let probe = BubbleProbe()
        let model = Model()
        var window: NSWindow? = host(Counter(model: model, probe: probe))

        let first = probe.handle
        probe.handle(.ping)
        XCTAssertEqual(probe.leafRenders, 1)

        model.count = 1
        spin()

        XCTAssertGreaterThan(probe.counterRenders, 1, "the installer's parent redrew")
        XCTAssertEqual(probe.handle, first, "the handle is the same node after the redraw")
        XCTAssertEqual(probe.leafRenders, 1, "so the leaf reading it was not invalidated")
        probe.handle(.ping)
        XCTAssertEqual(probe.log, ["count 0", "count 1"], "and the route that ran is the latest one")
        close(&window)
    }

    func testClosingTheWindowReleasesWhatRoutesCapture() {
        let probe = BubbleProbe()
        weak var tracked: Tracker?
        var window: NSWindow?

        autoreleasepool {
            let tracker = Tracker()
            tracked = tracker
            window = host(
                Leaf(probe: probe)
                    .onBubble { On(.ping) { tracker.hits += 1 } }
            )
        }

        XCTAssertTrue(probe.handle(.ping))
        XCTAssertEqual(tracked?.hits, 1)

        close(&window)

        XCTAssertNil(tracked, "the route's capture ended with the views")
        XCTAssertFalse(probe.handle(.ping), "and a handle kept past them bubbles nowhere")
    }

    // MARK: Hosting

    private func host<V: View>(_ view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        autoreleasepool {
            let hosting = NSHostingView(rootView: view)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
        }
        spin()
        return window
    }

    private func close(_ window: inout NSWindow?) {
        autoreleasepool {
            window?.contentView = nil
            window?.close()
            window = nil
        }
        spin()
    }

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
}

// MARK: Fixtures

extension GraniteBubble.Name {
    fileprivate static let ping: Self = "ping"
    fileprivate static let pong: Self = "pong"
    fileprivate static let upvote: Self = "upvote"
    fileprivate static let downvote: Self = "downvote"
    fileprivate static let reply: Self = "reply"
    fileprivate static let refresh: Self = "refresh"
}

@MainActor
private final class BubbleProbe {
    var handle = GraniteBubble()
    var fire: (() -> Void)?
    var log: [String] = []
    var leafRenders = 0
    var counterRenders = 0
}

private final class Tracker {
    var hits = 0
}

@MainActor
private final class Model: ObservableObject {
    @Published var count = 0
}

/// Stores the handle it is given, as any view sending bubbles from code would read it.
private struct Leaf: View {
    let probe: BubbleProbe
    @Environment(\.graniteBubble) var bubble

    var body: some View {
        let _ = probe.handle = bubble
        let _ = probe.leafRenders += 1
        Text("leaf")
    }
}

/// Declares `bubble` and calls it from a method, where the `.bubble(_:)` modifier is also in scope.
private struct Shadowing: View {
    let probe: BubbleProbe
    @Environment(\.graniteBubble) var bubble

    func fire() {
        bubble(.ping)
    }

    var body: some View {
        let _ = probe.fire = { self.fire() }
        Text("shadowing")
    }
}

private struct Counter: View {
    @ObservedObject var model: Model
    let probe: BubbleProbe

    var body: some View {
        let count = model.count
        let _ = probe.counterRenders += 1
        VStack {
            Text("\(count)")
            Leaf(probe: probe)
                .onBubble { On(.ping) { probe.log.append("count \(count)") } }
        }
    }
}

private struct Post {
    let score: Int
}

private struct Meta: GranitePayload {
    let value: Int
}

private struct BubbleCenter: GraniteCenter {
    struct State: GraniteState {}

    @Store var state: State
}

private struct VoteReducer: GraniteReducer {
    typealias Center = BubbleCenter
    typealias Metadata = Meta

    func reduce(state: inout Center.State, payload: Meta) {}
}

private struct UpReducer: GraniteReducer {
    typealias Center = BubbleCenter
    typealias Metadata = Meta

    func reduce(state: inout Center.State, payload: Meta) {}
}

private struct DownReducer: GraniteReducer {
    typealias Center = BubbleCenter
    typealias Metadata = Meta

    func reduce(state: inout Center.State, payload: Meta) {}
}

private struct RefreshReducer: GraniteReducer {
    typealias Center = BubbleCenter

    func reduce(state: inout Center.State) {}
}
#endif
