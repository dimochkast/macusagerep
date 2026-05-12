import Foundation

public struct ResourceSample: Codable, Sendable, Equatable {
    public var id: Int64?
    public var timestamp: Date
    public var bundleID: String
    public var appName: String
    public var cpuPercent: Double
    public var memoryBytes: Int64

    public init(
        id: Int64? = nil,
        timestamp: Date,
        bundleID: String,
        appName: String,
        cpuPercent: Double,
        memoryBytes: Int64
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bundleID = bundleID
        self.appName = appName
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct AppResourceUsage: Sendable, Equatable, Identifiable {
    public let bundleID: String
    public let appName: String
    public let avgCPU: Double
    public let peakCPU: Double
    public let avgMemoryBytes: Int64
    public let peakMemoryBytes: Int64
    public let samples: Int

    public var id: String { bundleID }
}
