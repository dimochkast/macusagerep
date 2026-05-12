import XCTest
@testable import MacUsageRepCore

final class SessionAggregatorTests: XCTestCase {
    final class Recorder: IntervalSink {
        /// Simulates a DB: INSERT on first persist (id == nil), UPDATE otherwise.
        /// After each call `rows[id]` holds the latest state, so test assertions
        /// see the same de-duplicated shape the real DB would.
        var rows: [Int64: ActiveInterval] = [:]
        var inserts: Int = 0
        var updates: Int = 0
        private var nextID: Int64 = 1

        func persist(interval: ActiveInterval) throws -> Int64 {
            if let id = interval.id {
                rows[id] = interval
                updates += 1
                return id
            }
            let id = nextID; nextID += 1
            var copy = interval; copy.id = id
            rows[id] = copy
            inserts += 1
            return id
        }

        var intervals: [ActiveInterval] {
            rows.keys.sorted().compactMap { rows[$0] }
        }
    }

    final class FrontStub: FrontmostProvider {
        var currentFrontmost: FrontmostApp
        init(_ app: FrontmostApp) { self.currentFrontmost = app }
    }

    private func makeConfig(idle: TimeInterval = 30, flush: TimeInterval = 30) -> Config {
        Config(
            idleCutoff: idle,
            heartbeatInterval: 1,
            flushInterval: flush,
            rawEventRetentionDays: 7,
            intervalRetentionDays: 180,
            mouseMoveThreshold: 4,
            storageDirectory: FileManager.default.temporaryDirectory,
            excludedBundleIDs: []
        )
    }

    func testOpensIntervalWhenUserActive() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let counters = InputCounters(clock: { now })
        let recorder = Recorder()
        let front = FrontStub(FrontmostApp(bundleID: "com.apple.Safari", name: "Safari"))
        let agg = SessionAggregator(
            config: makeConfig(),
            counters: counters,
            sink: recorder,
            frontmostProvider: front,
            clock: { now },
            systemIdleSeconds: { 0 }
        )
        counters.recordKey()
        agg.tick()
        XCTAssertNotNil(agg.openIntervalSnapshot)
        XCTAssertEqual(agg.openIntervalSnapshot?.bundleID, "com.apple.Safari")
        XCTAssertEqual(agg.openIntervalSnapshot?.keyCount, 1)

