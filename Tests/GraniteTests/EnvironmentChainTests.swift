#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import Granite

/// Hosts real components in a window to check the environment chain end to end: a child
/// component's command joins its parent component's scope, and tearing the views down ends
/// both scopes.
@MainActor
final class EnvironmentChainTests: XCTestCase {

    func testAChildComponentsCommandJoinsItsParentsScope() throws {
        let probe = ChainProbe()
        var window: NSWindow? = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                                         styleMask: [.titled],
                                         backing: .buffered,
                                         defer: false)
        window?.isReleasedWhenClosed = false

        autoreleasepool {
            let host = NSHostingView(rootView: ParentComponent(probe: probe))
            window?.contentView = host
            host.layoutSubtreeIfNeeded()
        }
        spin()

        let parent = try XCTUnwrap(probe.parent, "the parent component rendered")
        let child = try XCTUnwrap(probe.child, "the child component rendered")
        XCTAssertTrue(child.parent === parent, "the child's command scope sits under the parent's")
        XCTAssertFalse(child.isCancelled)

        autoreleasepool {
            window?.contentView = nil
            window?.close()
            window = nil
        }
        spin()

        XCTAssertTrue(parent.isCancelled, "the parent's command ended with its view")
        XCTAssertTrue(child.isCancelled, "and its child scope with it")
    }

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
}

@MainActor
private final class ChainProbe {
    var parent: Prospect?
    var child: Prospect?
}

private struct ChainCenter: GraniteCenter {
    struct State: GraniteState {}

    @Store var state: State
}

private struct ParentComponent: GraniteComponent {
    @Command var center: ChainCenter
    let probe: ChainProbe

    init(probe: ChainProbe) {
        self.probe = probe
    }

    var view: some View {
        let _ = MainActor.assumeIsolated { probe.parent = locate?.command.prospect }
        ChildComponent(probe: probe)
    }
}

private struct ChildComponent: GraniteComponent {
    @Command var center: ChainCenter
    let probe: ChainProbe

    init(probe: ChainProbe) {
        self.probe = probe
    }

    var view: some View {
        let _ = MainActor.assumeIsolated { probe.child = locate?.command.prospect }
        Text("child")
    }
}
#endif
