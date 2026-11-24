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

    /// Caregivers' own voices come after the listed ones, with whose they are.
    func testFamilyVoicesSayWhoseTheyAre() throws {
        let voices: [[String: Any]] = [
            ["id": "hope", "name": "Hope", "detail": "Natural, clear and calm · female"],
            ["id": "LindaVoice0000000001", "name": "Linda", "detail": "Family voice", "family": true, "memberID": "linda"],
            ["id": "TomVoice000000000001", "name": "Tom", "detail": "Family voice", "family": true, "memberID": "tom"],
        ]
        let state = try snapshot(speech: ["languages": ["en": ["selected": "LindaVoice0000000001", "defaultVoice": "hope", "voices": voices]]])
        let english = try XCTUnwrap(state.speech?.choices(for: .english))
        XCTAssertEqual(english.listedVoices.map(\.name), ["Hope"])
        XCTAssertEqual(english.familyVoices.map(\.name), ["Linda", "Tom"])
        XCTAssertEqual(english.familyVoices.map(\.memberID), ["linda", "tom"])
        XCTAssertEqual(english.familyVoice(of: "tom")?.id, "TomVoice000000000001")
        XCTAssertNil(english.familyVoice(of: "hope"), "a listed voice belongs to no one")
        XCTAssertNil(english.familyVoice(of: nil))
        let hope = try XCTUnwrap(english.voices.first)
        XCTAssertNil(hope.family, "listed voices don't say")
        XCTAssertFalse(hope.isFamily)
        XCTAssertNil(hope.memberID)
    }

    /// Caregiver mode on a phone gets the voices with the PIN-checked admin state, and the bedside's language.
    func testAdminStateCarriesTheVoicesAndTheBedsideLanguage() throws {
        let admin: [String: Any] = ["householdName": "Rose", "dropInEnabled": false, "people": [], "bedsideLanguage": "es",
            "speech": ["languages": [
                "en": ["selected": "hope", "defaultVoice": "hope", "voices": [["id": "hope", "name": "Hope", "detail": "Natural, clear and calm · female"]]],
                "es": ["selected": NSNull(), "defaultVoice": "eva", "voices": [
                    ["id": "eva", "name": "Eva Dorado", "detail": "Warm and soft · female"],
                    ["id": "LindaVoice0000000001", "name": "Linda", "detail": "Family voice", "family": true, "memberID": "linda"]]],
            ]]]
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: admin))
        XCTAssertEqual(state.bedsideLanguage, "es")
        XCTAssertEqual(state.language, .spanish)
        let spanish = try XCTUnwrap(state.announcementVoices)
        XCTAssertNil(spanish.selected, "null is the built-in voice")
        XCTAssertEqual(spanish.familyVoice(of: "linda")?.name, "Linda")
        XCTAssertEqual(state.speech?.choices(for: .english)?.selected, "hope")
    }

    func testAdminStateFromOlderServersHasNoVoices() throws {
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: Data(#"{"householdName":"Rose","dropInEnabled":false,"people":[]}"#.utf8))
        XCTAssertNil(state.speech)
        XCTAssertNil(state.bedsideLanguage)
        XCTAssertNil(state.announcementVoices)
        XCTAssertEqual(state.language, .english, "English until the server hears otherwise")
        // A language Porch doesn't know yet falls back the same way.
        let newer = try JSONDecoder().decode(FamilyAdminState.self, from: Data(#"{"householdName":"Rose","dropInEnabled":false,"people":[],"bedsideLanguage":"xx"}"#.utf8))
        XCTAssertEqual(newer.language, .english)
    }

    /// Phone voicemail greets callers in the bedside language, which only the iPad knows until it reports it.
    func testSavingReportsTheBedsideLanguageOnlyWhenTheServerHasAnother() throws {
        let english = try snapshot(speech: nil, bedsideLanguage: "en")
        XCTAssertEqual(english.languageToReport(.cantonese), .cantonese)
        XCTAssertNil(english.languageToReport(.english), "already known")
        XCTAssertNil(try snapshot(speech: nil).languageToReport(.spanish), "older servers can't keep it")
    }
}