        now = now.addingTimeInterval(1)
        counters.recordMouse()
        agg.tick()
        XCTAssertEqual(agg.openIntervalSnapshot?.mouseCount, 1)
    }

    func testClosesOnIdleTimeoutAndDoesNotInflate() {
        var now = Date(timeIntervalSince1970: 2_000_000)
        var lastRealInput = now
        let counters = InputCounters(clock: { now })
        let recorder = Recorder()
        let front = FrontStub(FrontmostApp(bundleID: "com.apple.Xcode", name: "Xcode"))
        let agg = SessionAggregator(
            config: makeConfig(idle: 30, flush: 3_600),
            counters: counters,
            sink: recorder,
            frontmostProvider: front,
            clock: { now },
            systemIdleSeconds: { max(0, now.timeIntervalSince(lastRealInput)) }
        )
        // 10 seconds of active typing
        for _ in 0..<10 {
            counters.recordKey()
            lastRealInput = now
            agg.tick()
            now = now.addingTimeInterval(1)
        }
        XCTAssertNotNil(agg.openIntervalSnapshot)
        let lastInput = now
        // 120 seconds of walk-away, no input
        now = now.addingTimeInterval(120)
        agg.tick()
        XCTAssertNil(agg.openIntervalSnapshot)
        XCTAssertEqual(recorder.intervals.count, 1)
        let interval = recorder.intervals[0]
        // end must be clamped to lastInput, not to now
        XCTAssertLessThanOrEqual(interval.endTs.timeIntervalSince1970, lastInput.timeIntervalSince1970 + 0.001)
        // duration must reflect real activity, never 120+10 seconds of wall-clock
        XCTAssertLessThanOrEqual(interval.duration, 15, "walk-away must not inflate beyond active time + IDLE_CUTOFF")
    }

    func testSwitchingAppsClosesInterval() {
        var now = Date(timeIntervalSince1970: 3_000_000)
        let counters = InputCounters(clock: { now })
        let recorder = Recorder()
        let front = FrontStub(FrontmostApp(bundleID: "com.apple.Safari", name: "Safari"))
        let agg = SessionAggregator(
            config: makeConfig(flush: 3_600),
            counters: counters,
            sink: recorder,
            frontmostProvider: front,
            clock: { now },
            systemIdleSeconds: { 0 }
        )
        counters.recordKey()
        agg.tick()
        now = now.addingTimeInterval(5)
        front.currentFrontmost = FrontmostApp(bundleID: "com.apple.Xcode", name: "Xcode")
        counters.recordKey()
        agg.tick()

        XCTAssertEqual(recorder.intervals.count, 1)
        XCTAssertEqual(recorder.intervals[0].bundleID, "com.apple.Safari")
        XCTAssertEqual(agg.openIntervalSnapshot?.bundleID, "com.apple.Xcode")
    }

    func testFlushDoesNotCreateDuplicateRows() {
        // Regression: before the fix, every 30s flush INSERTed a new row,
        // so SUM(end_ts - start_ts) double-counted active time.
        var now = Date(timeIntervalSince1970: 5_000_000)
        var lastRealInput = now
        let counters = InputCounters(clock: { now })
        let recorder = Recorder()
        let front = FrontStub(FrontmostApp(bundleID: "com.apple.Terminal", name: "Terminal"))
        // flushInterval: 30 s — must trigger several times over a 120 s session
        let agg = SessionAggregator(
            config: makeConfig(idle: 30, flush: 30),
            counters: counters,
            sink: recorder,
            frontmostProvider: front,
            clock: { now },
            systemIdleSeconds: { max(0, now.timeIntervalSince(lastRealInput)) }
        )
        // 120 s of continuous activity — ticks every second, one key per second
        for _ in 0..<120 {
            counters.recordKey()
            lastRealInput = now
            agg.tick()
            now = now.addingTimeInterval(1)
        }
        // Idle out to force close
        now = now.addingTimeInterval(60)
        agg.tick()

        XCTAssertEqual(recorder.rows.count, 1,
            "120 s session with 4 flushes must collapse into 1 row, got \(recorder.rows.count)")
        XCTAssertGreaterThanOrEqual(recorder.inserts, 1)
        XCTAssertGreaterThanOrEqual(recorder.updates, 1,
            "crash-safety flushes after the first must be UPDATEs, not INSERTs")
        let only = recorder.intervals[0]
        XCTAssertEqual(only.keyCount, 120)
        // duration should reflect actual active time, not sum across flushes
        XCTAssertGreaterThan(only.duration, 115)
        XCTAssertLessThanOrEqual(only.duration, 121)
    }

    func testExcludedAppIsNotRecorded() {
        var now = Date(timeIntervalSince1970: 4_000_000)
        let counters = InputCounters(clock: { now })
        let recorder = Recorder()
        let front = FrontStub(FrontmostApp(bundleID: "com.1password.1password", name: "1Password"))
        let agg = SessionAggregator(
            config: makeConfig(),
            counters: counters,
            sink: recorder,
            frontmostProvider: front,
            excludedBundleIDs: ["com.1password.1password"],
            clock: { now },
            systemIdleSeconds: { 0 }
        )
        counters.recordKey()
        agg.tick()
        now = now.addingTimeInterval(1)
        counters.recordKey()
        agg.tick()
        XCTAssertNil(agg.openIntervalSnapshot)
        XCTAssertTrue(recorder.intervals.isEmpty)
    }
}
