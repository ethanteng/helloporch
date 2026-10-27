import Foundation
import XCTest
@testable import PorchCore

/// Keypad contacts for Porch family members go by the name and photo the member chose (or a caregiver
/// chose for everyone) unless the caregiver typed a name or chose a photo for that key.
final class MemberProfileTests: XCTestCase {
    private let member = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let invitation = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private func fixture(_ body: (UserDefaults, ContactPhotoStore) throws -> Void) throws {
        let suite = "member-profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        try body(defaults, ContactPhotoStore(directoryURL: directory))
    }
    private func snapshot(people: [[String: Any]], invitations: [[String: Any]] = []) throws -> FamilySnapshot {
        let object: [String: Any] = ["householdID": "home", "householdName": "Pat", "dropInEnabled": false,
            "me": ["id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "name": "Pat", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true],
            "people": people, "invitations": invitations, "busy": false, "serverTime": 1]
        return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func person(name: String, photoID: String? = nil) -> [String: Any] {
        var person: [String: Any] = ["id": member, "invitationID": invitation, "name": name, "role": "family", "permissions": ["audio": false, "video": false], "online": true]
        person["photoID"] = photoID
        return person
    }
    private func porchContact(name: String = "", photo: Data? = nil) throws -> CallContact {
        try CallContact(name: name, nativeCall: NativeCall(room: "paired", mode: .video), invitationID: invitation, memberName: "Ethan", photoData: photo)
    }

    func testUnnamedContactFollowsTheInvitationThenTheMembersOwnNameAndPhoto() throws {
        try fixture { defaults, store in
            var slots = CallSlots()
            try slots.setContact(porchContact(), for: 1)
            XCTAssertEqual(slots.contact(for: 1)?.name, "Ethan")
            try slots.reconcile(with: snapshot(people: [], invitations: [["id": invitation, "name": "Ethan W", "expiresAt": 9]]), memberPhotos: store.familyMembers)
            XCTAssertEqual(slots.contact(for: 1)?.name, "Ethan W", "the invitation's current name until it's accepted")

            let photo = Data("ethan's photo".utf8), id = ContactPhotoStore.id(for: photo)
            let chosen = try snapshot(people: [person(name: "Ethan T.", photoID: id)])
            try slots.reconcile(with: chosen, memberPhotos: store.familyMembers)
            XCTAssertEqual(slots.contact(for: 1)?.name, "Ethan T.")
            XCTAssertEqual(slots.contact(for: 1)?.familyMemberID, member)
            XCTAssertNil(slots.contact(for: 1)?.photoData, "the photo shows once it has downloaded")
            try store.familyMembers.add(photo)
            try slots.reconcile(with: chosen, memberPhotos: store.familyMembers)
            XCTAssertEqual(slots.contact(for: 1)?.photoData, photo)
            XCTAssertNil(slots.contact(for: 1)?.photoID, "the keypad's own photo stays empty")

            // Saved and reloaded, it still follows them, and saving never prunes their photo.
            try slots.save(to: defaults, photoStore: store)
            var loaded = try CallSlots.load(from: defaults, photoStore: store)
            XCTAssertEqual(loaded, slots)
            XCTAssertEqual(loaded.contact(for: 1)?.photoData, photo)
            XCTAssertEqual(loaded.contact(for: 1)?.customName, "")

            // A replacement photo waits for its download; a removed one goes at once.
            let next = Data("a newer photo".utf8)
            try loaded.reconcile(with: snapshot(people: [person(name: "Ethan T.", photoID: ContactPhotoStore.id(for: next))]), memberPhotos: store.familyMembers)
            XCTAssertEqual(loaded.contact(for: 1)?.photoData, photo)
            try loaded.reconcile(with: snapshot(people: [person(name: "Ethan T.")]), memberPhotos: store.familyMembers)
            XCTAssertNil(loaded.contact(for: 1)?.photoData)
            // Once they leave, the key keeps the name it last showed.
            try loaded.reconcile(with: snapshot(people: []), memberPhotos: store.familyMembers)
            XCTAssertEqual(loaded.contact(for: 1)?.name, "Ethan T.")
            XCTAssertNil(loaded.contact(for: 1)?.familyMemberID)
        }
    }

    func testCaregiversKeypadNameAndPhotoComeFirst() throws {
        try fixture { _, store in
            let theirs = Data("their photo".utf8), keypad = Data("keypad photo".utf8)
            try store.familyMembers.add(theirs)
            var slots = CallSlots()
            try slots.setContact(porchContact(name: "Grandson", photo: keypad), for: 1)
            try slots.reconcile(with: snapshot(people: [person(name: "Ethan T.", photoID: ContactPhotoStore.id(for: theirs))]), memberPhotos: store.familyMembers)
            XCTAssertEqual(slots.contact(for: 1)?.name, "Grandson")
            XCTAssertEqual(slots.contact(for: 1)?.photoData, keypad)
            XCTAssertEqual(slots.contact(for: 1)?.memberName, "Ethan T.")
            XCTAssertEqual(slots.contact(for: 1)?.memberPhotoID, ContactPhotoStore.id(for: theirs))
        }
    }

    func testOnlyPorchFamilyMembersCanGoWithoutAName() throws {
        let call = try NativeCall(room: "paired", mode: .voice)
        XCTAssertThrowsError(try CallContact(name: " ", nativeCall: call, phoneNumber: "+14155550123", memberName: "Ethan"))
        XCTAssertThrowsError(try CallContact(name: "", nativeCall: call, invitationID: invitation))
        XCTAssertEqual(try CallContact(name: "", nativeCall: call, familyMemberID: member, memberName: " Ethan ").name, "Ethan")
    }

    func testEarlierSavedContactsKeepTheCaregiversName() throws {
        try fixture { defaults, store in
            // Settings saved before members could choose their own names.
            let legacy: [[String: Any]] = CallSlots.digits.map { digit in
                digit == 1 ? ["action": "person", "contact": ["name": "David", "address": "", "nativeCall": ["room": "paired", "mode": "video"], "invitationID": invitation]] : ["action": digit == 0 ? "callControl" : digit == 9 ? "toggleVideo" : "person"]
            }
            defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "porch.slots.v2")
            var slots = try CallSlots.load(from: defaults, photoStore: store)
            try slots.reconcile(with: snapshot(people: [person(name: "Ethan T.")]), memberPhotos: store.familyMembers)
            XCTAssertEqual(slots.contact(for: 1)?.name, "David")
            XCTAssertEqual(slots.contact(for: 1)?.customName, "David")
            // An earlier build reading new settings still finds a name for everyone.
            try slots.setContact(porchContact(), for: 2)
            try slots.save(to: defaults, photoStore: store)
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: defaults.data(forKey: "porch.slots.v2")!) as? [[String: Any]])
            XCTAssertEqual((saved[1]["contact"] as? [String: Any])?["name"] as? String, "Ethan")
        }
    }

    /// Caregiver settings change one detail of a key at a time, such as its color, and nothing else on it.
    func testUpdatingOneDetailKeepsTheRestOfTheKeyIncludingTheMembersPhoto() throws {
        try fixture { _, store in
            let photo = Data("ethan's photo".utf8)
            try store.familyMembers.add(photo)
            var slots = CallSlots()
            try slots.setContact(CallContact(name: "Grandpa Joe", nativeCall: NativeCall(room: "paired", mode: .voice), phoneNumber: "+14155550123",
                                             otherPhoneNumbers: ["+14155550199"], invitationID: invitation, memberName: "Ethan", buttonColorHex: "FFCC00"), for: 1)
            try slots.reconcile(with: snapshot(people: [person(name: "Ethan", photoID: ContactPhotoStore.id(for: photo))]), memberPhotos: store.familyMembers)
            let original = try XCTUnwrap(slots.contact(for: 1))
            XCTAssertEqual(original.photoData, photo)

            let video = try original.updating(mode: .video)
            XCTAssertEqual(video.nativeCall?.mode, .video)
            XCTAssertEqual(video.nativeCall?.room, "paired")
            XCTAssertEqual(video.customName, "Grandpa Joe")
            XCTAssertEqual(video.phoneNumbers, ["+14155550123", "+14155550199"])
            XCTAssertEqual(video.familyMemberID, member)
            XCTAssertEqual(video.buttonColorHex, "FFCC00")
            XCTAssertEqual(video.photoData, photo, "the member's photo stays on the key")

            // One name per family member: an empty name makes the key go by theirs.
            XCTAssertEqual(try original.updating(name: "").name, "Ethan")
            XCTAssertNil(try original.updating(buttonColorHex: .some(nil)).buttonColorHex)
            XCTAssertEqual(try original.updating(buttonColorHex: .some("00aa00")).buttonColorHex, "00AA00")

            let own = Data("a key photo".utf8)
            let withPhoto = try original.updating(photoData: .some(own))
            XCTAssertEqual(withPhoto.customPhotoData, own)
            XCTAssertEqual(withPhoto.photoData, own, "a key's own photo comes first")
            let cleared = try withPhoto.updating(photoData: .some(nil))
            XCTAssertNil(cleared.customPhotoData)
            XCTAssertEqual(cleared.photoData, photo, "back to the member's photo")
            XCTAssertThrowsError(try CallContact(name: "David", nativeCall: NativeCall(room: "phone", mode: .voice), phoneNumber: "+14155550123").updating(name: ""),
                                 "someone who isn't on Porch needs a name")
        }
    }
}
