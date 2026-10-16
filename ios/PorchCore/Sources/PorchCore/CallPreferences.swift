import Foundation

/// Device-wide caregiver preferences; old installations keep a 20-second wait.
public enum CallPreferences {
    public static let fallbackRange = 5...120
    public static let defaultFallbackSeconds = 20
    private static let fallbackKey = "porch.phoneFallbackSeconds"

    public static func fallbackSeconds(in defaults: UserDefaults = .standard) -> Int {
        let seconds = defaults.integer(forKey: fallbackKey)
        return fallbackRange.contains(seconds) ? seconds : defaultFallbackSeconds
    }

    public static func saveFallbackSeconds(_ seconds: Int, in defaults: UserDefaults = .standard) {
        defaults.set(min(fallbackRange.upperBound, max(fallbackRange.lowerBound, seconds)), forKey: fallbackKey)
    }
}
