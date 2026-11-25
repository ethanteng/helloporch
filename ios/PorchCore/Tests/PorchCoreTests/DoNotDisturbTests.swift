import XCTest
@testable import PorchCore

final class DoNotDisturbTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "DoNotDisturbTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: hour, minute: minute))!
    }

    func testOffUntilTurnedOnAndKeptOnThisPhone() {
        let prefs = defaults()
        let start = DoNotDisturb.load(from: prefs)
        XCTAssertFalse(start.on); XCTAssertFalse(start.scheduled)
        XCTAssertEqual([start.startHour, start.endHour], [22, 7], "the hours offered first are overnight")
        XCTAssertFalse(start.applies(at: at(23), calendar: calendar), "the hours do nothing until scheduled")
        var on = start; on.on = true; on.save(to: prefs)
        XCTAssertEqual(DoNotDisturb.load(from: prefs), on)
        XCTAssertTrue(DoNotDisturb.load(from: prefs).applies(at: at(12), calendar: calendar))
    }

    func testScheduledHoursRunPastMidnightAndTheSameHourIsAllDay() {
        var night = DoNotDisturb(); night.scheduled = true
        XCTAssertTrue(night.applies(at: at(22), calendar: calendar)); XCTAssertTrue(night.applies(at: at(6, 59), calendar: calendar))
        XCTAssertFalse(night.applies(at: at(7), calendar: calendar)); XCTAssertFalse(night.applies(at: at(21, 59), calendar: calendar))
        var work = night; work.startHour = 9; work.endHour = 17
        XCTAssertTrue(work.applies(at: at(9), calendar: calendar)); XCTAssertFalse(work.applies(at: at(17), calendar: calendar))
        var always = night; always.startHour = 9; always.endHour = 9
        XCTAssertTrue(always.applies(at: at(3), calendar: calendar))
    }

    func testCheckInsSayHoursOnlyWhenScheduledWithThisPhonesTimeZone() {
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        var settings = DoNotDisturb()
        XCTAssertEqual(settings.checkIn(timeZone: zone) as NSDictionary, ["on": false] as NSDictionary, "all off still says so, to clear it")
        settings.on = true
        XCTAssertEqual(settings.checkIn(timeZone: zone) as NSDictionary, ["on": true] as NSDictionary)
        settings.scheduled = true; settings.startHour = 23; settings.endHour = 6
        XCTAssertEqual(settings.checkIn(timeZone: zone) as NSDictionary,
                       ["on": true, "hours": ["start": 23, "end": 6], "timeZone": "Asia/Tokyo"] as NSDictionary)
    }

    func testSavedHoursOutOfRangeFallBackToTheDefaults() {
        let prefs = defaults()
        prefs.set(#"{"on":true,"scheduled":true,"startHour":30,"endHour":7}"#.data(using: .utf8), forKey: "porch.doNotDisturb.v1")
        XCTAssertEqual(DoNotDisturb.load(from: prefs), DoNotDisturb())
        var odd = DoNotDisturb(); odd.startHour = -2; odd.endHour = 40; odd.save(to: prefs)
        XCTAssertEqual([DoNotDisturb.load(from: prefs).startHour, DoNotDisturb.load(from: prefs).endHour], [0, 23])
    }
}
