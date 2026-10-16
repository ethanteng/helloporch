import Foundation

/// Key numbers are stable: clearing a person never shifts another person's key.
public struct CallSlots: Equatable {
    public static let count = 6
    private static let storageKey = "porch.slots.v1"
    private static let legacyKey = "porch.contact.v1"
    public private(set) var contacts: [CallContact?]

    public init() {
        contacts = Array(repeating: nil, count: Self.count)
    }

    public func contact(for slot: Int) -> CallContact? {
        guard (1...Self.count).contains(slot) else { return nil }
        return contacts[slot - 1]
    }

    public mutating func setContact(_ contact: CallContact?, for slot: Int) throws {
        guard (1...Self.count).contains(slot) else { throw ValidationError.invalidSlot }
        // Revalidate decoded contacts as well as contacts created by the form.
        contacts[slot - 1] = try contact.map {
            try CallContact(name: $0.name, address: $0.address, shortcutName: $0.shortcutName)
        }
    }

    public static func load(from defaults: UserDefaults = .standard) throws -> Self {
        var slots = Self()
        if let data = defaults.data(forKey: storageKey) {
            let saved = try JSONDecoder().decode([CallContact?].self, from: data)
            guard saved.count == count else { throw ValidationError.invalidSavedSlots }
            for (index, contact) in saved.enumerated() {
                try slots.setContact(contact, for: index + 1)
            }
        } else if let data = defaults.data(forKey: legacyKey) {
            let contact = try JSONDecoder().decode(CallContact.self, from: data)
            try slots.setContact(contact, for: 1)
            try slots.save(to: defaults)
        }
        return slots
    }

    public func save(to defaults: UserDefaults = .standard) throws {
        let data = try JSONEncoder().encode(contacts)
        defaults.set(data, forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.legacyKey)
    }

    public enum ValidationError: LocalizedError {
        case invalidSlot, invalidSavedSlots

        public var errorDescription: String? {
            switch self {
            case .invalidSlot: return "Choose a number from 1 to 6."
            case .invalidSavedSlots: return "The saved contact slots could not be read. Please check your people in setup."
            }
        }
    }
}
