import Foundation

/// Device-wide caregiver preferences. Silence disconnection is opt-in.
public enum CallPreferences {
    public static let fallbackRange = 5...120
    public static let defaultFallbackSeconds = 20
    /// How long calls to the bedside ring before voicemail. The household keeps it on the server.
    public static let voicemailRange = 15...120
    public static let defaultVoicemailSeconds = 45
    public static let silenceRange = 15...1800
    public static let defaultSilenceSeconds = 120
    private static let silenceEnabledKey = "porch.disconnectAfterSilence"
    private static let silenceSecondsKey = "porch.silenceSeconds"
    private static let fallbackKey = "porch.phoneFallbackSeconds"

    public static func disconnectAfterSilence(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: silenceEnabledKey)
    }

    public static func silenceSeconds(in defaults: UserDefaults = .standard) -> Int {
        let seconds = defaults.integer(forKey: silenceSecondsKey)
        return silenceRange.contains(seconds) ? seconds : defaultSilenceSeconds
    }

    public static func saveSilence(enabled: Bool, seconds: Int, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: silenceEnabledKey)
        defaults.set(min(silenceRange.upperBound, max(silenceRange.lowerBound, seconds)), forKey: silenceSecondsKey)
    }

    public static func fallbackSeconds(in defaults: UserDefaults = .standard) -> Int {
        let seconds = defaults.integer(forKey: fallbackKey)
        return fallbackRange.contains(seconds) ? seconds : defaultFallbackSeconds
    }

    public static func saveFallbackSeconds(_ seconds: Int, in defaults: UserDefaults = .standard) {
        defaults.set(min(fallbackRange.upperBound, max(fallbackRange.lowerBound, seconds)), forKey: fallbackKey)
    }
}
