import Foundation

public struct CallContact: Codable, Equatable {
    /// The name the caregiver typed. Empty for a Porch contact that goes by its family member's name.
    public let customName: String
    /// What Porch shows and speaks: the caregiver's name, or else the paired family member's.
    public var name: String { customName.isEmpty ? memberName ?? "" : customName }
    /// The paired family member's name and photo as Porch shows them: their own, or what a caregiver chose
    /// for them. `CallSlots.reconcile` keeps these current; the caregiver's keypad name and photo come first.
    public private(set) var memberName: String?
    private var memberPhoto: ContactPhoto?
    public let address: String
    public let shortcutName: String?
    public let nativeCall: NativeCall?
    /// The primary number: the only one Porch calls when it isn't answered.
    public let phoneNumber: String?
    /// The person's other numbers, such as home and mobile. They can call in like the primary number, but Porch never dials them.
    public let otherPhoneNumbers: [String]
    /// Every number saved for this person, primary first.
    public var phoneNumbers: [String] { phoneNumber.map { [$0] + otherPhoneNumbers } ?? [] }
    /// Numbers per person, the primary one included.
    public static let maximumPhoneNumbers = 5
    public let familyMemberID: String?
    public let invitationID: String?
    public let buttonColorHex: String?
    private var photo: ContactPhoto?
    /// The keypad photo the caregiver chose.
    public var photoID: String? { photo?.id }
    public var customPhotoData: Data? { photo?.data }
    public var memberPhotoID: String? { memberPhoto?.id }
    /// What Porch shows: the caregiver's keypad photo, or else the family member's.
    public var photoData: Data? { photo?.data ?? memberPhoto?.data }
    var hasInlinePhoto: Bool { photo?.inlineData != nil }

    // Metadata validation and pairing must preserve the reference without
    // reading the image file on the main actor.
    func preservingPhoto(from original: Self) -> Self {
        var result = self; result.photo = original.photo; result.memberPhoto = original.memberPhoto; return result
    }
    /// The same contact showing its family member's current name and photo, which must be in `photos`.
    func showingMember(name: String?, photoID: String?, photos: ContactPhotoStore) -> Self {
        var result = self
        result.memberName = name
        result.memberPhoto = photoID.flatMap { try? ContactPhoto(id: $0, store: photos) }
        return result
    }

    public init(name: String, address: String = "", shortcutName: String? = nil, buttonColorHex: String? = nil, photoData: Data? = nil) throws {
        self.buttonColorHex = try Self.validatedColor(buttonColorHex)
        self.photo = try photoData.map { try ContactPhoto(data: $0) }
        self.familyMemberID = nil
        self.invitationID = nil
        self.nativeCall = nil
        self.phoneNumber = nil
        self.otherPhoneNumbers = []
        self.memberName = nil
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.missingName }

        if let shortcutName {
            let shortcutName = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortcutName.isEmpty else { throw ValidationError.missingShortcutName }
            self.customName = name
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
        self.customName = name
        self.shortcutName = nil
    }

    /// `name` may be empty for a family member invited or paired with Porch, who then goes by `memberName`.
    public init(name: String, nativeCall: NativeCall, phoneNumber: String? = nil, otherPhoneNumbers: [String] = [], familyMemberID: String? = nil, invitationID: String? = nil, memberName: String? = nil, buttonColorHex: String? = nil, photoData: Data? = nil) throws {
        self.buttonColorHex = try Self.validatedColor(buttonColorHex)
        self.photo = try photoData.map { try ContactPhoto(data: $0) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let memberName = memberName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.memberName = memberName?.isEmpty == false ? memberName : nil
        guard !name.isEmpty || (self.memberName != nil && (familyMemberID != nil || invitationID != nil)) else { throw ValidationError.missingName }
        guard name.count <= 80 else { throw ValidationError.nameTooLong }
        if let familyMemberID, UUID(uuidString: familyMemberID) == nil { throw ValidationError.invalidFamilyMember }
        if let invitationID, UUID(uuidString: invitationID) == nil { throw ValidationError.invalidFamilyMember }
        self.invitationID = invitationID
        self.familyMemberID = familyMemberID
        self.customName = name
        self.address = ""
        self.shortcutName = nil
        self.nativeCall = try NativeCall(room: nativeCall.room, mode: nativeCall.mode)
        let primary = try phoneNumber.map(Self.normalizedPhoneNumber)
        self.phoneNumber = primary
        // Repeats, and the primary number listed again, are dropped.
        var others: [String] = []
        for number in try otherPhoneNumbers.map(Self.normalizedPhoneNumber) where number != primary && !others.contains(number) { others.append(number) }
        guard primary != nil || others.isEmpty else { throw ValidationError.missingPrimaryNumber }
        guard others.count < Self.maximumPhoneNumbers else { throw ValidationError.tooManyPhoneNumbers }
        self.otherPhoneNumbers = others
    }

    /// The same contact with some details changed. Its photos stay unless `photoData` replaces the caregiver's
    /// (nil inside removes it), and an empty `name` makes a Porch contact go by its family member's name.
    public func updating(name: String? = nil, mode: NativeCall.Mode? = nil, buttonColorHex: String?? = nil, photoData: Data?? = nil) throws -> Self {
        let color = buttonColorHex ?? self.buttonColorHex
        var result: CallContact
        if let nativeCall {
            result = try CallContact(name: name ?? customName, nativeCall: NativeCall(room: nativeCall.room, mode: mode ?? nativeCall.mode),
                phoneNumber: phoneNumber, otherPhoneNumbers: otherPhoneNumbers, familyMemberID: familyMemberID, invitationID: invitationID,
                memberName: memberName, buttonColorHex: color)
        } else {
            result = try CallContact(name: name ?? customName, address: address, shortcutName: shortcutName, buttonColorHex: color)
        }
        result = result.preservingPhoto(from: self)
        if let photoData { result.photo = try photoData.map { try ContactPhoto(data: $0) } }
        return result
    }

    private static func validatedColor(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard value.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw ValidationError.invalidAppearance }
        return value.uppercased()
    }

