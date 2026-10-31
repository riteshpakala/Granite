import Foundation
import GraniteAgents

/// A worker spec that says only its word and what it does: every other line is the app's.
enum QuietWorker: GraniteWorkerSpec {
    static let word = "quiet"
    static let summary = "reads what it is pointed at."
}
