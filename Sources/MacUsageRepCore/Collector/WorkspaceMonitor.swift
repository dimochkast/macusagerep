#if canImport(AppKit)
import AppKit
import Foundation

public final class WorkspaceMonitor {
    public private(set) var current: FrontmostApp = .unknown
    public var onChange: ((FrontmostApp) -> Void)?
    private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        snapshotCurrent()
        let center = NSWorkspace.shared.notificationCenter
        observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                ?? NSWorkspace.shared.frontmostApplication
            guard let app else { return }
            let front = FrontmostApp(
                bundleID: app.bundleIdentifier ?? "unknown",
                name: app.localizedName ?? "Unknown"
            )
            self.current = front
            self.onChange?(front)
        }
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func snapshotCurrent() {
        if let app = NSWorkspace.shared.frontmostApplication {
            current = FrontmostApp(
                bundleID: app.bundleIdentifier ?? "unknown",
                name: app.localizedName ?? "Unknown"
            )
        }
    }
}
#endif
