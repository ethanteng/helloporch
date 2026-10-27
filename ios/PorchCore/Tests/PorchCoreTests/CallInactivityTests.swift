import XCTest
@testable import PorchCore

final class CallInactivityTests: XCTestCase {
    func testRingingAndReconnectionNeverCountTowardSilence() {
        var timer = CallInactivityTimer(timeout: 120)
        XCTAssertFalse(timer.update(at: 0, connected: false, speaking: false))
        XCTAssertFalse(timer.update(at: 900, connected: false, speaking: false))
        XCTAssertFalse(timer.update(at: 901, connected: true, speaking: false))
        XCTAssertFalse(timer.update(at: 1020, connected: true, speaking: false))
        XCTAssertFalse(timer.update(at: 1021, connected: false, speaking: false))
        XCTAssertFalse(timer.update(at: 2000, connected: true, speaking: false))
        XCTAssertFalse(timer.update(at: 2119, connected: true, speaking: false))
        XCTAssertTrue(timer.update(at: 2120, connected: true, speaking: false))
    }

    func testVoicemailGreetingAndMessageRestartTheFullInterval() {
        var timer = CallInactivityTimer(timeout: 30)
        XCTAssertFalse(timer.update(at: 0, connected: true, speaking: false))
        // The remote voicemail greeting counts as speech, as does Mom's message.
        for second in 1...45 {
            XCTAssertFalse(timer.update(at: Double(second), connected: true, speaking: true))
        }
        XCTAssertFalse(timer.update(at: 74, connected: true, speaking: false))
        XCTAssertTrue(timer.update(at: 75, connected: true, speaking: false))
    }

    func testBriefUtteranceBetweenTicksResetsSilence() {
        var timer = CallInactivityTimer(timeout: 15)
        XCTAssertFalse(timer.update(at: 0, connected: true, speaking: false))
        XCTAssertFalse(timer.update(at: 14.5, connected: true, speaking: true))
        XCTAssertFalse(timer.update(at: 15, connected: true, speaking: false))
        XCTAssertFalse(timer.update(at: 29, connected: true, speaking: false))
        XCTAssertTrue(timer.update(at: 29.5, connected: true, speaking: false))
    }

    func testDisabledAndInvalidTimeoutsNeverDisconnect() {
        for timeout in [nil, 0, -10, .infinity, .nan] as [Double?] {
            var timer = CallInactivityTimer(timeout: timeout)
            XCTAssertFalse(timer.update(at: 0, connected: true, speaking: false))
            XCTAssertFalse(timer.update(at: 1_000_000, connected: true, speaking: false))
        }
    }

    func testResetAndBackwardsClockStartANewInterval() {
        var timer = CallInactivityTimer(timeout: 30)
        XCTAssertFalse(timer.update(at: 100, connected: true, speaking: false))
        timer.reset()
        XCTAssertFalse(timer.update(at: 200, connected: true, speaking: false))
        XCTAssertFalse(timer.update(at: 10, connected: true, speaking: false))
        XCTAssertFalse(timer.update(at: 39, connected: true, speaking: false))
        XCTAssertTrue(timer.update(at: 40, connected: true, speaking: false))
    }

    func testPreferencesDefaultOffPersistAndValidateBounds() throws {
        let suite = "porch.silence-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(CallPreferences.disconnectAfterSilence(in: defaults))
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 120)
        CallPreferences.saveSilence(enabled: true, seconds: 45, in: defaults)
        XCTAssertTrue(CallPreferences.disconnectAfterSilence(in: defaults))
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 45)
        CallPreferences.saveSilence(enabled: false, seconds: 0, in: defaults)
        XCTAssertFalse(CallPreferences.disconnectAfterSilence(in: defaults))
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 15)
        CallPreferences.saveSilence(enabled: true, seconds: 9999, in: defaults)
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 1800)
        defaults.set(-10, forKey: "porch.silenceSeconds")
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 120)
    }

    func testSilenceMinuteStepFollowsWholeMinutesAndMovesOneMinuteFromALeftover() {
        XCTAssertEqual(CallPreferences.silenceSeconds(choosing: 5, from: 120), 300)
        XCTAssertEqual(CallPreferences.silenceSeconds(choosing: 1, from: 120), 60)
        // 45 seconds shows as 45 sec. The first + is one minute, not two.
        XCTAssertEqual(CallPreferences.silenceSeconds(choosing: 1, from: 45), 60)
        // 1 min 30 sec: + is 2 min and − is 1 min, rather than jumping to 3 min.
        XCTAssertEqual(CallPreferences.silenceSeconds(choosing: 2, from: 90), 120)
        XCTAssertEqual(CallPreferences.silenceSeconds(choosing: 0, from: 90), 60)
        XCTAssertEqual(CallPreferences.silenceSeconds(choosing: 3, from: 150), 180)
        XCTAssertEqual(CallPreferences.silenceSeconds(choosing: 1, from: 150), 120)
    }
}
