import Foundation

/// Whether someone is at the bedside iPad, so family can tell whether a call now is likely to be answered. The bedside
/// notices someone when a key is pressed or the screen is touched and, if a caregiver turns it on, when its camera sees
/// a face close by. It can't tell who: an aide or a visitor counts too. Family only learn when, never how.
public enum BedsideAttendance {
    /// Noticed this recently counts as there now. The camera looks every `lookInterval`, so someone sitting still stays
    /// "at the iPad" between looks, and a look or two that misses a turned head doesn't change that.
    public static let presentSeconds: TimeInterval = 90
    /// After this long, family see nothing rather than a stale time.
    public static let shownSeconds: TimeInterval = 7 * 86400
    /// The camera looks for a face this often, for up to `lookSeconds`, and stops as soon as it sees one.
    public static let lookInterval: TimeInterval = 30
    public static let lookSeconds: TimeInterval = 5

    /// What family see under the bedside's name, from server times. Nil before anyone has been noticed, or once it's
    /// been a week. It never says no one is there: the camera can't see in the dark or across the room, and someone in
    /// bed can still hear a call ring.
    public static func text(attendedAt: TimeInterval?, now: TimeInterval) -> String? {
        guard let attendedAt else { return nil }
        if isPresent(attendedAt: attendedAt, now: now) { return "Someone is at the iPad" }
        let age = now - attendedAt
        guard age < shownSeconds else { return nil }
        return "Someone was at the iPad \(ago(age))"
    }
    /// Noticed recently enough to count as there now. A server time a little behind the bedside's report still is.
    public static func isPresent(attendedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let attendedAt else { return false }
        return now - attendedAt < presentSeconds
    }
    static func ago(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    // The camera's part is a caregiver's choice, kept on this iPad like starting messages when someone sits down.
    private static let cameraKey = "porch.attendanceCamera.v1"
    /// The camera also looks for someone, so family can see they're there. Off until a caregiver turns it on.
    public static func cameraEnabled(in defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: cameraKey) }
    public static func setCameraEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) { defaults.set(enabled, forKey: cameraKey) }
}

/// When this bedside last noticed someone. Main thread only. Kept for this launch; the server keeps the newest it heard.
public final class AttendanceTracker {
    public static let shared = AttendanceTracker()
    private let clock: () -> Date
    private var noticedAt: Date?
    public init(clock: @escaping () -> Date = { Date() }) { self.clock = clock }
    public func noticed() { noticedAt = clock() }
    /// While a caregiver has sharing off, so turning it back on can't report someone who was there meanwhile.
    public func forget() { noticedAt = nil }
    /// Whole seconds since then, for the bedside's poll. Nil until someone has been noticed, and nil when the clock has
    /// jumped back: reporting 0 would tell family someone just arrived. Seconds ago rather than a time, so a clock that
    /// is merely wrong, but still running forward, doesn't matter.
    public var secondsSince: Int? {
        guard let noticedAt else { return nil }
        let elapsed = clock().timeIntervalSince(noticedAt)
        guard elapsed >= 0 else { return nil }
        return Int(elapsed)
    }
}
