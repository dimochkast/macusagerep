import SwiftUI
import MacUsageRepCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today — top 5")
                .font(.headline)

            if let msg = model.errorMessage {
                Text(msg).foregroundStyle(.red).font(.caption)
            }

            if model.todayUsage.isEmpty {
                Text("No activity recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.todayUsage.prefix(5).enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.appName).lineLimit(1)
                        Spacer()
                        Text(AppModel.formatSeconds(row.activeSeconds))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button("Dashboard") { openWindow(id: "dashboard") }
                Spacer()
                Button("Refresh") { model.refresh() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
