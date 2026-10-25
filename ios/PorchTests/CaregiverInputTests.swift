import XCTest
import UIKit
import GameController
import AVFoundation
import Security
import SafariServices
import PorchCore
@testable import Porch
@testable import LiveKit

final class CaregiverInputTests: XCTestCase {
    @MainActor private func portraitData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        }.jpegData(compressionQuality: 0.8)!
    }

    @MainActor func testRecipientPhotosColorsAndLargerCallingControls() throws {
        let restore = localizedBedside(.english); defer { restore() }
        let photo = portraitData()
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "test", mode: .video), buttonColorHex: "FFCC00", photoData: photo), for: 1)
        let picker = PeoplePickerViewController(slots: slots); picker.loadViewIfNeeded()
        for size in [CGSize(width: 375, height: 667), CGSize(width: 1032, height: 1376), CGSize(width: 1376, height: 1032)] {
            picker.view.frame = CGRect(origin: .zero, size: size); picker.view.layoutIfNeeded(); picker.viewDidLayoutSubviews(); picker.view.layoutIfNeeded()
            let card = try XCTUnwrap(buttons(in: picker.view).first { $0.accessibilityIdentifier == "people.person.1" })
            XCTAssertNotNil(card.configuration?.image)
            XCTAssertGreaterThanOrEqual(card.configuration?.image?.size.width ?? 0, 250)
            XCTAssertGreaterThanOrEqual(card.titleLabel?.font.pointSize ?? 0, 54)
            XCTAssertEqual(card.configuration?.baseForegroundColor, .black)
            XCTAssertEqual(card.configuration?.baseBackgroundColor, RecipientAppearance.color(hex: "FFCC00"))
            XCTAssertEqual(card.configuration?.subtitle, "Press 1")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(buttons(in: picker.view).first { $0.accessibilityIdentifier == "people.back" }).bounds.height, 96)
        }
        let clock = CallViewController(); clock.loadViewIfNeeded()
        clock.view.frame = CGRect(x: 0, y: 0, width: 1032, height: 1376); clock.view.layoutIfNeeded()
        let call = try XCTUnwrap(buttons(in: clock.view).first { $0.accessibilityIdentifier == "clock.call" })
        XCTAssertGreaterThanOrEqual(call.bounds.width, 700); XCTAssertGreaterThanOrEqual(call.bounds.height, 96)
        XCTAssertGreaterThanOrEqual(call.titleLabel?.font.pointSize ?? 0, 32)
        XCTAssertEqual(RecipientAppearance.foreground(on: .white), .black)
        XCTAssertEqual(RecipientAppearance.foreground(on: .black), .white)
    }

    @MainActor func testSelectedPhotosAreDownsampledAndInvalidPhotosRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("porch-photo-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1800, height: 2400)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 2400))
        }
        try image.jpegData(compressionQuality: 1)!.write(to: url)
        let data = try XCTUnwrap(RecipientAppearance.preparedPhoto(at: url))
        let resized = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(resized.size.width, resized.size.height), 768)
        XCTAssertLessThanOrEqual(data.count, 1_000_000)
        try Data("invalid photo".utf8).write(to: url)
        XCTAssertNil(RecipientAppearance.preparedPhoto(at: url))
    }

    @MainActor func testCaregiverCanChangeColorRemovePhotoAndSave() async throws {
        let person = try CallContact(name: "David", nativeCall: NativeCall(room: "test", mode: .voice), familyMemberID: UUID().uuidString, buttonColorHex: "FFCC00", photoData: portraitData())
        let editor = SetupViewController(slot: 1, contact: person); editor.loadViewIfNeeded()
        let colorPicker = UIColorPickerViewController(); colorPicker.selectedColor = .white
        editor.colorPickerViewControllerDidSelectColor(colorPicker)
        let remove = try XCTUnwrap(buttons(in: editor.view).first { $0.accessibilityIdentifier == "recipient.removePhoto" })
        remove.sendActions(for: .touchUpInside)
        let saved = expectation(description: "Appearance saved with contact")
        editor.onSaveSlot = { action, contact in
            XCTAssertEqual(action, .person); XCTAssertEqual(contact?.buttonColorHex, "FFFFFF"); XCTAssertNil(contact?.photoData)
            saved.fulfill()
        }
        let save = try XCTUnwrap(editor.navigationItem.rightBarButtonItem)
        _ = editor.perform(try XCTUnwrap(save.action))
        await fulfillment(of: [saved], timeout: 2)
    }

    @MainActor func testCaregiverAdvancedMenuOpensSilenceSettings() throws {
        let slots = SlotsViewController(slots: CallSlots())
        let navigation = UINavigationController(rootViewController: slots)
        navigation.loadViewIfNeeded(); slots.loadViewIfNeeded()
        XCTAssertEqual(slots.tableView(slots.tableView, numberOfRowsInSection: 1), 4)
        let path = IndexPath(row: 3, section: 1)
        let cell = slots.tableView(slots.tableView, cellForRowAt: path)
        XCTAssertEqual((cell.contentConfiguration as? UIListContentConfiguration)?.text, "Advanced")
        slots.tableView(slots.tableView, didSelectRowAt: path)
        XCTAssertTrue(navigation.topViewController is AdvancedSettingsViewController)
    }

    @MainActor func testAdvancedSilenceSettingValidatesSavesAndCanBeTurnedOff() throws {
        let suite = "porch.advanced-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let screen = AdvancedSettingsViewController(defaults: defaults)
        screen.loadViewIfNeeded()
        func find<T: UIView>(_ view: UIView, _ type: T.Type) -> T? {
            if let found = view as? T { return found }
            return view.subviews.lazy.compactMap { find($0, type) }.first
        }
        let toggle = try XCTUnwrap(find(screen.view, UISwitch.self))
        let field = try XCTUnwrap(find(screen.view, UITextField.self))
        XCTAssertFalse(toggle.isOn); XCTAssertEqual(field.text, "120")
        toggle.isOn = true; toggle.sendActions(for: .valueChanged)
        for invalid in ["", "hello", "14", "1801", "3.5", "-30"] {
            field.text = invalid; field.sendActions(for: .editingChanged)
            XCTAssertFalse(screen.navigationItem.rightBarButtonItem!.isEnabled, invalid)
        }
        field.text = "45"; field.sendActions(for: .editingChanged)
        let navigation = UINavigationController(rootViewController: screen)
        navigation.loadViewIfNeeded()
        let original = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow })
        let window = UIWindow(windowScene: try XCTUnwrap(original.windowScene))
        window.rootViewController = navigation; window.makeKeyAndVisible()
        defer { window.isHidden = true; original.makeKeyAndVisible() }
        for size in [CGSize(width: 393, height: 852), CGSize(width: 1024, height: 768)] {
            window.frame = CGRect(origin: .zero, size: size)
            window.setNeedsLayout(); window.layoutIfNeeded()
            navigation.view.setNeedsLayout(); navigation.view.layoutIfNeeded(); screen.view.layoutIfNeeded()
            XCTAssertGreaterThan(try XCTUnwrap(find(screen.view, UIScrollView.self)).bounds.height, 100)
            XCTAssertGreaterThan(field.bounds.width, 100)
            XCTAssertFalse(field.superview!.isHidden)
        }
        let save = try XCTUnwrap(screen.navigationItem.rightBarButtonItem)
        XCTAssertTrue(save.isEnabled)
        UIApplication.shared.sendAction(try XCTUnwrap(save.action), to: save.target, from: save, for: nil)
        XCTAssertTrue(CallPreferences.disconnectAfterSilence(in: defaults))
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 45)
        let reloaded = AdvancedSettingsViewController(defaults: defaults); reloaded.loadViewIfNeeded()
        let reloadedToggle = try XCTUnwrap(find(reloaded.view, UISwitch.self))
        XCTAssertTrue(reloadedToggle.isOn)
        reloadedToggle.isOn = false; reloadedToggle.sendActions(for: .valueChanged)
        let off = try XCTUnwrap(reloaded.navigationItem.rightBarButtonItem)
        UIApplication.shared.sendAction(try XCTUnwrap(off.action), to: off.target, from: off, for: nil)
        XCTAssertFalse(CallPreferences.disconnectAfterSilence(in: defaults))
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 45)
    }

    @MainActor func testCallCredentialsCanMigrateToLockScreenAccessWithoutChangingOtherSecrets() throws {
        let account = "porch.test.incoming.\(UUID().uuidString)"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier!, kSecAttrAccount as String: account]
        defer { SecItemDelete(query as CFDictionary) }
        func accessibility() throws -> String {
            var result: CFTypeRef?
            var attributes = query; attributes[kSecReturnAttributes as String] = true
            XCTAssertEqual(SecItemCopyMatching(attributes as CFDictionary, &result), errSecSuccess)
            return try XCTUnwrap((result as? [String: Any])?[kSecAttrAccessible as String] as? String)
        }
        let secret = Data("private-device-credential".utf8)
        try NativeCallSettings.writeSecret(secret, account: account)
        XCTAssertEqual(try accessibility(), kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        try NativeCallSettings.writeSecret(secret, account: account, accessibleAfterFirstUnlock: true)
        XCTAssertEqual(try accessibility(), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(NativeCallSettings.readSecret(account), secret)
        try NativeCallSettings.writeSecret(secret, account: account)
        XCTAssertEqual(try accessibility(), kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    @MainActor func testBothPairedCallingCredentialsAreAvailableAfterFirstUnlock() throws {
        for role in [PorchExperience.bedside, .family] {
            let account = "porch.family.\(role.rawValue)"
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Bundle.main.bundleIdentifier!, kSecAttrAccount as String: account]
            let previous = NativeCallSettings.readSecret(account)
            var previousAttributes: CFTypeRef?
            var attributes = query; attributes[kSecReturnAttributes as String] = true
            SecItemCopyMatching(attributes as CFDictionary, &previousAttributes)
            let wasBackgroundAccessible = (previousAttributes as? [String: Any])?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
            defer {
                if let previous { try? NativeCallSettings.writeSecret(previous, account: account, accessibleAfterFirstUnlock: wasBackgroundAccessible) }
                else { SecItemDelete(query as CFDictionary) }
            }
            let profile = FamilyCredential(origin: URL(string: "https://example.invalid")!, credential: "test-device.test-secret", role: role)
            try PorchDevice.save(profile)
            var result: CFTypeRef?
            XCTAssertEqual(SecItemCopyMatching(attributes as CFDictionary, &result), errSecSuccess)
            XCTAssertEqual((result as? [String: Any])?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
            XCTAssertEqual(PorchDevice.credential(for: role)?.credential, profile.credential)
        }
    }

    @MainActor private func localizedBedside(_ language: BedsideLanguage = .traditionalChinese) -> () -> Void {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "porch.bedsideDisplay.v1"), experience = defaults.object(forKey: "porch.experience")
        var preferences = BedsidePreferences(); preferences.language = language; preferences.appearance = .dynamic; preferences.save()
        defaults.set("bedside", forKey: "porch.experience")
        return { defaults.set(saved, forKey: "porch.bedsideDisplay.v1"); defaults.set(experience, forKey: "porch.experience") }
    }
    @MainActor private func labels(in view: UIView) -> [UILabel] { (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) } }
    @MainActor private func incoming(_ kind: String, mode: NativeCall.Mode = .video, callerName: String = "家人", snapshot: FamilySnapshot? = nil, audio: IncomingCallAudioPlaying) throws -> IncomingFamilyCallViewController {
        let id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "from": id, "to": snapshot?.me.id ?? id, "mode": mode.rawValue, "kind": kind, "state": "pending", "createdAt": 1, "expiresAt": 90, "callerName": callerName])
        let call = try JSONDecoder().decode(FamilyCallRecord.self, from: data)
        return IncomingFamilyCallViewController(call: call, credential: FamilyCredential(origin: URL(string: "https://example.com")!, credential: "test", role: .bedside), snapshot: snapshot, audio: audio)
    }
    @MainActor func testRenamedContactIsShownAndAnnouncedForIncomingVoiceVideoAndDropIn() throws {
        let restoreLanguage = localizedBedside(); defer { restoreLanguage() }
        let defaults = UserDefaults.standard, keys = ["porch.slots.v2", "porch.slots.v2.symbols", "porch.slots.v1", "porch.contact.v1"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let caller = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let data = try JSONSerialization.data(withJSONObject: ["householdID": "home", "householdName": "Pat", "dropInEnabled": true,
            "me": ["id": "bedside", "name": "Pat", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true],
            "people": [["id": caller, "name": "Ethan", "role": "family", "permissions": ["audio": true, "video": true], "online": true]], "busy": false, "serverTime": 1])
        let snapshot = try JSONDecoder().decode(FamilySnapshot.self, from: data)
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "paired", mode: .video), familyMemberID: caller, buttonColorHex: "FFCC00", photoData: portraitData()), for: 1)
        try slots.save()
        for kind in ["call", "dropIn"] {
            for mode in [NativeCall.Mode.voice, .video] {
                let audio = TestIncomingAudio()
                let controller = try incoming(kind, mode: mode, callerName: "Ethan", snapshot: snapshot, audio: audio)
                controller.loadViewIfNeeded(); controller.viewDidAppear(false)
                XCTAssertTrue(labels(in: controller.view).contains { $0.text == "David" })
                XCTAssertFalse(labels(in: controller.view).contains { $0.text == "Ethan" })
                XCTAssertEqual(controller.session.peerName, "David", "The active call must keep the displayed/announced name")
                XCTAssertNotNil(controller.session.peerContact?.photoData)
                func images(_ view: UIView) -> [UIImageView] { (view as? UIImageView).map { [$0] } ?? view.subviews.flatMap(images) }
                XCTAssertTrue(images(controller.view).contains { $0.accessibilityIdentifier == "recipient.photo" && $0.image != nil })
                if kind == "dropIn" {
                    XCTAssertEqual(audio.name, "David"); XCTAssertEqual(audio.video, mode == .video)
                    XCTAssertEqual(audio.language, .traditionalChinese)
                } else { XCTAssertEqual(audio.ringCount, 1); XCTAssertNil(audio.name) }
                controller.viewWillDisappear(false)
            }
        }
    }
    @MainActor func testChineseBedsideClockAndLargeContactCards() throws {
        let restore = localizedBedside(); defer { restore() }
        let clock = CallViewController(); clock.loadViewIfNeeded()
        clock.view.frame = CGRect(x: 0, y: 0, width: 1032, height: 1376); clock.view.layoutIfNeeded(); clock.viewDidLayoutSubviews()
        XCTAssertEqual(buttons(in: clock.view).first { $0.accessibilityIdentifier == "clock.call" }?.configuration?.title, "打電話")
        XCTAssertTrue(labels(in: clock.view).first { $0.accessibilityIdentifier == "clock.weekday" }?.text?.contains("星期") == true)
        XCTAssertTrue(labels(in: clock.view).first { $0.accessibilityIdentifier == "clock.date" }?.text?.contains("年") == true)
        let time = labels(in: clock.view).first { $0.accessibilityIdentifier == "clock.time" }!.attributedText!
        if let first = time.string.first, !first.isNumber {
            let number = time.string.firstIndex(where: \.isNumber)!
            let numberIndex = time.string.distance(from: time.string.startIndex, to: number)
            XCTAssertLessThan((time.attribute(.font, at: 0, effectiveRange: nil) as! UIFont).pointSize, (time.attribute(.font, at: numberIndex, effectiveRange: nil) as! UIFont).pointSize / 2)
        }
        for _ in 0..<8 { NotificationCenter.default.post(name: .porchBedsideDisplayChanged, object: nil) }
        let repeated = labels(in: clock.view).first { $0.accessibilityIdentifier == "clock.time" }!.attributedText!
        let digit = repeated.string.firstIndex(where: \.isNumber)!
        let digitIndex = (repeated.string as NSString).range(of: String(repeated.string[digit])).location
        XCTAssertGreaterThan((repeated.attribute(.font, at: digitIndex, effectiveRange: nil) as! UIFont).pointSize, 250, "Chinese day-period prefixes must not shrink the clock on each update")
        var slots = CallSlots()
        for digit in CallSlots.digits { try slots.setContact(CallContact(name: digit == 1 ? "家人" : "A relative with a longer name", nativeCall: NativeCall(room: "test", mode: .video)), for: digit) }
        let picker = PeoplePickerViewController(slots: slots); picker.loadViewIfNeeded()
        for size in [CGSize(width: 744, height: 1133), CGSize(width: 1133, height: 744), CGSize(width: 1032, height: 1376)] {
            picker.view.frame = CGRect(origin: .zero, size: size); picker.view.layoutIfNeeded(); picker.viewDidLayoutSubviews(); picker.view.layoutIfNeeded()
            XCTAssertTrue(labels(in: picker.view).contains { $0.text == "您想打給誰？" })
            let people = buttons(in: picker.view).filter { $0.accessibilityIdentifier?.hasPrefix("people.person.") == true }
            XCTAssertEqual(people.count, CallSlots.count)
            XCTAssertEqual(people.compactMap { $0.configuration?.subtitle }.suffix(2), ["按 *", "按 #"])
            for person in people {
                person.layoutIfNeeded()
                XCTAssertNil(person.configuration?.image)
                XCTAssertGreaterThanOrEqual(person.titleLabel?.font.pointSize ?? 0, 44)
                XCTAssertGreaterThanOrEqual(person.bounds.height, 200)
                XCTAssertTrue(person.configuration?.subtitle?.hasPrefix("按 ") == true)
            }
        }
        UserDefaults.standard.set("family", forKey: "porch.experience")
        XCTAssertEqual(BedsideText.string("End call"), "End call", "Family mode keeps its existing language")
    }
    @MainActor func testCaregiverCanChooseAndSaveEveryLanguageWithoutChangingSchedule() {
        let restore = localizedBedside(); defer { restore() }
        var preferences = BedsidePreferences(); preferences.dayStart = 7; preferences.nightStart = 21
        preferences.hemisphere = .southern; preferences.appearance = .dynamic; preferences.save()
        for choice in BedsideLanguage.allCases {
            let settings = BedsideDisplaySettingsViewController(); settings.loadViewIfNeeded()
            let options = buttons(in: settings.view).filter { $0.accessibilityIdentifier?.hasPrefix("bedside.language.") == true }
            XCTAssertEqual(options.count, 5)
            let language = options.first { $0.accessibilityIdentifier == "bedside.language.\(choice.rawValue)" }!
            XCTAssertEqual(language.configuration?.title, choice.displayName)
            language.sendActions(for: .touchUpInside)
            XCTAssertTrue(language.accessibilityTraits.contains(.selected))
            XCTAssertEqual(options.filter { $0.accessibilityTraits.contains(.selected) }.count, 1)
            XCTAssertEqual(BedsidePreferences.load(), preferences, "Selection is only persisted on Save")
            for size in [CGSize(width: 320, height: 568), CGSize(width: 744, height: 1133)] {
                settings.view.frame = CGRect(origin: .zero, size: size); settings.view.layoutIfNeeded()
                for option in options {
                    XCTAssertGreaterThanOrEqual(option.bounds.height, 44)
                    XCTAssertLessThanOrEqual(option.bounds.width, size.width)
                    XCTAssertGreaterThan(option.bounds.width, 0)
                }
            }
            let save = settings.navigationItem.rightBarButtonItem!
            UIApplication.shared.sendAction(save.action!, to: save.target, from: save, for: nil)
            preferences.language = choice
            XCTAssertEqual(BedsidePreferences.load(), preferences)
            let reopened = BedsideDisplaySettingsViewController(); reopened.loadViewIfNeeded()
            XCTAssertTrue(buttons(in: reopened.view).first { $0.accessibilityIdentifier == language.accessibilityIdentifier }!.accessibilityTraits.contains(.selected))
        }
    }
    @MainActor func testAnnouncementVoiceResolverUsesMatchingChoicesAndFallsBackForMissingOrWrongLanguage() {
        for language in BedsideLanguage.allCases {
            let fallback = PorchAnnouncementVoice.resolve(for: language, identifier: nil)
            XCTAssertEqual(PorchAnnouncementVoice.resolve(for: language, identifier: "removed-voice")?.identifier, fallback?.identifier)
            if let fallback { XCTAssertTrue(language.supportsSpeechVoice(language: fallback.language)) }
            for voice in AVSpeechSynthesisVoice.speechVoices() {
                let resolved = PorchAnnouncementVoice.resolve(for: language, identifier: voice.identifier)
                if PorchAnnouncementVoice.isOffered(voice, for: language) {
                    XCTAssertEqual(resolved?.identifier, voice.identifier)
                } else {
                    XCTAssertEqual(resolved?.identifier, fallback?.identifier, "A voice from another language or a hidden voice must never be used")
                }
            }
        }
    }
    @MainActor func testAnnouncementVoicePickerHidesNoveltyAndPersonalVoices() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Voice traits require iOS 17") }
        let hidden: AVSpeechSynthesisVoice.Traits = [.isNoveltyVoice, .isPersonalVoice]
        for language in BedsideLanguage.allCases {
            let fallback = PorchAnnouncementVoice.resolve(for: language, identifier: nil)
            XCTAssertTrue(PorchAnnouncementVoice.available(for: language).allSatisfy { $0.voiceTraits.isDisjoint(with: hidden) })
            for voice in AVSpeechSynthesisVoice.speechVoices() where !voice.voiceTraits.isDisjoint(with: hidden) {
                XCTAssertFalse(PorchAnnouncementVoice.isOffered(voice, for: language), voice.name)
                XCTAssertEqual(PorchAnnouncementVoice.resolve(for: language, identifier: voice.identifier)?.identifier, fallback?.identifier,
                               "A saved \(voice.name) voice must fall back to the default, matching the picker")
            }
            for voice in AVSpeechSynthesisVoice.speechVoices() where voice.voiceTraits.isDisjoint(with: hidden) && language.supportsSpeechVoice(language: voice.language) {
                XCTAssertTrue(PorchAnnouncementVoice.isOffered(voice, for: language), voice.name)
            }
        }
    }
    @MainActor func testVoicePickerFiltersChoicesKeepsDraftsAndRestoresEachLanguage() throws {
        let suite = "voice-picker-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = BedsidePreferences()
        preferences.dayStart = 7; preferences.nightStart = 21
        preferences.save(to: defaults)
        let settings = BedsideDisplaySettingsViewController(defaults: defaults)
        settings.loadViewIfNeeded()
        let picker = try XCTUnwrap(buttons(in: settings.view).first { $0.accessibilityIdentifier == "bedside.announcementVoice" })
        XCTAssertTrue(picker.showsMenuAsPrimaryAction)
        XCTAssertNotNil(buttons(in: settings.view).first { $0.accessibilityIdentifier == "bedside.previewAnnouncement" })
        for language in BedsideLanguage.allCases {
            let choice = try XCTUnwrap(buttons(in: settings.view).first { $0.accessibilityIdentifier == "bedside.language.\(language.rawValue)" })
            choice.sendActions(for: .touchUpInside)
            let voices = PorchAnnouncementVoice.available(for: language)
            let actions = try XCTUnwrap(picker.menu).children.compactMap { $0 as? UIAction }
            XCTAssertEqual(actions.map(\.title), ["System default"] + voices.map(PorchAnnouncementVoice.label))
            XCTAssertEqual(actions.filter { $0.state == .on }.count, 1)
            let identifier = voices.first?.identifier ?? "unavailable-\(language.rawValue)"
            settings.selectAnnouncementVoice(identifier)
            preferences.setAnnouncementVoiceIdentifier(identifier, for: language)
            XCTAssertEqual(picker.accessibilityValue, voices.first.map(PorchAnnouncementVoice.label) ?? "System default")
            XCTAssertTrue(BedsidePreferences.load(from: defaults).announcementVoiceIdentifiers.isEmpty, "Draft choices must not be saved")
        }
        let save = try XCTUnwrap(settings.navigationItem.rightBarButtonItem)
        UIApplication.shared.sendAction(save.action!, to: save.target, from: save, for: nil)
        preferences.language = .spanish
        XCTAssertEqual(BedsidePreferences.load(from: defaults), preferences)
        let reopened = BedsideDisplaySettingsViewController(defaults: defaults)
        reopened.loadViewIfNeeded()
        let reopenedPicker = try XCTUnwrap(buttons(in: reopened.view).first { $0.accessibilityIdentifier == "bedside.announcementVoice" })
        for language in BedsideLanguage.allCases {
            buttons(in: reopened.view).first { $0.accessibilityIdentifier == "bedside.language.\(language.rawValue)" }!.sendActions(for: .touchUpInside)
            XCTAssertEqual(reopenedPicker.accessibilityValue, PorchAnnouncementVoice.available(for: language).first.map(PorchAnnouncementVoice.label) ?? "System default")
            for size in [CGSize(width: 320, height: 568), CGSize(width: 744, height: 1133)] {
                reopened.view.frame = CGRect(origin: .zero, size: size); reopened.view.layoutIfNeeded()
                XCTAssertGreaterThanOrEqual(reopenedPicker.bounds.height, 44)
                XCTAssertLessThanOrEqual(reopenedPicker.bounds.width, size.width)
            }
        }
        reopened.selectAnnouncementVoice(nil)
        XCTAssertEqual(reopenedPicker.accessibilityValue, "System default")
        XCTAssertEqual(BedsidePreferences.load(from: defaults), preferences, "Leaving a draft must preserve the saved choices")
    }
    @MainActor func testVoicePickerOffersTheFamilysNaturalVoicesAboveBuiltInOnes() throws {
        let suite = "natural-voice-picker-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        BedsidePreferences().save(to: defaults)
        let natural = try JSONDecoder().decode(NaturalVoices.self, from: Data("""
            {"languages": {
              "en": {"selected": "hope", "defaultVoice": "hope", "voices": [{"id": "hope", "name": "Hope", "detail": "Natural, clear and calm · female"}, {"id": "jon", "name": "Jon", "detail": "Warm and grounded · male"}]},
              "es": {"selected": null, "defaultVoice": "eva", "voices": [{"id": "eva", "name": "Eva Dorado", "detail": "Warm and soft · female"}]}
            }}
            """.utf8))
        let settings = BedsideDisplaySettingsViewController(defaults: defaults, naturalVoices: { natural })
        settings.loadViewIfNeeded()
        let picker = try XCTUnwrap(buttons(in: settings.view).first { $0.accessibilityIdentifier == "bedside.announcementVoice" })
        XCTAssertEqual(picker.accessibilityValue, "Hope · Natural")
        let sections = try XCTUnwrap(picker.menu).children.compactMap { $0 as? UIMenu }
        XCTAssertEqual(sections.map(\.title), ["Natural voices", "Built-in voices on this iPad"])
        let naturals = sections[0].children.compactMap { $0 as? UIAction }
        XCTAssertEqual(naturals.map(\.title), ["Hope · Natural, clear and calm · female", "Jon · Warm and grounded · male"])
        XCTAssertEqual(naturals.filter { $0.state == .on }.map(\.title), [naturals[0].title])
        XCTAssertTrue(sections[1].children.compactMap { $0 as? UIAction }.allSatisfy { $0.state == .off }, "The built-in voice is only the fallback")
        settings.selectNaturalVoice("jon")
        XCTAssertEqual(picker.accessibilityValue, "Jon · Natural")
        settings.selectAnnouncementVoice(nil)
        XCTAssertEqual(picker.accessibilityValue, "System default")
        // This family keeps the built-in voice for Spanish.
        try XCTUnwrap(buttons(in: settings.view).first { $0.accessibilityIdentifier == "bedside.language.es" }).sendActions(for: .touchUpInside)
        XCTAssertFalse(picker.accessibilityValue?.hasSuffix("· Natural") ?? false)
        XCTAssertEqual(try XCTUnwrap(picker.menu).children.compactMap { $0 as? UIMenu }.count, 2)
        // A language without natural voices keeps the plain list.
        try XCTUnwrap(buttons(in: settings.view).first { $0.accessibilityIdentifier == "bedside.language.yue-Hant" }).sendActions(for: .touchUpInside)
        XCTAssertTrue(try XCTUnwrap(picker.menu).children.allSatisfy { $0 is UIAction })
        XCTAssertTrue(BedsidePreferences.load(from: defaults).announcementVoiceIdentifiers.isEmpty, "Draft choices must not be saved")
    }
    @MainActor func testNaturalClipDeadlineDoesNotWaitForASlowDownload() async {
        let slow = Task<URL?, Never> { try? await Task.sleep(nanoseconds: 3_000_000_000); return URL(fileURLWithPath: "/late.mp3") }
        let started = Date()
        let result = await PorchNaturalVoice.first(of: slow, within: 0.2)
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "The built-in voice must not wait for the download")
        let quick = Task<URL?, Never> { URL(fileURLWithPath: "/ready.mp3") }
        let ready = await PorchNaturalVoice.first(of: quick, within: 5)
        XCTAssertEqual(ready?.path, "/ready.mp3")
        slow.cancel()
    }
    @MainActor func testNewLanguagesReachClockContactsIncomingCallsAndAnnouncements() throws {
        for language in [BedsideLanguage.simplifiedChinese, .cantonese, .spanish] {
            let restore = localizedBedside(language); defer { restore() }
            let clock = CallViewController(); clock.loadViewIfNeeded()
            XCTAssertEqual(buttons(in: clock.view).first { $0.accessibilityIdentifier == "clock.call" }?.configuration?.title, language.text("Call someone"))
            XCTAssertEqual(BedsideText.error("An unexpected server error"), language.text("Please ask your caregiver for help, then try again."))
            var slots = CallSlots()
            try slots.setContact(CallContact(name: "María 陳", nativeCall: NativeCall(room: "test", mode: .video)), for: 1)
            let picker = PeoplePickerViewController(slots: slots); picker.loadViewIfNeeded()
            for size in [CGSize(width: 744, height: 1133), CGSize(width: 1133, height: 744)] {
                picker.view.frame = CGRect(origin: .zero, size: size); picker.view.layoutIfNeeded(); picker.viewDidLayoutSubviews(); picker.view.layoutIfNeeded()
                XCTAssertTrue(labels(in: picker.view).contains { $0.text == language.text("Who would you like to call?") })
                let person = buttons(in: picker.view).first { $0.accessibilityIdentifier == "people.person.1" }!
                XCTAssertEqual(person.configuration?.title, "María 陳")
                XCTAssertEqual(person.configuration?.subtitle, language.format("Press %@", arguments: ["1"]))
                XCTAssertEqual(person.accessibilityLanguage, language.speechLanguage)
            }
            for mode in [NativeCall.Mode.voice, .video] {
                let audio = TestIncomingAudio()
                let controller = try incoming("dropIn", mode: mode, callerName: "María 陳", audio: audio)
                controller.loadViewIfNeeded(); controller.viewDidAppear(false)
                XCTAssertEqual(audio.language, language); XCTAssertEqual(audio.name, "María 陳")
                XCTAssertEqual(audio.video, mode == .video)
                XCTAssertTrue(labels(in: controller.view).contains { $0.text == language.text(mode == .video ? "Announcing video drop-in…" : "Announcing audio drop-in…") })
                XCTAssertTrue(buttons(in: controller.view).contains { $0.configuration?.title == language.text("Don't connect") })
                controller.viewWillDisappear(false)
            }
            UserDefaults.standard.set("family", forKey: "porch.experience")
            XCTAssertEqual(BedsideText.string("End call"), "End call")
        }
    }
    @MainActor func testInboundTelephoneCallRingsWithManualAudioAnswerAndNeverStartsDropInCountdown() throws {
        let restore = localizedBedside(.english); defer { restore() }
        let audio = TestIncomingAudio()
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "from": "sip:PA_caller", "to": "bedside", "mode": "voice", "kind": "call",
            "source": "phone", "state": "pending", "createdAt": 1, "expiresAt": 46, "callerName": "+14155550123",
        ])
        let call = try JSONDecoder().decode(FamilyCallRecord.self, from: data)
        let controller = IncomingFamilyCallViewController(call: call,
            credential: FamilyCredential(origin: URL(string: "https://example.invalid")!, credential: "test", role: .bedside), audio: audio)
        var answered = false
        controller.onAnswer = { _ in answered = true }
        controller.loadViewIfNeeded(); controller.viewDidAppear(false)
        for _ in 0..<50 { controller.advanceCountdown() }
        XCTAssertEqual(audio.ringCount, 1)
        XCTAssertNil(audio.completion, "Telephone caller ID must never trigger a drop-in announcement")
        XCTAssertFalse(answered)
        XCTAssertTrue(labels(in: controller.view).contains { $0.text == "+14155550123" })
        XCTAssertTrue(buttons(in: controller.view).contains { $0.configuration?.title == "Answer audio call" && !$0.isHidden })
        XCTAssertFalse(buttons(in: controller.view).contains { $0.configuration?.title == "Answer video call" })
        controller.viewWillDisappear(false)
        XCTAssertGreaterThan(audio.stopCount, 0)
    }

    @MainActor func testIncomingRingingRepeatsUntilTheScreenLeavesAndUsesChineseControls() throws {
        let restore = localizedBedside(); defer { restore() }
        let audio = TestIncomingAudio()
        let ringing = try incoming("call", audio: audio)
        ringing.loadViewIfNeeded(); ringing.viewDidAppear(false); ringing.viewDidAppear(false)
        XCTAssertEqual(audio.ringCount, 1)
        XCTAssertTrue(buttons(in: ringing.view).contains { $0.configuration?.title == "接聽視訊" })
        XCTAssertTrue(buttons(in: ringing.view).contains { $0.configuration?.title == "拒接" })
        ringing.viewWillDisappear(false); XCTAssertGreaterThan(audio.stopCount, 0)
    }
    @MainActor func testDropInWaitsForAnnouncementBeforeCountingDownAndStopsOnLeaving() throws {
        let restore = localizedBedside(); defer { restore() }
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!), audio = TestIncomingAudio()
        let controller = try incoming("dropIn", audio: audio)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { controller.viewWillDisappear(false); window.isHidden = true; original.makeKeyAndVisible() }
        controller.viewDidAppear(false)
        XCTAssertEqual(audio.language, .traditionalChinese); XCTAssertEqual(audio.video, true)
        for _ in 0..<6 { controller.advanceCountdown() }
        XCTAssertTrue(labels(in: controller.view).contains { $0.text == "正在提示視訊自動接聽…" })
        audio.completion?(true)
        XCTAssertTrue(labels(in: controller.view).contains { $0.text == "視訊自動接聽\n5 秒後接通…" })
        controller.advanceCountdown()
        XCTAssertTrue(labels(in: controller.view).contains { $0.text == "視訊自動接聽\n4 秒後接通…" })
        controller.viewWillDisappear(false); XCTAssertGreaterThan(audio.stopCount, 0)
    }
    @MainActor func testFailedAnnouncementRequiresManualAnswerInsteadOfStartingSilentVideo() throws {
        let restore = localizedBedside(); defer { restore() }
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!), audio = TestIncomingAudio()
        let controller = try incoming("dropIn", audio: audio)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { controller.viewWillDisappear(false); window.isHidden = true; original.makeKeyAndVisible() }
        controller.viewDidAppear(false); audio.completion?(false)
        for _ in 0..<6 { controller.advanceCountdown() }
        XCTAssertTrue(labels(in: controller.view).contains { $0.text == "無法播放提示音，請按接聽以接通。" })
        XCTAssertTrue(buttons(in: controller.view).contains { $0.configuration?.title == "接聽視訊" && !$0.isHidden })
        XCTAssertTrue(labels(in: controller.view).contains { $0.text?.contains("接聽，長按") == true })
    }
    @MainActor func testOutgoingCallSaysWhoItIsCallingAndWhatFollowsWaitsForTheSentence() async {
        let restore = localizedBedside(.spanish); defer { restore() }
        let audio = TestCallSpeaker()
        let announcement = OutgoingCallAnnouncement(calling: "María 陳", audio: audio)
        XCTAssertEqual(audio.message, "Llamando a María 陳."); XCTAssertEqual(audio.language, .spanish)
        var followed = 0
        announcement.then { followed += 1 }
        XCTAssertEqual(followed, 0, "Ringing and the message prompt must not talk over the name")
        audio.completion?(true)
        XCTAssertTrue(announcement.isFinished); XCTAssertEqual(followed, 1)
        announcement.then { followed += 1 }
        await announcement.finished()
        XCTAssertEqual(followed, 2, "Once it has been said, nothing waits")
        // A voice that couldn't speak never holds up the call.
        let unspoken = OutgoingCallAnnouncement(calling: "María 陳", audio: audio)
        audio.completion?(false)
        XCTAssertTrue(unspoken.isFinished)
        // Hanging up while the call is still opening silences it, and what was waiting goes on.
        let stopped = OutgoingCallAnnouncement(calling: "María 陳", audio: audio)
        var resumed = false
        stopped.then { resumed = true }
        stopped.stop()
        XCTAssertTrue(resumed); XCTAssertEqual(audio.stopCount, 1)
    }
    @MainActor func testOutgoingCallThatCannotSpeakDoesNotHoldUpWhatFollows() {
        // No installed voice, a failed chime, or the silent simulator finishes before init returns.
        let announcement = OutgoingCallAnnouncement(calling: "David", audio: ImmediateCallSpeaker())
        XCTAssertTrue(announcement.isFinished, "Speech that ends while the announcement is created must not leave ringback waiting")
        var followed = false
        announcement.then { followed = true }
        XCTAssertTrue(followed)
    }
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
            let attributed = time.attributedText!
            let digit = attributed.string.first(where: \.isNumber)!
            let digitIndex = (attributed.string as NSString).range(of: String(digit)).location
            XCTAssertGreaterThan((attributed.attribute(.font, at: digitIndex, effectiveRange: nil) as! UIFont).pointSize, 200)
            XCTAssertGreaterThan(time.bounds.width, size.width * 0.85)
            XCTAssertGreaterThanOrEqual(weekday.convert(weekday.bounds, to: clock.view).minY, 0)
            XCTAssertLessThan(date.convert(date.bounds, to: clock.view).maxY, button.frame.minY)
        }
    }

    @MainActor func testPhoneGuestKeypadSendsSIPCodesInOrderAndTheFormDialsANorthAmericanNumber() async throws {
        final class Sent { var keys: [(UInt32, String)] = []; var calls: [(String, String)] = [] }
        let sent = Sent()
        let keypad = PhoneKeypadViewController(name: "Bank") { code, digit in sent.keys.append((code, digit)) }
        let navigation = UINavigationController(rootViewController: keypad)
        for size in [CGSize(width: 375, height: 667), CGSize(width: 1032, height: 1376)] {
            navigation.view.frame = CGRect(origin: .zero, size: size); navigation.view.layoutIfNeeded()
            let keys = buttons(in: keypad.view).filter { $0.accessibilityIdentifier?.hasPrefix("phoneGuest.key.") == true }
            XCTAssertEqual(keys.count, 12)
            for key in keys {
                XCTAssertGreaterThanOrEqual(key.bounds.height, 44, "\(size)")
                XCTAssertTrue(keypad.view.bounds.contains(key.convert(key.bounds, to: keypad.view)), "\(size)")
            }
        }
        for key in ["1", "*", "0", "#"] {
            buttons(in: keypad.view).first { $0.accessibilityIdentifier == "phoneGuest.key.\(key)" }?.sendActions(for: .touchUpInside)
        }
        for _ in 0..<100 where sent.keys.count < 4 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(sent.keys.map(\.0), [1, 10, 0, 11])
        XCTAssertEqual(sent.keys.map(\.1), ["1", "*", "0", "#"])

        let form = AddPhoneGuestViewController { label, number in sent.calls.append((label, number)) }
        let formNavigation = UINavigationController(rootViewController: form)
        formNavigation.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667); formNavigation.view.layoutIfNeeded()
        func textField(_ id: String, in view: UIView) -> UITextField? {
            (view as? UITextField).flatMap { $0.accessibilityIdentifier == id ? $0 : nil } ?? view.subviews.lazy.compactMap { textField(id, in: $0) }.first
        }
        try XCTUnwrap(textField("phoneGuest.name", in: form.view)).text = "  Bank "
        try XCTUnwrap(textField("phoneGuest.number", in: form.view)).text = "(800) 555-0123"
        try XCTUnwrap(buttons(in: form.view).first { $0.configuration?.title == "Call and add to this call" }).sendActions(for: .touchUpInside)
        for _ in 0..<100 where sent.calls.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(sent.calls.first?.0, "Bank")
        XCTAssertEqual(sent.calls.first?.1, "+18005550123")
    }

    @MainActor func testTwoPeopleShareTheCallScreenSideBySideWhenWideAndStackedWhenTall() throws {
        let stage = CallVideoStage()
        func labels(_ text: String, in view: UIView) -> [UILabel] {
            ((view as? UILabel)?.text == text ? [view as! UILabel] : []) + view.subviews.flatMap { labels(text, in: $0) }
        }
        func visible(_ view: UIView) -> Bool { sequence(first: view, next: \.superview).allSatisfy { !$0.isHidden } }
        stage.show([CallVideoStage.Tile(name: "Mom", track: nil)])
        XCTAssertFalse(stage.isSplit)
        XCTAssertFalse(labels("Mom", in: stage).contains(where: visible), "with one person, the call screen shows its own photo and name")

        stage.show([CallVideoStage.Tile(name: "Mom", track: nil, photo: UIImage(data: portraitData())), CallVideoStage.Tile(name: "David", track: nil)])
        XCTAssertTrue(stage.isSplit)
        for (size, sideBySide) in [(CGSize(width: 1032, height: 768), true), (CGSize(width: 390, height: 844), false)] {
            stage.frame = CGRect(origin: .zero, size: size); stage.setNeedsLayout(); stage.layoutIfNeeded()
            let mom = try XCTUnwrap(labels("Mom", in: stage).first(where: visible)), david = try XCTUnwrap(labels("David", in: stage).first(where: visible))
            let momFrame = mom.convert(mom.bounds, to: stage), davidFrame = david.convert(david.bounds, to: stage)
            XCTAssertTrue(stage.bounds.contains(momFrame) && stage.bounds.contains(davidFrame), "\(size)")
            if sideBySide { XCTAssertLessThan(momFrame.maxX, size.width / 2); XCTAssertGreaterThan(davidFrame.minX, size.width / 2) }
            else { XCTAssertLessThan(momFrame.maxY, size.height / 2); XCTAssertGreaterThan(davidFrame.minY, size.height / 2) }
        }
        stage.show([])
        XCTAssertFalse(stage.isSplit)
        XCTAssertFalse(labels("David", in: stage).contains(where: visible))
    }

    @MainActor private func buttons(in view: UIView) -> [UIButton] {
        (view as? UIButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    @MainActor private func rows(in view: UIView) -> [PorchListRow] {
        (view as? PorchListRow).map { [$0] } ?? view.subviews.flatMap { rows(in: $0) }
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

    @MainActor func testConnectingAKeypadDoesNotReplaceTheNativeKeyboard() {
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!)
        let form = CaregiverFormViewController()
        window.rootViewController = form; window.makeKeyAndVisible()
        defer { form.view.endEditing(true); window.isHidden = true; original.makeKeyAndVisible() }
        let name = UITextField(), pin = UITextField(); pin.keyboardType = .numberPad
        form.form.addArrangedSubview(form.field(name, title: "Name", placeholder: "Name"))
        form.form.addArrangedSubview(form.field(pin, title: "PIN", placeholder: "Six digits"))
        XCTAssertTrue(name.becomeFirstResponder())
        XCTAssertNil(name.inputView)
        XCTAssertFalse(name.inputAssistantItem.allowsHidingShortcuts)
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        XCTAssertNil(name.inputView, "Connecting a keypad must not suppress the system keyboard")
        XCTAssertNil(pin.inputView, "Other fields must keep the native keyboard too")
        XCTAssertTrue(name.isFirstResponder)
        name.insertText("Pat")
        XCTAssertEqual(name.text, "Pat")
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
        XCTAssertNil(name.inputView)
    }

    @MainActor func testPorchKeyboardIsOptInAndSwitchingBackRestoresEveryField() {
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!)
        let form = CaregiverFormViewController()
        window.rootViewController = form; window.makeKeyAndVisible()
        defer { form.view.endEditing(true); window.isHidden = true; original.makeKeyAndVisible() }
        let name = UITextField(), phone = UITextField(); phone.keyboardType = .phonePad
        form.form.addArrangedSubview(form.field(name, title: "Name", placeholder: "Name"))
        form.form.addArrangedSubview(form.field(phone, title: "Phone", placeholder: "Phone"))
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
        XCTAssertTrue(name.becomeFirstResponder()); name.insertText("Pat")
        buttons(in: form.view).first { $0.accessibilityIdentifier == "caregiver.porchKeyboard" }!.sendActions(for: .touchUpInside)
        XCTAssertNotNil(name.inputView); XCTAssertNotNil(phone.inputView)
        let keyboard = form.view.subviews.flatMap { descendants($0) }.first { $0.accessibilityIdentifier == "caregiver.touchKeyboard" }!
        XCTAssertFalse(keyboard.isHidden)
        buttons(in: keyboard).first { $0.title(for: .normal) == "m" }!.sendActions(for: .touchUpInside)
        XCTAssertEqual(name.text, "Patm")
        buttons(in: keyboard).first { $0.accessibilityIdentifier == "caregiver.touchKeyboard.useNative" }!.sendActions(for: .touchUpInside)
        XCTAssertNil(name.inputView); XCTAssertNil(phone.inputView)
        XCTAssertTrue(keyboard.isHidden); XCTAssertTrue(name.isFirstResponder)
        XCTAssertEqual(name.text, "Patm", "Changing keyboards must preserve the text and selection")
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        XCTAssertNil(name.inputView)
        _ = form.textFieldShouldReturn(name)
        XCTAssertTrue(phone.isFirstResponder); XCTAssertNil(phone.inputView)
        phone.insertText("+1415"); XCTAssertEqual(phone.text, "+1415")
        form.setKeyboardControlVisible(false); form.view.endEditing(true)
        XCTAssertTrue(descendants(form.view).first { $0.accessibilityIdentifier == "caregiver.keyboardOptions" }!.isHidden)
    }

    @MainActor func testRequestingNativeKeyboardFocusesAnEditableFieldAndPreservesAssistant() {
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!)
        let form = CaregiverFormViewController()
        window.rootViewController = form; window.makeKeyAndVisible()
        defer { form.view.endEditing(true); window.isHidden = true; original.makeKeyAndVisible() }
        let hidden = UITextField(), disabled = UITextField(), detached = UITextField(), editable = UITextField()
        let hiddenGroup = form.field(hidden, title: "Hidden", placeholder: "Hidden"); hiddenGroup.isHidden = true
        form.form.addArrangedSubview(hiddenGroup)
        disabled.isEnabled = false; form.form.addArrangedSubview(form.field(disabled, title: "Disabled", placeholder: "Disabled"))
        _ = form.field(detached, title: "Detached", placeholder: "Detached")
        let item = UIBarButtonItem(title: "Test shortcut", style: .plain, target: nil, action: nil)
        let group = UIBarButtonItemGroup(barButtonItems: [item], representativeItem: nil)
        editable.inputAssistantItem.leadingBarButtonGroups = [group]
        form.form.addArrangedSubview(form.field(editable, title: "Name", placeholder: "Name"))
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
        XCTAssertEqual(editable.inputAssistantItem.leadingBarButtonGroups.count, 1)
        buttons(in: form.view).first { $0.accessibilityIdentifier == "caregiver.nativeKeyboard" }!.sendActions(for: .touchUpInside)
        XCTAssertTrue(editable.isFirstResponder); XCTAssertNil(editable.inputView)
        XCTAssertFalse(hidden.isFirstResponder); XCTAssertFalse(disabled.isFirstResponder); XCTAssertFalse(detached.isFirstResponder)
    }

    @MainActor func testKeyboardButtonExplainsHardwareSuppressionInsteadOfSilentlyRetrying() async {
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!)
        let form = CaregiverFormViewController()
        window.rootViewController = form; window.makeKeyAndVisible()
        defer { form.view.endEditing(true); window.isHidden = true; original.makeKeyAndVisible() }
        let name = UITextField()
        form.form.addArrangedSubview(form.field(name, title: "Name", placeholder: "Name"))
        XCTAssertTrue(name.becomeFirstResponder()); name.insertText("Pat")
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        let button = buttons(in: form.view).first { $0.accessibilityIdentifier == "caregiver.nativeKeyboard" }!
        XCTAssertEqual(button.configuration?.title, "Keyboard help")
        button.sendActions(for: .touchUpInside)
        let help = try! XCTUnwrap(form.presentedViewController as? UIAlertController)
        XCTAssertTrue(help.message?.contains("disconnect the keypad during setup") == true)
        XCTAssertTrue(help.message?.contains("cannot force the native keyboard open") == true)
        XCTAssertTrue(help.message?.contains("Software Keyboards") == true)
        XCTAssertFalse(help.message?.contains("bottom bar") == true, "A missing system bar cannot be the only recovery path")
        XCTAssertTrue(help.actions.contains { $0.title == "Use Porch keyboard" })
        XCTAssertNil(name.inputView, "Help must not silently replace the chosen native input")
        XCTAssertEqual(name.text, "Pat")
        await withCheckedContinuation { continuation in help.dismiss(animated: false) { continuation.resume() } }
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
        XCTAssertEqual(button.configuration?.title, UIDevice.current.userInterfaceIdiom == .phone ? "iPhone keyboard" : "iPad keyboard")
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(name.isFirstResponder); XCTAssertNil(name.inputView)
    }

    @MainActor func testNativeKeyboardHelpDoesNotDiscardThePorchKeyboardChoice() async {
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!)
        let form = CaregiverFormViewController()
        window.rootViewController = form; window.makeKeyAndVisible()
        defer { form.view.endEditing(true); window.isHidden = true; original.makeKeyAndVisible() }
        let pin = UITextField(); pin.keyboardType = .numberPad; pin.isSecureTextEntry = true
        form.form.addArrangedSubview(form.field(pin, title: "PIN", placeholder: "PIN"))
        XCTAssertTrue(pin.becomeFirstResponder()); pin.insertText("012345")
        buttons(in: form.view).first { $0.accessibilityIdentifier == "caregiver.porchKeyboard" }!.sendActions(for: .touchUpInside)
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        let system = buttons(in: form.view).first { $0.accessibilityIdentifier == "caregiver.touchKeyboard.useNative" }!
        XCTAssertEqual(system.title(for: .normal), "Keyboard help")
        system.sendActions(for: .touchUpInside)
        let help = try! XCTUnwrap(form.presentedViewController as? UIAlertController)
        XCTAssertNotNil(pin.inputView, "Opening help must keep the working touch keyboard selected")
        XCTAssertEqual(pin.text, "012345")
        await withCheckedContinuation { continuation in help.dismiss(animated: false) { continuation.resume() } }
        XCTAssertTrue(pin.becomeFirstResponder())
        let keyboard = descendants(form.view).first { $0.accessibilityIdentifier == "caregiver.touchKeyboard" }!
        XCTAssertFalse(keyboard.isHidden)
        buttons(in: keyboard).first { $0.title(for: .normal) == "6" }!.sendActions(for: .touchUpInside)
        XCTAssertEqual(pin.text, "0123456")
    }

    @MainActor private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }

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


    @MainActor func testContactEditorWithOtherNumbersKeepsFullWidthAndControlsAtTheirSize() throws {
        let person = try CallContact(name: "David", nativeCall: NativeCall(room: "family-david", mode: .voice), phoneNumber: "+14155550123", otherPhoneNumbers: ["+14155550199"])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        func all(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(all) }
        for size in [CGSize(width: 834, height: 1210), CGSize(width: 1210, height: 834), CGSize(width: 402, height: 874)] {
            let editor = SetupViewController(slot: 1, contact: person)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = PorchStyle.navigation(editor)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            // Drop-in by phone shows only on a paired bedside.
            for view in all(editor.view) where view.isHidden && all(view).contains(where: { $0.accessibilityLabel == "Audio drop-in when they call this Porch" }) { view.isHidden = false }
            window.layoutIfNeeded()
            XCTAssertEqual(editor.form.bounds.width, min(760, size.width - 48), "The other numbers must not squeeze the form at \(size)")
            let controls = all(editor.form).filter { $0 is UISwitch || ["Make primary", "Remove"].contains(($0 as? UIButton)?.configuration?.title) }
            XCTAssertEqual(controls.count, 4)
            // Converting between views leaves rounding noise (143.66666666666663 against 143.66666666666666);
            // a squeezed control is short by whole points.
            let tolerance: CGFloat = 0.5
            for control in controls {
                let frame = control.convert(control.bounds, to: editor.form)
                XCTAssertGreaterThanOrEqual(frame.width, control.intrinsicContentSize.width - tolerance, "\(control.accessibilityLabel ?? "") is squeezed at \(size)")
                XCTAssertGreaterThanOrEqual(frame.minX, -tolerance)
                XCTAssertLessThanOrEqual(frame.maxX, editor.form.bounds.width + tolerance, "\(control.accessibilityLabel ?? "") leaves its card at \(size)")
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
        XCTAssertTrue(text.contains("Primary number"))
        XCTAssertTrue(text.contains("Other numbers"))
        for obsolete in ["Call using", "Porch room", "Porch call", "FaceTime", "Shortcut"] { XCTAssertFalse(text.contains(obsolete)) }
        let settings = SlotsViewController(slots: CallSlots())
        settings.loadViewIfNeeded()
        let headings = (0..<settings.numberOfSections(in: settings.tableView)).compactMap { settings.tableView(settings.tableView, titleForHeaderInSection: $0) }
        XCTAssertEqual(headings, ["Keypad · people & controls", "Settings", "Device mode", "About"])
    }

    @MainActor func testCaregiverMenuOpensPrivacyPolicy() throws {
        let slots = SlotsViewController(slots: CallSlots())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = slots; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let path = IndexPath(row: 0, section: 3)
        let cell = slots.tableView(slots.tableView, cellForRowAt: path)
        XCTAssertEqual((cell.contentConfiguration as? UIListContentConfiguration)?.text, "Privacy policy")
        slots.tableView(slots.tableView, didSelectRowAt: path)
        XCTAssertTrue(slots.presentedViewController is SFSafariViewController)
        XCTAssertEqual(privacyPolicyURL.absoluteString, "https://helloporch.store/privacy")
    }

    @MainActor func testCaregiverPINScreenLinksPrivacyPolicy() {
        let setup = CaregiverPINViewController(profile: nil)
        setup.loadViewIfNeeded()
        func find(_ view: UIView) -> UIButton? {
            if view.accessibilityIdentifier == "caregiver.privacy" { return view as? UIButton }
            return view.subviews.compactMap(find).first
        }
        XCTAssertEqual(find(setup.view)?.configuration?.title, "Privacy policy")
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

    @MainActor func testEveryKeypadActionHasAnEditorChoice() {
        let editor = SetupViewController(slot: 8, contact: nil, action: .messages); editor.loadViewIfNeeded()
        func segments(_ view: UIView) -> [UISegmentedControl] { (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap(segments) }
        let control = segments(editor.view).first { $0.accessibilityLabel == "Keypad action" }
        XCTAssertEqual(control?.numberOfSegments, KeypadAction.allCases.count)
        XCTAssertEqual(control?.selectedSegmentIndex, KeypadAction.allCases.firstIndex(of: .messages))
    }

    @MainActor func testUnenrolledBedsideSetupOffersTheWayBackToFamilyMode() {
        let setup = CaregiverPINViewController(profile: nil); setup.loadViewIfNeeded()
        XCTAssertTrue(buttons(in: setup.view).contains { $0.configuration?.title == "Use this device as a family member" })
    }

    @MainActor func testRemoteCaregiverModeShowsOnlyServerSettingsAndProtectsThisPhone() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": true, "people": [
            ["id": "me", "name": "Ethan", "role": "family", "permissions": ["audio": true, "video": false], "online": true, "caregiver": true],
            ["id": "sam", "name": "Sam", "role": "family", "permissions": ["audio": false, "video": false], "online": false, "caregiver": false]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        XCTAssertFalse(rows(in: admin.view).contains { $0.accessibilityLabel == "Change caregiver PIN" }, "The bedside iPad keeps the PIN it uses for renewals")
        XCTAssertEqual(rows(in: admin.view).filter { $0.accessibilityIdentifier?.hasPrefix("family.person.") == true }.count, 2)
        XCTAssertTrue(rows(in: admin.view).contains { $0.accessibilityLabel == "Ethan (this phone). Porch is open. Audio drop-in · Caregiver." })
        XCTAssertTrue(rows(in: admin.view).contains { $0.accessibilityLabel == "Sam. Offline. Calls only." })
        func switches(_ view: UIView) -> [UISwitch] { (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches) }
        XCTAssertFalse(switches(admin.view).contains { $0.accessibilityIdentifier == "messages.autoplay" }, "Starting messages by camera is set on the bedside iPad itself")
        let me = FamilyPersonViewController(personID: "me", admin: admin); me.loadViewIfNeeded()
        XCTAssertFalse(buttons(in: me.view).contains { $0.configuration?.title == "Remove access" }, "A caregiver can't remove their own phone here")
        XCTAssertEqual(switches(me.view).filter { !$0.isEnabled }.map(\.accessibilityLabel), ["Caregiver mode"], "Another caregiver must change this phone's caregiver access")
        let sam = FamilyPersonViewController(personID: "sam", admin: admin); sam.loadViewIfNeeded()
        XCTAssertEqual(buttons(in: sam.view).filter { $0.configuration?.title == "Remove access" }.count, 1)
        XCTAssertEqual(switches(sam.view).filter { !$0.isEnabled }.map(\.accessibilityLabel), ["Drop in when they call"], "Calls drop in only as a drop-in they're approved for")
    }

    @MainActor func testCaregiverModeSetsWhoseOrdinaryCallsDropIn() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": true, "people": [
            ["id": "mia", "name": "Mia", "role": "family", "permissions": ["audio": true, "video": true], "online": true, "caregiver": false, "autoDropIn": true],
            ["id": "ana", "name": "Ana", "role": "family", "permissions": ["audio": true, "video": false], "online": true, "caregiver": false, "autoDropIn": false]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        XCTAssertTrue(rows(in: admin.view).contains { $0.accessibilityLabel == "Mia, Porch app, Audio and video · Calls drop in" })
        XCTAssertTrue(rows(in: admin.view).contains { $0.accessibilityLabel == "Mia. Porch is open. Audio and video drop-in · Calls drop in." })
        XCTAssertTrue(rows(in: admin.view).contains { $0.accessibilityLabel == "Ana, Porch app, Audio" })
        func switches(_ view: UIView) -> [UISwitch] { (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches) }
        func labels(_ view: UIView) -> [String] { (view as? UILabel).flatMap { $0.text }.map { [$0] } ?? view.subviews.flatMap(labels) }
        let mia = FamilyPersonViewController(personID: "mia", admin: admin); mia.loadViewIfNeeded()
        let calls = try XCTUnwrap(switches(mia.view).first { $0.accessibilityIdentifier == "person.autoDropIn" })
        XCTAssertTrue(calls.isOn); XCTAssertTrue(calls.isEnabled)
        XCTAssertTrue(labels(mia.view).contains("Their audio and video calls drop in too."))
        let ana = FamilyPersonViewController(personID: "ana", admin: admin); ana.loadViewIfNeeded()
        XCTAssertEqual(switches(ana.view).first { $0.accessibilityIdentifier == "person.autoDropIn" }?.isOn, false)
        XCTAssertTrue(labels(ana.view).contains("Their audio calls drop in too. Video calls ring."))
        let kept = try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": true, "people": [
            ["id": "noa", "name": "Noa", "role": "family", "permissions": ["audio": false, "video": false], "online": true, "caregiver": false, "autoDropIn": true]]]))
        let keptAdmin = FamilyAdminViewController(remote: remote, state: kept); keptAdmin.loadViewIfNeeded()
        let noa = FamilyPersonViewController(personID: "noa", admin: keptAdmin); noa.loadViewIfNeeded()
        let saved = try XCTUnwrap(switches(noa.view).first { $0.accessibilityIdentifier == "person.autoDropIn" })
        XCTAssertTrue(saved.isOn)
        XCTAssertTrue(saved.isEnabled, "A saved choice can be turned off after drop-in approval is removed")
        XCTAssertTrue(labels(noa.view).contains("Saved. It applies once audio or video drop-in is on."))
    }

    @MainActor func testCaregiverModeListsPhoneNumbersApprovedForDropIn() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": true, "people": [
            ["id": "mia", "name": "Mia", "role": "family", "permissions": ["audio": true, "video": true], "online": true, "caregiver": false]],
            "phoneDropIns": [["number": "+14155550200", "name": "David"]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        func labels(_ view: UIView) -> [String] { (view as? UILabel).flatMap { $0.text }.map { [$0] } ?? view.subviews.flatMap(labels) }
        XCTAssertTrue(labels(admin.view).contains("+14155550200 · Phone call, audio"))
        XCTAssertTrue(rows(in: admin.view).contains { $0.accessibilityLabel == "Mia, Porch app, Audio and video" }, "Approved family members are listed beside approved numbers")
        let titles = buttons(in: admin.view).compactMap { $0.configuration?.title }
        XCTAssertTrue(titles.contains("Approve a phone number"))
        XCTAssertEqual(buttons(in: admin.view).filter { $0.accessibilityLabel == "Remove phone drop-in for David" }.count, 1)
    }

    @MainActor func testCaregiverModeBlocksUnknownCallersAndListsBlockedNumbersSeparately() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": false, "people": [],
            "callScreening": ["enabled": true, "keypadNumbers": ["+14155550100"],
                "allowed": [["number": "+14155550300", "allowedAt": 1_800_000_000]],
                "blocked": [["number": "+14155550999", "firstCallAt": 1_800_000_000, "lastCallAt": 1_800_000_060, "calls": 2]]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state)
        let navigation = UINavigationController(rootViewController: admin); admin.loadViewIfNeeded()
        func switches(_ view: UIView) -> [UISwitch] { (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches) }
        let block = try XCTUnwrap(switches(admin.view).first { $0.accessibilityIdentifier == "calls.blockUnknown" })
        XCTAssertTrue(block.isOn); XCTAssertTrue(block.isEnabled)
        let list = try XCTUnwrap(rows(in: admin.view).first { $0.accessibilityIdentifier == "calls.blockedNumbers" })
        XCTAssertEqual(list.accessibilityLabel, "Blocked numbers, 1")
        list.sendActions(for: .touchUpInside)
        let blocked = try XCTUnwrap(navigation.topViewController as? BlockedCallersViewController)
        blocked.loadViewIfNeeded()
        let labels = buttons(in: blocked.view).compactMap(\.accessibilityLabel)
        XCTAssertEqual(labels.filter { $0.hasPrefix("Allow ") }.count, 1)
        XCTAssertEqual(labels.filter { $0.hasPrefix("Remove ") && $0.hasSuffix(" from allowed numbers") }.count, 1)
        XCTAssertTrue(buttons(in: blocked.view).contains { $0.configuration?.title == "Clear this list" })
        // A server without call screening can't turn it on.
        let older = FamilyAdminViewController(remote: remote, state: try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": false, "people": []])))
        older.loadViewIfNeeded()
        XCTAssertEqual(switches(older.view).first { $0.accessibilityIdentifier == "calls.blockUnknown" }?.isEnabled, false)
    }

    @MainActor func testPendingInvitationsAreListedByNameAndCancelledOneAtATime() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": false, "people": [],
            "invitations": [["id": "a", "name": "Ana", "expiresAt": 1_800_000_900], ["id": "b", "expiresAt": 1_800_000_900]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        let cancels = buttons(in: admin.view).compactMap(\.accessibilityLabel).filter { $0.hasPrefix("Cancel invitation") }
        XCTAssertEqual(cancels, ["Cancel invitation for Ana", "Cancel invitation for Invitation"])
        XCTAssertFalse(buttons(in: admin.view).contains { $0.configuration?.title == "Cancel unused invitations" })
    }

    @MainActor func testInvitationCreatedFromAPhoneAppearsInTheList() throws {
        let decode = { (json: [String: Any]) in try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: json)) }
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: try decode(["householdName": "Pat", "dropInEnabled": false, "people": []]))
        let navigation = UINavigationController(rootViewController: admin); admin.loadViewIfNeeded()
        buttons(in: admin.view).first { $0.configuration?.title == "Invite a family member" }!.sendActions(for: .touchUpInside)
        let invite = try XCTUnwrap(navigation.topViewController as? FamilyInviteViewController)
        invite.onAdminChanged?(try decode(["householdName": "Pat", "dropInEnabled": false, "people": [], "invitations": [["id": "a", "name": "Ana", "expiresAt": 1_800_000_900]]]))
        XCTAssertTrue(buttons(in: admin.view).contains { $0.accessibilityLabel == "Cancel invitation for Ana" }, "Caregiver mode on a phone keeps its own state, so it must take the one createInvite returns")
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
        XCTAssertEqual(settings.tableView(settings.tableView, numberOfRowsInSection: 0), 12)
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

