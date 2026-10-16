import Foundation
import XCTest
@testable import PorchCore

final class PorchCoreTests: XCTestCase {
    func testPhoneNormalizationPreservesInternationalNumber() throws {
        let contact = try CallContact(name: " David ", address: "+1 (415) 555-0123")
        XCTAssertEqual(contact.name, "David")
        XCTAssertEqual(contact.address, "+14155550123")
        XCTAssertEqual(contact.faceTimeURL.absoluteString, "facetime://+14155550123")
    }

    func testEmailIsOneEncodedRecipient() throws {
        let contact = try CallContact(name: "David", address: "david+family&home@example.com")
        XCTAssertEqual(contact.faceTimeURL.absoluteString, "facetime://david+family%26home@example.com")
        XCTAssertNil(URLComponents(url: contact.faceTimeURL, resolvingAgainstBaseURL: false)?.query)
    }

    func testRejectsURLsParametersListsAndPhoneExtensions() {
        for address in ["facetime://david@example.com", "david@example.com?x=1", "a@example.com;b@example.com", "+14155550123#42", "4155550123 ext 2", "++14155550123", "123", "", "１２３４５６７８９"] {
            XCTAssertThrowsError(try CallContact(name: "David", address: address), address)
        }
        XCTAssertThrowsError(try CallContact(name: " ", address: "david@example.com"))
    }

