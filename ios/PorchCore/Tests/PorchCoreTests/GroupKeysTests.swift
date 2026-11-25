import Foundation
import XCTest
@testable import PorchCore

/// A key that rings Ethan and David at once.
final class GroupKeysTests: XCTestCase {
    private let ethan = "11111111-1111-4111-8111-111111111111", david = "22222222-2222-4222-8222-222222222222"
    private func fixture(_ body: (UserDefaults, ContactPhotoStore) throws -> Void) throws {
        let suite = "group-keys.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        try body(defaults, ContactPhotoStore(directoryURL: directory))
    }
    private func kids(name: String = "", photo: Data? = nil) throws -> CallGroup {
        try CallGroup(name: name, memberIDs: [ethan, david], memberNames: ["Ethan", "David"], mode: .video, buttonColorHex: "1565c0", photoData: photo)
    }
    private func snapshot(people: [(String, String)]) throws -> FamilySnapshot {
        let object: [String: Any] = ["householdID": "home", "householdName": "Mom", "dropInEnabled": true,
            "me": ["id": "bed", "name": "Mom", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true],
            "people": people.map { ["id": $0.0, "name": $0.1, "role": "family", "permissions": ["audio": true, "video": true], "online": true] },
            "invitations": [], "busy": false, "serverTime": 1_800_000_000]
        return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testGroupGoesByItsPeoplesNamesUnlessTheCaregiverNamesIt() throws {
        XCTAssertEqual(try kids().name, "Ethan & David")
        XCTAssertEqual(try kids(name: "  Kids ").name, "Kids")
        XCTAssertEqual(try kids().buttonColorHex, "1565C0")
        let contact = try kids(name: "Kids").callContact
        XCTAssertEqual(contact.name, "Kids"); XCTAssertEqual(contact.nativeCall?.mode, .video); XCTAssertNil(contact.phoneNumber)
        XCTAssertEqual(contact.buttonColorHex, "1565C0")
        XCTAssertEqual(try kids(photo: Data([7, 8])).callContact.photoData, Data([7, 8]), "The call screen shows the key's photo")
        XCTAssertThrowsError(try CallGroup(name: "", memberIDs: [ethan, ethan], memberNames: ["Ethan", "Ethan"], mode: .voice))
        XCTAssertThrowsError(try CallGroup(name: "", memberIDs: [ethan, david, UUID().uuidString], memberNames: ["a", "b", "c"], mode: .voice))
        XCTAssertThrowsError(try CallGroup(name: "", memberIDs: [], memberNames: [], mode: .voice))
        XCTAssertThrowsError(try CallGroup(name: "", memberIDs: ["ethan"], memberNames: ["Ethan"], mode: .voice))
        XCTAssertThrowsError(try kids(name: String(repeating: "x", count: 81)))
    }

    func testAGroupKeyReplacesWhatWasOnItAndAnythingElseReplacesTheGroup() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "Lisa", nativeCall: NativeCall(room: "lisa", mode: .voice)), for: 3)
        try slots.setGroup(kids(), for: 3)
        XCTAssertEqual(slots.action(for: 3), .group)
        XCTAssertNil(slots.contact(for: 3)); XCTAssertEqual(slots.group(for: 3)?.name, "Ethan & David")
        XCTAssertEqual(slots.allGroups.map(\.digit), [3]); XCTAssertEqual(slots.digit(for: .group), 3)
        try slots.setAction(.group, for: 3)
        XCTAssertEqual(slots.action(for: 3), .group, "Choosing the group again keeps it")
        XCTAssertThrowsError(try slots.setAction(.group, for: 4), "A group needs its people")
        try slots.setAction(.messages, for: 3)
        XCTAssertEqual(slots.action(for: 3), .messages); XCTAssertNil(slots.group(for: 3))
        try slots.setGroup(kids(), for: 3)
        try slots.setContact(CallContact(name: "Lisa", nativeCall: NativeCall(room: "lisa", mode: .voice)), for: 3)
        XCTAssertEqual(slots.action(for: 3), .person); XCTAssertNil(slots.group(for: 3))
        try slots.setGroup(kids(), for: 3)
        try slots.setGroup(nil, for: 3)
        XCTAssertEqual(slots.action(for: 3), .unassigned)
    }

    func testGroupsAreSavedBesideTheKeypadSoAnOlderBuildSeesAnEmptyKey() throws {
        try fixture { defaults, store in
            var slots = CallSlots()
            try slots.setContact(CallContact(name: "Lisa", nativeCall: NativeCall(room: "lisa", mode: .voice)), for: 1)
            try slots.setGroup(kids(name: "Kids", photo: Data(repeating: 4, count: 2000)), for: CallSlots.star)
            try slots.save(to: defaults, photoStore: store)
            let symbols = try JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: "porch.slots.v2.symbols"))) as? [[String: Any]]
            XCTAssertEqual(symbols?.first?["action"] as? String, "person", "An older build reads * as an empty key")
            XCTAssertNil(symbols?.first?["contact"])
            XCTAssertFalse(String(decoding: try XCTUnwrap(defaults.data(forKey: "porch.slots.v2")), as: UTF8.self).contains("group"))
            let groups = String(decoding: try XCTUnwrap(defaults.data(forKey: "porch.slots.v2.groups")), as: UTF8.self)
            XCTAssertTrue(groups.contains("\"*\"")); XCTAssertFalse(groups.contains("photoData"))
            let restored = try CallSlots.load(from: defaults, photoStore: store)
            XCTAssertEqual(restored, slots)
            XCTAssertEqual(restored.group(for: CallSlots.star)?.name, "Kids")
            XCTAssertEqual(restored.group(for: CallSlots.star)?.photoData?.count, 2000, "Saving keeps the group's photo")
            XCTAssertEqual(restored.contact(for: 1)?.name, "Lisa")
            // Taking the group off clears what was saved for it.
            var cleared = restored
            try cleared.setGroup(nil, for: CallSlots.star)
            try cleared.save(to: defaults, photoStore: store)
            XCTAssertNil(defaults.data(forKey: "porch.slots.v2.groups"))
            XCTAssertNil(try CallSlots.load(from: defaults, photoStore: store).group(for: CallSlots.star))
            CallSlots.forget(in: defaults, photoStore: store)
            XCTAssertNil(defaults.data(forKey: "porch.slots.v2.groups"))
        }
    }

    func testAGroupOnAKeyThatIsSavedAsSomethingElseCannotBeRead() throws {
        try fixture { defaults, store in
            var slots = CallSlots()
            try slots.setContact(CallContact(name: "Lisa", nativeCall: NativeCall(room: "lisa", mode: .voice)), for: 1)
            try slots.save(to: defaults, photoStore: store)
            let encoder = JSONEncoder(); encoder.userInfo[ContactPhotoStore.codingKey] = store
            defaults.set(try encoder.encode(["1": kids()]), forKey: "porch.slots.v2.groups")
            XCTAssertThrowsError(try CallSlots.load(from: defaults, photoStore: store))
        }
    }

    func testGroupsShowTheirPeoplesCurrentNames() throws {
        var slots = CallSlots()
        try slots.setGroup(kids(), for: 2)
        try slots.setGroup(kids(name: "Kids"), for: 4)
        try slots.reconcile(with: snapshot(people: [(ethan, "Ethan T"), (david, "Dave")]))
        XCTAssertEqual(slots.group(for: 2)?.name, "Ethan T & Dave")
        XCTAssertEqual(slots.group(for: 4)?.name, "Kids")
        XCTAssertEqual(slots.group(for: 4)?.memberNames, ["Ethan T", "Dave"])
        // Someone no longer on Porch keeps the last name Porch showed.
        try slots.reconcile(with: snapshot(people: [(ethan, "Ethan")]))
        XCTAssertEqual(slots.group(for: 2)?.name, "Ethan & Dave")
        XCTAssertEqual(slots.group(for: 2)?.memberIDs, [ethan, david])
    }

    func testUpdatingKeepsThePhotoUnlessReplaced() throws {
        let group = try kids(photo: Data([1]))
        let renamed = try group.updating(name: "Boys", mode: .voice)
        XCTAssertEqual(renamed.name, "Boys"); XCTAssertEqual(renamed.mode, .voice); XCTAssertEqual(renamed.photoData, Data([1]))
        XCTAssertNil(try group.updating(photoData: .some(nil)).photoData)
        XCTAssertEqual(try group.updating(buttonColorHex: .some(nil)).buttonColorHex, nil)
        let swapped = try group.updating(memberIDs: [david], memberNames: ["David"])
        XCTAssertEqual(swapped.name, "David")
    }

    func testThePreviewSaysWhoAGroupKeyWouldCall() throws {
        var slots = CallSlots()
        try slots.setGroup(kids(name: "Kids"), for: 5)
        var preview = KeypadActionPreview(slots: slots)
        let result = preview.receive("5")
        XCTAssertEqual(result.kind, .person); XCTAssertEqual(result.title, "Would call Kids"); XCTAssertEqual(result.action, .group)
    }
}
