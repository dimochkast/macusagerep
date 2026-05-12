import Foundation

public struct Config {
    public var idleCutoff: TimeInterval
    public var heartbeatInterval: TimeInterval
    public var flushInterval: TimeInterval
    public var rawEventRetentionDays: Int
    public var intervalRetentionDays: Int
    public var mouseMoveThreshold: Double
    public var storageDirectory: URL
    public var excludedBundleIDs: Set<String>
    public var resourceSampleInterval: TimeInterval
    public var resourceSamplingEnabled: Bool

    public static let `default` = Config(
        idleCutoff: 30,
        heartbeatInterval: 1,
        flushInterval: 30,
        rawEventRetentionDays: 7,
        intervalRetentionDays: 180,
        mouseMoveThreshold: 4,
        storageDirectory: Config.defaultStorageDirectory(),
        excludedBundleIDs: [],
        resourceSampleInterval: 10,
        resourceSamplingEnabled: true
    )

    public init(
        idleCutoff: TimeInterval,
        heartbeatInterval: TimeInterval,
        flushInterval: TimeInterval,
        rawEventRetentionDays: Int,
        intervalRetentionDays: Int,
        mouseMoveThreshold: Double,
        storageDirectory: URL,
        excludedBundleIDs: Set<String>,
        resourceSampleInterval: TimeInterval = 10,
        resourceSamplingEnabled: Bool = true
    ) {
        self.idleCutoff = idleCutoff
        self.heartbeatInterval = heartbeatInterval
        self.flushInterval = flushInterval
        self.rawEventRetentionDays = rawEventRetentionDays
        self.intervalRetentionDays = intervalRetentionDays
        self.mouseMoveThreshold = mouseMoveThreshold
        self.storageDirectory = storageDirectory
        self.excludedBundleIDs = excludedBundleIDs
        self.resourceSampleInterval = resourceSampleInterval
        self.resourceSamplingEnabled = resourceSamplingEnabled
    }

    public static func defaultStorageDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MacUsageRep", isDirectory: true)
    }

    public var databaseURL: URL {
        storageDirectory.appendingPathComponent("macusagerep.sqlite")
    }
}
