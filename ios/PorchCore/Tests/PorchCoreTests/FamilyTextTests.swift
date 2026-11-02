import Foundation
import XCTest
@testable import PorchCore

/// Texts to the Porch number reach the bedside's snapshot without their words; the bedside fetches each one to show it.
final class FamilyTextTests: XCTestCase {
    private func snapshot(_ extra: [String: Any]) throws -> FamilySnapshot {
        var object: [String: Any] = ["householdID": "home", "householdName": "Pat", "dropInEnabled": false,
            "me": ["id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "name": "Pat", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true],
            "people": [], "busy": false, "serverTime": 1]
        object.merge(extra) { $1 }
        return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testTheBedsideSeesWaitingAndHeldTextsAndOlderServersSendNone() throws {
        let state = try snapshot(["texts": [
            ["id": "t1", "from": "+14155550123", "sentAt": 100, "held": false, "delivered": true],
            ["id": "t2", "from": "72975", "sentAt": 200, "pictures": 2, "held": true, "delivered": false],
        ]])
        XCTAssertEqual(state.texts?.map(\.id), ["t1", "t2"])
        XCTAssertEqual(state.texts?.map(\.held), [false, true])
        XCTAssertEqual(state.texts?.last?.pictures, 2)
        XCTAssertNil(state.texts?.first?.body, "the words aren't in the snapshot")
        XCTAssertNil(try snapshot([:]).texts)
        XCTAssertEqual(try snapshot(["heldTexts": 3]).heldTexts, 3)
    }

    func testAFetchedTextKeepsItsWordsTranslationAndLanguage() throws {
        let data = Data(#"{"id":"t1","from":"+14155550123","sentAt":100,"body":"I land at 6","language":"zh-Hant","text":"我六點到","translated":true,"sourceLanguage":"en"}"#.utf8)
        let text = try JSONDecoder().decode(ReceivedText.self, from: data)
        XCTAssertEqual([text.body, text.text, text.language, text.sourceLanguage], ["I land at 6", "我六點到", "zh-Hant", "en"])
        XCTAssertTrue(text.translated)
        XCTAssertNil(text.pictures)
        XCTAssertEqual(try JSONDecoder().decode(ReceivedText.self, from: JSONEncoder().encode(text)), text, "the iPad keeps it as it came")
        let untranslated = try JSONDecoder().decode(ReceivedText.self, from: Data(#"{"id":"t2","from":"72975","sentAt":1,"body":"","pictures":1,"language":"en","text":"","translated":false}"#.utf8))
        XCTAssertNil(untranslated.sourceLanguage)
        XCTAssertEqual(untranslated.pictures, 1)
    }

    func testCaregiverReviewCarriesTheWordsAndWhatTheBedsideShows() throws {
        let data = Data(#"[{"id":"t1","from":"+14155550123","sentAt":100,"held":true,"delivered":false,"body":"Hola mamá","translation":"Hi Mom","sourceLanguage":"es"}]"#.utf8)
        let text = try XCTUnwrap(try JSONDecoder().decode([FamilyText].self, from: data).first)
        XCTAssertEqual([text.body, text.translation, text.sourceLanguage], ["Hola mamá", "Hi Mom", "es"])
        let admin = try JSONDecoder().decode(FamilyAdminState.self, from: Data(#"{"householdName":"Pat","dropInEnabled":false,"people":[],"texts":[{"id":"t1","from":"+14155550123","sentAt":100,"held":true,"delivered":false}]}"#.utf8))
        XCTAssertEqual(admin.texts?.first?.held, true)
    }
}
