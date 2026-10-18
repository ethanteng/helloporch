import Foundation

/// Playing waiting messages when someone sits in front of the bedside iPad. Kept on this iPad,
/// off until a caregiver turns it on, and limited to waking hours.
public struct MessageAutoplay: Codable, Equatable {
    public static let hourRange = 0...23
    /// After Not now or Stop, the camera waits this long before trying again.
    public static let snoozeSeconds: TimeInterval = 30 * 60
    public var enabled = false
    /// Local hours, start inclusive and end exclusive: 8 and 21 mean 8:00 AM until 9:00 PM.
    public var startHour = 8
    public var endHour = 21
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, startHour, endHour }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        startHour = try values.decodeIfPresent(Int.self, forKey: .startHour) ?? 8
        endHour = try values.decodeIfPresent(Int.self, forKey: .endHour) ?? 21
    }
    /// Within the hours. A start after the end wraps past midnight.
    public func allows(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard enabled, startHour != endHour else { return enabled }
        let hour = calendar.component(.hour, from: date)
        return startHour < endHour ? (startHour..<endHour).contains(hour) : hour >= startHour || hour < endHour
    }
    private static let key = "porch.messageAutoplay.v1"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Self.self, from: data),
              hourRange.contains(saved.startHour), hourRange.contains(saved.endHour) else { return Self() }
        return saved
    }
    public func save(to defaults: UserDefaults = .standard) {
        var valid = self
        valid.startHour = min(23, max(0, startHour)); valid.endHour = min(23, max(0, endHour))
        defaults.set(try? JSONEncoder().encode(valid), forKey: Self.key)
    }

    /// After Stop: messages that were already waiting when playback started and still are.
    /// A message that arrived during playback is left out, so it can start on its own.
    public static func deferredMessageIDs(startedWith: [String], stillReady: [String]) -> Set<String> {
        let started = Set(startedWith)
        return Set(stillReady.filter { started.contains($0) })
    }
}

/// Decides from face detections that someone is sitting in front of the iPad: a face large enough
/// to be close by, seen steadily for a couple of seconds. Someone walking past or across the room
/// doesn't count. It fires once, then needs a reset.
public struct PresenceTrigger {
    /// Face height as a fraction of the frame. About 0.12 is a face roughly an arm's length or two away.
    public let minimumFaceHeight: Double
    public let requiredSeconds: TimeInterval
    /// A short miss (a blink, a turned head) doesn't restart the count.
    public let allowedGap: TimeInterval
    private var since: TimeInterval?
    private var lastSeen: TimeInterval?
    private var fired = false
    public init(minimumFaceHeight: Double = 0.12, requiredSeconds: TimeInterval = 2, allowedGap: TimeInterval = 1) {
        self.minimumFaceHeight = minimumFaceHeight; self.requiredSeconds = requiredSeconds; self.allowedGap = allowedGap
    }
    /// One analyzed frame: the height of the largest face found, or nil for none. Returns true
    /// the first time someone has been present long enough.
    public mutating func observe(faceHeight: Double?, at time: TimeInterval) -> Bool {
        guard !fired else { return false }
        if let faceHeight, faceHeight >= minimumFaceHeight {
            if let last = lastSeen, time - last > allowedGap { since = nil }
            since = since ?? time
            lastSeen = time
            if time - since! >= requiredSeconds { fired = true; return true }
        } else if let last = lastSeen, time - last > allowedGap {
            since = nil; lastSeen = nil
        }
        return false
    }
    public mutating func reset() { since = nil; lastSeen = nil; fired = false }
}
