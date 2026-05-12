import Foundation
import GRDB

enum Schema {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .double).notNull().indexed()
                t.column("bundle_id", .text).notNull().indexed()
                t.column("kind", .text).notNull()
                t.column("count", .integer).notNull()
            }

            try db.create(table: "active_intervals") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start_ts", .double).notNull().indexed()
                t.column("end_ts", .double).notNull()
                t.column("bundle_id", .text).notNull().indexed()
                t.column("app_name", .text).notNull()
                t.column("key_count", .integer).notNull().defaults(to: 0)
                t.column("mouse_count", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "daily_totals") { t in
                t.column("date", .text).notNull()
                t.column("bundle_id", .text).notNull()
                t.column("active_seconds", .integer).notNull().defaults(to: 0)
                t.column("keys", .integer).notNull().defaults(to: 0)
                t.column("mouse_events", .integer).notNull().defaults(to: 0)
                t.primaryKey(["date", "bundle_id"])
            }

            try db.create(table: "apps") { t in
                t.primaryKey("bundle_id", .text)
                t.column("display_name", .text).notNull()
                t.column("category", .text)
                t.column("excluded", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v2_resource_samples") { db in
            try db.create(table: "resource_samples") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .double).notNull().indexed()
                t.column("bundle_id", .text).notNull().indexed()
                t.column("app_name", .text).notNull()
                t.column("cpu_percent", .double).notNull()
                t.column("memory_bytes", .integer).notNull()
            }
        }

        // v3 — before this migration, the aggregator INSERTed a new row on every
        // 30-second crash-safety flush. For each open interval that spanned N
        // flushes, the table accumulated N rows sharing (bundle_id, start_ts)
        // with increasing end_ts. SUM(end_ts - start_ts) double-counted the
        // same wall-clock time. Collapse those groups to the row with the
        // latest end_ts (the last flush had the full duration).
        migrator.registerMigration("v3_dedupe_flush_duplicates") { db in
            try db.execute(sql: """
                DELETE FROM active_intervals
                WHERE id IN (
                    SELECT a.id FROM active_intervals a
                    JOIN active_intervals b
                      ON a.bundle_id = b.bundle_id
                     AND a.start_ts  = b.start_ts
                    WHERE a.end_ts < b.end_ts
                       OR (a.end_ts = b.end_ts AND a.id < b.id)
                )
            """)
        }

        return migrator
    }
}