@MainActor private final class TestIncomingAudio: IncomingCallAudioPlaying {
    var ringCount = 0, stopCount = 0
    var name: String?
    var language: BedsideLanguage?
    var video: Bool?
    var completion: ((Bool) -> Void)?
    func ring() -> Bool { ringCount += 1; return true }
    func announce(name: String, video: Bool, language: BedsideLanguage, completion: @escaping (Bool) -> Void) {
        self.name = name; self.language = language; self.video = video; self.completion = completion
    }
    func stop() { stopCount += 1; completion = nil }
}

@MainActor private final class TestCallSpeaker: OutgoingCallSpeaking {
    var stopCount = 0
    var message: String?
    var language: BedsideLanguage?
    var completion: ((Bool) -> Void)?
    func speak(_ message: String, language: BedsideLanguage, completion: @escaping (Bool) -> Void) {
        self.message = message; self.language = language; self.completion = completion
    }
    func stop() { stopCount += 1; completion = nil }
}

@MainActor private final class ImmediateCallSpeaker: OutgoingCallSpeaking {
    func speak(_ message: String, language: BedsideLanguage, completion: @escaping (Bool) -> Void) { completion(false) }
    func stop() {}
}


/// Exercise the pinned SDK's real teardown: identity/attributes disappear as
/// soon as the delegate returns, before a queued main-actor callback can run.
final class PhoneFallbackHangupTests: XCTestCase {
    @MainActor private func fixture() throws -> NativeCallViewController {
        let call = try NativeCall(room: "hangup-test", mode: .voice)
        let contact = try CallContact(name: "Family", nativeCall: call, phoneNumber: "+14155550123")
        let server = try NativeCallServer(url: "https://example.com", accessCode: "test-credential-no-network")
        // Do not load the view: no network, permissions, audio or telephone call.
        return try NativeCallViewController.phoneFallback(contact, server: server)
    }

