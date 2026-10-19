import Foundation
import XCTest
@testable import PorchCore

/// The bedside's snapshot lists the natural voices a caregiver can choose for each language,
/// and the family's choice, where null means the iPad's built-in voice.
final class NaturalVoicesTests: XCTestCase {
    private func snapshot(speech: Any?, bedsideLanguage: String? = nil) throws -> FamilySnapshot {
        var object: [String: Any] = ["householdID": "home", "householdName": "Pat", "dropInEnabled": false,
            "me": ["id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "name": "Pat", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true],
            "people": [], "busy": false, "serverTime": 1]
        object["speech"] = speech
        object["bedsideLanguage"] = bedsideLanguage
        return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testEachLanguageHasItsVoicesAndTheFamilysChoice() throws {
        let voices: [[String: Any]] = [["id": "suk-yee", "name": "Suk Yee", "detail": "Direct, warm narrator · female"], ["id": "lucky", "name": "Lucky Chan", "detail": "Warm and calm · male"]]
        let state = try snapshot(speech: ["languages": [
            "yue-Hant": ["selected": "lucky", "defaultVoice": "suk-yee", "voices": voices],
            "es": ["selected": NSNull(), "defaultVoice": "eva", "voices": [["id": "eva", "name": "Eva Dorado", "detail": "Warm and soft · female"]]],
        ]])
        let cantonese = try XCTUnwrap(state.speech?.choices(for: .cantonese))
        XCTAssertEqual(cantonese.selected, "lucky")
        XCTAssertEqual(cantonese.defaultVoice, "suk-yee")
        XCTAssertEqual(cantonese.voices.map(\.name), ["Suk Yee", "Lucky Chan"])
        XCTAssertNil(try XCTUnwrap(state.speech?.choices(for: .spanish)).selected, "null is the built-in voice")
        XCTAssertNil(state.speech?.choices(for: .english), "a language the server doesn't list has no natural voices")
    }

    func testOlderServersSendNoVoices() throws {
        XCTAssertNil(try snapshot(speech: nil).speech)
    }

    /// Phone voicemail greets callers in the bedside language, which only the iPad knows until it reports it.
    func testSavingReportsTheBedsideLanguageOnlyWhenTheServerHasAnother() throws {
        let english = try snapshot(speech: nil, bedsideLanguage: "en")
        XCTAssertEqual(english.languageToReport(.cantonese), .cantonese)
        XCTAssertNil(english.languageToReport(.english), "already known")
        XCTAssertNil(try snapshot(speech: nil).languageToReport(.spanish), "older servers can't keep it")
    }
}
