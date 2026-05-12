import Foundation

public protocol IntervalSink: AnyObject {
    /// Persists the interval. If `interval.id` is nil, inserts a new row and returns
    /// the assigned id. If `interval.id` is set, updates the existing row in place
    /// and returns the same id. This lets the aggregator flush an open interval
    /// repeatedly for crash-safety without creating duplicate rows.
    func persist(interval: ActiveInterval) throws -> Int64
}

public protocol FrontmostProvider: AnyObject {
    var currentFrontmost: FrontmostApp { get }
}

public final class SessionAggregator {
    private let config: Config
    private let counters: InputCounters
    private weak var sink: IntervalSink?
    private weak var frontmostProvider: FrontmostProvider?
    private let clock: () -> Date
    private let systemIdleSeconds: () -> TimeInterval

    private var openInterval: ActiveInterval?
    private var lastFlushAt: Date = .distantPast
    private var excluded: Set<String>

    public init(
        config: Config,
        counters: InputCounters,
        sink: IntervalSink,
        frontmostProvider: FrontmostProvider,
        excludedBundleIDs: Set<String> = [],
        clock: @escaping () -> Date = { Date() },
        systemIdleSeconds: @escaping () -> TimeInterval = { 0 }
    ) {
        self.config = config
        self.counters = counters
        self.sink = sink
        self.frontmostProvider = frontmostProvider
        self.excluded = excludedBundleIDs
        self.clock = clock
        self.systemIdleSeconds = systemIdleSeconds
    }

    public func updateExclusions(_ set: Set<String>) { excluded = set }

    public var openIntervalSnapshot: ActiveInterval? { openInterval }

    public func tick() {
        let now = clock()
        let drain = counters.drain()
        let lastInput = drain.lastInput
        let appState = frontmostProvider?.currentFrontmost ?? .unknown
        let idleFromEvents = lastInput == .distantPast ? .greatestFiniteMagnitude : now.timeIntervalSince(lastInput)
        let idleFromSystem = systemIdleSeconds()
        let idleFor = min(idleFromEvents, idleFromSystem.isFinite ? idleFromSystem : idleFromEvents)
        let isExcluded = excluded.contains(appState.bundleID)

        if let open = openInterval {
            let switched = open.bundleID != appState.bundleID
            if idleFor > config.idleCutoff || switched || isExcluded {
                var closed = open
                let candidateEnd = min(now, lastInput == .distantPast ? now : lastInput)
                closed.endTs = max(closed.startTs, candidateEnd)
                if closed.endTs > closed.startTs {
                    _ = try? sink?.persist(interval: closed)
                }
                openInterval = nil
            }
        }

        guard !isExcluded, idleFor <= config.idleCutoff else {
            return
        }

        if openInterval == nil {
            let start = (lastInput == .distantPast) ? now : lastInput
            openInterval = ActiveInterval(
                startTs: start,
                endTs: now,
                bundleID: appState.bundleID,
                appName: appState.name,
                keyCount: 0,
                mouseCount: 0
            )
            lastFlushAt = now
        }

        if var open = openInterval {
            open.endTs = now
            open.keyCount += drain.keys
            open.mouseCount += drain.mouse
            openInterval = open
        }

        if now.timeIntervalSince(lastFlushAt) >= config.flushInterval, var open = openInterval {
            if let id = try? sink?.persist(interval: open) {
                open.id = id
                openInterval = open
            }
            lastFlushAt = now
        }
    }

    public func flushAndClose() {
        guard var open = openInterval else { return }
        open.endTs = clock()
        if open.endTs > open.startTs {
            _ = try? sink?.persist(interval: open)
        }
        openInterval = nil
    }
}
