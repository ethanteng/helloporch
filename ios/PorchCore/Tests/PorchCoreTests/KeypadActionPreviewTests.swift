import XCTest
@testable import PorchCore

final class KeypadActionPreviewTests: XCTestCase {
    private func configured() throws -> CallSlots {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "Alex", nativeCall: NativeCall(room: "preview-alex", mode: .voice)), for: 1)
        try slots.setContact(CallContact(name: "Sam", nativeCall: NativeCall(room: "preview-sam", mode: .video)), for: 2)
        return slots
    }
    func testPeopleEmptyAndUnmappedSymbols() throws {
        let slots = try configured(); var preview = KeypadActionPreview(slots: slots)
        XCTAssertEqual(preview.receive("1").contactName, "Alex")
        XCTAssertEqual(preview.receive("2").title, "Would call Sam")
        XCTAssertTrue(preview.receive("2").detail.hasPrefix("Video"))
        XCTAssertEqual(preview.receive("3").kind, .unassigned)
        for key in ["*", "#", "A", "D", "12", "", "١"] { XCTAssertEqual(preview.receive(key).kind, .unmapped) }
        XCTAssertEqual(preview.slots, slots, "Preview must not edit the saved mapping")
    }
    func testSavedRemappingsAndSimulatedStates() throws {
        var slots = try configured()
        let person = try XCTUnwrap(slots.contact(for: 1))
        try slots.setContact(person, for: 0)
        try slots.setAction(.callControl, for: 4)
        try slots.setAction(.toggleVideo, for: 7)
        try slots.setAction(.messages, for: 8)
        var preview = KeypadActionPreview(slots: slots)
        XCTAssertEqual(preview.receive("0").kind, .person)
        XCTAssertEqual(preview.receive("4").kind, .ignored)
        XCTAssertEqual(preview.receive("8").kind, .playMessages)
        preview.setContext(.incoming)
        XCTAssertEqual(preview.receive("4").kind, .answer)
        XCTAssertEqual(preview.receive("0").kind, .ignored)
        preview.setContext(.videoCall)
        XCTAssertEqual(preview.receive("4").kind, .hangUp)
        XCTAssertEqual(preview.receive("7").cameraOn, false)
        XCTAssertEqual(preview.receive("7").cameraOn, true, "Repeated digits must remain distinct preview inputs")
        preview.setContext(.voiceCall)
        XCTAssertEqual(preview.receive("7").kind, .ignored)
        preview.setContext(.dropIn)
        XCTAssertEqual(preview.receive("4").kind, .cancelDropIn)
        preview.setContext(.messages)
        XCTAssertEqual(preview.receive("4").kind, .stopMessages)
        XCTAssertEqual(preview.receive("8").kind, .stopMessages)
        XCTAssertEqual(preview.slots, slots)
    }
    func testLegacyContactDoesNotPretendItCanCall() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "Old entry", address: "person@example.com"), for: 1)
        var preview = KeypadActionPreview(slots: slots)
        XCTAssertEqual(preview.receive("1").kind, .needsSetup)
    }
    func testSnapshotPreservesSavedAssignmentsWithoutChangingSource() throws {
        let name = "preview-snapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var slots = try configured()
        try slots.setAction(.messages, for: 5)
        try slots.save(to: defaults)
        let bytes = try XCTUnwrap(defaults.data(forKey: "porch.slots.v2"))
        let snapshot = try CallSlots.snapshot(from: bytes)
        XCTAssertEqual(snapshot, slots)
        XCTAssertEqual(defaults.data(forKey: "porch.slots.v2"), bytes)
        XCTAssertThrowsError(try CallSlots.snapshot(from: Data("[]".utf8)))
    }
}
