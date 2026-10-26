import XCTest
@testable import PorchCore

final class CallHistoryTests: XCTestCase {
    private func entry(_ json: String) throws -> CallHistoryEntry {
        try JSONDecoder().decode(CallHistoryEntry.self, from: Data(json.utf8))
    }

    func testCallsReadAsTheyWentFromTheBedsidesSide() throws {
        let talked = try entry(#"{"id":"a","direction":"incoming","via":"porch","name":"Ethan","memberID":"m","mode":"video","startedAt":100,"answeredAt":104,"endedAt":844,"outcome":"answered"}"#)
        XCTAssertEqual(talked.kindText, "Incoming video call"); XCTAssertEqual(talked.outcomeText, "Talked 12 min")
        XCTAssertFalse(talked.isMissed)
        let missed = try entry(#"{"id":"b","direction":"incoming","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"missed"}"#)
        XCTAssertEqual(missed.outcomeText, "Missed"); XCTAssertTrue(missed.isMissed)
        let unanswered = try entry(#"{"id":"c","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"endedAt":130,"outcome":"missed"}"#)
        XCTAssertEqual(unanswered.kindText, "Outgoing audio call"); XCTAssertEqual(unanswered.outcomeText, "No answer")
        XCTAssertFalse(unanswered.isMissed, "only calls to the bedside count as missed")
        XCTAssertEqual(try entry(#"{"id":"c2","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"missed","reached":true}"#).outcomeText, "No answer · Their phone showed the call")
        XCTAssertEqual(try entry(#"{"id":"c3","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"missed","reached":false}"#).outcomeText, "No answer · Didn't reach their phone")
        let dropIn = try entry(#"{"id":"d","direction":"incoming","via":"porch","name":"Ethan","mode":"video","dropIn":true,"startedAt":100,"answeredAt":105,"outcome":"answered"}"#)
        XCTAssertEqual(dropIn.kindText, "Video drop-in"); XCTAssertEqual(dropIn.outcomeText, "Answered", "older calls have no end time")
        let dialed = try entry(#"{"id":"e","direction":"outgoing","via":"phone","name":"David","number":"+14155550123","mode":"voice","startedAt":100,"outcome":"dialed"}"#)
        XCTAssertEqual(dialed.kindText, "Called their phone"); XCTAssertNil(dialed.outcomeText)
        let phone = try entry(#"{"id":"f","direction":"incoming","via":"phone","name":"+14155550999","number":"+14155550999","mode":"voice","startedAt":100,"outcome":"declined"}"#)
        XCTAssertEqual(phone.kindText, "Phone call"); XCTAssertEqual(phone.outcomeText, "Declined")
        XCTAssertEqual(try entry(#"{"id":"g","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"unavailable"}"#).outcomeText, "Couldn't reach their Porch")
        XCTAssertEqual(try entry(#"{"id":"h","direction":"outgoing","via":"porch","name":"Ethan","mode":"voice","startedAt":100,"outcome":"ringing"}"#).outcomeText, "Ringing now")
    }

    func testDurationsRoundToWholeMinutes() {
        XCTAssertEqual(CallHistoryEntry.duration(0), "0 sec")
        XCTAssertEqual(CallHistoryEntry.duration(45), "45 sec")
        XCTAssertEqual(CallHistoryEntry.duration(60), "1 min")
        XCTAssertEqual(CallHistoryEntry.duration(89), "1 min")
        XCTAssertEqual(CallHistoryEntry.duration(90), "2 min")
        XCTAssertEqual(CallHistoryEntry.duration(3600), "1 hr")
        XCTAssertEqual(CallHistoryEntry.duration(3900), "1 hr 5 min")
    }
}
