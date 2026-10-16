import Foundation

public struct BedsidePreferences: Codable, Equatable {
    public enum Appearance: String, Codable { case `default`, dynamic }
    public enum Hemisphere: String, Codable { case northern, southern }
    public var appearance: Appearance = .default
    public var hemisphere: Hemisphere = .northern
    public var dayStart: Int = 6
    public var nightStart: Int = 18
    public var language: BedsideLanguage = .english
    public init() {}
    private enum CodingKeys: String, CodingKey { case appearance, hemisphere, dayStart, nightStart, language }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .default
        hemisphere = try values.decodeIfPresent(Hemisphere.self, forKey: .hemisphere) ?? .northern
        dayStart = try values.decodeIfPresent(Int.self, forKey: .dayStart) ?? 6
        nightStart = try values.decodeIfPresent(Int.self, forKey: .nightStart) ?? 18
        language = (try values.decodeIfPresent(String.self, forKey: .language)).flatMap(BedsideLanguage.init(rawValue:)) ?? .english
    }
    private static let key = "porch.bedsideDisplay.v1"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Self.self, from: data),
              (0...11).contains(saved.dayStart), (12...23).contains(saved.nightStart) else { return Self() }
        return saved
    }
    public func save(to defaults: UserDefaults = .standard) {
        var valid = self
        valid.dayStart = min(11, max(0, dayStart)); valid.nightStart = min(23, max(12, nightStart))
        defaults.set(try? JSONEncoder().encode(valid), forKey: Self.key)
    }
}

/// An orientation cue based on a caregiver's daily schedule, not an astronomical
/// sunrise forecast. It needs no location access and always uses the local date.
public struct BedsideScene: Equatable {
    public enum Season: String, CaseIterable { case spring = "Spring", summer = "Summer", fall = "Fall", winter = "Winter" }
    public enum Period: String { case morning = "Morning", afternoon = "Afternoon", evening = "Evening", night = "Night" }
    public let season: Season
    public let period: Period
    public let isDay: Bool
    public let progress: Double
    public let hour: Double
    public init(date: Date, preferences: BedsidePreferences, calendar: Calendar = .autoupdatingCurrent) {
        let parts = calendar.dateComponents([.hour, .minute, .second, .month], from: date)
        hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
        let day = Double(preferences.dayStart), night = Double(preferences.nightStart)
        isDay = hour >= day && hour < night
        if isDay { progress = (hour - day) / (night - day) }
        else { progress = (hour >= night ? hour - night : hour + 24 - night) / (24 - night + day) }
        period = isDay ? (hour < 12 ? .morning : .afternoon) : (hour >= night && hour < min(22, night + 3) ? .evening : .night)
        let month = ((parts.month ?? 1) - 1 + (preferences.hemisphere == .southern ? 6 : 0)) % 12 + 1
        switch month { case 3...5: season = .spring; case 6...8: season = .summer; case 9...11: season = .fall; default: season = .winter }
    }
}
