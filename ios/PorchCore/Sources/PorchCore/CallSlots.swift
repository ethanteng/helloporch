import Foundation

public enum KeypadAction: String, Codable, CaseIterable {
    case person, callControl, toggleVideo
    public var title: String {
        switch self {
        case .person: return "Call a person"
        case .callControl: return "Answer / decline / hang up"
        case .toggleVideo: return "Turn video off / on"
        }
    }
}

/// Stable physical digits, in telephone order. Older six-person setups migrate
/// without moving anyone; 9 and 0 are initially reserved for call controls.
public struct CallSlots: Equatable {
    public static let digits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
    public static let count = digits.count
    private static let storageKey = "porch.slots.v2"
    private struct Slot: Codable, Equatable { var action: KeypadAction; var contact: CallContact? }
    private var slots: [Slot]
    public var contacts: [CallContact?] { slots.map { $0.action == .person ? $0.contact : nil } }

    public init() {
        slots = Self.digits.map { Slot(action: $0 == 0 ? .callControl : $0 == 9 ? .toggleVideo : .person) }
    }
    private func index(_ digit: Int) -> Int? { Self.digits.firstIndex(of: digit) }
    public func action(for digit: Int) -> KeypadAction? { index(digit).map { slots[$0].action } }
    public func contact(for digit: Int) -> CallContact? {
        guard let index = index(digit), slots[index].action == .person else { return nil }
        return slots[index].contact
    }
    public func digit(for action: KeypadAction) -> Int? { Self.digits.first { self.action(for: $0) == action } }
    public mutating func setAction(_ action: KeypadAction, for digit: Int) throws {
        guard let index = index(digit) else { throw ValidationError.invalidSlot }
        slots[index].action = action
        if action != .person { slots[index].contact = nil }
    }
    public mutating func setContact(_ contact: CallContact?, for digit: Int) throws {
        guard let index = index(digit) else { throw ValidationError.invalidSlot }
        let validated = try contact.map { contact in
            if let native = contact.nativeCall {
                guard contact.shortcutName == nil, contact.address.isEmpty else { throw ValidationError.invalidSavedSlots }
                return try CallContact(name: contact.name, nativeCall: native, phoneNumber: contact.phoneNumber,
                    familyMemberID: contact.familyMemberID, invitationID: contact.invitationID, buttonColorHex: contact.buttonColorHex, photoData: contact.photoData)
            }
            guard contact.phoneNumber == nil, contact.familyMemberID == nil, contact.invitationID == nil else { throw ValidationError.invalidSavedSlots }
            return try CallContact(name: contact.name, address: contact.address, shortcutName: contact.shortcutName, buttonColorHex: contact.buttonColorHex, photoData: contact.photoData)
        }
        slots[index] = Slot(action: .person, contact: validated)
    }
    /// Pair by the server-issued invitation identity, never a person's name.
    /// Removal of a member also removes their stale calling target.
    public mutating func reconcile(with state: FamilySnapshot) throws {
        guard state.me.role == .bedside else { return }
        for digit in Self.digits {
            guard let contact = contact(for: digit), let native = contact.nativeCall else { continue }
            let linked = Self.member(for: contact, in: state)?.id
            if linked != contact.familyMemberID {
                try setContact(CallContact(name: contact.name, nativeCall: native, phoneNumber: contact.phoneNumber,
                    familyMemberID: linked, invitationID: contact.invitationID, buttonColorHex: contact.buttonColorHex, photoData: contact.photoData), for: digit)
            }
        }
    }
    /// The caregiver's saved name also labels incoming calls and announcements.
    /// Resolve through the same identities as pairing, including newly accepted invites.
    public func incomingCallerName(for call: FamilyCallRecord, in state: FamilySnapshot) -> String {
        incomingContact(for: call, in: state)?.name ?? call.callerName
    }
    public func incomingContact(for call: FamilyCallRecord, in state: FamilySnapshot) -> CallContact? {
        guard state.me.role == .bedside, call.to == state.me.id else { return nil }
        return contacts.compactMap { $0 }.first {
            $0.nativeCall != nil && Self.member(for: $0, in: state)?.id == call.from
        }
    }
    private static func member(for contact: CallContact, in state: FamilySnapshot) -> FamilyPerson? {
        contact.invitationID.flatMap { id in state.people.first { $0.invitationID == id } }
            ?? contact.familyMemberID.flatMap { id in state.people.first { $0.id == id } }
    }
    public static func load(from defaults: UserDefaults = .standard) throws -> Self {
        var result = Self()
        if let data = defaults.data(forKey: storageKey) {
            let saved = try JSONDecoder().decode([Slot].self, from: data)
            guard saved.count == count else { throw ValidationError.invalidSavedSlots }
            for (digit, slot) in zip(digits, saved) {
                guard slot.action == .person || slot.contact == nil else { throw ValidationError.invalidSavedSlots }
                try result.setContact(slot.contact, for: digit)
                try result.setAction(slot.action, for: digit)
            }
        } else if let data = defaults.data(forKey: "porch.slots.v1") {
            let saved = try JSONDecoder().decode([CallContact?].self, from: data)
            guard saved.count == 6 else { throw ValidationError.invalidSavedSlots }
            for (index, contact) in saved.enumerated() { try result.setContact(contact, for: index + 1) }
            try result.save(to: defaults)
        } else if let data = defaults.data(forKey: "porch.contact.v1") {
            try result.setContact(JSONDecoder().decode(CallContact.self, from: data), for: 1)
            try result.save(to: defaults)
        }
        return result
    }
    public func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(slots), forKey: Self.storageKey)
        defaults.removeObject(forKey: "porch.slots.v1")
        defaults.removeObject(forKey: "porch.contact.v1")
    }
    public enum ValidationError: LocalizedError {
        case invalidSlot, invalidSavedSlots
        public var errorDescription: String? {
            switch self {
            case .invalidSlot: return "Choose a keypad digit from 0 to 9."
            case .invalidSavedSlots: return "The saved keypad settings could not be read. Please check them in caregiver mode."
            }
        }
    }
}
