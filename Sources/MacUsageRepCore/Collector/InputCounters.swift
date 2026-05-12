import Foundation

public final class InputCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: Int = 0
    private var mouse: Int = 0
    private var lastInput: Date = .distantPast
    private let clock: () -> Date

    public init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
    }

    public func recordKey() {
        lock.lock(); defer { lock.unlock() }
        keys += 1
        lastInput = clock()
    }

    public func recordMouse() {
        lock.lock(); defer { lock.unlock() }
        mouse += 1
        lastInput = clock()
    }

    public struct Drain: Sendable {
        public let keys: Int
        public let mouse: Int
        public let lastInput: Date
    }

    public func drain() -> Drain {
        lock.lock(); defer { lock.unlock() }
        let d = Drain(keys: keys, mouse: mouse, lastInput: lastInput)
        keys = 0
        mouse = 0
        return d
    }

    public func peekLastInput() -> Date {
        lock.lock(); defer { lock.unlock() }
        return lastInput
    }
}
