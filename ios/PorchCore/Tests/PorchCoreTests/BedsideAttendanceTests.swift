import XCTest
@testable import PorchCore

final class BedsideAttendanceTests: XCTestCase {
    func testFamilySeeSomeoneIsThereThenHowLongAgoAndNothingOnceItsStale() {
        XCTAssertNil(BedsideAttendance.text(attendedAt: nil, now: 1000))
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1000, now: 1000), "Someone is at the iPad")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1000, now: 1089), "Someone is at the iPad")
        // A server time a little behind the bedside's report still reads as now.
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1005, now: 1000), "Someone is at the iPad")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1000, now: 1090), "Someone was at the iPad 1 minute ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 25 * 60 + 59), "Someone was at the iPad 25 minutes ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 3600), "Someone was at the iPad 1 hour ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 5 * 3600 + 3599), "Someone was at the iPad 5 hours ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 86400), "Someone was at the iPad 1 day ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 6 * 86400 + 86399), "Someone was at the iPad 6 days ago")
        XCTAssertNil(BedsideAttendance.text(attendedAt: 0, now: 7 * 86400))
        XCTAssertTrue(BedsideAttendance.isPresent(attendedAt: 1000, now: 1089))
        XCTAssertFalse(BedsideAttendance.isPresent(attendedAt: 1000, now: 1090))
        XCTAssertFalse(BedsideAttendance.isPresent(attendedAt: nil, now: 1000))
    }

    func testTheCameraIsOffUntilACaregiverTurnsItOn() {
        let name = "BedsideAttendanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(BedsideAttendance.cameraEnabled(in: defaults))
        BedsideAttendance.setCameraEnabled(true, in: defaults)
        XCTAssertTrue(BedsideAttendance.cameraEnabled(in: defaults))
        BedsideAttendance.setCameraEnabled(false, in: defaults)
        XCTAssertFalse(BedsideAttendance.cameraEnabled(in: defaults))
    }

    func testTheBedsideReportsWholeSecondsSinceItLastNoticedSomeone() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let tracker = AttendanceTracker(clock: { now })
        XCTAssertNil(tracker.secondsSince, "nothing to report until someone is noticed")
        tracker.noticed()
        XCTAssertEqual(tracker.secondsSince, 0)
        now += 41.7
        XCTAssertEqual(tracker.secondsSince, 41)
        tracker.noticed()
        XCTAssertEqual(tracker.secondsSince, 0)
        // A clock set back must not be reported as someone just arriving.
        now -= 600
        XCTAssertNil(tracker.secondsSince)
        tracker.noticed()
        XCTAssertEqual(tracker.secondsSince, 0, "a touch after the clock changes still counts")
        tracker.forget()
        XCTAssertNil(tracker.secondsSince, "nothing from while sharing was off")
    }
}
