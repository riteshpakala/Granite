//  WHAT: A serial async queue: bodies run one after another in arrival order. Granite's effects run
//        concurrently and nothing else would serialize them, so a write path, a refresh or a keeper's
//        making goes through a lane when it must run one at a time.
//  PIN:  Cancelling a caller cancels its own body; the rest of the queue is unaffected.

public actor GraniteLane {
    private var tail: Task<Void, Never>?

    public init() {}

    public func run<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, any Error> {
            await previous?.value
            try Task.checkCancellation()
            return try await body()
        }
        tail = Task { _ = try? await task.value }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
