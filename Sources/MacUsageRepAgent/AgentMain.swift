import Foundation
#if canImport(AppKit)
import AppKit
import MacUsageRepCore

@main
@MainActor
struct AgentMain {
    static func main() {
        do {
            let service = try TrackerService()
            try service.start()
            installSignalHandlers()
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.run()
            service.stop()
        } catch {
            FileHandle.standardError.write(Data("macusagerep-agent: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func installSignalHandlers() {
        let stop: @convention(c) (Int32) -> Void = { _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
        signal(SIGINT, stop)
        signal(SIGTERM, stop)
    }
}
#else
#error("macusagerep-agent requires macOS / AppKit")
#endif
