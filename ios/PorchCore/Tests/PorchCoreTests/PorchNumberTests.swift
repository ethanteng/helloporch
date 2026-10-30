import XCTest
@testable import PorchCore

final class PorchNumberTests: XCTestCase {
    private func snapshot(_ extra: [String: Any]) throws -> FamilySnapshot {
        var object: [String: Any] = ["householdID": "home", "householdName": "Mom", "dropInEnabled": false,
            "me": ["id": "bedside", "name": "Mom", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true],
            "people": [], "busy": false, "serverTime": 1]
        object.merge(extra) { _, new in new }
        return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testUSNumbersReadTheWayPeopleWriteThemAndOthersAreLeftAlone() {
        XCTAssertEqual(PorchNumber.display("+15105677039"), "(510) 567-7039")
        for other in ["+447700900123", "+1510567703", "+1510567703x", "5105677039", ""] {
            XCTAssertEqual(PorchNumber.display(other), other)
        }
    }

    func testAreaCodesMatchWhatTheServerSearches() {
        for good in ["510", "978", "212", "800"] { XCTAssertTrue(PorchNumber.isAreaCode(good), good) }
        for bad in ["011", "123", "411", "911", "51", "5100", "51a", " 510", "٥١٠"] { XCTAssertFalse(PorchNumber.isAreaCode(bad), bad) }
    }

    func testTheSnapshotCarriesTheNumberOrHowItsSetupIsGoing() throws {
        let ready = try snapshot(["porchNumber": "+15105677039"])
        XCTAssertEqual(ready.porchNumber, "+15105677039"); XCTAssertNil(ready.phoneSetup)
        let waiting = try snapshot(["phoneSetup": ["areaCode": "510", "error": "Twilio request failed (500).", "needsChoice": true]])
        XCTAssertNil(waiting.porchNumber)
        XCTAssertEqual(waiting.phoneSetup, try JSONDecoder().decode(PorchNumberSetup.self, from: Data(#"{"areaCode":"510","error":"Twilio request failed (500).","needsChoice":true}"#.utf8)))
        let older = try snapshot([:])
        XCTAssertNil(older.porchNumber); XCTAssertNil(older.phoneSetup)
    }
}
