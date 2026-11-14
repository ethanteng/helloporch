import XCTest
@testable import PorchCore

final class CallTranslationTests: XCTestCase {
    func testLinesStatesAndSpeakingDecode() throws {
        let line = Data(#"{"type":"line","id":"3","speaker":"ethan","name":"Ethan","side":"family","heard":"The doctor said 你的血壓 is a little high","said":"醫生說你的血壓有點高","language":"zh-Hant","at":1800000000000}"#.utf8)
        XCTAssertEqual(CallTranslationMessage.decode(line), .line(CallTranslationLine(id: "3", speaker: "ethan", name: "Ethan", side: "family",
            heard: "The doctor said 你的血壓 is a little high", said: "醫生說你的血壓有點高", language: "zh-Hant", at: 1_800_000_000_000)))
        let passedThrough = Data(#"{"type":"line","id":"4","speaker":"ethan","name":"Ethan","side":"family","heard":"你今天吃飯了沒有？","said":null,"language":"zh-Hant","at":1}"#.utf8)
        guard case .line(let quiet)? = CallTranslationMessage.decode(passedThrough) else { return XCTFail("line") }
        XCTAssertNil(quiet.said); XCTAssertFalse(quiet.fromBedside)
        XCTAssertEqual(CallTranslationMessage.decode(Data(#"{"type":"state","on":true,"language":"yue-Hant"}"#.utf8)), .state(on: true, language: "yue-Hant"))
        XCTAssertEqual(CallTranslationMessage.decode(Data(#"{"type":"speaking","on":false}"#.utf8)), .speaking(false))
    }

    func testUnknownOrBrokenMessagesAreIgnored() {
        XCTAssertNil(CallTranslationMessage.decode(Data(#"{"type":"dtmf","digit":"1"}"#.utf8)))
        XCTAssertNil(CallTranslationMessage.decode(Data(#"{"type":"state"}"#.utf8)))
        XCTAssertNil(CallTranslationMessage.decode(Data("not json".utf8)))
        XCTAssertEqual(CallTranslationMessage.trackName(forBedside: true), "porch-translation-bedside")
        XCTAssertEqual(CallTranslationMessage.trackName(forBedside: false), "porch-translation-family")
    }

    func testCallsCarryTranslationWhenTheServerSendsIt() throws {
        let json = #"{"id":"c1","from":"ethan","to":"mom","mode":"video","kind":"call","state":"accepted","createdAt":1,"expiresAt":9007199254740991,"callerName":"Ethan","translationAvailable":true,"translation":{"on":true,"language":"zh-Hant","by":"ethan","at":5}}"#
        let call = try JSONDecoder().decode(FamilyCallRecord.self, from: Data(json.utf8))
        XCTAssertEqual(call.translation, FamilyCallTranslation(on: true, language: "zh-Hant", by: "ethan", at: 5))
        XCTAssertEqual(call.translationAvailable, true)
        let older = try JSONDecoder().decode(FamilyCallRecord.self, from: Data(#"{"id":"c1","from":"ethan","to":"mom","mode":"video","kind":"call","state":"accepted","createdAt":1,"expiresAt":2,"callerName":"Ethan"}"#.utf8))
        XCTAssertNil(older.translation); XCTAssertNil(older.translationAvailable)
    }
}
