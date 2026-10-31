import Foundation

/// What one call's process took, measured by the host when it reaped it: the measure a scheduler places a call
/// by, and what a person reads when an agent was slow or large.
public struct AgentProcessCost: Codable, Sendable, Equatable {
    /// From the spawn to the exit.
    public var seconds: Double
    /// User and system time.
    public var cpuSeconds: Double
    /// The most memory it held at once.
    public var peakBytes: Int64
    /// How it ended: `exit 0`, `exit 1`, `signal 9`.
    public var status: String

    public init(seconds: Double, cpuSeconds: Double, peakBytes: Int64, status: String) {
        self.seconds = seconds; self.cpuSeconds = cpuSeconds; self.peakBytes = peakBytes; self.status = status
    }

    /// "released · peak 412 MB · 1.8 s CPU in 2.4 s"
    public var sentence: String {
        let megabytes = Double(peakBytes) / 1_048_576
        let peak = megabytes >= 1024 ? String(format: "%.1f GB", megabytes / 1024) : String(format: "%.0f MB", megabytes)
        return "released · peak \(peak) · " + String(format: "%.1f s CPU in %.1f s", cpuSeconds, seconds)
    }
}
