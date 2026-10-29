import XCTest
@testable import PorchCore

final class FamilyNamesTests: XCTestCase {
    /// Both sets of parents' bedsides are often "Mom". Until the phone names one, the family it joined later is numbered.
    func testFamiliesWithTheSameNameAreNumberedInTheOrderTheyJoined() {
        XCTAssertEqual(FamilyNames.distinct(["Mom", "Mom"]), ["Mom", "Mom 2"])
        XCTAssertEqual(FamilyNames.distinct(["Mom", "mom", "Mom"]), ["Mom", "mom 2", "Mom 3"], "names that differ only in case read the same")
        XCTAssertEqual(FamilyNames.distinct(["Mom", "Sarah's parents"]), ["Mom", "Sarah's parents"])
        XCTAssertEqual(FamilyNames.distinct(["Mom 2", "Mom", "Mom"]), ["Mom 2", "Mom", "Mom 3"], "a number never repeats a name already here")
        XCTAssertEqual(FamilyNames.distinct([nil, "Mom", nil]), [nil, "Mom", nil])
    }
}
