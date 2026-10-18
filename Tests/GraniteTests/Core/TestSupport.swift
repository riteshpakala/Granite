import Foundation
@testable import Granite

/// A thread-safe recorder for values delivered to handlers under test.
final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }

    var values: [Value] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    var count: Int { values.count }
}

/// An object whose lifetime a test can watch through a weak reference.
final class Probe: @unchecked Sendable {}
