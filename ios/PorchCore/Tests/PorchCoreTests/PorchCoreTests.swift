import Foundation
import XCTest
@testable import PorchCore

final class PorchCoreTests: XCTestCase {
    func testPhoneNormalizationPreservesInternationalNumber() throws {
        let contact = try CallContact(name: " David ", address: "+1 (415) 555-0123")
        XCTAssertEqual(contact.name, "David")
        XCTAssertEqual(contact.address, "+14155550123")
        XCTAssertEqual(contact.faceTimeURL.absoluteString, "facetime://+14155550123")
    }

    func testEmailIsOneEncodedRecipient() throws {
        let contact = try CallContact(name: "David", address: "david+family&home@example.com")
        XCTAssertEqual(contact.faceTimeURL.absoluteString, "facetime://david+family%26home@example.com")
        XCTAssertNil(URLComponents(url: contact.faceTimeURL, resolvingAgainstBaseURL: false)?.query)
    }

    func testRejectsURLsParametersListsAndPhoneExtensions() {
        for address in ["facetime://david@example.com", "david@example.com?x=1", "a@example.com;b@example.com", "+14155550123#42", "4155550123 ext 2", "++14155550123", "123", "", "１２３４５６７８９"] {
            XCTAssertThrowsError(try CallContact(name: "David", address: address), address)
        }
        XCTAssertThrowsError(try CallContact(name: " ", address: "david@example.com"))
    }

    func testSavedContactRoundTrip() throws {
        let original = try CallContact(name: "David", address: "david@example.com")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(CallContact.self, from: data), original)
    }

    func testHeldKeyCannotRepeatUntilReleased() {
        var trigger = CallTrigger()
        XCTAssertTrue(trigger.keyDown(0x59))
        XCTAssertFalse(trigger.keyDown(0x59))
        trigger.keyUp(0x59)
        XCTAssertTrue(trigger.keyDown(0x59))
        XCTAssertFalse(trigger.keyDown(0x5A)) // keypad 2 must not call
    }

    func testTouchAndKeyboardShareCooldownEvenAfterFocusReset() {
        var trigger = CallTrigger()
        XCTAssertTrue(trigger.allowLaunch(at: 10))
        trigger.resetKeys()
        XCTAssertFalse(trigger.allowLaunch(at: 11))
        XCTAssertTrue(trigger.allowLaunch(at: 12))
    }
}
