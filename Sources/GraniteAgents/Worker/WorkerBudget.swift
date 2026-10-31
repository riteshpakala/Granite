import Foundation

/// How far a worker may go, in the app's own measure: the rounds it gives a worker that reads, or the
/// longer budget of one that runs commands.
public enum WorkerBudget: String, Sendable, Codable, CaseIterable {
    case reading
    case shell
}
