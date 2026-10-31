import Foundation
import GraniteAgents

/// A worker spec with a record in this test binary, saying everything a spec can.
enum ScoutWorker: GraniteWorkerSpec {
    static let word = "scout"
    static let summary = "maps a folder it is pointed at and says what each file is for."
    static let toolNames = ["read_file", "list_files"]
    static let budget = WorkerBudget.shell
    static let shell = true
    static let reportRule: String? = "List every file with one line."

    static func opening(word: String, project: String) -> String? {
        "You are a \(word), mapping \(project)."
    }
}

@used @section("__DATA_CONST,__granite")
let scoutRecord: GraniteRoster.Record = { GraniteRoster.record(worker: ScoutWorker.self) }
