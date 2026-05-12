import Foundation

public struct ActiveInterval: Codable, Sendable, Equatable {
    public var id: Int64?
    public var startTs: Date
    public var endTs: Date
    public var bundleID: String
    public var appName: String
    public var keyCount: Int
    public var mouseCount: Int

    public var duration: TimeInterval { endTs.timeIntervalSince(startTs) }

    public init(
        id: Int64? = nil,
        startTs: Date,
        endTs: Date,
        bundleID: String,
        appName: String,
        keyCount: Int,
        mouseCount: Int
    ) {
        self.id = id
        self.startTs = startTs
        self.endTs = endTs
        self.bundleID = bundleID
        self.appName = appName
        self.keyCount = keyCount
        self.mouseCount = mouseCount
    }
}

public struct DailyTotal: Codable, Sendable, Equatable {
    public var date: String
    public var bundleID: String
    public var activeSeconds: Int
    public var keys: Int
    public var mouseEvents: Int

    public init(date: String, bundleID: String, activeSeconds: Int, keys: Int, mouseEvents: Int) {
        self.date = date
        self.bundleID = bundleID
        self.activeSeconds = activeSeconds
        self.keys = keys
        self.mouseEvents = mouseEvents
    }
}
