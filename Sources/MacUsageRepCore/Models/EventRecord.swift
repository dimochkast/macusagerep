import Foundation

public enum InputKind: String, Codable, Sendable {
    case key
    case mouse
}

public struct EventRecord: Codable, Sendable, Equatable {
    public var id: Int64?
    public var timestamp: Date
    public var bundleID: String
    public var kind: InputKind
    public var count: Int

    public init(id: Int64? = nil, timestamp: Date, bundleID: String, kind: InputKind, count: Int) {
        self.id = id
        self.timestamp = timestamp
        self.bundleID = bundleID
        self.kind = kind
        self.count = count
    }
}
