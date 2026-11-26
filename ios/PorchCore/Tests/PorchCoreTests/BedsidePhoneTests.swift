import XCTest
@testable import PorchCore

final class BedsidePhoneTests: XCTestCase {
    func testTheCheckInFollowsThisIPad() {
        func report(onScreen: Bool = true, driver: Bool = false, on: Bool = false, answering: Bool = false, keyboard: Bool = false, heard: Bool = false) -> BedsidePhoneReport? {
            BedsidePhoneReport.make(onScreen: onScreen, driver: driver, driverOn: on, driverAnswering: answering, keyboard: keyboard, adapterHeard: heard)
        }
        // Off screen there's no telling, so nothing is said.
        XCTAssertNil(report(onScreen: false, driver: true, on: true, answering: true))
        XCTAssertEqual(report(), BedsidePhoneReport.none)
        // The driver: on, and answering or not.
        XCTAssertEqual(report(driver: true, on: true, answering: true), .phone(.cell2jack, connected: true))
        XCTAssertEqual(report(driver: true, on: true), .phone(.cell2jack, connected: false))
        XCTAssertEqual(report(driver: true), BedsidePhoneReport.none)
        // The adapter: a keyboard counts once the adapter has been heard here.
        XCTAssertEqual(report(keyboard: true, heard: true), .phone(.adapter, connected: true))
        XCTAssertEqual(report(heard: true), .phone(.adapter, connected: false))
        XCTAssertEqual(report(keyboard: true), BedsidePhoneReport.none)
        XCTAssertEqual(report(driver: true, on: true, keyboard: true, heard: true), .phone(.adapter, connected: true))
    }

    func testTheCheckInAsSent() throws {
        XCTAssertTrue(BedsidePhoneReport.none.json is NSNull)
        let sent = try XCTUnwrap(BedsidePhoneReport.phone(.adapter, connected: false).json as? [String: Any])
        XCTAssertEqual(sent["kind"] as? String, "adapter"); XCTAssertEqual(sent["connected"] as? Bool, false)
    }

    func testAKindFromALaterServerStillDecodes() throws {
        let phone = try JSONDecoder().decode(BedsidePhone.self, from: Data(#"{"since":1800000000,"kind":"bluetooth"}"#.utf8))
        XCTAssertNil(phone.phoneKind)
        XCTAssertEqual(PhoneChecks.steps(kind: phone.phoneKind, device: "iPad").count, 2)
    }

    func testTheStepsFollowHowThePhoneIsPluggedIn() {
        XCTAssertEqual(PhoneChecks.steps(kind: .adapter, device: "iPad"), ["Phone cord into the Cell2Jack", "Cell2Jack into the adapter", "Adapter into the hub by the iPad"])
        XCTAssertEqual(PhoneChecks.steps(kind: .cell2jack, device: "iPad"), ["Phone cord into the Cell2Jack", "Cell2Jack into the iPad or its hub"])
        XCTAssertEqual(PhoneChecks.steps(kind: .cell2jack, device: "tablet"), ["Phone cord into the Cell2Jack", "Cell2Jack into the hub by the tablet"])
        XCTAssertEqual(PhoneChecks.lead(name: "Rose", device: "iPad"), "At Rose’s iPad, check each plug:")
        XCTAssertEqual(PhoneChecks.shareText(name: "Rose", device: "iPad", kind: .adapter, guide: URL(string: "https://helloporch.store/pilot/ios#phone")!), """
            Rose’s phone isn’t connected to Porch. At Rose’s iPad, please check each plug:
            1. Phone cord into the Cell2Jack
            2. Cell2Jack into the adapter
            3. Adapter into the hub by the iPad
            Step-by-step: https://helloporch.store/pilot/ios#phone
            """)
    }
}
