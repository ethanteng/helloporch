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

    func testNativeCallsPersistAlongsideExistingMethods() throws {
        try withDefaults { defaults in
            var slots = CallSlots()
            let voice = try CallContact(name: "David", nativeCall: NativeCall(room: " Family-David ", mode: .voice))
            let video = try CallContact(name: "Maria", nativeCall: NativeCall(room: "family-maria", mode: .video))
            try slots.setContact(voice, for: 2)
            try slots.setContact(video, for: 6)
            try slots.setContact(CallContact(name: "Anna", shortcutName: "Call Anna"), for: 1)
            try slots.setContact(CallContact(name: "James", address: "james@example.com"), for: 3)
            try slots.save(to: defaults)
            let loaded = try CallSlots.load(from: defaults)
            XCTAssertEqual(loaded, slots)
            XCTAssertEqual(loaded.contact(for: 2)?.nativeCall?.room, "family-david")
            XCTAssertEqual(loaded.contact(for: 2)?.nativeCall?.mode, .voice)
            XCTAssertEqual(loaded.contact(for: 6)?.nativeCall?.mode, .video)
            XCTAssertNil(loaded.contact(for: 1)?.nativeCall)
            XCTAssertNil(loaded.contact(for: 3)?.nativeCall)
        }
    }

    func testNativeRoomNamesRejectURLsAndInvalidNames() {
        for room in ["", " ", "family/other", "a?x=1", "a#b", "a b", "家人", "-room", String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try NativeCall(room: room, mode: .voice), room)
        }
    }

    func testMalformedNativeSavedDataIsRevalidated() throws {
        try withDefaults { defaults in
            for json in [
                #"[{"name":"David","address":"","nativeCall":{"room":"../room","mode":"voice"}},null,null,null,null,null]"#,
                #"[{"name":"David","address":"david@example.com","nativeCall":{"room":"room","mode":"video"}},null,null,null,null,null]"#,
                #"[{"name":"David","address":"","nativeCall":{"room":"room","mode":"invalid"}},null,null,null,null,null]"#,
            ] {
                defaults.set(Data(json.utf8), forKey: "porch.slots.v1")
                XCTAssertThrowsError(try CallSlots.load(from: defaults))
            }
        }
    }

    func testNativeServerAllowsHTTPSAndLocalhostOnly() throws {
        let code = "prototype-code-for-test"
        let server = try NativeCallServer(url: " https://porch.example.com/ ", accessCode: code)
        XCTAssertEqual(server.tokenURL.absoluteString, "https://porch.example.com/api/calls/token")
        XCTAssertNoThrow(try NativeCallServer(url: "http://localhost:3000", accessCode: code))
        for url in ["http://porch.example.com", "https://a:b@porch.example.com", "https://porch.example.com/path", "https://porch.example.com?code=secret", "https://porch.example.com#room", "wss://porch.example.com", "porch.example.com"] {
            XCTAssertThrowsError(try NativeCallServer(url: url, accessCode: code), url)
        }
        for invalid in ["short", "code with spaces in it", "abcdefghijklmnop\r\nAuthorization: bad", String(repeating: "a", count: 257)] {
            XCTAssertThrowsError(try NativeCallServer(url: "https://porch.example.com", accessCode: invalid))
        }
    }

    func testPhoneFallbackRetainsPorchModeAndStableSlotAcrossRelaunch() throws {
        try withDefaults { defaults in
            var slots = CallSlots()
            let contact = try CallContact(name: "David", nativeCall: NativeCall(room: "family-david", mode: .video),
                phoneNumber: " +1 (415) 555-0123 ")
            try slots.setContact(contact, for: 4)
            try slots.save(to: defaults)
            let loaded = try CallSlots.load(from: defaults)
            XCTAssertEqual(loaded.contact(for: 4)?.nativeCall?.mode, .video)
            XCTAssertEqual(loaded.contact(for: 4)?.nativeCall?.room, "family-david")
            XCTAssertEqual(loaded.contact(for: 4)?.phoneNumber, "+14155550123")
            XCTAssertNil(loaded.contact(for: 1))
            try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "family-david", mode: .video)), for: 4)
            try slots.save(to: defaults)
            XCTAssertNil(try CallSlots.load(from: defaults).contact(for: 4)?.phoneNumber)
        }
    }

    func testPhoneFallbackRequiresAnInternationalNumberWithoutExtensions() throws {
        XCTAssertEqual(try CallContact.normalizedPhoneNumber("+44 20 7946 0123"), "+442079460123")
        for phone in ["4155550123", "", " ", "+01415550123", "+1911", "+14155550123 ext 2", "+14155550123#2", "++14155550123", "tel:+14155550123", "+１２３４５６７８９０", "+1234567890123456"] {
            XCTAssertThrowsError(try CallContact.normalizedPhoneNumber(phone), phone)
        }
    }

    func testCorruptPhoneFallbackCannotChangeLegacyContactsOrBypassValidation() throws {
        try withDefaults { defaults in
            for json in [
                #"[{"name":"David","address":"david@example.com","phoneNumber":"+14155550123"},null,null,null,null,null]"#,
                #"[{"name":"David","address":"","phoneNumber":"4155550123","nativeCall":{"room":"family-david","mode":"voice"}},null,null,null,null,null]"#,
            ] {
                defaults.set(Data(json.utf8), forKey: "porch.slots.v1")
                XCTAssertThrowsError(try CallSlots.load(from: defaults))
            }
        }
    }
    func testFallbackWaitDefaultsPersistsAndBoundsInvalidValues() throws {
        try withDefaults { defaults in
            XCTAssertEqual(CallPreferences.fallbackSeconds(in: defaults), 20)
            CallPreferences.saveFallbackSeconds(45, in: defaults)
            XCTAssertEqual(CallPreferences.fallbackSeconds(in: defaults), 45)
            CallPreferences.saveFallbackSeconds(1, in: defaults)
            XCTAssertEqual(CallPreferences.fallbackSeconds(in: defaults), 5)
            CallPreferences.saveFallbackSeconds(500, in: defaults)
            XCTAssertEqual(CallPreferences.fallbackSeconds(in: defaults), 120)
            defaults.set(-10, forKey: "porch.phoneFallbackSeconds")
            XCTAssertEqual(CallPreferences.fallbackSeconds(in: defaults), 20)
        }
    }

}

