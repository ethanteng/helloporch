import Foundation

/// A family phone's Do Not Disturb: Porch calls don't ring it, and your loved one can leave a message instead. On until
/// turned off, or every day for set hours, or both. Kept on this phone for all its families, each of which hears it with
/// every check-in (lib/family/do-not-disturb.ts), so the server can turn the bedside's calls away while the phone is
/// closed. Hours are whole hours on this phone's clock, as for the bedside's message hours.
public struct DoNotDisturb: Codable, Equatable {
    public static let hourRange = 0...23
    public var on = false
    public var scheduled = false
    /// Start inclusive and end exclusive: 22 and 7 mean 10:00 PM until 7:00 AM. A start after the end runs past
    /// midnight, and the same hour for both is all day.
    public var startHour = 22
    public var endHour = 7
    public init() {}
    private enum CodingKeys: String, CodingKey { case on, scheduled, startHour, endHour }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        on = try values.decodeIfPresent(Bool.self, forKey: .on) ?? false
        scheduled = try values.decodeIfPresent(Bool.self, forKey: .scheduled) ?? false
        startHour = try values.decodeIfPresent(Int.self, forKey: .startHour) ?? 22
        endHour = try values.decodeIfPresent(Int.self, forKey: .endHour) ?? 7
    }

    /// Whether Porch calls don't ring now.
    public func applies(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        if on { return true }
        guard scheduled else { return false }
        guard startHour != endHour else { return true }
        let hour = calendar.component(.hour, from: date)
        return startHour < endHour ? (startHour..<endHour).contains(hour) : hour >= startHour || hour < endHour
    }

    /// What a family check-in says. Hours go with this phone's time zone, so a phone that travels keeps them on its own clock.
    public func checkIn(timeZone: TimeZone = .autoupdatingCurrent) -> [String: Any] {
        var value: [String: Any] = ["on": on]
        if scheduled { value["hours"] = ["start": startHour, "end": endHour]; value["timeZone"] = timeZone.identifier }
        return value
    }

    private static let key = "porch.doNotDisturb.v1"
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
}
