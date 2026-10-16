import Foundation

/// Measures one continuous silent interval using a monotonic clock supplied by
/// the caller. Ringing, fallback setup and reconnection each clear the interval.
public struct CallInactivityTimer {
    public let timeout: TimeInterval?
    private var lastActivity: TimeInterval?

    public init(timeout: TimeInterval?) {
        self.timeout = timeout.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    public mutating func reset() { lastActivity = nil }

    public mutating func update(at now: TimeInterval, connected: Bool, speaking: Bool) -> Bool {
        guard let timeout, connected else { reset(); return false }
        guard let lastActivity, now >= lastActivity, !speaking else {
            self.lastActivity = now
            return false
        }
        return now - lastActivity >= timeout
    }
}
