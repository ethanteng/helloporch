import XCTest
@testable import PorchCore

final class IncomingCallCheckInTests: XCTestCase {
    /// A phone in both sets of parents' families hears about each family's calls on every check-in.
    func testACheckInRingsOnlyForANewCallWhileNoOtherIsUp() {
        let lee = UUID(), teng = UUID()
        XCTAssertTrue(IncomingCallCheckIn.reports(lee, current: nil, finished: []))
        XCTAssertFalse(IncomingCallCheckIn.reports(lee, current: lee, finished: []), "already ringing")
        XCTAssertFalse(IncomingCallCheckIn.reports(teng, current: lee, finished: []), "another family's call waits instead of ringing on every check-in")
        // Hung up here: until its family's next check-in says so, that family still lists it as ringing.
        XCTAssertFalse(IncomingCallCheckIn.reports(lee, current: nil, finished: [lee]))
        XCTAssertTrue(IncomingCallCheckIn.reports(teng, current: nil, finished: [lee]), "still ringing once the other call is over")
    }
}
