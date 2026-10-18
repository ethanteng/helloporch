import XCTest
@testable import PorchCore

final class MessageAutoplayTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "MessageAutoplayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: hour, minute: minute))!
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testAutoplayIsOffUntilACaregiverTurnsItOnAndKeepsToItsHours() {
        let prefs = defaults()
        var settings = MessageAutoplay.load(from: prefs)
        XCTAssertFalse(settings.enabled); XCTAssertFalse(settings.allows(at(12), calendar: calendar))
        settings.enabled = true; settings.save(to: prefs)
        let saved = MessageAutoplay.load(from: prefs)
        XCTAssertEqual(saved, settings)
        XCTAssertFalse(saved.allows(at(7, 59), calendar: calendar))
        XCTAssertTrue(saved.allows(at(8), calendar: calendar)); XCTAssertTrue(saved.allows(at(20, 59), calendar: calendar))
        XCTAssertFalse(saved.allows(at(21), calendar: calendar))
        // Hours that wrap past midnight, for a night owl.
        var late = saved; late.startHour = 20; late.endHour = 2
        XCTAssertTrue(late.allows(at(23), calendar: calendar)); XCTAssertTrue(late.allows(at(1), calendar: calendar))
        XCTAssertFalse(late.allows(at(12), calendar: calendar))
        var always = saved; always.startHour = 9; always.endHour = 9
        XCTAssertTrue(always.allows(at(3), calendar: calendar))
    }

    func testPresenceNeedsACloseFaceForTwoSecondsAndFiresOnce() {
        var trigger = PresenceTrigger()
        // Someone across the room, or walking past, doesn't count.
        for t in stride(from: 0.0, to: 5, by: 0.3) { XCTAssertFalse(trigger.observe(faceHeight: 0.05, at: t)) }
        XCTAssertFalse(trigger.observe(faceHeight: 0.3, at: 5)); XCTAssertFalse(trigger.observe(faceHeight: nil, at: 6.5))
        XCTAssertFalse(trigger.observe(faceHeight: 0.3, at: 7), "a gap restarts the count")
        XCTAssertFalse(trigger.observe(faceHeight: 0.3, at: 8))
        // A blink or a turned head for a moment doesn't.
        XCTAssertFalse(trigger.observe(faceHeight: nil, at: 8.3))
        XCTAssertTrue(trigger.observe(faceHeight: 0.25, at: 9))
        XCTAssertFalse(trigger.observe(faceHeight: 0.25, at: 12), "only once until reset")
        trigger.reset()
        XCTAssertFalse(trigger.observe(faceHeight: 0.25, at: 20)); XCTAssertFalse(trigger.observe(faceHeight: 0.25, at: 21))
        XCTAssertTrue(trigger.observe(faceHeight: 0.25, at: 22))
    }
}
