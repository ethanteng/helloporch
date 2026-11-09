import XCTest
@testable import PorchCore

final class BedsideAttendanceTests: XCTestCase {
    func testFamilySeeSomeoneIsThereThenHowLongAgoAndNothingOnceItsStale() {
        XCTAssertNil(BedsideAttendance.text(attendedAt: nil, now: 1000, device: "iPad"))
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1000, now: 1000, device: "iPad"), "Someone is at the iPad")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1000, now: 1089, device: "iPad"), "Someone is at the iPad")
        // A server time a little behind the bedside's report still reads as now.
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1005, now: 1000, device: "iPad"), "Someone is at the iPad")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1000, now: 1090, device: "iPad"), "Someone was at the iPad 1 minute ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 25 * 60 + 59, device: "iPad"), "Someone was at the iPad 25 minutes ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 3600, device: "iPad"), "Someone was at the iPad 1 hour ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 5 * 3600 + 3599, device: "iPad"), "Someone was at the iPad 5 hours ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 86400, device: "iPad"), "Someone was at the iPad 1 day ago")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 6 * 86400 + 86399, device: "iPad"), "Someone was at the iPad 6 days ago")
        XCTAssertNil(BedsideAttendance.text(attendedAt: 0, now: 7 * 86400, device: "iPad"))
        XCTAssertTrue(BedsideAttendance.isPresent(attendedAt: 1000, now: 1089))
        XCTAssertFalse(BedsideAttendance.isPresent(attendedAt: 1000, now: 1090))
        XCTAssertFalse(BedsideAttendance.isPresent(attendedAt: nil, now: 1000))
    }

    func testFamilyCallAnAndroidBedsideItsTablet() throws {
        func snapshot(me: [String: Any], people: [[String: Any]]) throws -> FamilySnapshot {
            let object: [String: Any] = ["householdID": "home", "householdName": "Pat", "dropInEnabled": false, "me": me, "people": people, "busy": false, "serverTime": 1]
            return try JSONDecoder().decode(FamilySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let permissions = ["audio": false, "video": false]
        let phone: [String: Any] = ["id": "fam", "name": "Ethan", "role": "family", "platform": "ios", "permissions": permissions, "online": true]
        func bedside(_ platform: String?) -> [String: Any] {
            var person: [String: Any] = ["id": "bed", "name": "Pat", "role": "bedside", "permissions": permissions, "online": true]
            person["platform"] = platform
            return person
        }
        let android = try snapshot(me: phone, people: [bedside("android")])
        XCTAssertEqual(BedsideAttendance.device(in: android), "tablet")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 1000, now: 1000, device: BedsideAttendance.device(in: android)), "Someone is at the tablet")
        XCTAssertEqual(BedsideAttendance.text(attendedAt: 0, now: 3600, device: BedsideAttendance.device(in: android)), "Someone was at the tablet 1 hour ago")
        XCTAssertEqual(BedsideAttendance.device(in: try snapshot(me: phone, people: [bedside("ios")])), "iPad")
        // A server from before Android doesn't say.
        XCTAssertEqual(BedsideAttendance.device(in: try snapshot(me: phone, people: [bedside(nil)])), "iPad")
        // The bedside's own snapshot has it as `me`.
        XCTAssertEqual(BedsideAttendance.device(in: try snapshot(me: bedside("android"), people: [phone])), "tablet")
    }

    func testTheCameraIsOnUntilACaregiverTurnsItOff() {
        let name = "BedsideAttendanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(BedsideAttendance.cameraEnabled(in: defaults))
        BedsideAttendance.setCameraEnabled(false, in: defaults)
        XCTAssertFalse(BedsideAttendance.cameraEnabled(in: defaults))
        BedsideAttendance.setCameraEnabled(true, in: defaults)
        XCTAssertTrue(BedsideAttendance.cameraEnabled(in: defaults))
        BedsideAttendance.setCameraEnabled(false, in: defaults)
        BedsideAttendance.forgetCamera(in: defaults)
        XCTAssertTrue(BedsideAttendance.cameraEnabled(in: defaults), "A new household starts with the default")
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
