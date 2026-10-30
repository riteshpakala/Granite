import Foundation
import XCTest

extension XCTestCase {
    /// Waits up to `timeout` seconds for `condition`, polling, while main stays free to drain frames.
    @MainActor
    func until(_ timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
