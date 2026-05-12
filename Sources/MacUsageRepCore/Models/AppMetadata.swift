import Foundation

public struct AppMetadata: Codable, Sendable, Equatable {
    public var bundleID: String
    public var displayName: String
    public var category: String?
    public var excluded: Bool

    public init(bundleID: String, displayName: String, category: String? = nil, excluded: Bool = false) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.category = category
        self.excluded = excluded
    }
}

public struct FrontmostApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    public static let unknown = FrontmostApp(bundleID: "unknown", name: "Unknown")
}
