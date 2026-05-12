import SwiftUI
import Charts
import MacUsageRepCore

struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            usageList(title: "Today", rows: model.todayUsage)
                .tabItem { Label("Today", systemImage: "sun.max") }
            usageList(title: "Last 7 days", rows: model.weekUsage)
                .tabItem { Label("Week", systemImage: "calendar") }
            resourcesList(title: "Resources today", rows: model.resourcesToday)
                .tabItem { Label("Resources", systemImage: "cpu") }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 460)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: model.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
    }

    @ViewBuilder
    private func usageList(title: String, rows: [AppUsage]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold()

            if rows.isEmpty {
                Text("No activity recorded yet.").foregroundStyle(.secondary)
            } else {
                Chart(rows.prefix(10), id: \.bundleID) { row in
                    BarMark(
                        x: .value("Active seconds", row.activeSeconds),
                        y: .value("App", row.appName)
                    )
                }
                .frame(height: 240)

                Table(rows) {
                    TableColumn("App") { Text($0.appName) }
                    TableColumn("Active") { Text(AppModel.formatSeconds($0.activeSeconds)) }
                    TableColumn("Keys") { Text("\($0.keys)") }
                    TableColumn("Mouse") { Text("\($0.mouseEvents)") }
                }
            }
        }
    }

    @ViewBuilder
    private func resourcesList(title: String, rows: [AppResourceUsage]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold()

            if rows.isEmpty {
                Text("No resource samples yet. Wait ~20 seconds after first launch.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(rows.prefix(10), id: \.bundleID) { row in
                    BarMark(
                        x: .value("Avg CPU %", row.avgCPU),
                        y: .value("App", row.appName)
                    )
                }
                .frame(height: 240)

                Table(rows) {
                    TableColumn("App") { Text($0.appName) }
                    TableColumn("Avg CPU") { Text(String(format: "%.1f%%", $0.avgCPU)) }
                    TableColumn("Peak CPU") { Text(String(format: "%.1f%%", $0.peakCPU)) }
                    TableColumn("Avg RAM") { Text(AppModel.formatBytes($0.avgMemoryBytes)) }
                    TableColumn("Peak RAM") { Text(AppModel.formatBytes($0.peakMemoryBytes)) }
                }
            }
        }
    }
}
