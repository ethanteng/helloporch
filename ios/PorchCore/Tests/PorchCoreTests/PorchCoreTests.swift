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
        XCTAssertFalse(trigger.keyDown(0x58)) // keypad Enter must not call
    }

    func testKeypadAndKeyboardRouteToAllTenDigits() {
        var trigger = CallTrigger()
        for slot in 1...9 {
            for code in [0x59 + slot - 1, 0x1E + slot - 1] {
                XCTAssertEqual(CallTrigger.slot(for: code), slot)
                XCTAssertTrue(trigger.keyDown(code))
                XCTAssertFalse(trigger.keyDown(code))
                trigger.keyUp(code)
            }
        }
        XCTAssertEqual(CallTrigger.slot(for: 0x62), 0)
        XCTAssertEqual(CallTrigger.slot(for: 0x27), 0)
        for code in [0x58, 0x63, 0x28, 0x04] {
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
            XCTAssertEqual(loaded.contacts.count, 10)
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
        for number in [-1, 0, 1, 2, 3, 4, 5, 7, 8, 9, 10] {
            XCTAssertNil(slots.contact(for: number))
        }
        for number in [-1, 10] {
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

final class IncomingCallerNameTests: XCTestCase {
    private let caller = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let bedside = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let invitation = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private func snapshot(role: String = "bedside", includeCaller: Bool = true) throws -> FamilySnapshot {
        let object: [String: Any] = ["householdID": "home", "householdName": "Pat", "dropInEnabled": true,
            "me": ["id": bedside, "name": "Pat", "role": role, "permissions": ["audio": false, "video": false], "online": true],
            "people": includeCaller ? [["id": caller, "invitationID": invitation, "name": "Ethan", "role": "family", "permissions": ["audio": true, "video": true], "online": true]] : [],
            "busy": false, "serverTime": 1]
        return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func call(kind: String = "call", mode: String = "video", recipient: String? = nil) throws -> FamilyCallRecord {
        let object: [String: Any] = ["id": "test-call", "from": caller, "to": recipient ?? bedside, "mode": mode,
            "kind": kind, "state": "pending", "createdAt": 1, "expiresAt": 90, "callerName": "Ethan"]
        return try JSONDecoder().decode(FamilyCallRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testSavedRenameOverridesOriginalInviteNameForVoiceVideoCallsAndDropIns() throws {
        let suite = "CallerNameTests.\(UUID().uuidString)", state = try snapshot()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "paired", mode: .video),
            phoneNumber: "+14155550123", familyMemberID: caller), for: 1)
        try slots.save(to: defaults)
        var loaded = try CallSlots.load(from: defaults)
        try loaded.reconcile(with: state)
        for kind in ["call", "dropIn"] {
            for mode in ["voice", "video"] {
                let incoming = try call(kind: kind, mode: mode)
                XCTAssertEqual(loaded.incomingCallerName(for: incoming, in: state), "David")
                XCTAssertEqual(incoming.callerName, "Ethan", "The local label must not change the caller's server identity")
            }
        }
        XCTAssertEqual(loaded.contact(for: 1)?.phoneNumber, "+14155550123")
    }
    func testAcceptedInvitationUsesSavedNameBeforeAndAfterLinkReconciliation() throws {
        let state = try snapshot(), incoming = try call()
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "家駿", nativeCall: NativeCall(room: "paired", mode: .video),
            familyMemberID: UUID().uuidString, invitationID: invitation), for: 1)
        XCTAssertEqual(slots.incomingCallerName(for: incoming, in: state), "家駿")
        try slots.reconcile(with: state)
        XCTAssertEqual(slots.contact(for: 1)?.familyMemberID, caller)
        XCTAssertEqual(slots.incomingCallerName(for: incoming, in: state), "家駿")
    }
    func testMissingRemovedAndUnrelatedSlotsFallBackWithoutMatchingByName() throws {
        let state = try snapshot(), incoming = try call()
        var slots = CallSlots()
        XCTAssertEqual(slots.incomingCallerName(for: incoming, in: state), "Ethan")
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "other", mode: .voice),
            familyMemberID: UUID().uuidString, invitationID: UUID().uuidString), for: 1)
        XCTAssertEqual(slots.incomingCallerName(for: incoming, in: state), "Ethan")
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "paired", mode: .voice), familyMemberID: caller), for: 1)
        XCTAssertEqual(try slots.incomingCallerName(for: incoming, in: snapshot(includeCaller: false)), "Ethan")
        try slots.setAction(.callControl, for: 1)
        XCTAssertEqual(slots.incomingCallerName(for: incoming, in: state), "Ethan")
    }
    func testBedsideAliasesDoNotLabelFamilyModeOrCallsToAnotherRecipient() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "paired", mode: .voice), familyMemberID: caller), for: 1)
        XCTAssertEqual(try slots.incomingCallerName(for: call(), in: snapshot(role: "family")), "Ethan")
        XCTAssertEqual(try slots.incomingCallerName(for: call(recipient: caller), in: snapshot()), "Ethan")
    }
    func testOnlyTelephoneDropInsUseTheSavedPersonForTheirNumber() throws {
        let state = try snapshot()
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "paired", mode: .voice), phoneNumber: "+14155550200"), for: 1)
        func phone(kind: String, number: String? = "+14155550200") throws -> FamilyCallRecord {
            var object: [String: Any] = ["id": "phone-call", "from": "sip:PA_test", "to": bedside, "mode": "voice", "kind": kind, "state": "pending",
                "createdAt": 1, "expiresAt": 46, "callerName": kind == "dropIn" ? "Dave" : "+14155550200", "source": "phone"]
            if let number { object["callerNumber"] = number }
            return try JSONDecoder().decode(FamilyCallRecord.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertEqual(try slots.incomingCallerName(for: phone(kind: "dropIn"), in: state), "David")
        XCTAssertEqual(try slots.incomingCallerName(for: phone(kind: "call"), in: state), "+14155550200", "An unverified number must not borrow a saved name")
        XCTAssertEqual(try slots.incomingCallerName(for: phone(kind: "dropIn", number: "+14155550999"), in: state), "Dave")
        XCTAssertEqual(try slots.incomingCallerName(for: phone(kind: "dropIn", number: nil), in: state), "Dave")
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

final class BedsideAndKeypadTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "BedsideTests.\(UUID().uuidString)")! }
    func testSixContactsMigrateToTenDigitsWithoutMovingAnyone() throws {
        let prefs = defaults()
        let contacts = try (1...6).map { try CallContact(name: "Person \($0)", nativeCall: NativeCall(room: "person-\($0)", mode: .voice)) }
        prefs.set(try JSONEncoder().encode(contacts), forKey: "porch.slots.v1")
        let slots = try CallSlots.load(from: prefs)
        for digit in 1...6 { XCTAssertEqual(slots.contact(for: digit), contacts[digit - 1]) }
        XCTAssertNil(slots.contact(for: 7)); XCTAssertNil(slots.contact(for: 8))
        XCTAssertEqual(slots.action(for: 9), .toggleVideo); XCTAssertEqual(slots.action(for: 0), .callControl)
        XCTAssertEqual(try CallSlots.load(from: prefs), slots)
        XCTAssertNil(prefs.data(forKey: "porch.slots.v1"))
    }
    func testAnyDigitCanBeAPersonOrControlAndChangesSurviveRelaunch() throws {
        let prefs = defaults(); var slots = CallSlots()
        let person = try CallContact(name: "Pat", nativeCall: NativeCall(room: "pat", mode: .video))
        for digit in CallSlots.digits { try slots.setContact(person, for: digit) }
        XCTAssertEqual(slots.contacts.compactMap { $0 }.count, 10)
        try slots.setAction(.callControl, for: 4); try slots.setAction(.toggleVideo, for: 7)
        try slots.save(to: prefs)
        let loaded = try CallSlots.load(from: prefs)
        XCTAssertEqual(loaded.digit(for: .callControl), 4); XCTAssertNil(loaded.contact(for: 4))
        XCTAssertEqual(loaded.action(for: 7), .toggleVideo); XCTAssertEqual(loaded.contact(for: 0), person)
    }
    func testMessagesKeySurvivesRelaunchAndBedsideQueueDecodes() throws {
        let prefs = defaults(); var slots = CallSlots()
        try slots.setAction(.messages, for: 8); try slots.save(to: prefs)
        XCTAssertEqual(try CallSlots.load(from: prefs).digit(for: .messages), 8)
        let object: [String: Any] = ["householdID": "home", "householdName": "Pat", "dropInEnabled": false, "messagesEnabled": true,
            "me": ["id": "bed", "name": "Pat", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true], "people": [], "busy": false, "serverTime": 1,
            "messages": [["id": "m1", "from": "f1", "fromName": "Ethan", "kind": "voicemail", "mode": "video", "contentType": "video/quicktime", "durationSeconds": 42, "sentAt": 1_800_000_000, "delivered": false]]]
        let state = try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(state.messages?.first?.fileExtension, "mov"); XCTAssertEqual(state.messagesEnabled, true)
    }
    func testCallControlDistinguishesTapHoldDropInAndCancellation() {
        var input = IncomingCallKey()
        XCTAssertNil(input.begin(0x62, dropIn: false)); XCTAssertNil(input.begin(0x62, dropIn: false))
        XCTAssertEqual(input.release(0x62), .answer); XCTAssertNil(input.release(0x62))
        XCTAssertNil(input.begin(0x62, dropIn: false)); XCTAssertEqual(input.held(0x62), .decline)
        XCTAssertNil(input.release(0x62), "A declined call must never also answer on key release")
        XCTAssertEqual(input.begin(0x62, dropIn: true), .decline); XCTAssertNil(input.release(0x62))
        XCTAssertNil(input.begin(0x62, dropIn: false)); input.cancel(); XCTAssertNil(input.release(0x62))
    }
    func testAcceptingInvitationLinksOnlyMatchingContactAndKeepsFallback() throws {
        let invite = UUID().uuidString, otherInvite = UUID().uuidString, person = UUID().uuidString
        let contact = try CallContact(name: "Same name", nativeCall: NativeCall(room: "person", mode: .video), phoneNumber: "+14158676937", invitationID: invite)
        var slots = CallSlots(); try slots.setContact(contact, for: 8)
        try slots.setContact(CallContact(name: "Same name", nativeCall: NativeCall(room: "other", mode: .voice), invitationID: otherInvite), for: 2)
        func snapshot(people: [[String: Any]]) throws -> FamilySnapshot {
            let object: [String: Any] = ["householdID": "home", "householdName": "Pat", "dropInEnabled": false, "me": ["id": "bed", "name": "Pat", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true], "people": people, "busy": false, "serverTime": 1]
            return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let state = try snapshot(people: [["id": person, "invitationID": invite, "name": "Same name", "role": "family", "permissions": ["audio": false, "video": false], "online": true]])
        try slots.reconcile(with: state)
        XCTAssertEqual(slots.contact(for: 8)?.familyMemberID, person)
        XCTAssertEqual(slots.contact(for: 8)?.phoneNumber, contact.phoneNumber)
        XCTAssertEqual(slots.contact(for: 8)?.nativeCall, contact.nativeCall)
        XCTAssertNil(slots.contact(for: 2)?.familyMemberID)
        let prefs = defaults(); try slots.save(to: prefs)
        XCTAssertEqual(try CallSlots.load(from: prefs), slots)
        try slots.reconcile(with: snapshot(people: []))
        XCTAssertNil(slots.contact(for: 8)?.familyMemberID, "Revoked devices must not remain linked")
    }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(month: Int = 10, hour: Int, minute: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: 16, hour: hour, minute: minute))! }
    func testSunAndMoonFollowScheduleAcrossMidnight() {
        let prefs = BedsidePreferences()
        let dawn = BedsideScene(date: date(hour: 6), preferences: prefs, calendar: calendar)
        let midday = BedsideScene(date: date(hour: 12), preferences: prefs, calendar: calendar)
        let dusk = BedsideScene(date: date(hour: 18), preferences: prefs, calendar: calendar)
        let midnight = BedsideScene(date: date(hour: 0), preferences: prefs, calendar: calendar)
        XCTAssertTrue(dawn.isDay); XCTAssertEqual(dawn.progress, 0)
        XCTAssertEqual(midday.progress, 0.5); XCTAssertEqual(midday.period, .afternoon)
        XCTAssertFalse(dusk.isDay); XCTAssertEqual(dusk.progress, 0); XCTAssertEqual(dusk.period, .evening)
        XCTAssertEqual(midnight.progress, 0.5); XCTAssertEqual(midnight.period, .night)
        for hour in 0...23 {
            let scene = BedsideScene(date: date(hour: hour, minute: 59), preferences: prefs, calendar: calendar)
            XCTAssertGreaterThanOrEqual(scene.progress, 0); XCTAssertLessThan(scene.progress, 1)
        }
    }
    func testSeasonsFollowHemisphereAndLocalCalendar() {
        var prefs = BedsidePreferences()
        let seasons: [(Int, BedsideScene.Season, BedsideScene.Season)] = [(1, .winter, .summer), (4, .spring, .fall), (7, .summer, .winter), (10, .fall, .spring)]
        for (month, north, south) in seasons {
            prefs.hemisphere = .northern
            XCTAssertEqual(BedsideScene(date: date(month: month, hour: 12), preferences: prefs, calendar: calendar).season, north)
            prefs.hemisphere = .southern
            XCTAssertEqual(BedsideScene(date: date(month: month, hour: 12), preferences: prefs, calendar: calendar).season, south)
        }
        var local = calendar; local.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        prefs.hemisphere = .northern
        XCTAssertFalse(BedsideScene(date: date(hour: 8), preferences: prefs, calendar: local).isDay)
    }
    func testDisplayPreferencesDefaultDarkAndPersistSchedule() {
        let defaults = defaults(); var prefs = BedsidePreferences.load(from: defaults)
        XCTAssertEqual(prefs.appearance, .default)
        prefs.appearance = .dynamic; prefs.hemisphere = .southern; prefs.dayStart = 7; prefs.nightStart = 20; prefs.save(to: defaults)
        XCTAssertEqual(BedsidePreferences.load(from: defaults), prefs)
        XCTAssertFalse(BedsideScene(date: date(hour: 19), preferences: .init(), calendar: calendar).isDay)
        XCTAssertTrue(BedsideScene(date: date(hour: 19), preferences: prefs, calendar: calendar).isDay)
    }
}

