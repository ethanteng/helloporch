import XCTest
@testable import PorchCore

final class MessageBadgeTests: XCTestCase {
    /// A notification said 3, counting both families. The first to check in mustn't lower it to its own 1.
    func testTheBadgeWaitsForEveryFamilyToCheckIn() {
        XCTAssertNil(MessageBadge.count([1, nil]))
        XCTAssertEqual(MessageBadge.count([1, 2]), 3)
        XCTAssertEqual(MessageBadge.count([0, 0]), 0)
        XCTAssertNil(MessageBadge.count([]), "no family, nothing to say")
    }
}
