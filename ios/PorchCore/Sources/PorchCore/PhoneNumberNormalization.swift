import Foundation
import PhoneNumberKit

public enum PhoneNumberNormalization {
    private static let utility = PhoneNumberUtility()
    public static var deviceRegion: String { (Locale.current as NSLocale).countryCode ?? "US" }

    /// Parse national numbers using an explicit region; preserve international country codes.
    /// Extensions cannot be sent to the SIP destination field and are never silently dropped.
    public static func e164(_ value: String, region: String = deviceRegion) throws -> String {
        do {
            let number = try utility.parse(value, withRegion: region.uppercased())
            guard number.numberExtension?.isEmpty != false else { throw CallContact.ValidationError.invalidPhoneNumber }
            return try CallContact.normalizedPhoneNumber(utility.format(number, toType: .e164))
        } catch { throw CallContact.ValidationError.invalidPhoneNumber }
    }
}