final class RecipientAppearancePersistenceTests: XCTestCase {
    func testPhotoAndColorSurviveSavingAndAcceptedInvitation() throws {
        let suite = "appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let photoStore = ContactPhotoStore(directoryURL: directory)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let invitation = UUID().uuidString, member = UUID().uuidString
        let photo = Data([1, 2, 3, 4])
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "david", mode: .video),
            phoneNumber: "+14155550123", invitationID: invitation, buttonColorHex: "fFcC00", photoData: photo), for: 3)
        try slots.save(to: defaults, photoStore: photoStore)
        slots = try CallSlots.load(from: defaults, photoStore: photoStore)
        let object: [String: Any] = ["householdID": "home", "householdName": "Pat", "dropInEnabled": true,
            "me": ["id": "bedside", "name": "Pat", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true],
            "people": [["id": member, "invitationID": invitation, "name": "Original name", "role": "family", "permissions": ["audio": true, "video": true], "online": true]], "busy": false, "serverTime": 1]
        let state = try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        try slots.reconcile(with: state)
        try slots.save(to: defaults, photoStore: photoStore)
        let loaded = try CallSlots.load(from: defaults, photoStore: photoStore)
        let saved = try XCTUnwrap(loaded.contact(for: 3))
        XCTAssertEqual(saved.buttonColorHex, "FFCC00"); XCTAssertEqual(saved.photoData, photo)
        XCTAssertEqual(saved.familyMemberID, member); XCTAssertEqual(saved.phoneNumber, "+14155550123")
        for kind in ["call", "dropIn"] {
            let call: [String: Any] = ["id": "call", "from": member, "to": "bedside", "mode": "video", "kind": kind, "state": "pending", "createdAt": 1, "expiresAt": 90, "callerName": "Original name"]
            let incoming = try JSONDecoder().decode(FamilyCallRecord.self, from: JSONSerialization.data(withJSONObject: call))
            XCTAssertEqual(loaded.incomingContact(for: incoming, in: state), saved)
        }
    }

    func testOldContactsRemainReadableAndAppearanceValidationIsBounded() throws {
        let legacy = Data(#"{"name":"David","address":"david@example.com"}"#.utf8)
        let contact = try JSONDecoder().decode(CallContact.self, from: legacy)
        XCTAssertNil(contact.photoData); XCTAssertNil(contact.buttonColorHex)
        var slots = CallSlots(); try slots.setContact(contact, for: 1)
        let call = try NativeCall(room: "test", mode: .voice)
        for color in ["#FFFFFF", "FFF", "ZZZZZZ", "12345678"] {
            XCTAssertThrowsError(try CallContact(name: "David", nativeCall: call, buttonColorHex: color))
        }
        XCTAssertThrowsError(try CallContact(name: "David", nativeCall: call, photoData: Data()))
        XCTAssertThrowsError(try CallContact(name: "David", nativeCall: call, photoData: Data(repeating: 0, count: 1_000_001)))
    }
}