final class PhoneNormalizationTests: XCTestCase {
    func testContactsNumbersBecomeE164UsingTheirRegion() throws {
        for input in ["(415) 867-6937", "4158676937", "1 (415) 867-6937", "+1 415 867 6937"] {
            XCTAssertEqual(try PhoneNumberNormalization.e164(input, region: "US"), "+14158676937")
        }
        XCTAssertEqual(try PhoneNumberNormalization.e164("020 7031 3000", region: "GB"), "+442070313000")
        XCTAssertEqual(try PhoneNumberNormalization.e164("+44 20 7031 3000", region: "US"), "+442070313000")
        for invalid in ["911", "not a number", "+1 415 867 6937 ext 42"] {
            XCTAssertThrowsError(try PhoneNumberNormalization.e164(invalid, region: "US"))
        }
    }
}

final class FamilyModelTests: XCTestCase {
    func testInvitationCarriesOnlyItsServerAndOneTimeCode() throws {
        let origin = URL(string: "https://porch.example")!
        let code = String(repeating: "a", count: 64)
        let url = FamilyInvitation.url(origin: origin, code: code)
        let parsed = try FamilyInvitation(url: url)
        XCTAssertEqual(parsed.origin, origin); XCTAssertEqual(parsed.code, code)
        for raw in ["https://porch.example/pair?code=\(code)", "porch://pair?server=https://porch.example&code=short", "porch://pair?server=https://porch.example&code=\(code)&server=https://evil.example", "porch://pair?server=http://public.example&code=\(code)", "porch://pair?server=https://porch.example/path&code=\(code)", "porch://user@pair?server=https://porch.example&code=\(code)"] {
            XCTAssertThrowsError(try FamilyInvitation(url: URL(string: raw)!))
        }
    }
    func testLinkedContactSurvivesPersistenceWithoutChangingPhoneFallback() throws {
        let key = UUID().uuidString
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        let person = UUID().uuidString.lowercased()
        let contact = try CallContact(name: "Ethan", nativeCall: NativeCall(room: "paired", mode: .video), phoneNumber: "+14158676937", familyMemberID: person)
        var slots = CallSlots(); try slots.setContact(contact, for: 3); try slots.save(to: defaults)
        let loaded = try CallSlots.load(from: defaults).contact(for: 3)
        XCTAssertEqual(loaded?.familyMemberID, person); XCTAssertEqual(loaded?.phoneNumber, "+14158676937")
        XCTAssertThrowsError(try CallContact(name: "Ethan", nativeCall: NativeCall(room: "paired", mode: .voice), familyMemberID: "a display name"))
    }
}

final class BedsideInvitationTests: XCTestCase {
    func testActivationLinksCannotBeConfusedWithFamilyInvitations() throws {
        let code = String(repeating: "a", count: 64)
        let url = URL(string: "porch://activate?server=https%3A%2F%2Fexample.com&code=\(code)")!
        XCTAssertEqual(try BedsideInvitation(url: url).origin.absoluteString, "https://example.com")
        XCTAssertThrowsError(try FamilyInvitation(url: url))
        XCTAssertThrowsError(try BedsideInvitation(url: FamilyInvitation.url(origin: URL(string: "https://example.com")!, code: code)))
        XCTAssertThrowsError(try BedsideInvitation(url: URL(string: "porch://activate?server=http%3A%2F%2Fexample.com&code=\(code)")!))
    }
}
