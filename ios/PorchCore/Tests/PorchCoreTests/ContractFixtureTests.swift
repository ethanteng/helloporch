import XCTest
@testable import PorchCore

/// The server's own responses, saved by tests/contract-fixtures.test.mjs. The Android app's tests decode the same files,
/// so a server change that breaks either app fails CI.
final class ContractFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("tests/fixtures/\(name).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func decode<T: Decodable>(_ type: T.Type, _ value: Any?) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: try XCTUnwrap(value)))
    }

    func testEverySavedSnapshotDecodes() throws {
        let bedside = try decode(FamilySnapshot.self, try fixture("bedside-poll")["state"])
        XCTAssertEqual(bedside.me.role, .bedside)
        XCTAssertEqual(bedside.people.map(\.name), ["Ethan", "Lee"])
        XCTAssertEqual(bedside.invitations?.map(\.name), ["Sam"])
        let family = try decode(FamilySnapshot.self, try fixture("family-poll")["state"])
        XCTAssertEqual(family.me.caregiver, true); XCTAssertNil(family.call)
        let ringing = try decode(FamilySnapshot.self, try fixture("family-incoming-call")["state"])
        XCTAssertEqual(ringing.call?.state, "pending"); XCTAssertEqual(ringing.call?.callerName, "Mom")
        // An answered call has no time limit: Number.MAX_SAFE_INTEGER.
        let answered = try decode(FamilySnapshot.self, try fixture("family-answered-call")["state"])
        XCTAssertEqual(answered.call?.state, "accepted"); XCTAssertEqual(answered.call?.expiresAt, 9007199254740991)
    }

    func testCaregiverStateAndErrorsDecode() throws {
        let response = try fixture("caregiver-admin")
        _ = try decode(FamilySnapshot.self, response["state"])
        let admin = try decode(FamilyAdminState.self, response["admin"])
        XCTAssertEqual(admin.people.map(\.name), ["Ethan", "Lee"])
        XCTAssertEqual(try fixture("error-busy")["error"] as? String, "Another call is already in progress.")
    }
}
