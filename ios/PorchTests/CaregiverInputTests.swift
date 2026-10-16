import XCTest
import UIKit
import PorchCore
@testable import Porch

final class CaregiverInputTests: XCTestCase {
    @MainActor func testLargeClockFitsPortraitAndLandscapeWithoutCoveringCallButton() {
        func find(_ identifier: String, in view: UIView) -> UIView? {
            if view.accessibilityIdentifier == identifier { return view }
            return view.subviews.compactMap { find(identifier, in: $0) }.first
        }
        for size in [CGSize(width: 744, height: 1133), CGSize(width: 1133, height: 744), CGSize(width: 1032, height: 1376), CGSize(width: 1376, height: 1032)] {
            let clock = CallViewController()
            clock.loadViewIfNeeded()
            clock.view.frame = CGRect(origin: .zero, size: size)
            clock.view.layoutIfNeeded()
            clock.viewDidLayoutSubviews()
            clock.view.layoutIfNeeded()
            let time = find("clock.time", in: clock.view) as! UILabel
            let date = find("clock.date", in: clock.view)!
            let weekday = find("clock.weekday", in: clock.view)!
            let button = find("clock.call", in: clock.view)!
            XCTAssertGreaterThan(time.font.pointSize, 200)
            XCTAssertGreaterThan(time.bounds.width, size.width * 0.85)
            XCTAssertGreaterThanOrEqual(weekday.convert(weekday.bounds, to: clock.view).minY, 0)
            XCTAssertLessThan(date.convert(date.bounds, to: clock.view).maxY, button.frame.minY)
        }
    }

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


