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
    /// How many times it asked the host's model, counted by the host as the asks came.
    public var asks: Int

    public init(seconds: Double, cpuSeconds: Double, peakBytes: Int64, status: String, asks: Int = 0) {
        self.seconds = seconds; self.cpuSeconds = cpuSeconds; self.peakBytes = peakBytes; self.status = status; self.asks = asks
    }

    private enum Keys: String, CodingKey { case seconds, cpuSeconds, peakBytes, status, asks }

    /// A cost recorded before asks were counted reads as none.
    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        seconds = try keyed.decode(Double.self, forKey: .seconds)
        cpuSeconds = try keyed.decode(Double.self, forKey: .cpuSeconds)
        peakBytes = try keyed.decode(Int64.self, forKey: .peakBytes)
        status = try keyed.decode(String.self, forKey: .status)
        asks = try keyed.decodeIfPresent(Int.self, forKey: .asks) ?? 0
    }

    /// "released · peak 412 MB · 1.8 s CPU in 2.4 s"
    public var sentence: String {
        let megabytes = Double(peakBytes) / 1_048_576
        let peak = megabytes >= 1024 ? String(format: "%.1f GB", megabytes / 1024) : String(format: "%.0f MB", megabytes)
        return "released · peak \(peak) · " + String(format: "%.1f s CPU in %.1f s", cpuSeconds, seconds)
    }
}
