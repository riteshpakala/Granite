import XCTest
@testable import Granite

final class ProspectTests: XCTestCase {

    func testObservingInsideWithScopeStoresInThatScope() {
        let scope = Prospect(label: "owner", type: .custom, parent: nil)
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()

        scope.withScope {
            signal += { received.append($0) }
        }
        XCTAssertEqual(scope.subscriptionCount, 1)

        scope.cancel()
        signal.send(1)

        XCTAssertTrue(received.values.isEmpty)
        XCTAssertEqual(signal.observerCount, 0)
    }

    func testNoScopeIsBoundOutsideWithScope() {
        XCTAssertNil(Prospector.current)
        let scope = Prospect(label: "owner", type: .custom, parent: nil)
        scope.withScope { XCTAssertTrue(Prospector.current === scope) }
        XCTAssertNil(Prospector.current)
    }

    func testNestedScopesRestoreTheOuterBinding() {
        let outer = Prospect(label: "outer", type: .custom, parent: nil)
        let inner = outer.child(label: "inner", type: .custom)

        outer.withScope {
            inner.withScope { XCTAssertTrue(Prospector.current === inner) }
            XCTAssertTrue(Prospector.current === outer)
        }
    }

    func testScopesCreatedInsideWithScopeBecomeChildren() {
        let parent = Prospect(label: "parent", type: .custom, parent: nil)
        let child = parent.withScope { Prospect(label: "child", type: .custom) }

        XCTAssertTrue(child.parent === parent)
        XCTAssertEqual(parent.childScopes, [child])
    }

    func testCancelCascadesToChildren() {
        let parent = Prospect(label: "parent", type: .custom, parent: nil)
        let child = parent.child(label: "child", type: .custom)
        let grandchild = child.child(label: "grandchild", type: .custom)
        let signal = GraniteSignal.Payload<Int>()
        let token = signal.observe(in: grandchild) { _ in }

        parent.cancel()

        XCTAssertTrue(child.isCancelled)
        XCTAssertTrue(grandchild.isCancelled)
        XCTAssertTrue(token.isCancelled)
        XCTAssertEqual(signal.observerCount, 0)
    }

    func testCancellingAChildLeavesTheParentRunning() {
        let parent = Prospect(label: "parent", type: .custom, parent: nil)
        let child = parent.child(label: "child", type: .custom)
        let signal = GraniteSignal.Payload<Int>()
        let parentToken = signal.observe(in: parent) { _ in }

        child.cancel()

        XCTAssertFalse(parent.isCancelled)
        XCTAssertFalse(parentToken.isCancelled)
        XCTAssertTrue(parent.childScopes.isEmpty, "a cancelled child detaches")
    }

    func testReleasingAScopeEndsItsSubscriptions() {
        let signal = GraniteSignal.Payload<Int>()
        let received = Recorder<Int>()

        do {
            let scope = Prospect(label: "owner", type: .custom, parent: nil)
            scope.withScope { signal += { received.append($0) } }
        }
        signal.send(1)

        XCTAssertTrue(received.values.isEmpty)
        XCTAssertEqual(signal.observerCount, 0)
    }

    func testParentsHoldChildrenWeakly() {
        let parent = Prospect(label: "parent", type: .custom, parent: nil)
        weak var weakChild: Prospect?

        do {
            let child = parent.child(label: "child", type: .custom)
            weakChild = child
            XCTAssertEqual(parent.childScopes.count, 1)
        }

        XCTAssertNil(weakChild)
        XCTAssertTrue(parent.childScopes.isEmpty)
    }

    func testStoringIntoAnEndedScopeCancelsImmediately() {
        let scope = Prospect(label: "owner", type: .custom, parent: nil)
        scope.cancel()

        let signal = GraniteSignal.Payload<Int>()
        let token = signal.observe(in: scope) { _ in }

        XCTAssertTrue(token.isCancelled)
        XCTAssertEqual(signal.observerCount, 0)
    }

