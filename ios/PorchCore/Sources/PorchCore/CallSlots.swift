import Foundation

public enum KeypadAction: String, Codable, CaseIterable {
    case unassigned, person, callControl, toggleVideo, messages
    public var title: String {
        switch self {
        case .unassigned: return "No action"
        case .person: return "Call a person"
        case .callControl: return "Answer / decline / hang up"
        case .toggleVideo: return "Turn video off / on"
        case .messages: return "Play / stop messages"
        }
    }
}

/// Stable physical keys: the digits in telephone order, then * and #, numbered 10 and 11 as DTMF
/// events are. Older six-person setups migrate without moving anyone; 9 and 0 are initially
/// reserved for call controls, and the other keys start with no action.
public struct CallSlots: Equatable {
    public static let star = 10, pound = 11
    public static let digits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, star, pound]
    public static let count = digits.count
    /// The key as the keypad labels it.
    public static func symbol(for digit: Int) -> String { digit == star ? "*" : digit == pound ? "#" : String(digit) }
    /// The key a keypad or phone symbol names: "0" to "9", "*" or "#".
    public static func digit(forSymbol symbol: String) -> Int? { digits.first { self.symbol(for: $0) == symbol } }
    private static let storageKey = "porch.slots.v2"
    /// 0–9 stay under `storageKey` as ten slots, and * and # go beside them, so a build from before
    /// those two keys can still read the keypad.
    private static let digitSlots = 10
    private static let symbolsStorageKey = "porch.slots.v2.symbols"
    /// A key with no action is saved as a person key with no one on it, the way builds from before
    /// No action saved an empty key, so they can still read the keypad.
    private struct Slot: Codable, Equatable { var action: KeypadAction; var contact: CallContact? }
    private var slots: [Slot]
    public var contacts: [CallContact?] { slots.map { $0.action == .person ? $0.contact : nil } }

    public init() {
        slots = Self.digits.map { Slot(action: $0 == 0 ? .callControl : $0 == 9 ? .toggleVideo : .person) }
    }
    private func index(_ digit: Int) -> Int? { Self.digits.firstIndex(of: digit) }
    public func action(for digit: Int) -> KeypadAction? {
        index(digit).map { slots[$0].action == .person && slots[$0].contact == nil ? .unassigned : slots[$0].action }
    }
    public func contact(for digit: Int) -> CallContact? {
        guard let index = index(digit), slots[index].action == .person else { return nil }
        return slots[index].contact
    }
    public func digit(for action: KeypadAction) -> Int? { Self.digits.first { self.action(for: $0) == action } }
    public mutating func setAction(_ action: KeypadAction, for digit: Int) throws {
        guard let index = index(digit) else { throw ValidationError.invalidSlot }
        slots[index].action = action == .unassigned ? .person : action
        if action != .person { slots[index].contact = nil }
    }
    public mutating func setContact(_ contact: CallContact?, for digit: Int) throws {
        guard let index = index(digit) else { throw ValidationError.invalidSlot }
        let validated = try contact.map { contact in
            if let native = contact.nativeCall {
                guard contact.shortcutName == nil, contact.address.isEmpty else { throw ValidationError.invalidSavedSlots }
                return try CallContact(name: contact.customName, nativeCall: native, phoneNumber: contact.phoneNumber, otherPhoneNumbers: contact.otherPhoneNumbers,
                    familyMemberID: contact.familyMemberID, invitationID: contact.invitationID, memberName: contact.memberName, buttonColorHex: contact.buttonColorHex).preservingPhoto(from: contact)
            }
            guard contact.phoneNumber == nil, contact.otherPhoneNumbers.isEmpty, contact.familyMemberID == nil, contact.invitationID == nil else { throw ValidationError.invalidSavedSlots }
            return try CallContact(name: contact.customName, address: contact.address, shortcutName: contact.shortcutName, buttonColorHex: contact.buttonColorHex).preservingPhoto(from: contact)
        }
        slots[index] = Slot(action: .person, contact: validated)
    }
    /// Pair by the server-issued invitation identity, never a person's name.
    /// Removal of a member also removes their stale calling target.
    /// Also keeps each contact showing its family member's current name and photo, once the
    /// photo is in `memberPhotos`. A removed member's last name and photo stay until the caregiver edits the key.
    public mutating func reconcile(with state: FamilySnapshot, memberPhotos: ContactPhotoStore = ContactPhotoStore.standard.familyMembers) throws {
        guard state.me.role == .bedside else { return }
        for digit in Self.digits {
            guard let contact = contact(for: digit), let native = contact.nativeCall else { continue }
            let member = Self.member(for: contact, in: state)
            // Until the invitation is accepted, a contact goes by the name the caregiver gave it.
            let invited = member == nil ? contact.invitationID.flatMap { id in state.invitations?.first { $0.id == id }?.name } : nil
            let name = member?.name ?? invited ?? contact.memberName
            var photoID = contact.memberPhotoID
            if let member {
                // A new photo replaces the previous one once it has downloaded. This checks for the file without reading it.
                photoID = member.photoID.flatMap { memberPhotos.contains($0) ? $0 : contact.memberPhotoID }
            }
            if member?.id != contact.familyMemberID || name != contact.memberName || photoID != contact.memberPhotoID {
                try setContact(CallContact(name: contact.customName, nativeCall: native, phoneNumber: contact.phoneNumber, otherPhoneNumbers: contact.otherPhoneNumbers,
                    familyMemberID: member?.id, invitationID: contact.invitationID, memberName: name, buttonColorHex: contact.buttonColorHex)
                    .preservingPhoto(from: contact).showingMember(name: name, photoID: photoID, photos: memberPhotos), for: digit)
            }
        }
    }
    /// The caregiver's saved name also labels incoming calls and announcements.
    /// Resolve through the same identities as pairing, including newly accepted invites.
    public func incomingCallerName(for call: FamilyCallRecord, in state: FamilySnapshot) -> String {
        incomingContact(for: call, in: state)?.name ?? call.callerName
    }
    /// Every keypad contact's phone numbers, sorted and without repeats. These can ring while unknown callers are blocked.
    public var phoneNumbers: [String] { Array(Set(contacts.flatMap { $0?.phoneNumbers ?? [] })).sorted() }
    /// The keypad contact saved with this phone number, primary or not, which names (and releases) a phone voicemail.
    public func contact(forPhoneNumber number: String?) -> CallContact? {
        guard let number, !number.isEmpty else { return nil }
        return contacts.compactMap { $0 }.first { $0.phoneNumbers.contains(number) }
    }
    public func incomingContact(for call: FamilyCallRecord, in state: FamilySnapshot) -> CallContact? {
        guard state.me.role == .bedside, call.to == state.me.id else { return nil }
        if call.source == "phone" {
            // Only a server-verified telephone drop-in borrows a saved person's name and photo;
            // an ordinary phone call keeps showing its number, which anyone can fake.
            guard call.kind == "dropIn", let number = call.callerNumber else { return nil }
            return contacts.compactMap { $0 }.first { $0.nativeCall != nil && $0.phoneNumbers.contains(number) }
        }
        return contacts.compactMap { $0 }.first {
            $0.nativeCall != nil && Self.member(for: $0, in: state)?.id == call.from
        }
    }
    private static func member(for contact: CallContact, in state: FamilySnapshot) -> FamilyPerson? {
        contact.invitationID.flatMap { id in state.people.first { $0.invitationID == id } }
            ?? contact.familyMemberID.flatMap { id in state.people.first { $0.id == id } }
    }
    public static func load(from defaults: UserDefaults = .standard, photoStore: ContactPhotoStore = .standard) throws -> Self {
        var result = Self()
        let decoder = JSONDecoder()
        decoder.userInfo[ContactPhotoStore.codingKey] = photoStore
        if let data = defaults.data(forKey: storageKey) {
            var saved = try decoder.decode([Slot].self, from: data)
            if let symbols = defaults.data(forKey: symbolsStorageKey) { saved += try decoder.decode([Slot].self, from: symbols) }
            result = try restoring(saved)
            if result.contacts.contains(where: { $0?.hasInlinePhoto == true }) {
                // An unavailable filesystem must not make existing contacts
                // unusable. Keep the inline record and retry migration later.
                try? result.save(to: defaults, photoStore: photoStore)
            }
        } else if let data = defaults.data(forKey: "porch.slots.v1") {
            let saved = try decoder.decode([CallContact?].self, from: data)
            guard saved.count == 6 else { throw ValidationError.invalidSavedSlots }
            for (index, contact) in saved.enumerated() { try result.setContact(contact, for: index + 1) }
            try result.save(to: defaults, photoStore: photoStore)
        } else if let data = defaults.data(forKey: "porch.contact.v1") {
            try result.setContact(decoder.decode(CallContact.self, from: data), for: 1)
            try result.save(to: defaults, photoStore: photoStore)
        }
        return result
    }
    /// Read a v2 setup snapshot for a preview without migrations, preferences
    /// writes, photo persistence, or pruning the original app's photo store.
    /// `symbols` is the * and # data saved beside it, which a setup from before those keys doesn't have.
    public static func snapshot(from data: Data, symbols: Data? = nil, photoStore: ContactPhotoStore = .standard) throws -> Self {
        let decoder = JSONDecoder()
        decoder.userInfo[ContactPhotoStore.codingKey] = photoStore
        var saved = try decoder.decode([Slot].self, from: data)
        if let symbols { saved += try decoder.decode([Slot].self, from: symbols) }
        return try restoring(saved)
    }
    /// Saved slots in `digits` order. Setups from before * and # have only the ten digits,
    /// and those two keys keep their defaults.
    private static func restoring(_ saved: [Slot]) throws -> Self {
        guard saved.count == count || saved.count == digitSlots else { throw ValidationError.invalidSavedSlots }
        var result = Self()
        for (digit, slot) in zip(digits, saved) {
            guard slot.action == .person || slot.contact == nil else { throw ValidationError.invalidSavedSlots }
            try result.setContact(slot.contact, for: digit)
            try result.setAction(slot.action, for: digit)
        }
        return result
    }
    public func save(to defaults: UserDefaults = .standard, photoStore: ContactPhotoStore = .standard) throws {
        let encoder = JSONEncoder()
        encoder.userInfo[ContactPhotoStore.codingKey] = photoStore
        // Encoding stores new photos. Finish both halves before either write, so a photo on * or #
        // that cannot be stored does not leave the ten digits already replaced.
        let digits = try encoder.encode(Array(slots.prefix(Self.digitSlots)))
        let symbols = try encoder.encode(Array(slots.dropFirst(Self.digitSlots)))
        defaults.set(digits, forKey: Self.storageKey)
        defaults.set(symbols, forKey: Self.symbolsStorageKey)
        defaults.removeObject(forKey: "porch.slots.v1")
        defaults.removeObject(forKey: "porch.contact.v1")
        photoStore.prune(keeping: Set(contacts.compactMap { $0?.photoID }))
    }
    public enum ValidationError: LocalizedError {
        case invalidSlot, invalidSavedSlots
        public var errorDescription: String? {
            switch self {
            case .invalidSlot: return "Choose a keypad key: 0 to 9, * or #."
            case .invalidSavedSlots: return "The saved keypad settings could not be read. Please check them in caregiver mode."
            }
        }
    }
}