    private func participant(in room: Room, identity: String = "phone") -> HangupTestParticipant {
        let participant = HangupTestParticipant(room: room, identity: Participant.Identity(from: identity))
        participant._state.mutate { $0.attributes = ["sip.callStatus": "active"] }
        return participant
    }

    @MainActor private func deliverAndReset(_ participant: Participant, event: @escaping @Sendable () -> Void) throws {
        let reset = DispatchSemaphore(value: 0)
        Task.detached {
            event()
            await participant.cleanUp(notify: false)
            reset.signal()
        }
        // Hold the main actor until real SDK cleanup resets participant state.
        XCTAssertEqual(reset.wait(timeout: .now() + 5), .success)
        XCTAssertNil(participant.identity)
        XCTAssertTrue(participant.attributes.isEmpty)
    }

    @MainActor private func drainCallbacks() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @MainActor func testRemoteHangupEndsFallbackAfterLiveKitClearsParticipant() async throws {
        let screen = try fixture(), room = screen.room, phone = participant(in: room)
        try deliverAndReset(phone) { screen.handleParticipantDisconnect(phone, in: room) }
        await drainCallbacks()
        XCTAssertTrue(screen.isEnding, "The disconnected phone must end the call even after its identity is cleared")
    }

    @MainActor func testEndingTheCallStopsSayingWhoItIsCalling() throws {
        let screen = try fixture(), audio = TestCallSpeaker()
        let announcement = OutgoingCallAnnouncement(calling: "Family", audio: audio)
        screen.announcement = announcement
        screen.finish()
        XCTAssertTrue(announcement.isFinished); XCTAssertEqual(audio.stopCount, 1)
    }

