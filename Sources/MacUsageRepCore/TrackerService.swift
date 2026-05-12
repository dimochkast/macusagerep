#if canImport(AppKit)
import Foundation
import AppKit

public final class TrackerService: IntervalSink, FrontmostProvider {
    public let config: Config
    public let database: Database
    public let counters: InputCounters
    private let eventTap: EventTapCollector
    private let workspace: WorkspaceMonitor
    private var aggregator: SessionAggregator?
    private let resourceSampler: ResourceSampler
    private var heartbeatTimer: DispatchSourceTimer?
    private var rollupTimer: DispatchSourceTimer?
    private var resourceTimer: DispatchSourceTimer?

    public private(set) var currentFrontmost: FrontmostApp = .unknown

    public init(config: Config = .default) throws {
        self.config = config
        self.database = try Database(url: config.databaseURL)
        let counters = InputCounters()
        self.counters = counters
        self.eventTap = EventTapCollector(counters: counters, mouseMoveThreshold: config.mouseMoveThreshold)
        self.workspace = WorkspaceMonitor()
        self.resourceSampler = ResourceSampler()

        let excluded = (try? database.excludedBundleIDs()) ?? []
        let aggregator = SessionAggregator(
            config: config,
            counters: counters,
            sink: self,
            frontmostProvider: self,
            excludedBundleIDs: excluded.union(config.excludedBundleIDs),
            systemIdleSeconds: { IdleMonitor.systemIdleSeconds() }
        )
        self.aggregator = aggregator

        self.workspace.onChange = { [weak self] front in
            self?.currentFrontmost = front
        }
    }

    public func start() throws {
        try eventTap.start()
        workspace.start()
        currentFrontmost = workspace.current

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + config.heartbeatInterval, repeating: config.heartbeatInterval)
        timer.setEventHandler { [weak self] in self?.aggregator?.tick() }
        timer.resume()
        heartbeatTimer = timer

        let rollup = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        rollup.schedule(deadline: .now() + 3_600, repeating: 3_600)
        rollup.setEventHandler { [weak self] in
            guard let self else { return }
            try? self.database.rollupDailyTotals()
            try? self.database.purgeOldData(
                rawRetentionDays: self.config.rawEventRetentionDays,
                intervalRetentionDays: self.config.intervalRetentionDays
            )
        }
        rollup.resume()
        rollupTimer = rollup

        if config.resourceSamplingEnabled {
            let interval = config.resourceSampleInterval
            let resource = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            resource.schedule(deadline: .now() + interval, repeating: interval)
            resource.setEventHandler { [weak self] in
                guard let self else { return }
                let excluded = (try? self.database.excludedBundleIDs()) ?? []
                let merged = excluded.union(self.config.excludedBundleIDs)
                let samples = self.resourceSampler.sample(excluded: merged)
                try? self.database.insertResourceSamples(samples)
            }
            resource.resume()
            resourceTimer = resource
        }
    }

    public func stop() {
        heartbeatTimer?.cancel(); heartbeatTimer = nil
        rollupTimer?.cancel(); rollupTimer = nil
        resourceTimer?.cancel(); resourceTimer = nil
        aggregator?.flushAndClose()
        eventTap.stop()
        workspace.stop()
    }

    public func persist(interval: ActiveInterval) throws -> Int64 {
        let id: Int64
        if let existing = interval.id {
            try database.updateInterval(id: existing, interval)
            id = existing
        } else {
            id = try database.insertInterval(interval)
        }
        try database.upsertApp(AppMetadata(bundleID: interval.bundleID, displayName: interval.appName))
        return id
    }
}
#endif
