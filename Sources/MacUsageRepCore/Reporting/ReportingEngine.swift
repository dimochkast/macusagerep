import Foundation
import GRDB

public struct AppUsage: Sendable, Equatable, Identifiable {
    public let bundleID: String
    public let appName: String
    public let activeSeconds: Int
    public let keys: Int
    public let mouseEvents: Int

    public var id: String { bundleID }
}

public final class ReportingEngine {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    public func usage(from: Date, to: Date) throws -> [AppUsage] {
        try db.writer.read { dbh in
            let rows = try Row.fetchAll(dbh, sql: """
                SELECT bundle_id,
                       MAX(app_name) AS app_name,
                       CAST(SUM(end_ts - start_ts) AS INTEGER) AS active_seconds,
                       SUM(key_count) AS keys,
                       SUM(mouse_count) AS mouse_events
                FROM active_intervals
                WHERE start_ts >= ? AND start_ts < ?
                GROUP BY bundle_id
                ORDER BY active_seconds DESC
            """, arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970])
            return rows.map { row in
                AppUsage(
                    bundleID: row["bundle_id"] ?? "",
                    appName: row["app_name"] ?? "",
                    activeSeconds: row["active_seconds"] ?? 0,
                    keys: row["keys"] ?? 0,
                    mouseEvents: row["mouse_events"] ?? 0
                )
            }
        }
    }

    public func today(now: Date = Date()) throws -> [AppUsage] {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try usage(from: start, to: end)
    }

    public func lastNDays(_ days: Int, now: Date = Date()) throws -> [AppUsage] {
        let cal = Calendar(identifier: .gregorian)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let start = cal.date(byAdding: .day, value: -days + 1, to: cal.startOfDay(for: now))!
        return try usage(from: start, to: end)
    }

    public func exportCSV(from: Date, to: Date) throws -> String {
        let rows = try usage(from: from, to: to)
        var out = "bundle_id,app_name,active_seconds,keys,mouse_events\n"
        for r in rows {
            let name = r.appName.replacingOccurrences(of: "\"", with: "\"\"")
            out += "\(r.bundleID),\"\(name)\",\(r.activeSeconds),\(r.keys),\(r.mouseEvents)\n"
        }
        return out
    }

    public func resourceUsage(from: Date, to: Date) throws -> [AppResourceUsage] {
        try db.writer.read { dbh in
            let rows = try Row.fetchAll(dbh, sql: """
                SELECT bundle_id,
                       MAX(app_name) AS app_name,
                       AVG(cpu_percent) AS avg_cpu,
                       MAX(cpu_percent) AS peak_cpu,
                       CAST(AVG(memory_bytes) AS INTEGER) AS avg_mem,
                       MAX(memory_bytes) AS peak_mem,
                       COUNT(*) AS n
                FROM resource_samples
                WHERE timestamp >= ? AND timestamp < ?
                GROUP BY bundle_id
                ORDER BY avg_cpu DESC
            """, arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970])
            return rows.map { row in
                AppResourceUsage(
                    bundleID: row["bundle_id"] ?? "",
                    appName: row["app_name"] ?? "",
                    avgCPU: row["avg_cpu"] ?? 0,
                    peakCPU: row["peak_cpu"] ?? 0,
                    avgMemoryBytes: row["avg_mem"] ?? 0,
                    peakMemoryBytes: row["peak_mem"] ?? 0,
                    samples: row["n"] ?? 0
                )
            }
        }
    }

    public func resourcesToday(now: Date = Date()) throws -> [AppResourceUsage] {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try resourceUsage(from: start, to: end)
    }

    public func exportJSON(from: Date, to: Date) throws -> Data {
        struct Row: Encodable {
            let bundleID: String
            let appName: String
            let activeSeconds: Int
            let keys: Int
            let mouseEvents: Int
        }
        let rows = try usage(from: from, to: to).map {
            Row(bundleID: $0.bundleID, appName: $0.appName, activeSeconds: $0.activeSeconds, keys: $0.keys, mouseEvents: $0.mouseEvents)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.keyEncodingStrategy = .convertToSnakeCase
        return try enc.encode(rows)
    }
}
