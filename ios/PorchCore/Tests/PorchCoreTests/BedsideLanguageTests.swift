import XCTest
@testable import PorchCore

final class BedsideLanguageTests: XCTestCase {
    func testOlderDisplaySettingsKeepTheirScheduleAndDefaultToEnglish() throws {
        let data = Data(#"{"appearance":"dynamic","hemisphere":"southern","dayStart":7,"nightStart":21}"#.utf8)
        let saved = try JSONDecoder().decode(BedsidePreferences.self, from: data)
        XCTAssertEqual(saved.appearance, .dynamic); XCTAssertEqual(saved.hemisphere, .southern)
        XCTAssertEqual(saved.dayStart, 7); XCTAssertEqual(saved.nightStart, 21); XCTAssertEqual(saved.language, .english)
        var chinese = saved; chinese.language = .traditionalChinese
        XCTAssertEqual(try JSONDecoder().decode(BedsidePreferences.self, from: JSONEncoder().encode(chinese)), chinese)
        let future = Data(#"{"appearance":"dynamic","dayStart":7,"nightStart":21,"language":"future"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BedsidePreferences.self, from: future).language, .english)
    }
    func testTraditionalChineseCoversOrientationAndCallActions() {
        let language = BedsideLanguage.traditionalChinese
        for key in ["Morning", "Afternoon", "Evening", "Night", "Spring", "Summer", "Fall", "Winter", "Call someone", "Who would you like to call?", "Answer video call", "Don't connect", "End call", "Back to clock"] {
            XCTAssertNotEqual(language.text(key), key)
        }
        XCTAssertEqual(language.format("Call %@, key %d", arguments: ["家人", 8]), "打給家人，按 8")
        XCTAssertEqual(language.format("Video drop-in\nConnecting in %d…", arguments: [5]), "視訊自動接聽\n5 秒後接通…")
        XCTAssertEqual(language.speechLanguage, "zh-TW", "Use Mandarin, not a Cantonese voice")
        XCTAssertTrue(language.format("%@ is dropping in with video. Connecting in five seconds.", arguments: ["家人"]).contains("視訊"))
    }
    func testTraditionalChineseDateKeepsTheLocalDateAndWeekday() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 19, minute: 35))!
        let formatter = DateFormatter(); formatter.locale = BedsideLanguage.traditionalChinese.locale
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        XCTAssertEqual(formatter.string(from: date), "星期五")
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMMd")
        let text = formatter.string(from: date)
        XCTAssertTrue(text.contains("2026年")); XCTAssertTrue(text.contains("10月")); XCTAssertTrue(text.contains("16日"))
    }
    func testCallCuesAreValidAudiblePCMWithFadesAndRingbackSilence() {
        for tone in CallTone.allCases {
            let data = tone.wave()
            XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
            XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
            XCTAssertEqual(data.count, 44 + Int(tone.duration * 16_000) * 2)
            let samples: [Int] = stride(from: 44, to: data.count, by: 2).map { Int(Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8)) }
            XCTAssertEqual(samples.first, 0); XCTAssertLessThan(abs(samples.last!), 250)
            XCTAssertGreaterThan(samples.map(abs).max()!, 10_000); XCTAssertLessThan(samples.map(abs).max()!, 30_000)
            if tone == .ringback { XCTAssertTrue(samples[32_000...].allSatisfy { $0 == 0 }) }
        }
        XCTAssertTrue(CallTone.incoming.loops); XCTAssertTrue(CallTone.ringback.loops)
        XCTAssertFalse(CallTone.connected.loops); XCTAssertFalse(CallTone.announcement.loops)
    }
}
