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

/// Sends `value` on `emitter` as it is released: what a captured object's `deinit` might do.
final class SendsOnRelease<Value: Sendable>: @unchecked Sendable {
    private let emitter: GraniteEmitter<Value>
    private let value: Value

    init(_ value: Value, on emitter: GraniteEmitter<Value>) {
        self.emitter = emitter
        self.value = value
    }

    deinit {
        emitter.send(value)
    }
}

/// A mutable reference a test's handlers can share.
final class Holder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }
}
