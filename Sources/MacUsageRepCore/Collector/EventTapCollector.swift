#if canImport(CoreGraphics)
import Foundation
import CoreGraphics
import CoreFoundation

public final class EventTapCollector {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let counters: InputCounters
    private var lastMousePoint: CGPoint = .zero
    private let mouseMoveThreshold: Double

    public init(counters: InputCounters, mouseMoveThreshold: Double) {
        self.counters = counters
        self.mouseMoveThreshold = mouseMoveThreshold
    }

    public func start() throws {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let collector = Unmanaged<EventTapCollector>.fromOpaque(refcon).takeUnretainedValue()
                collector.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: opaque
        ) else {
            throw CollectorError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.runLoopSource = source
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            counters.recordKey()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            counters.recordMouse()
        case .mouseMoved:
            let p = event.location
            let dx = p.x - lastMousePoint.x
            let dy = p.y - lastMousePoint.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist >= mouseMoveThreshold {
                lastMousePoint = p
                counters.recordMouse()
            }
        default:
            break
        }
    }
}

public enum CollectorError: Error {
    case eventTapCreationFailed
}
#endif
