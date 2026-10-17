import XCTest
@testable import PorchCore

final class BedsideLanguageTests: XCTestCase {
    func testOlderDisplaySettingsKeepTheirScheduleAndDefaultToEnglish() throws {
        let data = Data(#"{"appearance":"dynamic","hemisphere":"southern","dayStart":7,"nightStart":21}"#.utf8)
        let saved = try JSONDecoder().decode(BedsidePreferences.self, from: data)
        XCTAssertEqual(saved.appearance, .dynamic); XCTAssertEqual(saved.hemisphere, .southern)
        XCTAssertEqual(saved.dayStart, 7); XCTAssertEqual(saved.nightStart, 21); XCTAssertEqual(saved.language, .english)
        XCTAssertTrue(saved.announcementVoiceIdentifiers.isEmpty)
        for language in BedsideLanguage.allCases {
            var localized = saved; localized.language = language
            XCTAssertEqual(try JSONDecoder().decode(BedsidePreferences.self, from: JSONEncoder().encode(localized)), localized)
        }
        let future = Data(#"{"appearance":"dynamic","dayStart":7,"nightStart":21,"language":"future"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BedsidePreferences.self, from: future).language, .english)
    }
    func testAnnouncementVoiceChoicesSurviveLanguageChangesAndRelaunch() throws {
        let suite = "voice-preferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = BedsidePreferences()
        preferences.dayStart = 7; preferences.nightStart = 21; preferences.hemisphere = .southern
        for language in BedsideLanguage.allCases {
            XCTAssertNil(preferences.announcementVoiceIdentifier(for: language))
            preferences.setAnnouncementVoiceIdentifier("voice-\(language.rawValue)", for: language)
        }
        preferences.language = .cantonese
        preferences.save(to: defaults)
        var loaded = BedsidePreferences.load(from: defaults)
        XCTAssertEqual(loaded, preferences)
        loaded.language = .spanish
        loaded.setAnnouncementVoiceIdentifier(nil, for: .spanish)
        loaded.save(to: defaults)
        let reopened = BedsidePreferences.load(from: defaults)
        XCTAssertNil(reopened.announcementVoiceIdentifier(for: .spanish))
        for language in BedsideLanguage.allCases where language != .spanish {
            XCTAssertEqual(reopened.announcementVoiceIdentifier(for: language), "voice-\(language.rawValue)")
        }
        XCTAssertEqual(reopened.dayStart, 7); XCTAssertEqual(reopened.nightStart, 21)
        XCTAssertEqual(reopened.hemisphere, .southern)
    }
    func testVoiceMatchingAllowsRegionalAccentsButKeepsChineseDialectsSeparate() {
        let cases: [(String, BedsideLanguage)] = [
            ("en-US", .english), ("en-GB", .english), ("en_AU", .english),
            ("es-ES", .spanish), ("es-MX", .spanish), ("es-US", .spanish),
            ("zh-TW", .traditionalChinese), ("zh-Hant-TW", .traditionalChinese), ("cmn-TW", .traditionalChinese),
            ("zh-CN", .simplifiedChinese), ("zh-Hans-CN", .simplifiedChinese), ("cmn-CN", .simplifiedChinese),
            ("zh-HK", .cantonese), ("zh-Hant-HK", .cantonese), ("yue-HK", .cantonese), ("yue-Hant-HK", .cantonese),
        ]
        for (tag, expected) in cases {
            for language in BedsideLanguage.allCases {
                XCTAssertEqual(language.supportsSpeechVoice(language: tag), language == expected, "\(tag) / \(language)")
            }
        }
        for unsupported in ["fr-FR", "zh", "zh-SG", "enochian", "", "yue-CN"] {
            XCTAssertFalse(BedsideLanguage.allCases.contains { $0.supportsSpeechVoice(language: unsupported) }, unsupported)
        }
    }
    func testEveryLanguageCoversAllBedsideStringsAndPreservesFormatArguments() throws {
        let keys = Set(BedsideLanguage.traditionalChinese.translations.keys)
        let placeholders = try NSRegularExpression(pattern: "%[@d]")
        func arguments(in text: String) -> [String] {
            placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
        }
        for language in BedsideLanguage.allCases where language != .english {
            XCTAssertEqual(Set(language.translations.keys), keys, language.rawValue)
            for key in keys {
                let text = language.text(key)
                XCTAssertFalse(text.isEmpty, "\(language): \(key)")
                XCTAssertNotEqual(text, key, "\(language): \(key)")
                XCTAssertEqual(arguments(in: text), arguments(in: key), "\(language): \(key)")
            }
            XCTAssertTrue(language.format("Call %@, key %d", arguments: ["María 陳", 8]).contains("María 陳"))
            XCTAssertTrue(language.format("Call %@, key %d", arguments: ["María 陳", 8]).contains("8"))
        }
    }
    func testNewLanguagesUseDistinctTranslationsAndAnnouncementVoices() {
        XCTAssertEqual(BedsideLanguage.simplifiedChinese.text("End call"), "挂断")
        XCTAssertEqual(BedsideLanguage.cantonese.text("End call"), "收線")
        XCTAssertEqual(BedsideLanguage.spanish.text("End call"), "Colgar")
        XCTAssertEqual(BedsideLanguage.simplifiedChinese.speechLanguage, "zh-CN")
        XCTAssertEqual(BedsideLanguage.cantonese.speechLanguage, "zh-HK")
        XCTAssertEqual(BedsideLanguage.spanish.speechLanguage, "es-ES")
        XCTAssertEqual(BedsideLanguage.cantonese.format("%@ is dropping in with video. Connecting in five seconds.", arguments: ["陳先生"]), "陳先生想同您視像通話，五秒後接通。")
        XCTAssertEqual(BedsideLanguage.simplifiedChinese.format("Video drop-in\nConnecting in %d…", arguments: [5]), "视频自动接听\n5 秒后接通…")
        XCTAssertEqual(BedsideLanguage.spanish.format("Tap %d to answer. Hold %d to decline.", arguments: [0, 0]), "Pulse 0 para contestar. Mantenga pulsado 0 para rechazar.")
        XCTAssertEqual(BedsideLanguage.english.text("End call"), "End call")
    }
    func testNewLanguageDatesKeepTheLocalDateAndWeekday() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 23, minute: 35))!
        for language in [BedsideLanguage.simplifiedChinese, .cantonese, .spanish] {
            let formatter = DateFormatter(); formatter.locale = language.locale
            formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            XCTAssertEqual(formatter.string(from: date), language == .spanish ? "viernes" : "星期五")
            formatter.setLocalizedDateFormatFromTemplate("yyyyMMMMd")
            let text = formatter.string(from: date)
            XCTAssertTrue(text.contains("2026")); XCTAssertTrue(text.contains("16"))
            XCTAssertTrue(text.contains(language == .spanish ? "octubre" : "10月"))
        }
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
