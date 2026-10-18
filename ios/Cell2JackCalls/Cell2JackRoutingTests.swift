import XCTest
import UIKit
import PorchCore
@testable import Porch

final class Cell2JackRoutingTests: XCTestCase {
    private final class Receiver: UIViewController, Cell2JackDigitReceiving {
        var received: [Int] = []
        var overlay: UIViewController?
        override var presentedViewController: UIViewController? { overlay }
        func receiveCell2JackDigit(_ digit: Int) -> String { received.append(digit); return "handled" }
    }
    @MainActor func testRoutesToCurrentScreenAndBlocksUnknownModal() {
        let clock = Receiver(), call = Receiver()
        XCTAssertEqual(Cell2JackDigitRouter.route("1", root: clock), "handled")
        clock.overlay = call
        XCTAssertEqual(Cell2JackDigitRouter.route("0", root: clock), "handled")
        XCTAssertEqual(clock.received, [1]); XCTAssertEqual(call.received, [0])
        call.overlay = UIViewController() // settings, alert, PIN, permission UI
        XCTAssertEqual(Cell2JackDigitRouter.route("1", root: clock), "screen does not accept phone keys")
        XCTAssertEqual(clock.received, [1]); XCTAssertEqual(call.received, [0])
    }
    @MainActor func testNoHookOrNonDigitInputAndSeparateRepeatedPresses() {
        let screen = Receiver()
        for symbol in ["*", "#", "A", "OFF_HOOK", "ON_HOOK", "١", "10", ""] {
            XCTAssertEqual(Cell2JackDigitRouter.route(symbol, root: screen), "unassigned symbol")
        }
        XCTAssertTrue(screen.received.isEmpty)
        for symbol in ["5", "5", "0"] { _ = Cell2JackDigitRouter.route(symbol, root: screen) }
        XCTAssertEqual(screen.received, [5, 5, 0])
    }
    @MainActor func testNavigationRoutesOnlyToVisibleReceiver() {
        let screen = Receiver(), nav = UINavigationController(rootViewController: screen)
        XCTAssertEqual(Cell2JackDigitRouter.route("2", root: nav), "handled")
        nav.setViewControllers([screen, UIViewController()], animated: false)
        XCTAssertEqual(Cell2JackDigitRouter.route("1", root: nav), "screen does not accept phone keys")
        XCTAssertEqual(screen.received, [2])
    }
    @MainActor func testFragmentedUsbAndDoubleReportsDoNotDoubleActions() {
        var parser = Cell2JackDTMFParser()
        let screen = Receiver()
        var events = parser.append(Data("OFF_HOOK\r\n DT".utf8))
        events += parser.append(Data("MF 1 :0 20: 2\r\nDouble DTMF 1\r\nDTMF 0 :1 20: 2\r\nON_HOOK\r\n".utf8))
        for event in events where event.kind == .digit { _ = Cell2JackDigitRouter.route(event.digit, root: screen) }
        XCTAssertEqual(screen.received, [1, 0])
        XCTAssertEqual(events.filter { $0.kind == .doubleReport }.count, 1)
    }
    @MainActor func testRealCallScreenUsesSavedHangupAssignmentWithoutConnecting() throws {
        let defaults = UserDefaults.standard
        let keys = ["porch.slots.v2", "porch.slots.v1", "porch.contact.v1"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        var slots = CallSlots()
        try slots.setAction(.callControl, for: 4)
        try slots.setAction(.person, for: 0)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try slots.save(photoStore: ContactPhotoStore(directoryURL: folder))
        let call = try NativeCall(room: "local-test", mode: .voice)
        let person = try CallContact(name: "Local fixture", nativeCall: call)
        let server = try NativeCallServer(url: "https://example.invalid", accessCode: "local-fixture-only-access-code")
        let screen = NativeCallViewController(contact: person, call: call, server: server)
        // Deliberately do not load its view: no media or connection task starts.
        _ = screen.receiveCell2JackDigit(0)
        XCTAssertFalse(screen.isEnding)
        _ = screen.receiveCell2JackDigit(4)
        XCTAssertTrue(screen.isEnding)
        XCTAssertEqual(screen.receiveCell2JackDigit(4), "call ending")
        XCTAssertFalse(screen.isViewLoaded)
    }
    @MainActor func testPhoneStatusFitsBelowCallButton() throws {
        func find(_ id: String, in view: UIView) -> UIView? {
            if view.accessibilityIdentifier == id { return view }
            return view.subviews.compactMap { find(id, in: $0) }.first
        }
        for size in [CGSize(width: 744, height: 1133), CGSize(width: 1133, height: 744), CGSize(width: 1032, height: 1376), CGSize(width: 1376, height: 1032)] {
            let clock = CallViewController(); clock.loadViewIfNeeded()
            clock.displayPhoneKeypadStatus("Phone keypad ready", enabled: true)
            clock.view.frame = CGRect(origin: .zero, size: size)
            clock.view.layoutIfNeeded(); clock.viewDidLayoutSubviews(); clock.view.layoutIfNeeded()
            let status = try XCTUnwrap(find("clock.cell2jack", in: clock.view))
            let button = try XCTUnwrap(find("clock.call", in: clock.view))
            XCTAssertFalse(status.isHidden)
            XCTAssertGreaterThan(status.frame.minY, button.frame.maxY)
            XCTAssertLessThanOrEqual(status.frame.maxY, clock.view.safeAreaLayoutGuide.layoutFrame.maxY)
            XCTAssertGreaterThan(status.frame.height, 0)
        }
    }
    @MainActor func testReadyConfirmationDisappearsAfterThreeSecondsWithoutReappearingOnDuplicate() async throws {
        let clock = CallViewController(); clock.loadViewIfNeeded()
        let label = try XCTUnwrap(clock.view.subviews.first { $0.accessibilityIdentifier == "clock.cell2jack" })
        clock.displayPhoneKeypadStatus("Phone keypad ready", enabled: true)
        XCTAssertFalse(label.isHidden)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertFalse(label.isHidden, "The confirmation must remain visible for three seconds")
        clock.displayPhoneKeypadStatus("Phone keypad ready", enabled: true)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(label.isHidden, "A duplicate ready update must not extend the confirmation")
        clock.displayPhoneKeypadStatus("Phone keypad ready", enabled: true)
        XCTAssertTrue(label.isHidden)
        for diagnostic in ["Connecting phone keypad…", "Phone keypad paused", "Stopping phone keypad…",
                           "Phone keypad unavailable: No running Cell2Jack driver service was found.",
                           "Phone keypad stopped: USB stage 10: 0xe00002ed · /q unconfirmed; unplug Cell2Jack if logging persists"] {
            clock.displayPhoneKeypadStatus(diagnostic, enabled: true)
            XCTAssertTrue(label.isHidden, "Connection diagnostics must not appear on the bedside screen")
            XCTAssertNil((label as? UILabel)?.text)
        }
        clock.displayPhoneKeypadStatus("Phone keypad ready", enabled: true)
        XCTAssertFalse(label.isHidden, "A new connection gets its own confirmation")
        clock.displayPhoneKeypadStatus("Phone keypad stopped: USB disconnected", enabled: true)
        XCTAssertTrue(label.isHidden, "A stopped update must also dismiss a visible ready confirmation")
        clock.displayPhoneKeypadStatus("Phone keypad ready", enabled: true)
        XCTAssertFalse(label.isHidden)
        clock.displayPhoneKeypadStatus("Phone keypad off", enabled: false)
        XCTAssertTrue(label.isHidden)
    }
    private final class Connection: Cell2JackKeypadConnection {
        var starts = 0, stops = 0
        let update: (Cell2JackKeypadUpdate) -> Void
        init(_ update: @escaping (Cell2JackKeypadUpdate) -> Void) { self.update = update }
        func start() { starts += 1 }
        func stop() { stops += 1 }
    }
    @MainActor func testEnabledBeforeSceneActivationConnectsAndForegroundReturnWaitsForCleanup() throws {
        let name = "cell2jack-lifecycle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var connections: [Connection] = []
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }) { update in
            let connection = Connection(update); connections.append(connection); return connection
        }
        keypad.setEnabled(true) // launch happens before the window activates
        XCTAssertTrue(connections.isEmpty)
        keypad.activate()
        XCTAssertEqual(connections.count, 1); XCTAssertEqual(connections[0].starts, 1)
        connections[0].update(.ready)
        XCTAssertEqual(keypad.status, "Phone keypad ready")
        keypad.pause()
        XCTAssertEqual(connections[0].stops, 1)
        keypad.activate() // a quick return must not open two USB clients
        XCTAssertEqual(connections.count, 1)
        connections[0].update(.finished("/q sent"))
        XCTAssertEqual(connections.count, 2); XCTAssertEqual(connections[1].starts, 1)
        connections[0].update(.ready) // stale work from the previous activation
        XCTAssertEqual(keypad.status, "Connecting phone keypad…")
        connections[1].update(.ready)
        XCTAssertEqual(keypad.status, "Phone keypad ready")
        keypad.setEnabled(false)
        XCTAssertEqual(connections[1].stops, 1)
        connections[1].update(.finished("/q sent"))
    }
    @MainActor func testDisabledAndFamilyModeNeverOpenUsb() throws {
        let name = "cell2jack-family-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var bedside = false
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { bedside }) { update in
            XCTFail("Inactive, disabled, and family windows must not open USB")
            return Connection(update)
        }
        keypad.activate()
        keypad.setEnabled(true)
        keypad.refresh()
        keypad.pause()
        bedside = true
        keypad.refresh()
        keypad.setEnabled(false)
    }

    @MainActor func testUsbHangupReachesFullScreenReceiverWhenClockViewIsDetached() throws {
        let name = "cell2jack-fullscreen-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var connection: Connection?
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }) { update in
            let result = Connection(update); connection = result; return result
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let clock = Receiver(), call = Receiver()
        clock.loadViewIfNeeded(); clock.overlay = call
        XCTAssertNil(clock.view.window) // UIKit removes a full-screen presenter's view
        keypad.root = clock; keypad.windowScene = scene
        keypad.setEnabled(true); keypad.activate()
        let transport = try XCTUnwrap(connection)
        transport.update(.digits([Cell2JackDigitEvent(kind: .digit, digit: "0", line: "DTMF 0 :0 20: 2")], ProcessInfo.processInfo.systemUptime))
        XCTAssertEqual(call.received, [0]); XCTAssertTrue(clock.received.isEmpty)
        keypad.pause()
        transport.update(.digits([Cell2JackDigitEvent(kind: .digit, digit: "0", line: "DTMF 0")], ProcessInfo.processInfo.systemUptime))
        XCTAssertEqual(call.received, [0], "Input must still stop when the scene becomes inactive")
        transport.update(.finished("/q sent"))
    }

    @MainActor func testNormalPreferenceStartsOffEvenAfterPrototypeOptIn() throws {
        let name = "cell2jack-default-off-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "porch.cell2jack.realCalls.enabled")
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }) { update in
            XCTFail("The old test opt-in must not open USB in the normal app")
            return Connection(update)
        }
        keypad.activate()
        XCTAssertFalse(keypad.enabled)
        XCTAssertNil(defaults.object(forKey: Cell2JackKeypad.enabledKey))
        XCTAssertEqual(keypad.status, "Phone keypad off")
    }
    @MainActor func testCaregiverCell2JackSwitchIsIndependentOfSilenceSaveAndStartsOff() throws {
        guard Cell2JackKeypad.supportsDriverPlatform else { return }
        let name = "cell2jack-switch-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { false }) { Connection($0) }
        let screen = AdvancedSettingsViewController(defaults: defaults, phoneKeypad: keypad)
        screen.loadViewIfNeeded()
        func switches(_ view: UIView) -> [UISwitch] { (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches) }
        let toggle = try XCTUnwrap(switches(screen.view).first { $0.accessibilityIdentifier == "advanced.cell2jack" })
        XCTAssertFalse(toggle.isOn)
        toggle.isOn = true; toggle.sendActions(for: .valueChanged)
        XCTAssertTrue(keypad.enabled)
        XCTAssertFalse(CallPreferences.disconnectAfterSilence(in: defaults))
        toggle.isOn = false; toggle.sendActions(for: .valueChanged)
        XCTAssertFalse(keypad.enabled)
    }
    private final class HardwareKey: UIKey {
        var code: UIKeyboardHIDUsage = .keypad0
        override var keyCode: UIKeyboardHIDUsage { code }
        override var modifierFlags: UIKeyModifierFlags { [] }
        override var characters: String { code == .keypad0 ? "0" : "1" }
        override var charactersIgnoringModifiers: String { characters }
    }
    private final class HardwarePress: UIPress {
        let hardwareKey = HardwareKey()
        override var key: UIKey? { hardwareKey }
    }
    @MainActor func testStandardKeypadStillSelectsPeopleAndHangsUpWithCell2JackOffReadyOrDisconnected() throws {
        let defaults = UserDefaults.standard
        let keys = ["porch.slots.v2", "porch.slots.v1", "porch.contact.v1"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let call = try NativeCall(room: "backup-keypad", mode: .voice)
        let person = try CallContact(name: "Backup keypad fixture", nativeCall: call)
        var slots = CallSlots(); try slots.setContact(person, for: 1)
        try slots.save(photoStore: ContactPhotoStore(directoryURL: folder))
        let server = try NativeCallServer(url: "https://example.invalid", accessCode: "local-fixture-only-access-code")
        for mode in ["off", "ready", "disconnected"] {
            let name = "backup-keypad-\(UUID().uuidString)"
            let settings = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { settings.removePersistentDomain(forName: name) }
            var connection: Connection?
            let keypad = Cell2JackKeypad(defaults: settings, isBedside: { true }) { update in
                let result = Connection(update); connection = result; return result
            }
            keypad.setEnabled(mode != "off"); keypad.activate()
            if mode == "ready" { connection?.update(.ready) }
            if mode == "disconnected" { connection?.update(.finished("Cell2Jack disconnected")) }
            let picker = PeoplePickerViewController(slots: slots)
            var chosen: [Int] = []; picker.onCall = { chosen.append($0) }
            let personPress = HardwarePress(); personPress.hardwareKey.code = .keypad1
            picker.pressesBegan([personPress], with: nil)
            picker.pressesBegan([personPress], with: nil)
            XCTAssertEqual(chosen, [1], "\(mode): held HID key must not duplicate selection")
            picker.pressesEnded([personPress], with: nil)
            let screen = NativeCallViewController(contact: person, call: call, server: server)
            let hangup = HardwarePress()
            screen.pressesBegan([hangup], with: nil)
            XCTAssertTrue(screen.isEnding, "\(mode): standard HID 0 must still hang up")
            keypad.pause(); connection?.update(.finished("/q sent"))
        }
    }
    @MainActor func testTouchCallSomeoneStillOpensPeopleWithCell2JackOff() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let original = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene), clock = CallViewController()
        window.rootViewController = clock; window.makeKeyAndVisible()
        defer { clock.dismiss(animated: false); window.isHidden = true; original?.makeKeyAndVisible() }
        clock.loadViewIfNeeded()
        func buttons(_ view: UIView) -> [UIButton] { (view as? UIButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        let button = try XCTUnwrap(buttons(clock.view).first { $0.accessibilityIdentifier == "clock.call" })
        XCTAssertTrue(button.isEnabled)
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(clock.presentedViewController is PeoplePickerViewController)
    }

}
