//  WHAT: The build as the installer hands it to each finisher (`AgentBuildFinishing`), after the runner is built and
//        described and its executable staged, before the executable is hashed and shelved: the installation's name,
//        the staged executable, the runner package and its products folder, the agent package's own folder, and a
//        line to say what the finisher is doing under the install's `finishing <name>` stage.
//
//            build → describe → stage → finishers (AgentBuild) → hash → installation.json → shelf
//
//  PIN:  WHAT A FINISHER WRITES BESIDE THE EXECUTABLE GOES WITH IT. Anything put in `staged` lands on the shelf with
//        the executable; only the executable is hashed (the tamper rule, `AgentShelf`). The runner, its products and
//        the package are read, never written: the first two go with the work folder, the last may be the person's.

import Foundation

/// One build, as a finisher sees it.
public struct AgentBuild: Sendable {
    /// The installation's name: the package's, and its folder's on the shelf.
    public let name: String
    /// The staged executable: the file that will be hashed and shelved.
    public let executable: URL
    /// The runner package the installer wrote and built: its `.build` holds what the build resolved and checked out.
    public let runner: URL
    /// The build's products folder, as `swift build --show-bin-path` names it.
    public let products: URL
    /// The agent package's own folder, as it was fetched, or the folder it was installed from: read it, write nothing.
    public let package: URL
    /// Says a line of what the finisher is doing, shown under the install's `finishing <name>` stage.
    public let say: @Sendable (String) -> Void

    public init(name: String, executable: URL, runner: URL, products: URL, package: URL,
                say: @escaping @Sendable (String) -> Void = { _ in }) {
        self.name = name; self.executable = executable; self.runner = runner; self.products = products; self.package = package
        self.say = say
    }

    /// The folder the executable is staged in: what lands on the shelf with it.
    public var staged: URL { executable.deletingLastPathComponent() }
}