    private enum CodingKeys: String, CodingKey {
        case name, customName, memberName, memberPhotoID, address, shortcutName, nativeCall, phoneNumber, otherPhoneNumbers, familyMemberID, invitationID, buttonColorHex, photoID, photoData
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let shown = try values.decode(String.self, forKey: .name)
        // Earlier records have only `name`, which was always the caregiver's.
        customName = try values.decodeIfPresent(String.self, forKey: .customName) ?? shown
        memberName = try values.decodeIfPresent(String.self, forKey: .memberName)
        address = try values.decode(String.self, forKey: .address)
        shortcutName = try values.decodeIfPresent(String.self, forKey: .shortcutName)
        nativeCall = try values.decodeIfPresent(NativeCall.self, forKey: .nativeCall)
        phoneNumber = try values.decodeIfPresent(String.self, forKey: .phoneNumber)
        otherPhoneNumbers = try values.decodeIfPresent([String].self, forKey: .otherPhoneNumbers) ?? []
        familyMemberID = try values.decodeIfPresent(String.self, forKey: .familyMemberID)
        invitationID = try values.decodeIfPresent(String.self, forKey: .invitationID)
        buttonColorHex = try values.decodeIfPresent(String.self, forKey: .buttonColorHex)
        let store = decoder.userInfo[ContactPhotoStore.codingKey] as? ContactPhotoStore ?? .standard
        if let data = try values.decodeIfPresent(Data.self, forKey: .photoData) {
            // The first load migrates earlier inline-photo records to files.
            photo = try ContactPhoto(data: data, store: store)
        } else if let id = try values.decodeIfPresent(String.self, forKey: .photoID) {
            photo = try ContactPhoto(id: id, store: store)
        }
        memberPhoto = try values.decodeIfPresent(String.self, forKey: .memberPhotoID).flatMap { try? ContactPhoto(id: $0, store: store.familyMembers) }
    }
    public func encode(to encoder: Encoder) throws {
        let store = encoder.userInfo[ContactPhotoStore.codingKey] as? ContactPhotoStore ?? photo?.store ?? .standard
        try photo?.persist(to: store)
        var values = encoder.container(keyedBy: CodingKeys.self)
        // `name` is what Porch shows, so an earlier build reading these settings still has a name for everyone.
        try values.encode(name, forKey: .name)
        try values.encode(customName, forKey: .customName)
        try values.encodeIfPresent(memberName, forKey: .memberName)
        try values.encodeIfPresent(memberPhoto?.id, forKey: .memberPhotoID)
        try values.encode(address, forKey: .address)
        try values.encodeIfPresent(shortcutName, forKey: .shortcutName)
        try values.encodeIfPresent(nativeCall, forKey: .nativeCall)
        try values.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        if !otherPhoneNumbers.isEmpty { try values.encode(otherPhoneNumbers, forKey: .otherPhoneNumbers) }
        try values.encodeIfPresent(familyMemberID, forKey: .familyMemberID)
        try values.encodeIfPresent(invitationID, forKey: .invitationID)
        try values.encodeIfPresent(buttonColorHex, forKey: .buttonColorHex)
        try values.encodeIfPresent(photo?.id, forKey: .photoID)
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
        case missingName, missingShortcutName, invalidAddress, nameTooLong, invalidPhoneNumber, invalidFamilyMember, invalidAppearance, missingPrimaryNumber, tooManyPhoneNumbers

        public var errorDescription: String? {
            switch self {
            case .invalidAppearance: return "Choose a button color and a photo smaller than 1 MB."
            case .invalidFamilyMember: return "Choose a paired family member."
            case .missingName: return "Enter the person's name."
            case .nameTooLong: return "Use a name with 80 characters or fewer."
            case .invalidPhoneNumber: return "That phone number doesn't look right. For an international number, start with + and the country code."
            case .missingPrimaryNumber: return "Choose which of their numbers Porch calls if it isn't answered."
            case .tooManyPhoneNumbers: return "Save up to \(CallContact.maximumPhoneNumbers) phone numbers for one person."
            case .missingShortcutName: return "Enter the exact name of a shortcut saved in the Shortcuts app on this iPad."
            case .invalidAddress:
                return "Use one FaceTime email address or a phone number with 7–15 digits. Use + and the country code for international numbers. Extensions and multiple recipients aren't supported."
            }
        }
    }
}
