import XCTest
@testable import PorchCore

/// Every call drops in: the server's `everyCall`, and what it means for drop-in buttons and the caregiver's choice.
final class EveryCallTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("tests/fixtures/\(name).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    /// The saved family poll, with drop-ins and `everyCall` as given and this phone approved for nothing.
    private func familySnapshot(dropInEnabled: Bool = true, everyCall: [String: Any]?) throws -> FamilySnapshot {
        var state = try XCTUnwrap(try fixture("family-poll")["state"] as? [String: Any])
        state["dropInEnabled"] = dropInEnabled
        var me = try XCTUnwrap(state["me"] as? [String: Any])
        me["permissions"] = ["audio": false, "video": false]
        state["me"] = me
        if let everyCall { state["everyCall"] = everyCall } else { state.removeValue(forKey: "everyCall") }
        return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: state))
    }

    func testOlderServersAndOffDecodeWithoutIt() throws {
        let snapshot = try familySnapshot(everyCall: nil)
        XCTAssertNil(snapshot.everyCall)
        XCTAssertFalse(snapshot.canDropIn(.voice))
        XCTAssertFalse(snapshot.canDropIn(.video))
        let admin = try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: try XCTUnwrap(try fixture("caregiver-admin")["admin"])))
        XCTAssertNil(admin.everyCall)
        XCTAssertEqual(admin.dropInChoice, admin.dropInEnabled ? .approved : .off)
    }

    func testEveryCallLetsAnyoneDropInWhileDropInsAreOn() throws {
        let snapshot = try familySnapshot(everyCall: ["by": "Tom Reyes", "at": 1_800_000_000])
        XCTAssertEqual(snapshot.everyCall, EveryCallDropIn(by: "Tom Reyes", at: 1_800_000_000))
        XCTAssertTrue(snapshot.canDropIn(.voice))
        XCTAssertTrue(snapshot.canDropIn(.video))
        // Paused drop-ins win, whatever the server sent.
        XCTAssertFalse(try familySnapshot(dropInEnabled: false, everyCall: ["by": "Tom", "at": 1]).canDropIn(.voice))
    }

    func testCaregiverStateCarriesWhoTurnedItOn() throws {
        var admin = try XCTUnwrap(try fixture("caregiver-admin")["admin"] as? [String: Any])
        admin["dropInEnabled"] = true
        admin["everyCall"] = ["by": "Rose", "at": 1_800_000_060, "atBedside": true]
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: admin))
        XCTAssertEqual(state.dropInChoice, .everyCall)
        XCTAssertEqual(state.everyCall?.who(bedsideDevice: "iPad"), "Rose’s iPad")
        XCTAssertEqual(EveryCallDropIn(by: "Tom Reyes", at: 0).who(bedsideDevice: "tablet"), "Tom")
    }

    func testChoiceFollowsTheSwitchAndEveryCall() {
        let on = EveryCallDropIn(by: "Tom", at: 0)
        XCTAssertEqual(DropInChoice(dropInEnabled: false, everyCall: nil), .off)
        XCTAssertEqual(DropInChoice(dropInEnabled: false, everyCall: on), .off)
        XCTAssertEqual(DropInChoice(dropInEnabled: true, everyCall: nil), .approved)
        XCTAssertEqual(DropInChoice(dropInEnabled: true, everyCall: on), .everyCall)
        XCTAssertEqual(DropInChoice.allCases.map(\.rawValue), ["off", "approved", "everyCall"])
    }
}
