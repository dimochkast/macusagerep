import Foundation
import GRDB

public final class Database {
    public let writer: DatabaseWriter

    public init(url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            try db.execute(sql: "PRAGMA synchronous=NORMAL")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        self.writer = pool
        try Schema.migrator().migrate(pool)
    }

    public func insertEvent(_ event: EventRecord) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (timestamp, bundle_id, kind, count)
                    VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    event.timestamp.timeIntervalSince1970,
                    event.bundleID,
                    event.kind.rawValue,
                    event.count,
                ]
            )
        }
    }

    public func insertInterval(_ interval: ActiveInterval) throws -> Int64 {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO active_intervals (start_ts, end_ts, bundle_id, app_name, key_count, mouse_count)
                    VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    interval.startTs.timeIntervalSince1970,
                    interval.endTs.timeIntervalSince1970,
                    interval.bundleID,
                    interval.appName,
                    interval.keyCount,
                    interval.mouseCount,
                ]
            )
            return db.lastInsertedRowID
        }
    }

    public func updateInterval(id: Int64, _ interval: ActiveInterval) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    UPDATE active_intervals
                    SET start_ts = ?, end_ts = ?, bundle_id = ?, app_name = ?,
                        key_count = ?, mouse_count = ?
                    WHERE id = ?
                """,
                arguments: [
                    interval.startTs.timeIntervalSince1970,
                    interval.endTs.timeIntervalSince1970,
                    interval.bundleID,
                    interval.appName,
                    interval.keyCount,
                    interval.mouseCount,
                    id,
                ]
            )
        }
    }

    public func insertResourceSamples(_ samples: [ResourceSample]) throws {
        guard !samples.isEmpty else { return }
        try writer.write { db in
            for s in samples {
                try db.execute(
                    sql: """
                        INSERT INTO resource_samples (timestamp, bundle_id, app_name, cpu_percent, memory_bytes)
                        VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        s.timestamp.timeIntervalSince1970,
                        s.bundleID,
                        s.appName,
                        s.cpuPercent,
                        s.memoryBytes,
                    ]
                )
            }
        }
    }

    public func upsertApp(_ app: AppMetadata) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO apps (bundle_id, display_name, category, excluded)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(bundle_id) DO UPDATE SET
                      display_name=excluded.display_name,
                      category=excluded.category,
                      excluded=excluded.excluded
                """,
                arguments: [app.bundleID, app.displayName, app.category, app.excluded]
            )
        }
    }

    public func excludedBundleIDs() throws -> Set<String> {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT bundle_id FROM apps WHERE excluded = 1")
            return Set(rows.compactMap { $0["bundle_id"] as String? })
        }
    }

    public func rollupDailyTotals(for date: Date = Date()) throws {
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let dateString = Self.isoDateString(startOfDay)

        try writer.write { db in
            try db.execute(sql: "DELETE FROM daily_totals WHERE date = ?", arguments: [dateString])
            try db.execute(
                sql: """
                    INSERT INTO daily_totals (date, bundle_id, active_seconds, keys, mouse_events)
                    SELECT ?, bundle_id,
                           CAST(SUM(end_ts - start_ts) AS INTEGER),
                           SUM(key_count),
                           SUM(mouse_count)
                    FROM active_intervals
                    WHERE start_ts >= ? AND start_ts < ?
                    GROUP BY bundle_id
                """,
                arguments: [
                    dateString,
                    startOfDay.timeIntervalSince1970,
                    endOfDay.timeIntervalSince1970,
                ]
            )
        }
    }

    public func purgeOldData(rawRetentionDays: Int, intervalRetentionDays: Int, now: Date = Date()) throws {
        let rawCutoff = now.addingTimeInterval(-Double(rawRetentionDays) * 86_400)
        let intervalCutoff = now.addingTimeInterval(-Double(intervalRetentionDays) * 86_400)
        try writer.write { db in
            try db.execute(sql: "DELETE FROM events WHERE timestamp < ?", arguments: [rawCutoff.timeIntervalSince1970])
            try db.execute(sql: "DELETE FROM active_intervals WHERE end_ts < ?", arguments: [intervalCutoff.timeIntervalSince1970])
            try db.execute(sql: "DELETE FROM resource_samples WHERE timestamp < ?", arguments: [intervalCutoff.timeIntervalSince1970])
        }
    }

    static func isoDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter.string(from: date)
    }
}
