import Foundation

/// A key that rings two family members on Porch at once, such as Ethan and his brother David. Whoever answers first
/// talks with the bedside, and the other can still answer and join (the server's lib/family/group-calls.ts).
public struct CallGroup: Codable, Equatable {
    /// People in a group: with the bedside, the three-person call Porch already has.
    public static let maximumPeople = 2
    /// The name the caregiver typed. Empty goes by the people's names, "Ethan & David".
    public let customName: String
    /// The family members it rings, by their Porch IDs, in the order chosen. The first who can ring is called first.
    public let memberIDs: [String]
    /// Their names as Porch last showed them, in the same order. `CallSlots.reconcile` keeps these current;
    /// someone no longer on Porch keeps the last one.
    public private(set) var memberNames: [String]
    public let mode: NativeCall.Mode
    public let buttonColorHex: String?
    private var photo: ContactPhoto?

    /// What Porch shows and says: the caregiver's name, or else the people's.
    public var name: String { customName.isEmpty ? Self.joined(memberNames) : customName }
    public var photoID: String? { photo?.id }
    /// The caregiver's photo for the key, if they chose one.
    public var photoData: Data? { photo?.data }
    /// The people's names as one: "Ethan & David".
    public static func joined(_ names: [String]) -> String { names.joined(separator: " & ") }

    public init(name: String, memberIDs: [String], memberNames: [String], mode: NativeCall.Mode, buttonColorHex: String? = nil, photoData: Data? = nil) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= 80 else { throw CallContact.ValidationError.nameTooLong }
        guard (1...Self.maximumPeople).contains(memberIDs.count), Set(memberIDs).count == memberIDs.count,
              memberIDs.allSatisfy({ UUID(uuidString: $0) != nil }), memberNames.count == memberIDs.count else { throw ValidationError.invalidPeople }
        if let buttonColorHex { guard buttonColorHex.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw CallContact.ValidationError.invalidAppearance } }
        customName = name
        self.memberIDs = memberIDs
        self.memberNames = memberNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        self.mode = mode
        self.buttonColorHex = buttonColorHex?.uppercased()
        photo = try photoData.map { try ContactPhoto(data: $0) }
    }

    /// The same group with some details changed. Its photo stays unless `photoData` replaces it (nil inside removes it).
    public func updating(name: String? = nil, memberIDs: [String]? = nil, memberNames: [String]? = nil, mode: NativeCall.Mode? = nil,
                         buttonColorHex: String?? = nil, photoData: Data?? = nil) throws -> Self {
        var result = try CallGroup(name: name ?? customName, memberIDs: memberIDs ?? self.memberIDs, memberNames: memberNames ?? self.memberNames,
                                   mode: mode ?? self.mode, buttonColorHex: buttonColorHex ?? self.buttonColorHex)
        result.photo = photo
        if let photoData { result.photo = try photoData.map { try ContactPhoto(data: $0) } }
        return result
    }
    /// The same group showing its people's current names, from Porch's IDs to names.
    func showing(names: [String: String]) -> Self {
        var result = self
        result.memberNames = zip(memberIDs, memberNames).map { id, name in names[id] ?? name }
        return result
    }
    /// The key as the call screen and its announcement show it: its name, photo and color. A group has no phone to fall back to.
    public var callContact: CallContact {
        // Two long names joined can pass a contact's 80 characters, so the name is cut to fit. With a fixed room and a
        // known color, that always makes a valid contact.
        try! CallContact(name: name.isEmpty ? "Family" : String(name.prefix(80)), nativeCall: NativeCall(room: "group", mode: mode), buttonColorHex: buttonColorHex).showing(photo: photo)
    }

    private enum CodingKeys: String, CodingKey { case customName, memberIDs, memberNames, mode, buttonColorHex, photoID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let store = decoder.userInfo[ContactPhotoStore.codingKey] as? ContactPhotoStore ?? .standard
        try self.init(name: values.decode(String.self, forKey: .customName), memberIDs: values.decode([String].self, forKey: .memberIDs),
                      memberNames: values.decode([String].self, forKey: .memberNames), mode: values.decode(NativeCall.Mode.self, forKey: .mode),
                      buttonColorHex: values.decodeIfPresent(String.self, forKey: .buttonColorHex))
        photo = try values.decodeIfPresent(String.self, forKey: .photoID).map { try ContactPhoto(id: $0, store: store) }
    }
    public func encode(to encoder: Encoder) throws {
        let store = encoder.userInfo[ContactPhotoStore.codingKey] as? ContactPhotoStore ?? photo?.store ?? .standard
        try photo?.persist(to: store)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(customName, forKey: .customName)
        try values.encode(memberIDs, forKey: .memberIDs)
        try values.encode(memberNames, forKey: .memberNames)
        try values.encode(mode, forKey: .mode)
        try values.encodeIfPresent(buttonColorHex, forKey: .buttonColorHex)
        try values.encodeIfPresent(photo?.id, forKey: .photoID)
    }

    public enum ValidationError: LocalizedError {
        case invalidPeople
        public var errorDescription: String? { "Choose two people on Porch." }
    }
}
