#if os(macOS)
import Foundation

/// How many of one agent's processes run at once: its `lanes`. A call past them waits for one to end.
actor RemoteLanes {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = max(1, limit) }

    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        if running >= limit { await withCheckedContinuation { waiting.append($0) } } else { running += 1 }
        defer { release() }
        return try await body()
    }

    private func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }
}
#endif
