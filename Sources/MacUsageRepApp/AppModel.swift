import Foundation
import Combine
import MacUsageRepCore

@MainActor
final class AppModel: ObservableObject {
    @Published var todayUsage: [AppUsage] = []
    @Published var weekUsage: [AppUsage] = []
    @Published var resourcesToday: [AppResourceUsage] = []
    @Published var lastRefresh: Date = .distantPast
    @Published var errorMessage: String?

    private let config: Config
    private var database: Database?
    private var engine: ReportingEngine?
    private var refreshTimer: Timer?

    init(config: Config = .default) {
        self.config = config
        do {
            let db = try Database(url: config.databaseURL)
            self.database = db
            self.engine = ReportingEngine(db: db)
        } catch {
            self.errorMessage = "DB open failed: \(error.localizedDescription)"
        }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard let engine else { return }
        do {
            todayUsage = try engine.today()
            weekUsage = try engine.lastNDays(7)
            resourcesToday = try engine.resourcesToday()
            lastRefresh = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Query failed: \(error.localizedDescription)"
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f.string(fromByteCount: bytes)
    }

    static func formatSeconds(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }
}
