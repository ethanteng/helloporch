import XCTest
@testable import PorchCore

final class CallScreeningTests: XCTestCase {
    private func screening(keypad: [String]?) throws -> CallScreening {
        var object: [String: Any] = ["enabled": true, "allowed": [["number": "+14155550300", "allowedAt": 1_800_000_000]],
            "blocked": [["number": "+14155550999", "firstCallAt": 1_800_000_000, "lastCallAt": 1_800_000_060, "calls": 2]]]
        if let keypad { object["keypadNumbers"] = keypad } else { object["keypadNumbers"] = NSNull() }
        return try JSONDecoder().decode(CallScreening.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testKeypadReportsEachSavedPhoneNumberOnceInOrder() throws {
        var slots = CallSlots()
        XCTAssertEqual(slots.phoneNumbers, [])
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "david", mode: .voice), phoneNumber: "+14155550200"), for: 3)
        try slots.setContact(CallContact(name: "May", nativeCall: NativeCall(room: "may", mode: .video), phoneNumber: "+14155550100"), for: 1)
        try slots.setContact(CallContact(name: "Dave", nativeCall: NativeCall(room: "dave", mode: .voice), phoneNumber: "+14155550200"), for: 2)
        // Only Porch calls, no phone: nothing to let through.
        try slots.setContact(CallContact(name: "Sam", nativeCall: NativeCall(room: "sam", mode: .video)), for: 4)
        XCTAssertEqual(slots.phoneNumbers, ["+14155550100", "+14155550200"])
        // A key turned into a control no longer lets its person ring.
        try slots.setAction(.messages, for: 1)
        XCTAssertEqual(slots.phoneNumbers, ["+14155550200"])
    }

    func testKeypadIsReportedOnlyWhenTheServerCopyDiffers() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "david", mode: .voice), phoneNumber: "+14155550200"), for: 1)
        XCTAssertNil(try screening(keypad: ["+14155550200"]).keypadNumbersToReport(slots))
        XCTAssertEqual(try screening(keypad: []).keypadNumbersToReport(slots), ["+14155550200"])
        // Never reported yet: even an empty keypad is reported, so blocking can be turned on.
        XCTAssertEqual(try screening(keypad: nil).keypadNumbersToReport(CallSlots()), [])
        XCTAssertNil(try screening(keypad: []).keypadNumbersToReport(CallSlots()))
    }

    func testScreeningDecodesForTheBedsideAndCaregiversAndIsOptionalForOlderServers() throws {
        let decoded = try screening(keypad: ["+14155550200"])
        XCTAssertEqual(decoded.allowed, [AllowedCaller(number: "+14155550300", allowedAt: 1_800_000_000)])
        XCTAssertEqual(decoded.blocked.first?.calls, 2)
        let admin: [String: Any] = ["householdName": "Pat", "dropInEnabled": false, "people": []]
        XCTAssertNil(try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: admin)).callScreening)
        let unreported: [String: Any] = ["enabled": false, "keypadNumbers": NSNull(), "allowed": [Any](), "blocked": [Any]()]
        var withScreening = admin
        withScreening["callScreening"] = unreported
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: withScreening))
        XCTAssertEqual(state.callScreening?.enabled, false)
        XCTAssertNil(state.callScreening?.keypadNumbers)
    }
}