    @MainActor func testExplicitSIPHangupEndsFallbackBeforeParticipantRemoval() async throws {
        let screen = try fixture(), room = screen.room, phone = participant(in: room)
        try deliverAndReset(phone) { screen.room(room, participant: phone, didUpdateAttributes: ["sip.callStatus": "hangup"]) }
        await drainCallbacks()
        XCTAssertTrue(screen.isEnding)
    }

    @MainActor func testRingingActiveAndAutomationDoNotEndFallback() async throws {
        for status in ["dialing", "ringing", "active", "automation"] {
            let screen = try fixture(), room = screen.room, phone = participant(in: room)
            screen.room(room, participant: phone, didUpdateAttributes: ["sip.callStatus": status])
            await drainCallbacks()
            XCTAssertFalse(screen.isEnding, status)
        }
    }

    @MainActor func testStaleRoomsAndOtherParticipantsCannotEndFallback() async throws {
        let screen = try fixture(), room = screen.room, previousRoom = Room()
        let oldPhone = participant(in: previousRoom)
        try deliverAndReset(oldPhone) { screen.handleParticipantDisconnect(oldPhone, in: previousRoom) }
        let other = participant(in: room, identity: "someone-else")
        try deliverAndReset(other) { screen.handleParticipantDisconnect(other, in: room) }
        await drainCallbacks()
        XCTAssertFalse(screen.isEnding)
    }
}