    func testSavedContactRoundTrip() throws {
        let original = try CallContact(name: "David", address: "david@example.com")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(CallContact.self, from: data), original)
    }

    func testShortcutNameIsOneEncodedQueryValue() throws {
        let name = "Call José & 家人 + #1?input=clipboard%"
        let contact = try CallContact(name: " José ", shortcutName: " \(name)\n")
        XCTAssertEqual(contact.name, "José")
        XCTAssertEqual(contact.shortcutName, name)
        XCTAssertEqual(contact.address, "")
        let url = contact.launchURL
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "shortcuts")
        XCTAssertEqual(components.host, "run-shortcut")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "name", value: name)])
        XCTAssertNil(components.fragment)
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        let data = try JSONEncoder().encode(contact)
        XCTAssertEqual(try JSONDecoder().decode(CallContact.self, from: data), contact)
    }

    func testShortcutRequiresNameAndLabel() throws {
        XCTAssertThrowsError(try CallContact(name: "David", shortcutName: " \n"))
        XCTAssertThrowsError(try CallContact(name: " ", shortcutName: "Call David"))
        let contact = try CallContact(name: "David", shortcutName: "Call David")
        XCTAssertEqual(contact.launchURL.absoluteString, "shortcuts://run-shortcut?name=Call%20David")
    }

    func testExistingSavedContactKeepsDirectFaceTimeCalling() throws {
        let data = Data(#"{"name":"David","address":"+14155550123"}"#.utf8)
        let saved = try JSONDecoder().decode(CallContact.self, from: data)
        let contact = try CallContact(name: saved.name, address: saved.address, shortcutName: saved.shortcutName)
        XCTAssertNil(contact.shortcutName)
        XCTAssertEqual(contact.launchURL, contact.faceTimeURL)
        XCTAssertEqual(contact.launchURL.absoluteString, "facetime://+14155550123")
    }

    func testHeldKeyCannotRepeatUntilReleased() {
        var trigger = CallTrigger()
        XCTAssertTrue(trigger.keyDown(0x59))
        XCTAssertFalse(trigger.keyDown(0x59))
        trigger.keyUp(0x59)
        XCTAssertTrue(trigger.keyDown(0x59))
        XCTAssertFalse(trigger.keyDown(0x5F)) // keypad 7 must not call
    }

    func testKeypadAndKeyboardRouteToAllSixSlots() {
        var trigger = CallTrigger()
        for slot in 1...6 {
            for code in [0x59 + slot - 1, 0x1E + slot - 1] {
                XCTAssertEqual(CallTrigger.slot(for: code), slot)
                XCTAssertTrue(trigger.keyDown(code))
                XCTAssertFalse(trigger.keyDown(code))
                trigger.keyUp(code)
            }
        }
        for code in [0x58, 0x5F, 0x60, 0x61, 0x62, 0x24, 0x25, 0x26, 0x27, 0x04] {
            XCTAssertNil(CallTrigger.slot(for: code))
            XCTAssertFalse(trigger.keyDown(code))
        }
    }

    func testSixMixedCallingMethodsPersistAndRouteWithoutShiftingKeys() throws {
        try withDefaults { defaults in
            var slots = CallSlots()
            for number in 1...6 {
                let contact = try number.isMultiple(of: 2)
                    ? CallContact(name: "Person \(number)", address: "+1415555000\(number)")
                    : CallContact(name: "Person \(number)", shortcutName: "Call person \(number)")
                try slots.setContact(contact, for: number)
            }
            try slots.save(to: defaults)
            XCTAssertEqual(try CallSlots.load(from: defaults), slots)
            for number in 1...6 {
                let routedSlot = try XCTUnwrap(CallTrigger.slot(for: 0x59 + number - 1))
                XCTAssertEqual(slots.contact(for: routedSlot)?.name, "Person \(number)")
            }
            let sixth = slots.contact(for: 6)
            try slots.setContact(nil, for: 2)
            try slots.save(to: defaults)
            let loaded = try CallSlots.load(from: defaults)
            XCTAssertEqual(loaded.contacts.count, 6)
            XCTAssertNil(loaded.contact(for: 2))
            XCTAssertEqual(loaded.contact(for: 3)?.shortcutName, "Call person 3")
            XCTAssertEqual(loaded.contact(for: 6), sixth)
            XCTAssertEqual(loaded.contact(for: 6)?.launchURL.absoluteString, "facetime://+14155550006")
        }
    }

    func testExistingContactMigratesToSlotOneForBothCallingMethods() throws {
        for contact in [try CallContact(name: "David", address: "david@example.com"),
                        try CallContact(name: "David", shortcutName: "Call David")] {
            try withDefaults { defaults in
                defaults.set(try JSONEncoder().encode(contact), forKey: "porch.contact.v1")
                var slots = try CallSlots.load(from: defaults)
                XCTAssertEqual(slots.contact(for: 1), contact)
                XCTAssertTrue(slots.contacts.dropFirst().allSatisfy { $0 == nil })
                XCTAssertNil(defaults.data(forKey: "porch.contact.v1"))
                XCTAssertEqual(try CallSlots.load(from: defaults), slots)
                // Clearing key 1 must not resurrect the contact on relaunch.
                try slots.setContact(nil, for: 1)
                try slots.save(to: defaults)
                XCTAssertTrue(try CallSlots.load(from: defaults).contacts.allSatisfy { $0 == nil })
            }
        }
    }

    func testEmptyAndOutOfRangeSlotsCannotResolveToAPerson() throws {
        var slots = CallSlots()
        let contact = try CallContact(name: "David", shortcutName: "Call David")
        try slots.setContact(contact, for: 6)
        for number in [-1, 0, 1, 2, 3, 4, 5, 7] {
            XCTAssertNil(slots.contact(for: number))
        }
        for number in [-1, 0, 7] {
            XCTAssertThrowsError(try slots.setContact(contact, for: number))
        }
        XCTAssertEqual(slots.contact(for: 6), contact)
    }

    func testMalformedSavedSlotsAreRejectedWithoutRestoringLegacyContact() throws {
        try withDefaults { defaults in
            let legacy = try JSONEncoder().encode(CallContact(name: "David", shortcutName: "Call David"))
            defaults.set(legacy, forKey: "porch.contact.v1")
            for json in ["[null]", #"[{"name":"Bad","address":"https://example.com"},null,null,null,null,null]"#] {
                defaults.set(Data(json.utf8), forKey: "porch.slots.v1")
                XCTAssertThrowsError(try CallSlots.load(from: defaults))
                XCTAssertEqual(defaults.data(forKey: "porch.contact.v1"), legacy)
            }
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "PorchCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testTouchAndKeyboardShareCooldownEvenAfterFocusReset() {
        var trigger = CallTrigger()
        XCTAssertTrue(trigger.allowLaunch(at: 10))
        trigger.resetKeys()
        XCTAssertFalse(trigger.allowLaunch(at: 11))
        XCTAssertTrue(trigger.allowLaunch(at: 12))
    }
}
