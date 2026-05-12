import SwiftUI
import MacUsageRepCore

@main
struct MacUsageRepApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("MacUsageRep", systemImage: "clock.badge.checkmark") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "dashboard") {
            DashboardView(model: model)
        }
    }
}