/// The base SDK cleanup is the same state-reset path used by RemoteParticipant;
/// avoid constructing a transport/protobuf fixture or publishing any tracks.
private final class HangupTestParticipant: Participant, @unchecked Sendable {
    override func unpublishAll(notify: Bool = true) async {}
}

final class CallScreenLayoutTests: XCTestCase {
    @MainActor func testLargePortraitFitsCallingSpaceAndRemainsBesideNameDuringVideo() throws {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 568, height: 320), CGSize(width: 1032, height: 1376)] {
            let screen = UIViewController(), video = VideoView()
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
                UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
            }
            let photo = RecipientAppearance.photoView(image.jpegData(compressionQuality: 0.8))
            let title = PorchStyle.label("David", size: 40, color: .white)
            let status = PorchStyle.label("Calling David…", size: 17, color: .white)
            let placeholder = PorchStyle.label("Voice call", size: 28, color: .white)
            let end = PorchStyle.button("End call")
            CallScreenLayout.install(in: screen.view, video: video, placeholder: placeholder, title: title, status: status, photo: photo, buttons: [end])
            screen.view.frame = CGRect(origin: .zero, size: size); screen.view.layoutIfNeeded()
            let rect = photo.convert(photo.bounds, to: screen.view)
            XCTAssertGreaterThan(rect.height, 20)
            XCTAssertTrue(screen.view.bounds.contains(rect), "Photo must fit in \(size): \(rect)")
            XCTAssertLessThan(title.convert(title.bounds, to: screen.view).maxY, rect.minY)
            XCTAssertLessThan(rect.maxY, end.convert(end.bounds, to: screen.view).minY)
            XCTAssertFalse(photo.hasAmbiguousLayout)
            photo.isHidden = true; placeholder.isHidden = true; screen.view.layoutIfNeeded()
            func photos(_ view: UIView) -> [UIImageView] { (view as? UIImageView).map { [$0] } ?? view.subviews.flatMap(photos) }
            XCTAssertTrue(photos(screen.view).contains { $0 !== photo && $0.accessibilityIdentifier == "recipient.photo" && !$0.isHidden && $0.image != nil })
        }
    }

    @MainActor func testLongNamesAndAccessibilityTextScrollWithoutCoveringControls() throws {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        for size in [CGSize(width: 320, height: 568), CGSize(width: 568, height: 320), CGSize(width: 1024, height: 768)] {
            let screen = UIViewController(), remote = VideoView(), preview = VideoView()
            remote.backgroundColor = UIColor(white: 0.18, alpha: 1)
            preview.backgroundColor = UIColor(white: 0.35, alpha: 1)
            let title = PorchStyle.label(String(String(repeating: "Family member ", count: 7).prefix(80)), size: 26)
            let status = PorchStyle.label("Trying your family on Porch…\nTheir phone will ring if Porch isn't answered.", size: 17)
            let hint = PorchStyle.label("Key 0: hang up · Key 9: video off / on", size: 16)
            for (label, pointSize) in [(title, CGFloat(26)), (status, CGFloat(17)), (hint, CGFloat(16))] {
                // Keep the explicit accessibility metrics when this unmounted
                // fixture inherits the test host's default content-size trait.
                label.adjustsFontForContentSizeCategory = false
                label.textColor = .white
                label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: pointSize), compatibleWith: traits)
            }
            let buttons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
            for (button, text) in zip(buttons, ["Mute", "Camera off", "End call"]) {
                CallScreenLayout.configure(button, title: text, symbol: "phone")
                button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = PorchStyle.centeredTextAttributes(attributes)
                    attributes.font = UIFont.systemFont(ofSize: UIFontMetrics.default.scaledValue(for: 16, compatibleWith: traits))
                    return attributes
                }
            }
            CallScreenLayout.install(in: screen.view, video: remote, preview: preview,
                                     title: title, status: status, hint: hint, buttons: buttons)
            screen.view.frame = CGRect(origin: .zero, size: size)
            screen.view.layoutIfNeeded()
            let scroll = try XCTUnwrap(screen.view.subviews.first { $0.accessibilityIdentifier == "call.overlays" } as? UIScrollView)
            let heading = try XCTUnwrap(scroll.subviews.first { $0.accessibilityIdentifier == "call.heading" })
            let controls = try XCTUnwrap(scroll.subviews.first { $0.accessibilityIdentifier == "call.controls" })
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
            XCTAssertGreaterThanOrEqual(controls.frame.minY - heading.frame.maxY, 16)
            XCTAssertGreaterThanOrEqual(preview.frame.minY - heading.frame.maxY, 12)
            for label in [title, status, hint] {
                let fitting = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertGreaterThanOrEqual(label.bounds.height + 1, fitting.height, "Large text must remain readable")
            }
            let end = buttons[2]
            scroll.scrollRectToVisible(end.convert(end.bounds, to: scroll), animated: false)
            let endRect = end.convert(end.bounds, to: screen.view)
            XCTAssertTrue(screen.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(endRect), "End call must be reachable in \(size): \(endRect)")
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(size: size).image { screen.view.layer.render(in: $0.cgContext) })
            attachment.name = "Accessibility call controls \(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(remote.frame, screen.view.bounds, "Scrolling overlays must not move or shrink the remote video")
            XCTAssertFalse(heading.hasAmbiguousLayout)
            XCTAssertFalse(controls.hasAmbiguousLayout)

        }
    }

    @MainActor func testRemoteVideoFillsPhoneAndTabletInBothOrientations() throws {
        // Both call controllers use this layout. Include the smallest supported
        // phone, landscape safe areas, and iPad split-view widths.
        for hasPreview in [true, false] {
            let screen = UIViewController()
            let remote = VideoView(), preview = VideoView()
            remote.backgroundColor = UIColor(white: 0.18, alpha: 1)
            preview.backgroundColor = UIColor(white: 0.35, alpha: 1)
            let title = PorchStyle.label("Family", size: 26, color: .white)
            let status = PorchStyle.label("Video call connected", size: 17, color: .white)
            let buttons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
            for ((button, text), symbol) in zip(zip(buttons, ["Mute", "Camera off", "End call"]), ["mic.slash", "video", "phone.down.fill"]) {
                CallScreenLayout.configure(button, title: text, symbol: symbol, isEnd: button === buttons.last)
            }
            let hint = PorchStyle.label("Key 0: hang up · Key 9: video off / on", size: 16, color: .white)
            CallScreenLayout.install(in: screen.view, video: remote, preview: hasPreview ? preview : nil,
                                     title: title, status: status, hint: hasPreview ? hint : nil, buttons: buttons)
            for size in [CGSize(width: 320, height: 568), CGSize(width: 393, height: 852),
                         CGSize(width: 568, height: 320), CGSize(width: 852, height: 393), CGSize(width: 768, height: 1024),
                         CGSize(width: 1024, height: 768), CGSize(width: 375, height: 1024)] {
                screen.view.frame = CGRect(origin: .zero, size: size)
                screen.additionalSafeAreaInsets = size.width > size.height && size.height < 500
                    ? UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)
                    : UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
                screen.view.setNeedsLayout(); screen.view.layoutIfNeeded()
                XCTAssertEqual(remote.frame, screen.view.bounds)
                XCTAssertEqual(remote.layoutMode, .fill)
                let scroll = try XCTUnwrap(screen.view.subviews.first { $0.accessibilityIdentifier == "call.overlays" } as? UIScrollView)
                let controls = try XCTUnwrap(scroll.subviews.first { $0.accessibilityIdentifier == "call.controls" })
                let controlsRect = controls.convert(controls.bounds, to: screen.view)
                XCTAssertGreaterThan(controlsRect.minY, title.convert(title.bounds, to: screen.view).maxY)
                XCTAssertLessThanOrEqual(controlsRect.maxY, screen.view.safeAreaLayoutGuide.layoutFrame.maxY)
                XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 1)
                for button in buttons {
                    let rect = button.convert(button.bounds, to: screen.view)
                    XCTAssertGreaterThanOrEqual(rect.width, 44)
                    XCTAssertGreaterThanOrEqual(rect.height, 64)
                    XCTAssertTrue(screen.view.bounds.contains(rect))
                    XCTAssertFalse(button.hasAmbiguousLayout)
                }
                if hasPreview {
                    XCTAssertLessThanOrEqual(preview.bounds.width, 112)
                    XCTAssertLessThan(preview.bounds.width * preview.bounds.height, size.width * size.height * 0.04)
                    XCTAssertLessThan(preview.frame.maxY, controls.frame.minY)
                    XCTAssertTrue(screen.view.safeAreaLayoutGuide.layoutFrame.contains(preview.convert(preview.bounds, to: screen.view)))
                }
                XCTAssertFalse(remote.hasAmbiguousLayout)
                if size == CGSize(width: 393, height: 852) || size == CGSize(width: 1024, height: 768) {
                    let image = UIGraphicsImageRenderer(size: size).image { screen.view.layer.render(in: $0.cgContext) }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Call layout \(Int(size.width))x\(Int(size.height)) preview-\(hasPreview)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            // Audio-only calls hide the camera control without wasting its slot.
            buttons[1].isHidden = true
            screen.view.layoutIfNeeded()
            XCTAssertGreaterThan(buttons[0].bounds.width, 100)
        }
    }
}
