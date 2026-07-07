import XCTest
@testable import GraniteUI

final class GraniteUITests: XCTestCase {
    func testInteractionPublisherIsAvailable() {
        // Smoke test: the interaction publisher accessor produces a publisher without
        // relying on shared mutable global state (see the Swift 6 concurrency fix).
        _ = GraniteInteraction.Tranlate.publisher
    }
}