    func testAChildOfAnEndedScopeStartsEnded() {
        let parent = Prospect(label: "parent", type: .custom, parent: nil)
        parent.cancel()

        let child = parent.child(label: "child", type: .custom)
        XCTAssertTrue(child.isCancelled)
    }

    func testAttachMovesAScopeBetweenParents() {
        let first = Prospect(label: "first", type: .custom, parent: nil)
        let second = Prospect(label: "second", type: .custom, parent: nil)
        let child = first.child(label: "child", type: .custom)

        child.attach(to: second)

        XCTAssertTrue(child.parent === second)
        XCTAssertTrue(first.childScopes.isEmpty)
        XCTAssertEqual(second.childScopes, [child])

        first.cancel()
        XCTAssertFalse(child.isCancelled, "the old parent no longer reaches it")
        second.cancel()
        XCTAssertTrue(child.isCancelled)
    }

    func testAttachingToAnEndedParentEndsTheScope() {
        let ended = Prospect(label: "ended", type: .custom, parent: nil)
        ended.cancel()
        let scope = Prospect(label: "scope", type: .custom, parent: nil)

        scope.attach(to: ended)
        XCTAssertTrue(scope.isCancelled)
    }

    func testAttachingUnderADescendantIsIgnored() {
        let parent = Prospect(label: "parent", type: .custom, parent: nil)
        let child = parent.child(label: "child", type: .custom)

        parent.attach(to: child)

        XCTAssertNil(parent.parent)
        XCTAssertTrue(child.parent === parent)
    }

    func testTopLevelScopesAreListedUntilAttachedOrEnded() {
        let root = Prospect(label: "root-\(UUID())", type: .custom, parent: nil)
        let other = Prospect(label: "other-\(UUID())", type: .custom, parent: nil)
        XCTAssertTrue(Prospector.roots.contains(root))

        root.attach(to: other)
        XCTAssertFalse(Prospector.roots.contains(root))
        XCTAssertTrue(Prospector.find(id: root.id) === root)

        other.cancel()
        XCTAssertFalse(Prospector.roots.contains(other))
        XCTAssertNil(Prospector.find(id: root.id))
    }

    func testTasksInheritTheScopeAndDetachedTasksDoNot() async {
        let scope = Prospect(label: "owner", type: .custom, parent: nil)

        let inherited = await Prospector.withScope(scope) {
            Task { Prospector.current }
        }.value
        let detached = await Prospector.withScope(scope) {
            Task.detached { Prospector.current }
        }.value

        XCTAssertTrue(inherited === scope)
        XCTAssertNil(detached)
    }

    /// Many threads building scopes at once: each binding is private to its own thread, so no
    /// subscription lands in another iteration's scope.
    func testConcurrentScopesNeverCrossAttach() {
        let signal = GraniteSignal.Payload<Int>()
        let mismatches = Recorder<Int>()
        let parent = Prospect(label: "parent", type: .custom, parent: nil)

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            let scope = parent.child(label: "iteration \(index)", type: .custom)
            scope.withScope {
                signal += { _ in }
                if Prospector.current !== scope { mismatches.append(index) }
            }
            if scope.subscriptionCount != 1 { mismatches.append(index) }
            scope.cancel()
        }

        XCTAssertTrue(mismatches.values.isEmpty)
        XCTAssertEqual(signal.observerCount, 0)
        XCTAssertTrue(parent.childScopes.isEmpty)
    }

    func testConcurrentCancelOfATreeIsSafe() {
        let root = Prospect(label: "root", type: .custom, parent: nil)
        let signal = GraniteSignal.Payload<Int>()
        let children = (0..<200).map { root.child(label: "child \($0)", type: .custom) }
        for child in children {
            signal.observe(in: child) { _ in }
        }

        DispatchQueue.concurrentPerform(iterations: children.count + 1) { index in
            if index == children.count {
                root.cancel()
            } else {
                children[index].cancel()
            }
        }

        XCTAssertTrue(children.allSatisfy(\.isCancelled))
        XCTAssertEqual(signal.observerCount, 0)
    }
}
