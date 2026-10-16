import Foundation

public struct CallContact: Codable, Equatable {
    public let name: String
    public let address: String
    public let shortcutName: String?
    public let nativeCall: NativeCall?
    public let phoneNumber: String?

    public init(name: String, address: String = "", shortcutName: String? = nil) throws {
        self.nativeCall = nil
        self.phoneNumber = nil
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.missingName }

        if let shortcutName {
            let shortcutName = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortcutName.isEmpty else { throw ValidationError.missingShortcutName }
            self.name = name
            self.address = ""
            self.shortcutName = shortcutName
            return
        }

        if address.contains("@") {
            // Accept a plain email address, never a URL, list, or URL parameters.
            let pattern = #"^[A-Za-z0-9.!$%&'*+/=_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#
            guard address.range(of: pattern, options: .regularExpression) != nil else {
                throw ValidationError.invalidAddress
            }
            self.address = address
        } else {
            let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
            guard address.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw ValidationError.invalidAddress
            }
            let normalized = address.filter { $0 == "+" || ($0 >= "0" && $0 <= "9") }
            let digits = normalized.filter { $0 != "+" }
            guard (7...15).contains(digits.count),
                  !normalized.dropFirst().contains("+") else {
                throw ValidationError.invalidAddress
            }
            self.address = normalized
        }
        self.name = name
        self.shortcutName = nil
    }

    public init(name: String, nativeCall: NativeCall, phoneNumber: String? = nil) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.missingName }
        guard name.count <= 80 else { throw ValidationError.nameTooLong }
        self.name = name
        self.address = ""
        self.shortcutName = nil
        self.nativeCall = try NativeCall(room: nativeCall.room, mode: nativeCall.mode)
        self.phoneNumber = try phoneNumber.map(Self.normalizedPhoneNumber)
    }

    public static func normalizedPhoneNumber(_ value: String) throws -> String {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
        guard input.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw ValidationError.invalidPhoneNumber }
        let number = input.filter { $0 == "+" || ($0 >= "0" && $0 <= "9") }
        guard number.range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) != nil else {
            throw ValidationError.invalidPhoneNumber
        }
        return number
    }

    public var launchURL: URL {
        guard let shortcutName else { return faceTimeURL }
        // Keep the entire name in one query value, including &, +, # and Unicode.
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = shortcutName.addingPercentEncoding(withAllowedCharacters: safe)!
        return URL(string: "shortcuts://run-shortcut?name=\(encoded)")!
    }

    public var faceTimeURL: URL {
        // Encode the recipient as one opaque value. In particular, #, %, &, and
        // + in an email must not become URL syntax or change the recipient.
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@.-_+")
        let encoded = address.addingPercentEncoding(withAllowedCharacters: safe)!
        return URL(string: "facetime://\(encoded)")!
    }

    public enum ValidationError: LocalizedError {
        case missingName, missingShortcutName, invalidAddress, nameTooLong, invalidPhoneNumber

        public var errorDescription: String? {
            switch self {
            case .missingName: return "Enter the person's name."
            case .nameTooLong: return "Use a name with 80 characters or fewer."
            case .invalidPhoneNumber: return "Enter the fallback phone number with + and the country code, such as +1 415 555 0123. Extensions aren't supported."
            case .missingShortcutName: return "Enter the exact name of a shortcut saved in the Shortcuts app on this iPad."
            case .invalidAddress:
                return "Use one FaceTime email address or a phone number with 7–15 digits. Use + and the country code for international numbers. Extensions and multiple recipients aren't supported."
            }
        }
    }
}
