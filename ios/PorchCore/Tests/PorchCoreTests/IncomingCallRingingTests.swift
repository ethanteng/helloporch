import XCTest
@testable import PorchCore

final class IncomingCallRingingTests: XCTestCase {
    /// A phone in both sets of parents' families hears about each family's calls on every check-in.
    func testACallRingsOnlyWhileNoOtherCallIsUp() {
        let lee = UUID(), teng = UUID()
        XCTAssertTrue(IncomingCallRinging.canRing(lee, current: nil, onAnotherCall: false, finished: []))
        XCTAssertFalse(IncomingCallRinging.canRing(lee, current: lee, onAnotherCall: false, finished: []), "already ringing")
        XCTAssertFalse(IncomingCallRinging.canRing(teng, current: lee, onAnotherCall: false, finished: []), "another family's call waits instead of ringing on every check-in")
        // Hung up here: until its family's next check-in says so, that family still lists it as ringing.
        XCTAssertFalse(IncomingCallRinging.canRing(lee, current: nil, onAnotherCall: false, finished: [lee]))
        XCTAssertTrue(IncomingCallRinging.canRing(teng, current: nil, onAnotherCall: false, finished: [lee]), "still ringing once the other call is over")
    }
    /// The phone called one family itself. CallKit doesn't know about that call, so another family's can't ring over it.
    func testACallThisPhoneStartedKeepsAnotherFamilysCallFromRinging() {
        let teng = UUID()
        XCTAssertFalse(IncomingCallRinging.canRing(teng, current: nil, onAnotherCall: true, finished: []))
        XCTAssertTrue(IncomingCallRinging.pushBlocked(teng, current: nil, onAnotherCall: true, finished: []), "a push during it is reported, ended and finished")
    }
    /// The second family's VoIP push is reported and ended while the first call is up. That UUID can't ring again.
    func testAPushDuringAnotherCallIsFinishedSoALaterCheckInDoesNotReportIt() {
        let lee = UUID(), teng = UUID()
        XCTAssertTrue(IncomingCallRinging.pushBlocked(teng, current: lee, onAnotherCall: false, finished: []))
        XCTAssertFalse(IncomingCallRinging.pushBlocked(teng, current: nil, onAnotherCall: false, finished: []), "nothing else is up, so the push can ring")
        XCTAssertFalse(IncomingCallRinging.pushBlocked(lee, current: lee, onAnotherCall: false, finished: []))
        XCTAssertFalse(IncomingCallRinging.pushBlocked(teng, current: lee, onAnotherCall: false, finished: [teng]), "already remembered")
        XCTAssertFalse(IncomingCallRinging.canRing(teng, current: nil, onAnotherCall: false, finished: [teng]), "already handed to CallKit")
        XCTAssertTrue(IncomingCallRinging.canRing(teng, current: nil, onAnotherCall: false, finished: [lee]), "a check-in that never reported it still rings once the other call is over")
    }
    /// The push often arrives before the check-in that lists the call. That check-in hangs it up as missed.
    /// A guest ring uses the same id in its own snapshot, and ending it would count as a decline.
    func testABusyPushIsMissedOnceTheCheckInShowsItAndAGuestRingIsLeftToTimeOut() {
        let id = UUID()
        XCTAssertTrue(IncomingCallRinging.endAsMissed(id, snapshotCallID: id.uuidString.lowercased(), guest: false))
        XCTAssertFalse(IncomingCallRinging.endAsMissed(id, snapshotCallID: nil, guest: false), "the check-in has not listed it yet")
        XCTAssertFalse(IncomingCallRinging.endAsMissed(id, snapshotCallID: UUID().uuidString, guest: false))
        XCTAssertFalse(IncomingCallRinging.endAsMissed(id, snapshotCallID: id.uuidString.lowercased(), guest: true), "ending a guest ring counts as a decline")
    }
}
