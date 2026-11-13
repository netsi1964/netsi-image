import Foundation

public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// In-process log. Never receives headers or keys; callers pass only messages.
public protocol LogSink: Sendable {
    func write(_ line: String)
}

public final class DebugLog: @unchecked Sendable {
    public static let shared = DebugLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private var sink: (any LogSink)?
    private let limit = 2_000

    public init() {}

    public func setSink(_ sink: (any LogSink)?) {
        lock.lock()
        defer { lock.unlock() }
        self.sink = sink
    }

    public func log(_ message: String) {
        lock.lock()
        lines.append(message)
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
        let currentSink = sink
        lock.unlock()
        currentSink?.write(message)
    }

    public func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        lines.removeAll()
    }
}
