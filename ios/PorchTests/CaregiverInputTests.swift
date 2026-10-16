import XCTest
import UIKit
@testable import Porch

final class CaregiverInputTests: XCTestCase {
    @MainActor private func buttons(in view: UIView) -> [UIButton] {
        (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    @MainActor func testTouchKeyboardEditsSelectedTextAndDeletesCharacters() {
        let field = UITextField()
        let keyboard = CaregiverTouchKeyboard()
        keyboard.field = field
        field.text = "David"
        let start = field.position(from: field.beginningOfDocument, offset: 1)!
        let end = field.position(from: field.beginningOfDocument, offset: 4)!
        field.selectedTextRange = field.textRange(from: start, to: end)
        buttons(in: keyboard).first { $0.title(for: .normal) == "m" }!.sendActions(for: .touchUpInside)
        XCTAssertEqual(field.text, "Dmd")
        buttons(in: keyboard).first { $0.title(for: .normal) == "⌫" }!.sendActions(for: .touchUpInside)
        XCTAssertEqual(field.text, "Dd")
    }

    @MainActor func testPhoneKeyboardCanEnterCountryCodeAndNumber() {
        let field = UITextField()
        field.keyboardType = .phonePad
        let keyboard = CaregiverTouchKeyboard()
        keyboard.field = field
        for key in ["+", "1", "4", "1", "5"] {
            buttons(in: keyboard).first { $0.title(for: .normal) == key }!.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(field.text, "+1415")
        var next = false
        var done = false
        keyboard.onNext = { next = true }
        keyboard.onDone = { done = true }
        buttons(in: keyboard).first { $0.title(for: .normal) == "Next" }!.sendActions(for: .touchUpInside)
        buttons(in: keyboard).first { $0.title(for: .normal) == "Done" }!.sendActions(for: .touchUpInside)
        XCTAssertTrue(next)
        XCTAssertTrue(done)
    }

    @MainActor func testClockResumeDoesNotStealFocusFromCaregiverForm() async {
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let window = UIWindow(windowScene: original!.windowScene!)
        let clock = CallViewController()
        window.rootViewController = clock
        window.makeKeyAndVisible()
        defer { window.isHidden = true; original?.makeKeyAndVisible() }
        let form = CaregiverFormViewController()
        form.loadViewIfNeeded()
        let field = UITextField()
        field.inputView = UIView()
        form.form.addArrangedSubview(form.field(field, title: "Name", placeholder: "Name"))
        let nav = PorchStyle.navigation(form)
        await withCheckedContinuation { continuation in clock.present(nav, animated: false) { continuation.resume() } }
        XCTAssertTrue(field.becomeFirstResponder())
        clock.resume()
        XCTAssertTrue(field.isFirstResponder, "Foregrounding must preserve caregiver text entry")
        field.insertText("123")
        XCTAssertEqual(field.text, "123")
        XCTAssertTrue(clock.presentedViewController === nav, "Typing keypad digits must not open a call")
        await withCheckedContinuation { continuation in nav.dismiss(animated: false) { continuation.resume() } }
        clock.resume()
        XCTAssertTrue(clock.isFirstResponder, "Returning to the clock restores keypad calling")
    }

    @MainActor func testCaregiverFieldsRemainLegibleWhenDeviceUsesDarkMode() {
        let form = CaregiverFormViewController()
        form.loadViewIfNeeded()
        let field = UITextField()
        _ = form.field(field, title: "Name", placeholder: "Name")
        XCTAssertEqual(form.overrideUserInterfaceStyle, .light)
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.ink, PorchStyle.surface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.secondary, PorchStyle.surface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(.white, PorchStyle.accent), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.nightSecondary, PorchStyle.night), 4.5)
        XCTAssertEqual(field.textColor, PorchStyle.ink)
    }

    @MainActor private func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
        func luminance(_ color: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return linear(r) * 0.2126 + linear(g) * 0.7152 + linear(b) * 0.0722
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
