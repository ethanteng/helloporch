import XCTest
@testable import PorchCore

final class IPadChipTests: XCTestCase {
    func testTheStandardIPadAndIPadMiniAndOlderIPadsHaveNoMChip() {
        for model in ["iPad13,18", "iPad13,19",  // iPad (10th generation)
                      "iPad15,7", "iPad15,8",    // iPad (A16)
                      "iPad14,1", "iPad14,2",    // iPad mini (6th generation)
                      "iPad16,1", "iPad16,2",    // iPad mini (A17 Pro)
                      "iPad13,1", "iPad13,2",    // iPad Air (4th generation)
                      "iPad8,12",                // iPad Pro 12.9-inch (4th generation), A12Z
                      "iPad12,1", "iPad11,3", "iPad7,5", "iPad6,11"] {
            XCTAssertTrue(IPadChip.lacksMChip(model: model), model)
            XCTAssertFalse(IPadChip.hasMChip(model: model), model)
        }
    }

    func testIPadProFrom2021AndIPadAirFrom2022HaveAnMChip() {
        for model in ["iPad13,4", "iPad13,11",               // iPad Pro, M1
                      "iPad13,16", "iPad13,17",              // iPad Air (5th generation), M1
                      "iPad14,3", "iPad14,6",                // iPad Pro, M2
                      "iPad14,8", "iPad14,11",               // iPad Air, M2
                      "iPad15,3", "iPad15,4", "iPad15,5", "iPad15,6", // iPad Air, M3, like Mom's
                      "iPad16,3", "iPad16,6",                // iPad Pro, M4
                      "iPad16,8", "iPad16,9", "iPad16,10", "iPad16,11", // iPad Air, M4
                      "iPad17,1", "iPad17,4"] {              // iPad Pro, M5
            XCTAssertFalse(IPadChip.lacksMChip(model: model), model)
            XCTAssertTrue(IPadChip.hasMChip(model: model), model)
        }
    }

    func testAModelItDoesntKnowIsNotCountedOut() {
        // Newer than the list, or not an iPad's identifier at all, such as an iOS app on a Mac.
        for model in ["iPad19,1", "iPad18,2", "iPad17,5", "arm64", "", "iPad", "iPad13", "iPad13,x", "iPhone17,1"] {
            XCTAssertFalse(IPadChip.lacksMChip(model: model), model)
            // Nor is it said to have an M chip: it could be a standard iPad, which needs the adapter.
            XCTAssertFalse(IPadChip.hasMChip(model: model), model)
        }
    }
}
