import XCTest
@testable import PorchCore

/// A key waiting for someone takes up the invitation sent for them from anywhere, so no caregiver has to link it by hand.
final class KeysFollowInvitationsTests: XCTestCase {
    private let now: TimeInterval = 1_800_000_000
    private let lisaInvite = "11111111-1111-4111-8111-111111111111"
    private let lisa = "22222222-2222-4222-8222-222222222222"
    private func snapshot(invitations: [[String: Any]] = [], people: [[String: Any]] = [], role: String = "bedside") throws -> FamilySnapshot {
        let object: [String: Any] = ["householdID": "home", "householdName": "Mom", "dropInEnabled": true,
            "me": ["id": "bed", "name": "Mom", "role": role, "permissions": ["audio": false, "video": false], "online": true],
            "people": people, "invitations": invitations, "busy": false, "serverTime": now]
        return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func invitation(_ id: String, _ name: String) -> [String: Any] { ["id": id, "name": name, "expiresAt": now + 3600] }
    private func member(_ id: String, invitation: String, invited: String, name: String? = nil, joinedAt: TimeInterval?, photoID: String? = nil) -> [String: Any] {
        var person: [String: Any] = ["id": id, "name": name ?? invited, "invitedName": invited, "invitationID": invitation, "role": "family",
            "permissions": ["audio": true, "video": true], "online": true]
        if let joinedAt { person["joinedAt"] = joinedAt }
        if let photoID { person["photoID"] = photoID }
        return person
    }
    private func phoneKey(_ name: String, room: String = "lisa", number: String = "+14155550123") throws -> CallContact {
        try CallContact(name: name, nativeCall: NativeCall(room: room, mode: .video), phoneNumber: number, buttonColorHex: "FFCC00", photoData: Data([1, 2, 3]))
    }

    func testPhoneKeyFollowsAnInvitationSentElsewhereThenLinksWhenTheyJoin() throws {
        var slots = CallSlots()
        try slots.setContact(phoneKey("Lisa"), for: 2)
        try slots.reconcile(with: snapshot(invitations: [invitation(lisaInvite, " lisa ")]))
        let invited = try XCTUnwrap(slots.contact(for: 2))
        XCTAssertEqual(invited.invitationID, lisaInvite)
        XCTAssertNil(invited.familyMemberID)
        XCTAssertEqual(invited.name, "lisa", "Until they join, the key goes by the invitation's name")
        XCTAssertEqual(invited.phoneNumber, "+14155550123"); XCTAssertEqual(invited.nativeCall?.room, "lisa")
        XCTAssertEqual(invited.buttonColorHex, "FFCC00"); XCTAssertEqual(invited.customPhotoData, Data([1, 2, 3]))

        // She joins and chooses her own name, which the key then shows.
        try slots.reconcile(with: snapshot(people: [member(lisa, invitation: lisaInvite, invited: "lisa", name: "Lisa Chen", joinedAt: now - 60)]))
        XCTAssertEqual(slots.contact(for: 2)?.familyMemberID, lisa)
        XCTAssertEqual(slots.contact(for: 2)?.name, "Lisa Chen")
        XCTAssertEqual(slots.contact(for: 2)?.phoneNumber, "+14155550123", "Porch still calls her phone when the app isn't answered")
    }

    func testKeyTakesUpAnInvitationAcceptedWhileTheBedsideWasOfflineForADay() throws {
        for (joinedAt, linked) in [(now - 3600, true), (now - CallSlots.joinedRecentlySeconds, false), (nil, false)] as [(TimeInterval?, Bool)] {
            var slots = CallSlots()
            try slots.setContact(phoneKey("Lisa"), for: 2)
            try slots.reconcile(with: snapshot(people: [member(lisa, invitation: lisaInvite, invited: "LISA", name: "Lisa Chen", joinedAt: joinedAt)]))
            XCTAssertEqual(slots.contact(for: 2)?.familyMemberID, linked ? lisa : nil, "joinedAt \(String(describing: joinedAt))")
            XCTAssertEqual(slots.contact(for: 2)?.name, linked ? "Lisa Chen" : "Lisa")
        }
    }

    func testKeysWhoseInvitationRanOutOrWhosePersonLeftFollowANewOne() throws {
        let expired = "33333333-3333-4333-8333-333333333333", gone = "44444444-4444-4444-8444-444444444444"
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "", nativeCall: NativeCall(room: "a", mode: .voice), invitationID: expired, memberName: "Lisa"), for: 2)
        try slots.setContact(CallContact(name: "", nativeCall: NativeCall(room: "b", mode: .voice), familyMemberID: gone, invitationID: expired.replacingOccurrences(of: "3", with: "5"), memberName: "Dad"), for: 3)
        let dadInvite = "66666666-6666-4666-8666-666666666666"
        try slots.reconcile(with: snapshot(invitations: [invitation(lisaInvite, "Lisa"), invitation(dadInvite, "Dad")]))
        XCTAssertEqual(slots.contact(for: 2)?.invitationID, lisaInvite)
        XCTAssertEqual(slots.contact(for: 3)?.invitationID, dadInvite)
        XCTAssertEqual(slots.contact(for: 3)?.nativeCall?.room, "b")
    }

    func testOnlyTheCaregiversNameForTheInvitationCounts() throws {
        var slots = CallSlots()
        try slots.setContact(phoneKey("Lisa"), for: 2)
        // Someone invited as Ethan who calls herself Lisa doesn't get Lisa's key.
        try slots.reconcile(with: snapshot(people: [member(lisa, invitation: lisaInvite, invited: "Ethan", name: "Lisa", joinedAt: now - 60)]))
        XCTAssertNil(slots.contact(for: 2)?.invitationID)
        XCTAssertNil(slots.contact(for: 2)?.familyMemberID)
        XCTAssertEqual(slots.contact(for: 2)?.name, "Lisa")
    }

    func testAmbiguousNamesAreLeftToTheCaregiver() throws {
        let other = "77777777-7777-4777-8777-777777777777"
        // Two keys named Lisa, one of them already linked: an invitation for "Lisa" could be for either.
        var twoKeys = CallSlots()
        try twoKeys.setContact(phoneKey("Lisa"), for: 2)
        try twoKeys.setContact(CallContact(name: "Lisa", nativeCall: NativeCall(room: "other", mode: .voice), familyMemberID: other), for: 3)
        try twoKeys.reconcile(with: snapshot(invitations: [invitation(lisaInvite, "Lisa")],
            people: [member(other, invitation: "88888888-8888-4888-8888-888888888888", invited: "Lisa", joinedAt: now - 60)]))
        XCTAssertNil(twoKeys.contact(for: 2)?.invitationID)
        // Two invitations named Lisa.
        var oneKey = CallSlots()
        try oneKey.setContact(phoneKey("Lisa"), for: 2)
        try oneKey.reconcile(with: snapshot(invitations: [invitation(lisaInvite, "Lisa"), invitation(other, "lisa")]))
        XCTAssertNil(oneKey.contact(for: 2)?.invitationID)
    }

    func testKeysAlreadyWaitingOrLinkedKeepTheirOwnInvitation() throws {
        let own = "99999999-9999-4999-8999-999999999999"
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "", nativeCall: NativeCall(room: "own", mode: .voice), invitationID: own, memberName: "Lisa"), for: 2)
        try slots.setContact(phoneKey("Sam", room: "sam"), for: 3)
        // Sam's invitation is already on key 2 under another name, so key 3 can't take it.
        try slots.reconcile(with: snapshot(invitations: [invitation(own, "Lisa"), invitation(lisaInvite, "Lisa")]))
        XCTAssertEqual(slots.contact(for: 2)?.invitationID, own, "A key's own open invitation stays")
        XCTAssertNil(slots.contact(for: 3)?.invitationID)
        try slots.reconcile(with: snapshot(invitations: [invitation(own, "Sam")]))
        XCTAssertNil(slots.contact(for: 3)?.invitationID, "An invitation already on a key stays there")
    }

    func testFamilyPhonesLeaveTheKeypadAlone() throws {
        var slots = CallSlots()
        try slots.setContact(phoneKey("Lisa"), for: 2)
        try slots.reconcile(with: snapshot(invitations: [invitation(lisaInvite, "Lisa")], role: "family"))
        XCTAssertNil(slots.contact(for: 2)?.invitationID)
    }

    /// Hand-linking a key drops the previous person's photo. Following an invitation has to do the same, or the key
    /// shows someone who left while it waits for the new person.
    func testAKeyThatFollowsSomeoneNewDropsThePreviousPersonsPhoto() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keys-follow-photo.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ContactPhotoStore(directoryURL: directory)
        let photo = Data("dad's photo".utf8), keypad = Data("keypad photo".utf8)
        try store.familyMembers.add(photo)
        let gone = "44444444-4444-4444-8444-444444444444"
        let expired = "33333333-3333-4333-8333-333333333333"
        let dadInvite = "66666666-6666-4666-8666-666666666666"
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "", nativeCall: NativeCall(room: "dad", mode: .voice), familyMemberID: gone, invitationID: expired, memberName: "Dad", photoData: keypad), for: 3)
        try slots.reconcile(with: snapshot(people: [member(gone, invitation: expired, invited: "Dad", joinedAt: now - 60, photoID: ContactPhotoStore.id(for: photo))]), memberPhotos: store.familyMembers)
        XCTAssertEqual(slots.contact(for: 3)?.memberPhotoID, ContactPhotoStore.id(for: photo))
        XCTAssertEqual(slots.contact(for: 3)?.customPhotoData, keypad)

        try slots.reconcile(with: snapshot(invitations: [invitation(dadInvite, "Dad")]), memberPhotos: store.familyMembers)
        let followed = try XCTUnwrap(slots.contact(for: 3))
        XCTAssertEqual(followed.invitationID, dadInvite)
        XCTAssertNil(followed.familyMemberID)
        XCTAssertNil(followed.memberPhotoID, "The previous person's photo must not stay on a key that picked up someone else")
        XCTAssertEqual(followed.customPhotoData, keypad, "The caregiver's own photo of the key stays")
    }

    func testNamesMatchWithoutCaseAccentsOrExtraSpaces() {
        XCTAssertEqual(CallSlots.matchingName("  Lísa   Chen "), CallSlots.matchingName("lisa chen"))
        XCTAssertNotEqual(CallSlots.matchingName("Lisa"), CallSlots.matchingName("Lisa Chen"))
        XCTAssertEqual(CallSlots.matchingName("家駿"), "家駿")
    }
}