    @MainActor func testPINKeyboardProvidesDigitsWithoutPhoneSymbols() {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.isSecureTextEntry = true
        let keyboard = CaregiverTouchKeyboard()
        keyboard.field = field
        XCTAssertNil(buttons(in: keyboard).first { $0.title(for: .normal) == "+" })
        for key in ["0", "1", "2", "3", "4", "5"] {
            buttons(in: keyboard).first { $0.title(for: .normal) == key }!.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(field.text, "012345", "PINs must preserve a leading zero")
    }

    @MainActor func testIncomingCallControlsRemainReachableOnSmallPhone() throws {
        let id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "from": id, "to": id, "mode": "video", "kind": "call", "state": "pending", "createdAt": 1, "expiresAt": 90, "callerName": "A family member with a long display name"])
        let call = try JSONDecoder().decode(FamilyCallRecord.self, from: data)
        for size in [CGSize(width: 320, height: 568), CGSize(width: 568, height: 320)] {
            let incoming = IncomingFamilyCallViewController(call: call, credential: FamilyCredential(origin: URL(string: "https://example.com")!, credential: "test", role: .family))
            incoming.loadViewIfNeeded()
            incoming.view.frame = CGRect(origin: .zero, size: size)
            incoming.view.layoutIfNeeded()
            for button in buttons(in: incoming.view) {
                let frame = button.convert(button.bounds, to: incoming.view)
                XCTAssertGreaterThanOrEqual(frame.height, 64)
                XCTAssertGreaterThanOrEqual(frame.minY, 0)
                XCTAssertLessThanOrEqual(frame.maxY, size.height)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, size.width)
            }
        }
    }


    @MainActor func testContactEditorOnlyOffersPorchDetailsAndPhoneFallback() {
        let editor = SetupViewController(slot: 1, contact: nil)
        editor.loadViewIfNeeded()
        func labels(_ view: UIView) -> [String] {
            (view as? UILabel).flatMap { $0.text }.map { [$0] } ?? view.subviews.flatMap(labels)
        }
        let text = labels(editor.view)
        XCTAssertTrue(text.contains("Their details"))
        XCTAssertTrue(text.contains("Default calling mode"))
        XCTAssertTrue(text.contains("Phone number"))
        for obsolete in ["Call using", "Porch room", "Porch call", "FaceTime", "Shortcut"] { XCTAssertFalse(text.contains(obsolete)) }
        let settings = SlotsViewController(slots: CallSlots())
        settings.loadViewIfNeeded()
        let headings = (0..<settings.numberOfSections(in: settings.tableView)).compactMap { settings.tableView(settings.tableView, titleForHeaderInSection: $0) }
        XCTAssertEqual(headings, ["Keypad · people & controls", "Settings", "Device mode"])
    }

    @MainActor func testFirstCaregiverEntryAsksForChosenPINAndConfirmation() {
        let setup = CaregiverPINViewController(profile: nil)
        setup.loadViewIfNeeded()
        func find(_ id: String, _ view: UIView) -> UITextField? {
            if view.accessibilityIdentifier == id { return view as? UITextField }
            return view.subviews.compactMap { find(id, $0) }.first
        }
        let pin = find("caregiver.pin", setup.view)
        let confirm = find("caregiver.confirm", setup.view)
        XCTAssertNotNil(pin); XCTAssertNotNil(confirm)
        XCTAssertEqual(pin?.text ?? "", "", "A generated PIN must never prefill the chooser")
        XCTAssertEqual(pin?.keyboardType, .numberPad)
        XCTAssertTrue(confirm?.isSecureTextEntry == true)
    }

    @MainActor func testFirstTapOnGearOpensCaregiverGate() async {
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!)
        let clock = CallViewController(); window.rootViewController = clock; window.makeKeyAndVisible()
        defer { window.isHidden = true; original.makeKeyAndVisible() }
        let gear = buttons(in: clock.view).first { $0.accessibilityIdentifier == "clock.caregiver" }!
        gear.sendActions(for: .touchUpInside)
        XCTAssertTrue((clock.presentedViewController as? UINavigationController)?.topViewController is CaregiverPINViewController)
        await withCheckedContinuation { continuation in clock.dismiss(animated: false) { continuation.resume() } }
    }

    @MainActor func testAllTenKeypadRowsIncludeDefaultControlsAndCanBeRemapped() throws {
        let settings = SlotsViewController(slots: CallSlots()); settings.loadViewIfNeeded()
        XCTAssertEqual(settings.tableView(settings.tableView, numberOfRowsInSection: 0), 10)
        let nine = settings.tableView(settings.tableView, cellForRowAt: IndexPath(row: 8, section: 0))
        let zero = settings.tableView(settings.tableView, cellForRowAt: IndexPath(row: 9, section: 0))
        XCTAssertEqual(nine.accessibilityLabel, "Key 9, Turn video off / on")
        XCTAssertEqual(zero.accessibilityLabel, "Key 0, Answer / decline / hang up")
        let editor = SetupViewController(slot: 4, contact: nil, action: .callControl)
        editor.loadViewIfNeeded()
        var saved: KeypadAction?
        editor.onSaveSlot = { action, contact in saved = action; XCTAssertNil(contact) }
        let save = editor.navigationItem.rightBarButtonItem!
        _ = editor.perform(save.action)
        XCTAssertEqual(saved, .callControl, "A control can be saved on any digit without a person's name or phone number")
    }

    @MainActor func testDynamicClockRetainsCurrentDateTimeAndReadableLayout() {
        let old = UserDefaults.standard.data(forKey: "porch.bedsideDisplay.v1")
        defer { UserDefaults.standard.set(old, forKey: "porch.bedsideDisplay.v1") }
        var preferences = BedsidePreferences(); preferences.appearance = .dynamic; preferences.save()
        func find(_ id: String, _ view: UIView) -> UIView? {
            if view.accessibilityIdentifier == id { return view }
            return view.subviews.compactMap { find(id, $0) }.first
        }
        for size in [CGSize(width: 744, height: 1133), CGSize(width: 1133, height: 744), CGSize(width: 320, height: 568), CGSize(width: 568, height: 320)] {
            let clock = CallViewController(); clock.loadViewIfNeeded(); clock.view.frame = CGRect(origin: .zero, size: size)
            clock.view.layoutIfNeeded(); clock.viewDidLayoutSubviews(); clock.view.layoutIfNeeded()
            let time = find("clock.time", clock.view) as! UILabel
            let date = find("clock.date", clock.view) as! UILabel
            let context = find("clock.context", clock.view) as! UILabel
            let call = find("clock.call", clock.view)!
            XCTAssertFalse(time.isHidden); XCTAssertFalse(date.isHidden); XCTAssertFalse(context.isHidden)
            XCTAssertFalse(time.attributedText?.string.isEmpty ?? true)
            XCTAssertEqual(date.text, { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMMdyyyy"); return f.string(from: Date()) }())
            XCTAssertGreaterThanOrEqual(context.convert(context.bounds, to: clock.view).minY, 0)
            XCTAssertLessThan(date.convert(date.bounds, to: clock.view).maxY, call.frame.minY)
        }
    }

    @MainActor func testFamilyInvitationCopyAndGearAreClear() {
        func labels(_ view: UIView) -> [String] { (view as? UILabel).flatMap { $0.text }.map { [$0] } ?? view.subviews.flatMap(labels) }
        let home = FamilyHomeViewController(); home.loadViewIfNeeded()
        XCTAssertFalse(labels(home.view).contains("Close, even from here."))
        XCTAssertNotNil(home.navigationItem.rightBarButtonItem?.image)
        let pairing = FamilyPairingViewController(); pairing.loadViewIfNeeded()
        XCTAssertTrue(labels(pairing.view).contains("Your Porch invite"))
        let editor = SetupViewController(slot: 1, contact: nil); editor.loadViewIfNeeded()
        func segments(_ view: UIView) -> [UISegmentedControl] { (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap(segments) }
        let mode = segments(editor.view).first { $0.accessibilityLabel == "Default calling mode" }
        XCTAssertEqual(mode?.titleForSegment(at: 0), "Voice-only")
        XCTAssertFalse(buttons(in: editor.view).contains { $0.configuration?.title == "Link their Porch app" })
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
