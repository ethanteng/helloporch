import XCTest
import UIKit
import GameController
import AVFoundation
import Security
import SafariServices
import UserNotifications
import CoreImage
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

    @MainActor func testCaregiverCanChangeColorRemovePhotoAndSave() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "test", mode: .voice), phoneNumber: "+14155550123", buttonColorHex: "FFCC00", photoData: portraitData()), for: 1)
        let home = FamilyAdminViewController(slots: slots)
        var saved: CallSlots?
        home.onSaveSlots = { saved = $0 }
        let person = PersonViewController(admin: home, slot: 1); person.loadViewIfNeeded()
        XCTAssertEqual(person.title, "David")
        XCTAssertEqual(descendants(person.view).first { $0.accessibilityIdentifier == "person.preview" }?.accessibilityLabel, "David, press 1",
                       "Their page starts with their button as the bedside shows it")
        func swatch(_ hex: String) -> UIControl? { descendants(person.view).compactMap { $0 as? UIControl }.first { $0.accessibilityIdentifier == "add.color.\(hex)" } }
        XCTAssertTrue(swatch("FFCC00")?.accessibilityTraits.contains(.selected) == true, "A color chosen before the six swatches stays, chosen")
        try XCTUnwrap(swatch("1565C0")).sendActions(for: .touchUpInside)
        XCTAssertEqual(saved?.contact(for: 1)?.buttonColorHex, "1565C0")
        XCTAssertNil(swatch("FFCC00"), "and goes once another color is chosen")
        func photo() -> UIButton? { buttons(in: person.view).first { $0.accessibilityIdentifier == "person.choosePhoto" } }
        func choices(_ menu: UIMenu?) -> [String] { menu?.children.flatMap { ($0 as? UIMenu).map(choices) ?? [$0.title] } ?? [] }
        XCTAssertEqual(photo()?.configuration?.title, "Change photo")
        XCTAssertTrue(choices(photo()?.menu).contains("Remove photo"))
        person.removePhoto()
        let contact = try XCTUnwrap(saved?.contact(for: 1))
        XCTAssertNil(contact.photoData); XCTAssertEqual(contact.buttonColorHex, "1565C0")
        XCTAssertEqual(contact.phoneNumber, "+14155550123", "Changing one detail keeps the rest of the key")
        XCTAssertEqual(photo()?.configuration?.title, "Photo")
        XCTAssertFalse(choices(photo()?.menu).contains("Remove photo"))
    }

    @MainActor func testCaregiverHomeOpensEachBedsidePage() throws {
        let home = FamilyAdminViewController(slots: CallSlots())
        let navigation = UINavigationController(rootViewController: home); home.loadViewIfNeeded()
        XCTAssertEqual(rows(in: home.view).compactMap(\.accessibilityIdentifier).filter { $0.hasPrefix("caregiver.page.") }, CaregiverPage.allCases.map { "caregiver.page.\($0.rawValue)" })
        XCTAssertEqual(Array(CaregiverPage.pages(onBedside: true).map { $0.title(onBedside: true) }.prefix(7)), ["People", "Calls", "Drop-in", "Messages", "Display & voice", "Privacy", "Caregivers & PIN"])
        let expected: [(CaregiverPage, AnyClass)] = [(.people, PeopleSettingsViewController.self), (.calls, CallSettingsViewController.self), (.dropIn, DropInSettingsViewController.self),
            (.messages, MessageSettingsViewController.self), (.display, BedsideDisplaySettingsViewController.self), (.privacy, PrivacySettingsViewController.self),
            (.caregivers, CaregiverAccessViewController.self), (.device, DeviceSettingsViewController.self), (.about, AboutViewController.self)]
        for (page, screen) in expected {
            navigation.popToRootViewController(animated: false)
            try XCTUnwrap(rows(in: home.view).first { $0.accessibilityIdentifier == "caregiver.page.\(page.rawValue)" }).sendActions(for: .touchUpInside)
            XCTAssertTrue(navigation.topViewController?.isKind(of: screen) == true, "\(page)")
        }
    }

    @MainActor func testCallsPageOpensCallHistory() throws {
        let home = FamilyAdminViewController(slots: CallSlots())
        let calls = CallSettingsViewController(admin: home)
        let navigation = UINavigationController(rootViewController: calls); calls.loadViewIfNeeded()
        try XCTUnwrap(rows(in: calls.view).first { $0.accessibilityIdentifier == "calls.history" }).sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.topViewController is CallHistoryViewController)
    }

    @MainActor func testSilenceHangUpIsSetInMinutesAndCanBeTurnedOff() throws {
        let suite = "porch.calls-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = FamilyAdminViewController(slots: CallSlots())
        let calls = CallSettingsViewController(admin: home, defaults: defaults); calls.loadViewIfNeeded()
        func switches(_ view: UIView) -> [UISwitch] { descendants(view).compactMap { $0 as? UISwitch } }
        func minutes(_ view: UIView) -> UIStepper? { descendants(view).compactMap { $0 as? UIStepper }.first { $0.accessibilityIdentifier == "calls.silenceMinutes" } }
        let silence = try XCTUnwrap(switches(calls.view).first { $0.accessibilityIdentifier == "calls.silence" })
        XCTAssertTrue(silence.isOn, "On until a caregiver turns it off")
        XCTAssertEqual(minutes(calls.view)?.accessibilityValue, "2 min")
        silence.isOn = false; silence.sendActions(for: .valueChanged)
        XCTAssertFalse(CallPreferences.disconnectAfterSilence(in: defaults))
        XCTAssertNil(minutes(calls.view), "The time shows only while it's on")
        let again = try XCTUnwrap(switches(calls.view).first { $0.accessibilityIdentifier == "calls.silence" })
        again.isOn = true; again.sendActions(for: .valueChanged)
        XCTAssertTrue(CallPreferences.disconnectAfterSilence(in: defaults))
        let stepper = try XCTUnwrap(minutes(calls.view))
        XCTAssertEqual(stepper.value, 2); XCTAssertEqual(stepper.accessibilityValue, "2 min")
        stepper.value = 5; stepper.sendActions(for: .valueChanged)
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 300)
        XCTAssertEqual(stepper.accessibilityValue, "5 min")
        // A time saved in seconds by an older version shows as it is.
        CallPreferences.saveSilence(enabled: true, seconds: 45, in: defaults)
        let reopened = CallSettingsViewController(admin: home, defaults: defaults); reopened.loadViewIfNeeded()
        XCTAssertEqual(minutes(reopened.view)?.accessibilityValue, "45 sec")
        let off = try XCTUnwrap(switches(reopened.view).first { $0.accessibilityIdentifier == "calls.silence" })
        off.isOn = false; off.sendActions(for: .valueChanged)
        XCTAssertFalse(CallPreferences.disconnectAfterSilence(in: defaults))
        XCTAssertEqual(CallPreferences.silenceSeconds(in: defaults), 45)
        XCTAssertNil(minutes(reopened.view))
        // Phone fallback and leaving a message save as they change too.
        let fallback = try XCTUnwrap(descendants(reopened.view).compactMap { $0 as? UIStepper }.first { $0.accessibilityIdentifier == "calls.fallbackWait" })
        fallback.value = 30; fallback.sendActions(for: .valueChanged)
        XCTAssertEqual(CallPreferences.fallbackSeconds(in: defaults), 30)
        let leave = try XCTUnwrap(switches(reopened.view).first { $0.accessibilityIdentifier == "calls.leaveMessage" })
        leave.isOn = false; leave.sendActions(for: .valueChanged)
        XCTAssertFalse(CallPreferences.leaveMessageWhenUnanswered(in: defaults))
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

    /// Runs `body`, then puts back this device's pairings, its old single-family copy and what it calls each family.
    @MainActor private func preservingPairings(_ body: () throws -> Void) rethrows {
        let accounts = ["porch.family.bedside", "porch.family.family", "porch.family.families"]
        func query(_ account: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier!, kSecAttrAccount as String: account]
        }
        let saved = accounts.map { account -> (Data, Bool)? in
            guard let data = NativeCallSettings.readSecret(account) else { return nil }
            var attributes = query(account); attributes[kSecReturnAttributes as String] = true
            var found: CFTypeRef?
            SecItemCopyMatching(attributes as CFDictionary, &found)
            return (data, (found as? [String: Any])?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        }
        let defaults = UserDefaults.standard, keys = ["porch.family.current", "porch.family.nicknames", "porch.family.households"]
        let values = keys.map { defaults.object(forKey: $0) }
        defer {
            for (account, previous) in zip(accounts, saved) {
                if let previous { try? NativeCallSettings.writeSecret(previous.0, account: account, accessibleAfterFirstUnlock: previous.1) }
                else { SecItemDelete(query(account) as CFDictionary) }
            }
            for (key, value) in zip(keys, values) { defaults.set(value, forKey: key) }
        }
        try body()
    }

    @MainActor func testBothPairedCallingCredentialsAreAvailableAfterFirstUnlock() throws {
        try preservingPairings {
            for role in [PorchExperience.bedside, .family] {
                // A family phone keeps every family it's in under one account.
                let account = role == .family ? "porch.family.families" : "porch.family.bedside"
                var attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: Bundle.main.bundleIdentifier!, kSecAttrAccount as String: account]
                attributes[kSecReturnAttributes as String] = true
                let profile = FamilyCredential(origin: URL(string: "https://example.invalid")!, credential: "test-device.test-secret", role: role)
                try PorchDevice.save(profile)
                if role == .family { PorchDevice.select(profile) }
                var result: CFTypeRef?
                XCTAssertEqual(SecItemCopyMatching(attributes as CFDictionary, &result), errSecSuccess)
                XCTAssertEqual((result as? [String: Any])?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
                XCTAssertEqual(PorchDevice.credential(for: role)?.credential, profile.credential)
            }
        }
    }

    /// A phone in both sets of parents' families keeps both pairings. Taking one off leaves the other ringing.
    @MainActor func testAFamilyPhoneKeepsEveryFamilyItJoins() throws {
        try preservingPairings {
            let origin = URL(string: "https://example.invalid")!
            let lee = FamilyCredential(origin: origin, credential: "lee-device.lee-secret", role: .family)
            let teng = FamilyCredential(origin: origin, credential: "teng-device.teng-secret", role: .family)
            // Paired before Porch allowed more than one family: the pairing is under the old single-family account.
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier!,
                           kSecAttrAccount as String: "porch.family.families"] as CFDictionary)
            try NativeCallSettings.writeSecret(try JSONEncoder().encode(lee), account: "porch.family.family", accessibleAfterFirstUnlock: true)
            UserDefaults.standard.removeObject(forKey: "porch.family.current")
            XCTAssertEqual(PorchDevice.families, [lee])
            XCTAssertEqual(PorchDevice.credential(for: .family), lee)
            try PorchDevice.save(teng)
            XCTAssertEqual(PorchDevice.families, [lee, teng], "joining another family keeps the first")
            XCTAssertEqual(PorchDevice.currentFamily, lee, "the screens stay on the family they showed")
            PorchDevice.select(teng)
            XCTAssertEqual(PorchDevice.credential(for: .family), teng)
            try PorchDevice.save(lee)
            XCTAssertEqual(PorchDevice.families, [lee, teng], "saving a family again keeps its place")
            // Calls and messages say which member they're for, and each family knows this phone by its own ID.
            XCTAssertEqual(PorchDevice.family(memberID: "lee-device"), lee)
            XCTAssertEqual(PorchDevice.family(memberID: "teng-device"), teng)
            XCTAssertNil(PorchDevice.family(memberID: "someone-else"))
            XCTAssertNil(PorchDevice.family(memberID: nil))
            // Both are "Mom" until this phone names one, or a check-in says what its caregiver called it.
            let data = try JSONSerialization.data(withJSONObject: ["householdID": "lee-home", "householdName": "Lee family", "dropInEnabled": false,
                "me": ["id": "lee-device", "name": "Ethan", "role": "family", "permissions": ["audio": false, "video": false], "online": true],
                "people": [[String: Any]](), "busy": false, "serverTime": 1])
            PorchDevice.noteHousehold(try JSONDecoder().decode(FamilySnapshot.self, from: data), for: lee)
            XCTAssertEqual(PorchDevice.familyName(lee), "Lee family")
            XCTAssertEqual(PorchDevice.householdID(lee), "lee-home")
            XCTAssertNil(PorchDevice.familyName(teng))
            PorchDevice.setNickname("  Sarah's parents ", for: teng)
            XCTAssertEqual(PorchDevice.familyName(teng), "Sarah's parents")
            PorchDevice.setNickname("Mom & Dad", for: lee)
            XCTAssertEqual(PorchDevice.familyName(lee), "Mom & Dad", "the name chosen here wins")
            PorchDevice.setNickname(" ", for: lee)
            XCTAssertNil(PorchDevice.nickname(lee))
            XCTAssertEqual(PorchDevice.familyName(lee), "Lee family")
            try PorchDevice.removeFamily(teng)
            XCTAssertEqual(PorchDevice.families, [lee])
            XCTAssertEqual(PorchDevice.currentFamily, lee, "the family left is the one shown")
            XCTAssertNil(PorchDevice.nickname(teng))
            try PorchDevice.removeFamily(lee)
            XCTAssertEqual(PorchDevice.families, [])
            XCTAssertNil(PorchDevice.credential(for: .family), "the old single-family copy doesn't come back")
            XCTAssertNil(PorchDevice.familyName(lee))
        }
    }

    /// While every call drops in, a caregiver's Call tab says so on the bedside's card, with Turn off. Everyone may
    /// drop in meanwhile; only caregivers see the banner.
    @MainActor func testCaregiversSeeEveryCallOnTheirCallTab() throws {
        let coordinator = FamilyCoordinator.shared, wasActive = coordinator.isActive
        defer { coordinator.start(); if !wasActive { coordinator.pause() } }
        try preservingPairings {
            let defaults = UserDefaults.standard, experience = defaults.object(forKey: "porch.experience")
            defer { coordinator.pause(); defaults.set(experience, forKey: "porch.experience") }
            defaults.set("family", forKey: "porch.experience")
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier!,
                           kSecAttrAccount as String: "porch.family.families"] as CFDictionary)
            try NativeCallSettings.writeSecret(Data(), account: "porch.family.family")
            let family = FamilyCredential(origin: URL(string: "https://example.invalid")!, credential: "tom-device.tom-secret", role: .family)
            try PorchDevice.save(family)
            // Not `start`: it would ask for notification and microphone permission, which stops later tests.
            coordinator.installForTesting([family])
            @MainActor func show(caregiver: Bool) throws {
                let state: [String: Any] = ["householdID": "reyes", "householdName": "Rose", "dropInEnabled": true,
                    "me": ["id": "tom-device", "name": "Tom Reyes", "role": "family", "permissions": ["audio": false, "video": false], "online": true, "caregiver": caregiver],
                    "people": [["id": "rose", "name": "Rose", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true]],
                    "busy": false, "serverTime": 1, "everyCall": ["by": "Linda Reyes", "at": Date().timeIntervalSince1970]]
                coordinator.update(try JSONDecoder().decode(FamilyResponse.self, from: JSONSerialization.data(withJSONObject: ["state": state])))
            }
            try show(caregiver: true)
            let home = FamilyHomeViewController(); home.loadViewIfNeeded()
            let banner = try XCTUnwrap(descendants(home.view).first { $0.accessibilityIdentifier == "family.everyCall" })
            XCTAssertTrue(labels(in: banner).compactMap(\.text).contains("Every call drops in"))
            XCTAssertTrue(labels(in: banner).compactMap(\.text).contains { $0.hasPrefix("Linda, ") }, "who turned it on, by first name")
            XCTAssertEqual(buttons(in: banner).first { $0.accessibilityIdentifier == "family.everyCall.turnOff" }?.configuration?.title, "Turn off")
            XCTAssertEqual(buttons(in: home.view).first { $0.accessibilityIdentifier == "family.dropIn" }?.accessibilityLabel, "Drop in on Rose",
                           "Every call lets this phone drop in either way, though it isn't approved itself")
            try show(caregiver: false)
            XCTAssertFalse(descendants(home.view).contains { $0.accessibilityIdentifier == "family.everyCall" }, "Only caregivers can turn it off")
            XCTAssertNotNil(buttons(in: home.view).first { $0.accessibilityIdentifier == "family.dropIn" })
        }
    }

    /// A phone call that came in while every call drops in shows on a caregiver's Call tab, ringing or with how long
    /// it's been on, and End call; it stays there after Every call is turned off, until the call ends.
    @MainActor func testCaregiversSeeAPhoneCallOnTheBedsideAndCanEndIt() throws {
        let coordinator = FamilyCoordinator.shared, wasActive = coordinator.isActive
        defer { coordinator.start(); if !wasActive { coordinator.pause() } }
        try preservingPairings {
            let defaults = UserDefaults.standard, experience = defaults.object(forKey: "porch.experience")
            defer { coordinator.pause(); defaults.set(experience, forKey: "porch.experience") }
            defaults.set("family", forKey: "porch.experience")
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier!,
                           kSecAttrAccount as String: "porch.family.families"] as CFDictionary)
            try NativeCallSettings.writeSecret(Data(), account: "porch.family.family")
            let family = FamilyCredential(origin: URL(string: "https://example.invalid")!, credential: "tom-device.tom-secret", role: .family)
            try PorchDevice.save(family)
            // Not `start`: it would ask for notification and microphone permission, which stops later tests.
            coordinator.installForTesting([family])
            @MainActor func show(caregiver: Bool, everyCall: Bool, call: [String: Any]) throws {
                var state: [String: Any] = ["householdID": "reyes", "householdName": "Rose", "dropInEnabled": true,
                    "me": ["id": "tom-device", "name": "Tom Reyes", "role": "family", "permissions": ["audio": false, "video": false], "online": true, "caregiver": caregiver],
                    "people": [["id": "rose", "name": "Rose", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true]],
                    "busy": true, "serverTime": 1_800_000_200, "bedsideCall": call]
                if everyCall { state["everyCall"] = ["by": "Linda Reyes", "at": 1_800_000_000] }
                coordinator.update(try JSONDecoder().decode(FamilyResponse.self, from: JSONSerialization.data(withJSONObject: ["state": state])))
            }
            try show(caregiver: true, everyCall: false, call: ["id": "call-1", "title": "(510) 555-0162", "kind": "dropIn", "state": "accepted", "acceptedAt": 1_800_000_066])
            let home = FamilyHomeViewController(); home.loadViewIfNeeded()
            let strip = try XCTUnwrap(descendants(home.view).first { $0.accessibilityIdentifier == "family.liveCall" }, "It stays after Every call is off")
            XCTAssertTrue(labels(in: strip).compactMap(\.text).contains("(510) 555-0162"))
            XCTAssertEqual(labels(in: strip).first { $0.accessibilityIdentifier == "family.liveCall.status" }?.text, "On a call · 2:14", "by the server's clock")
            XCTAssertEqual(buttons(in: strip).first { $0.accessibilityIdentifier == "family.liveCall.end" }?.configuration?.title, "End call")
            XCTAssertFalse(descendants(home.view).contains { $0.accessibilityIdentifier == "family.everyCall" })
            // Ringing, under the Every call banner.
            try show(caregiver: true, everyCall: true, call: ["id": "call-2", "title": "Hidden number", "kind": "call", "state": "pending"])
            let card = try XCTUnwrap(descendants(home.view).first { $0.accessibilityIdentifier == "family.card" } as? UIStackView)
            XCTAssertEqual(card.arrangedSubviews.prefix(2).map(\.accessibilityIdentifier), ["family.everyCall", "family.liveCall"])
            XCTAssertEqual(labels(in: card).first { $0.accessibilityIdentifier == "family.liveCall.status" }?.text, "Ringing")
            try show(caregiver: true, everyCall: true, call: ["id": "call-3", "title": "Carmen", "kind": "dropIn", "state": "pending"])
            XCTAssertEqual(labels(in: home.view).first { $0.accessibilityIdentifier == "family.liveCall.status" }?.text, "Dropping in")
            try show(caregiver: false, everyCall: true, call: ["id": "call-3", "title": "Carmen", "kind": "dropIn", "state": "pending"])
            XCTAssertFalse(descendants(home.view).contains { $0.accessibilityIdentifier == "family.liveCall" }, "Only caregivers can end it")
        }
        // The notice's buttons work without opening Porch: End call, and turning Every call off.
        XCTAssertEqual(FamilyMessageAlerts.callNotice.identifier, "PORCH_CALL_NOTICE")
        XCTAssertEqual(FamilyMessageAlerts.callNotice.actions.map(\.identifier), ["endCall", "turnOffEveryCall"])
        XCTAssertEqual(FamilyMessageAlerts.callNotice.actions.map(\.title), ["End call", "Turn off Every call"])
        XCTAssertEqual(FamilyMessageAlerts.callNotice.actions.map { $0.options.contains(.foreground) }, [false, false])
        XCTAssertTrue(FamilyMessageAlerts.callNotice.actions[0].options.contains(.destructive))
        XCTAssertEqual(["endCall", "turnOffEveryCall", UNNotificationDefaultActionIdentifier].map(FamilyMessageAlerts.serverAction), ["endBedsideCall", "turnOffEveryCall", nil])
    }

    /// Both bedsides are "Mom" until this phone names one: the family joined later shows as "Mom 2" meanwhile.
    @MainActor func testTwoFamiliesCalledMomAreNumberedUntilOneIsNamed() throws {
        try preservingPairings {
            let origin = URL(string: "https://example.invalid")!
            let lee = FamilyCredential(origin: origin, credential: "lee-device.lee-secret", role: .family)
            let teng = FamilyCredential(origin: origin, credential: "teng-device.teng-secret", role: .family)
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier!,
                           kSecAttrAccount as String: "porch.family.families"] as CFDictionary)
            try NativeCallSettings.writeSecret(Data(), account: "porch.family.family")
            for (family, id) in [(lee, "lee-home"), (teng, "teng-home")] {
                PorchDevice.setNickname(nil, for: family)
                try PorchDevice.save(family)
                let data = try JSONSerialization.data(withJSONObject: ["householdID": id, "householdName": "Mom", "dropInEnabled": false,
                    "me": ["id": family.deviceID, "name": "Ethan", "role": "family", "permissions": ["audio": false, "video": false], "online": true],
                    "people": [[String: Any]](), "busy": false, "serverTime": 1])
                PorchDevice.noteHousehold(try JSONDecoder().decode(FamilySnapshot.self, from: data), for: family)
            }
            XCTAssertEqual(PorchDevice.families.map(PorchDevice.familyName), ["Mom", "Mom 2"])
            XCTAssertEqual(PorchDevice.unnumberedName(teng), "Mom", "what joining compares, to ask for a name")
            PorchDevice.setNickname("Sarah's parents", for: teng)
            XCTAssertEqual(PorchDevice.families.map(PorchDevice.familyName), ["Mom", "Sarah's parents"])
            PorchDevice.setNickname(nil, for: teng)
            try PorchDevice.removeFamily(lee)
            XCTAssertEqual(PorchDevice.familyName(teng), "Mom", "with the other one gone, there's nothing to tell it from")
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
            XCTAssertEqual(options.count, BedsideLanguage.allCases.count)
            let language = options.first { $0.accessibilityIdentifier == "bedside.language.\(choice.rawValue)" }!
            XCTAssertEqual(language.configuration?.title, choice.choiceLabel)
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
        // The last language chosen above is the one saved.
        preferences.language = try XCTUnwrap(BedsideLanguage.allCases.last)
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
        XCTAssertTrue(help.message?.contains("Unplug it while you type") == true)
        XCTAssertTrue(help.message?.contains("use Porch keyboard") == true)
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

    /// The website's palette: links and the chosen tab in deep tomato read on cards and on the page, white reads on
    /// ink buttons and on End call, and the night colors read on the bedside's night.
    @MainActor func testBrandColorsMeetContrast() throws {
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.accent, PorchStyle.surface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.accent, PorchStyle.page), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.secondary, PorchStyle.page), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(.white, PorchStyle.action), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(.white, PorchStyle.danger), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(.white, PorchStyle.go), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.go, PorchStyle.surface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.nightText, PorchStyle.nightSurface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.ink, CallTranslationColors.on), 4.5)
        // "Played" is 15-point text on a faint green tag, which sits on the cream page. `go` there is 3.9:1.
        XCTAssertGreaterThanOrEqual(contrast(PorchStyle.played, blended(PorchStyle.go, alpha: 0.12, over: PorchStyle.page)), 4.5)
        // "Porch calls" is 14-point text on its honey chip, as on Android. Tomato on a faint tomato wash was 4.3:1.
        let calls = PaddedLabel("Porch calls")
        XCTAssertGreaterThanOrEqual(contrast(calls.textColor, try XCTUnwrap(calls.backgroundColor)), 4.5)
    }

    /// Family and caregiver screens use the website's fonts; Mom's own screens keep the system font.
    @MainActor func testBrandFontsLoadAndBedsideKeepsSystemFont() {
        XCTAssertTrue(PorchFonts.registered)
        XCTAssertEqual(PorchStyle.font(17).fontName, "DMSans-Regular")
        XCTAssertEqual(PorchStyle.font(17, weight: .medium).fontName, "DMSans-Medium")
        XCTAssertEqual(PorchStyle.font(17, weight: .semibold).fontName, "DMSans-SemiBold")
        XCTAssertEqual(PorchStyle.font(17, weight: .bold).fontName, "DMSans-Bold")
        XCTAssertEqual(PorchStyle.titleFont(24).fontName, "Newsreader-Medium")
        XCTAssertEqual(PorchFonts.wordmark(24).fontName, "BricolageGrotesque-ExtraBold")
        XCTAssertEqual(PorchStyle.systemFont(17).familyName, UIFont.systemFont(ofSize: 17).familyName)
        XCTAssertEqual(PorchStyle.label("Rose").font.fontName, "DMSans-Regular")
        XCTAssertEqual(PorchStyle.systemLabel("Rose").font.familyName, UIFont.systemFont(ofSize: 17).familyName)
        // A configured button takes its title's font from its configuration, so it's checked as drawn.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let brand = PorchStyle.button("Save"), system = PorchStyle.systemButton("Save")
        let stack = UIStackView(arrangedSubviews: [brand, system]); stack.axis = .vertical
        stack.frame = window.bounds
        window.addSubview(stack); window.isHidden = false
        window.layoutIfNeeded()
        XCTAssertEqual(brand.titleLabel?.font.fontName, "DMSans-Medium")
        XCTAssertEqual(brand.titleLabel?.font.pointSize, system.titleLabel?.font.pointSize)
        XCTAssertEqual(system.titleLabel?.font.familyName, UIFont.systemFont(ofSize: 17).familyName)
        let navigation = PorchStyle.navigation(UIViewController())
        XCTAssertEqual((navigation.navigationBar.standardAppearance.titleTextAttributes[.font] as? UIFont)?.fontName, "Newsreader-Medium")
        let wordmark = PorchWordmark()
        XCTAssertEqual(wordmark.accessibilityLabel, "Porch")
        XCTAssertGreaterThan(wordmark.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width, 60)
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


    @MainActor func testPhoneNumbersKeepFullWidthAndControlsAtTheirSize() throws {
        let person = try CallContact(name: "David", nativeCall: NativeCall(room: "family-david", mode: .voice), phoneNumber: "+14155550123", otherPhoneNumbers: ["+14155550199"])
        var slots = CallSlots(); try slots.setContact(person, for: 1)
        let home = FamilyAdminViewController(slots: slots)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        func all(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(all) }
        for size in [CGSize(width: 834, height: 1210), CGSize(width: 1210, height: 834), CGSize(width: 402, height: 874)] {
            let numbers = AddPhoneNumbersViewController(admin: home, key: 1, contact: person)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = PorchStyle.navigation(numbers)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            XCTAssertEqual(numbers.title, "Phone")
            XCTAssertEqual(numbers.form.bounds.width, min(760, size.width - 48), "The numbers must not squeeze the form at \(size)")
            let controls = all(numbers.form).filter { ($0 as? UIButton)?.accessibilityLabel?.hasPrefix("Remove ") == true || $0.accessibilityIdentifier == "add.addNumber" }
            XCTAssertEqual(controls.count, 3)
            // Converting between views leaves rounding noise; a squeezed control is short by whole points.
            let tolerance: CGFloat = 0.5
            for control in controls {
                let frame = control.convert(control.bounds, to: numbers.form)
                XCTAssertGreaterThanOrEqual(frame.width, control.intrinsicContentSize.width - tolerance, "\(control.accessibilityLabel ?? "") is squeezed at \(size)")
                XCTAssertGreaterThanOrEqual(frame.minX, -tolerance)
                XCTAssertLessThanOrEqual(frame.maxX, numbers.form.bounds.width + tolerance, "\(control.accessibilityLabel ?? "") leaves its card at \(size)")
            }
        }
    }

    @MainActor func testCaregiverModeOnAPhoneOffersOnlyFamilySettings() {
        XCTAssertEqual(CaregiverPage.pages(onBedside: false).map { $0.title(onBedside: false) }, ["Family", "Calls", "Drop-in", "Messages", "Privacy", "Caregivers", "About"])
        XCTAssertEqual(CaregiverPage.pages(onBedside: true).last, .about, "About is the last page on the bedside too")
    }

    @MainActor func testThisIPadAndPrivacyPagesLinkThePrivacyPolicy() throws {
        let device = DeviceSettingsViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = device; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try XCTUnwrap(buttons(in: device.view).first { $0.configuration?.title == "Privacy policy" }).sendActions(for: .touchUpInside)
        XCTAssertTrue(device.presentedViewController is SFSafariViewController)
        XCTAssertEqual(privacyPolicyURL.absoluteString, "https://helloporch.store/privacy")
        let home = FamilyAdminViewController(slots: CallSlots())
        let privacy = PrivacySettingsViewController(admin: home); privacy.loadViewIfNeeded()
        XCTAssertTrue(buttons(in: privacy.view).contains { $0.configuration?.title == "Privacy policy" })
    }

    @MainActor func testAboutShowsTheVersionFirstThenOpensContactAndEachLicense() throws {
        let about = AboutViewController()
        let navigation = UINavigationController(rootViewController: about); about.loadViewIfNeeded()
        XCTAssertEqual(about.title, "About")
        let info = Bundle.main.infoDictionary
        let version = try XCTUnwrap(info?["CFBundleShortVersionString"] as? String), build = try XCTUnwrap(info?["CFBundleVersion"] as? String)
        let shown = texts(about.view)
        for text in ["Porch", "Version \(version) (\(build))", "Built with ❤️ in Oakland, CA", "Licenses"] { XCTAssertTrue(shown.contains(text), text) }
        XCTAssertLessThan(try XCTUnwrap(shown.firstIndex(of: "Version \(version) (\(build))")), try XCTUnwrap(shown.firstIndex(of: "Licenses")))
        let contact = try XCTUnwrap(buttons(in: about.view).first { $0.accessibilityIdentifier == "about.contact" })
        XCTAssertEqual(contact.configuration?.attributedTitle.map { String($0.characters) }, "Questions or feedback? Contact me.")
        contact.sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.topViewController is ContactViewController)
        navigation.popToRootViewController(animated: false)
        try XCTUnwrap(rows(in: about.view).first { $0.accessibilityIdentifier == "about.licenses" }).sendActions(for: .touchUpInside)
        let licenses = try XCTUnwrap(navigation.topViewController as? LicensesViewController); licenses.loadViewIfNeeded()
        XCTAssertEqual(licenses.title, "Licenses")
        // The list Settings → Porch → Acknowledgements shows, without its introduction.
        let all = Acknowledgement.bundled
        XCTAssertGreaterThan(all.count, 10)
        XCTAssertTrue(all.contains { $0.title.hasPrefix("LiveKit Swift SDK") })
        for font in ["Bricolage Grotesque", "DM Sans", "Newsreader"] {
            XCTAssertTrue(all.contains { $0.title == font && $0.text.contains("SIL OPEN FONT LICENSE") }, font)
        }
        XCTAssertFalse(all.contains { $0.text.hasPrefix("Porch includes") })
        let listed = rows(in: licenses.view).filter { $0.accessibilityIdentifier == "licenses.row" }
        XCTAssertEqual(listed.map(\.accessibilityLabel), all.map(\.title))
        try XCTUnwrap(listed.first).sendActions(for: .touchUpInside)
        let license = try XCTUnwrap(navigation.topViewController as? LicenseViewController); license.loadViewIfNeeded()
        XCTAssertEqual(license.title, all[0].title)
        XCTAssertEqual(labels(in: license.view).first { $0.accessibilityIdentifier == "license.text" }?.text, all[0].reflowed)
    }

    func testLicenseTextRewrapsToTheScreenButKeepsShortLinesAndParagraphs() {
        let mit = Acknowledgement(title: "PhoneNumberKit 5.0.9", text: """
        The MIT License (MIT)

        Copyright (c) 2018 Roy Marmelstein
        Copyright (c) 2026 Bruno Guidolim and contributors

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software.\r
           \r
              "License" shall mean the terms and conditions for use, reproduction,
              and distribution.
        """)
        XCTAssertEqual(mit.reflowed, """
        The MIT License (MIT)

        Copyright (c) 2018 Roy Marmelstein
        Copyright (c) 2026 Bruno Guidolim and contributors

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software.

        "License" shall mean the terms and conditions for use, reproduction, and distribution.
        """)
    }

    @MainActor func testContactIsReachableFromAFamilyDeviceAndOnlyShownOnTheBedside() throws {
        func actions(_ screen: ContactViewController) -> [String: String] {
            screen.loadViewIfNeeded()
            return Dictionary(uniqueKeysWithValues: buttons(in: screen.view).compactMap { button in
                guard let id = button.accessibilityIdentifier, id.hasPrefix("contact."), let title = button.configuration?.title else { return nil }
                return (id, title)
            })
        }
        let phone = ContactViewController(onBedside: false, onPhone: true)
        XCTAssertEqual(actions(phone), ["contact.email": "ethan@helloporch.store", "contact.phone": "(415) 867-6937"])
        XCTAssertEqual(phone.title, "Contact")
        XCTAssertEqual(actions(ContactViewController(onBedside: false, onPhone: false)), ["contact.email": "ethan@helloporch.store"], "An iPad can't call")
        let bedside = ContactViewController(onBedside: true, onPhone: false)
        XCTAssertEqual(actions(bedside), [:], "The bedside iPad doesn't leave Porch for Mail")
        XCTAssertEqual(descendants(bedside.view).filter { $0.accessibilityIdentifier?.hasPrefix("contact.") == true }.map(\.accessibilityLabel),
                       ["Email, ethan@helloporch.store", "Phone, (415) 867-6937"])
    }

    func testVersionShowsTheBuildInBrackets() {
        XCTAssertEqual(PorchVersion.text(["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "78"]), "0.1.0 (78)")
        XCTAssertEqual(PorchVersion.text(["CFBundleShortVersionString": "0.1.0"]), "0.1.0")
    }

    @MainActor func testSetupsFirstScreenLinksPrivacyPolicy() {
        let navigation = BedsideSetup.start { _ in }
        let setup = try! XCTUnwrap(navigation.topViewController); setup.loadViewIfNeeded()
        func find(_ view: UIView) -> UIButton? {
            if view.accessibilityIdentifier == "caregiver.privacy" { return view as? UIButton }
            return view.subviews.compactMap(find).first
        }
        XCTAssertEqual(find(setup.view)?.configuration?.title, "Privacy policy")
    }

    @MainActor func testSetupAsksForAChosenPINAndItsConfirmation() {
        let setup = SetupPINViewController(BedsideSetup())
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

    @MainActor func testEveryKeyActionHasAChoice() throws {
        var slots = CallSlots(); try slots.setAction(.messages, for: 8)
        let home = FamilyAdminViewController(slots: slots)
        let screen = KeyActionViewController(admin: home, key: 8, offersSomeone: false); screen.loadViewIfNeeded()
        let choices = rows(in: screen.view).filter { $0.accessibilityIdentifier?.hasPrefix("keypad.action.") == true }
        func chosen() -> [String?] { choices.filter { $0.accessibilityTraits.contains(.selected) }.map(\.accessibilityIdentifier) }
        XCTAssertEqual(choices.compactMap(\.accessibilityLabel), ["Answer / hang up", "Video on / off", "Play messages", "Nothing"])
        XCTAssertEqual(Set(choices.compactMap(\.accessibilityIdentifier)), Set(KeypadAction.allCases.filter { $0 != .person }.map { "keypad.action.\($0.rawValue)" }), "Every key action but a person is offered")
        XCTAssertEqual(chosen(), ["keypad.action.messages"])
        choices.first { $0.accessibilityIdentifier == "keypad.action.callControl" }?.sendActions(for: .touchUpInside)
        XCTAssertEqual(chosen(), ["keypad.action.callControl"])
    }

    @MainActor func testUnenrolledBedsideSetupOffersTheWayBackToFamilyMode() {
        let setup = try! XCTUnwrap(BedsideSetup.start { _ in }.topViewController); setup.loadViewIfNeeded()
        XCTAssertTrue(buttons(in: setup.view).contains { $0.configuration?.title == "Use this device as a family member" })
    }

    @MainActor func testRemoteCaregiverModeShowsOnlyServerSettingsAndProtectsThisPhone() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": true, "people": [
            ["id": "me", "name": "Ethan", "role": "family", "permissions": ["audio": true, "video": false], "online": true, "caregiver": true],
            ["id": "sam", "name": "Sam", "role": "family", "permissions": ["audio": false, "video": false], "online": false, "caregiver": false]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        XCTAssertEqual(rows(in: admin.view).compactMap(\.accessibilityIdentifier).filter { $0.hasPrefix("caregiver.page.") },
                       ["caregiver.page.people", "caregiver.page.calls", "caregiver.page.dropIn", "caregiver.page.messages", "caregiver.page.privacy", "caregiver.page.caregivers", "caregiver.page.about"])
        for bedsideOnly in ["Keypad", "Display & voice", "Caregiver PIN"] {
            XCTAssertTrue(descendants(admin.view).contains { $0.accessibilityLabel == "\(bedsideOnly), set on the bedside iPad" }, bedsideOnly)
        }
        let family = PeopleSettingsViewController(admin: admin); family.loadViewIfNeeded()
        XCTAssertEqual(family.title, "Family")
        XCTAssertFalse(descendants(family.view).contains { $0.accessibilityIdentifier?.hasPrefix("keypad.key.") == true }, "The keypad is set on the bedside iPad")
        XCTAssertEqual(rows(in: family.view).filter { $0.accessibilityIdentifier?.hasPrefix("family.person.") == true }.count, 2)
        XCTAssertTrue(rows(in: family.view).contains { $0.accessibilityLabel == "Ethan (this phone). Porch is open. Audio drop-in · Caregiver." })
        XCTAssertTrue(rows(in: family.view).contains { $0.accessibilityLabel == "Sam. Offline. Calls only." })
        let caregivers = CaregiverAccessViewController(admin: admin); caregivers.loadViewIfNeeded()
        XCTAssertFalse(rows(in: caregivers.view).contains { $0.accessibilityLabel == "Change caregiver PIN" }, "The bedside iPad keeps the PIN it uses for renewals")
        func switches(_ view: UIView) -> [UISwitch] { descendants(view).compactMap { $0 as? UISwitch } }
        XCTAssertEqual(switches(caregivers.view).filter { !$0.isEnabled }.map(\.accessibilityLabel), ["Ethan is a caregiver"], "Another caregiver must change this phone's caregiver access")
        let messages = MessageSettingsViewController(admin: admin); messages.loadViewIfNeeded()
        XCTAssertFalse(switches(messages.view).contains { $0.accessibilityIdentifier == "messages.autoplay" }, "Starting messages by camera is set on the bedside iPad itself")
        let privacy = PrivacySettingsViewController(admin: admin); privacy.loadViewIfNeeded()
        XCTAssertFalse(switches(privacy.view).contains { $0.accessibilityIdentifier == "attendance.camera" }, "So is looking for someone at the iPad by camera")
        let share = try XCTUnwrap(switches(privacy.view).first { $0.accessibilityIdentifier == "attendance.share" }, "Sharing that someone is at the iPad is a server setting a phone can change")
        XCTAssertFalse(share.isEnabled, "An older server without the setting can't change it")
        let me = PersonViewController(admin: admin, memberID: "me"); me.loadViewIfNeeded()
        XCTAssertFalse(buttons(in: me.view).contains { $0.accessibilityIdentifier == "person.remove" }, "A caregiver can't remove their own phone here")
        XCTAssertFalse(descendants(me.view).contains { $0.accessibilityIdentifier == "person.key" }, "Keys are set on the bedside iPad")
        XCTAssertEqual(rows(in: me.view).compactMap(\.accessibilityIdentifier).filter { $0.hasPrefix("person.") }, ["person.row.name", "person.row.dropIn"])
        XCTAssertEqual(switches(me.view).filter { !$0.isEnabled }.map(\.accessibilityLabel), ["Caregiver mode"], "Another caregiver must change this phone's caregiver access")
        let sam = PersonViewController(admin: admin, memberID: "sam"); sam.loadViewIfNeeded()
        XCTAssertEqual(buttons(in: sam.view).filter { $0.configuration?.title == "Remove Sam" }.count, 1)
    }

    @MainActor func testPersonPageSetsPorchAppDropInsApart() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": true, "people": [
            ["id": "mia", "name": "Mia", "role": "family", "permissions": ["audio": true, "video": true], "online": true, "caregiver": false],
            ["id": "noa", "name": "Noa", "role": "family", "permissions": ["audio": false, "video": false], "online": true, "caregiver": false]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        let dropIn = DropInSettingsViewController(admin: admin); dropIn.loadViewIfNeeded()
        XCTAssertTrue(rows(in: dropIn.view).contains { $0.accessibilityLabel == "Mia, Porch app, Audio and video" })
        XCTAssertTrue(rows(in: dropIn.view).contains { $0.accessibilityLabel == "Noa, can't drop in" })
        let family = PeopleSettingsViewController(admin: admin); family.loadViewIfNeeded()
        XCTAssertTrue(rows(in: family.view).contains { $0.accessibilityLabel == "Mia. Porch is open. Audio and video drop-in." })
        func switches(_ view: UIView) -> [UISwitch] { descendants(view).compactMap { $0 as? UISwitch } }
        func texts(_ view: UIView) -> [String] { labels(in: view).compactMap(\.text) }
        let mia = PersonViewController(admin: admin, memberID: "mia")
        let navigation = UINavigationController(rootViewController: mia); mia.loadViewIfNeeded()
        let row = try XCTUnwrap(rows(in: mia.view).first { $0.accessibilityIdentifier == "person.row.dropIn" })
        XCTAssertEqual(row.accessibilityLabel, "Drop-in, Audio and video")
        XCTAssertTrue(switches(mia.view).filter { $0.accessibilityIdentifier?.hasSuffix("DropIn") == true }.isEmpty, "Drop-in has a screen of its own")
        row.sendActions(for: .touchUpInside)
        let screen = try XCTUnwrap(navigation.topViewController as? PersonDetailViewController); screen.loadViewIfNeeded()
        XCTAssertEqual(screen.title, "Drop-in")
        XCTAssertTrue(texts(screen.view).contains("Connects without Pat answering."))
        XCTAssertTrue(texts(screen.view).contains("Porch app"), "Porch app drop-ins are set apart from phone calls")
        XCTAssertEqual(switches(screen.view).filter { $0.accessibilityIdentifier?.hasSuffix("DropIn") == true }.map(\.accessibilityLabel), ["Audio drop-in", "Video drop-in"])
        let noa = PersonViewController(admin: admin, memberID: "noa"); noa.loadViewIfNeeded()
        XCTAssertEqual(rows(in: noa.view).first { $0.accessibilityIdentifier == "person.row.dropIn" }?.accessibilityLabel, "Drop-in, Off")
        // The Drop-in page opens someone's drop-in itself, rather than their whole page.
        let list = UINavigationController(rootViewController: dropIn)
        try XCTUnwrap(rows(in: dropIn.view).first { $0.accessibilityLabel == "Noa, can't drop in" }).sendActions(for: .touchUpInside)
        let noaDropIn = try XCTUnwrap(list.topViewController as? PersonDetailViewController); noaDropIn.loadViewIfNeeded()
        XCTAssertEqual(noaDropIn.title, "Noa")
        XCTAssertEqual(switches(noaDropIn.view).filter { $0.accessibilityIdentifier?.hasSuffix("DropIn") == true }.map(\.isOn), [false, false])
    }

    @MainActor func testCaregiverModeListsPhoneNumbersApprovedForDropIn() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": true, "people": [
            ["id": "mia", "name": "Mia", "role": "family", "permissions": ["audio": true, "video": true], "online": true, "caregiver": false]],
            "phoneDropIns": [["number": "+14155550200", "name": "David"]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        let dropIn = DropInSettingsViewController(admin: admin); dropIn.loadViewIfNeeded()
        XCTAssertTrue(labels(in: dropIn.view).compactMap(\.text).contains("\(PhoneNumberNormalization.display("+14155550200")) · By phone"))
        XCTAssertTrue(rows(in: dropIn.view).contains { $0.accessibilityLabel == "Mia, Porch app, Audio and video" }, "Approved family members are listed beside approved numbers")
        XCTAssertTrue(buttons(in: dropIn.view).compactMap { $0.configuration?.title }.contains("Add a phone number"))
        XCTAssertEqual(buttons(in: dropIn.view).filter { $0.accessibilityLabel == "Remove phone drop-in for David" }.count, 1)
    }

    @MainActor func testDropInPageAsksWhoAndEveryCallNeedsThePINAgain() throws {
        func state(_ extra: [String: Any]) throws -> FamilyAdminState {
            var object: [String: Any] = ["householdName": "Pat", "dropInEnabled": true, "people": [
                ["id": "mia", "name": "Mia", "role": "family", "permissions": ["audio": true, "video": false], "online": true, "caregiver": false]]]
            object.merge(extra) { $1 }
            return try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: try state([:])); admin.loadViewIfNeeded()
        let dropIn = DropInSettingsViewController(admin: admin)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(rootViewController: dropIn); window.makeKeyAndVisible()
        defer { window.isHidden = true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func choice(_ id: String) -> PorchListRow? { rows(in: dropIn.view).first { $0.accessibilityIdentifier == "dropIn.choice.\(id)" } }
        XCTAssertEqual(["off", "approved", "everyCall"].compactMap { choice($0)?.accessibilityLabel },
                       ["No one, Paused", "People you approve, Listed below", "Every call, Needs the PIN"])
        XCTAssertEqual(["off", "approved", "everyCall"].map { choice($0)?.accessibilityTraits.contains(.selected) }, [false, true, false])
        XCTAssertTrue(labels(in: dropIn.view).compactMap(\.text).contains("Can drop in"))
        XCTAssertFalse(labels(in: dropIn.view).compactMap(\.text).contains("Drop-ins connect on their own after a short announcement."), "The answers say it")
        // Every call warns first; the PIN is typed again on a page of its own.
        try XCTUnwrap(choice("everyCall")).sendActions(for: .touchUpInside)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let alert = try XCTUnwrap(dropIn.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, "Let every call drop in?")
        XCTAssertEqual(alert.message, "Anyone who calls will connect without Pat answering, unknown numbers too.")
        XCTAssertEqual(alert.actions.map(\.title), ["Cancel", "Continue"])
        XCTAssertEqual(alert.actions.last?.style, .destructive)
        alert.dismiss(animated: false)
        let pin = EveryCallPINViewController(admin: admin, unknownNumbers: false); pin.loadViewIfNeeded()
        XCTAssertEqual(pin.title, "Every call")
        XCTAssertTrue(labels(in: pin.view).compactMap(\.text).contains("Every call will drop in."), "Unknown numbers are named only while they can ring")
        XCTAssertTrue(descendants(pin.view).contains { $0.accessibilityIdentifier == "everyCall.pin" && ($0 as? UITextField)?.isSecureTextEntry == true })
        XCTAssertEqual(buttons(in: pin.view).first { $0.accessibilityIdentifier == "everyCall.turnOn" }?.configuration?.title, "Turn on")
        // On: the answer is red with who and when, approvals wait, and the caregiver menu says so.
        let on = FamilyAdminViewController(remote: remote, state: try state(["everyCall": ["by": "Tom Reyes", "at": Date().timeIntervalSince1970]]))
        on.loadViewIfNeeded()
        let onPage = DropInSettingsViewController(admin: on); onPage.loadViewIfNeeded()
        let everyCall = try XCTUnwrap(rows(in: onPage.view).first { $0.accessibilityIdentifier == "dropIn.choice.everyCall" })
        XCTAssertTrue(everyCall.accessibilityLabel?.hasPrefix("Every call, On · Tom, ") == true, everyCall.accessibilityLabel ?? "")
        XCTAssertTrue(everyCall.accessibilityTraits.contains(.selected))
        XCTAssertTrue(labels(in: onPage.view).compactMap(\.text).contains("Saved approvals"))
        XCTAssertTrue(rows(in: on.view).contains { $0.accessibilityLabel == "Drop-in, Every call" })
        let mia = PersonViewController(admin: on, memberID: "mia"); mia.loadViewIfNeeded()
        XCTAssertEqual(rows(in: mia.view).first { $0.accessibilityIdentifier == "person.row.dropIn" }?.accessibilityLabel, "Drop-in, Every call")
        // No one: paused.
        let off = FamilyAdminViewController(remote: remote, state: try state(["dropInEnabled": false])); off.loadViewIfNeeded()
        XCTAssertTrue(rows(in: off.view).contains { $0.accessibilityLabel == "Drop-in, Off" })
    }

    @MainActor func testCaregiverModeBlocksUnknownCallersAndListsBlockedNumbersSeparately() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": false, "people": [],
            "callScreening": ["enabled": true, "keypadNumbers": ["+14155550100"],
                "allowed": [["number": "+14155550300", "allowedAt": 1_800_000_000]],
                "blocked": [["number": "+14155550999", "firstCallAt": 1_800_000_000, "lastCallAt": 1_800_000_060, "calls": 2]]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        let calls = CallSettingsViewController(admin: admin)
        let navigation = UINavigationController(rootViewController: calls); calls.loadViewIfNeeded()
        XCTAssertEqual(calls.title, "Calls")
        func switches(_ view: UIView) -> [UISwitch] { descendants(view).compactMap { $0 as? UISwitch } }
        let block = try XCTUnwrap(switches(calls.view).first { $0.accessibilityIdentifier == "calls.blockUnknown" })
        XCTAssertTrue(block.isOn); XCTAssertTrue(block.isEnabled)
        XCTAssertFalse(descendants(calls.view).contains { $0.accessibilityIdentifier == "calls.silence" }, "Hanging up after silence is set on the bedside iPad")
        let list = try XCTUnwrap(rows(in: calls.view).first { $0.accessibilityIdentifier == "calls.blockedNumbers" })
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
        let olderCalls = CallSettingsViewController(admin: older); olderCalls.loadViewIfNeeded()
        XCTAssertEqual(switches(olderCalls.view).first { $0.accessibilityIdentifier == "calls.blockUnknown" }?.isEnabled, false)
    }

    @MainActor func testPendingInvitationsAreListedByNameAndCancelledOneAtATime() throws {
        let data = try JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": false, "people": [],
            "invitations": [["id": "a", "name": "Ana", "expiresAt": 1_800_000_900], ["id": "b", "expiresAt": 1_800_000_900]]])
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: data)
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        let family = PeopleSettingsViewController(admin: admin); family.loadViewIfNeeded()
        let cancels = buttons(in: family.view).compactMap(\.accessibilityLabel).filter { $0.hasPrefix("Cancel invitation") }
        XCTAssertEqual(cancels, ["Cancel invitation for Ana", "Cancel invitation for Invitation"])
        XCTAssertFalse(buttons(in: family.view).contains { $0.configuration?.title == "Cancel unused invitations" })
    }

    @MainActor func testInvitationCreatedFromAPhoneAppearsInTheList() throws {
        let decode = { (json: [String: Any]) in try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: json)) }
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        let admin = FamilyAdminViewController(remote: remote, state: try decode(["householdName": "Pat", "dropInEnabled": false, "people": []]))
        admin.loadViewIfNeeded()
        let family = PeopleSettingsViewController(admin: admin)
        let navigation = UINavigationController(rootViewController: family); family.loadViewIfNeeded()
        buttons(in: family.view).first { $0.configuration?.title == "Invite someone" }!.sendActions(for: .touchUpInside)
        let invite = try XCTUnwrap(navigation.topViewController as? FamilyInviteViewController)
        XCTAssertTrue(descendants(invite.view).contains { ($0 as? UILabel)?.text == FamilyInviteViewController.keypadHint },
            "An invitation from People finds its key by name, so it says to use the name on their key")
        invite.onAdminChanged?(try decode(["householdName": "Pat", "dropInEnabled": false, "people": [], "invitations": [["id": "a", "name": "Ana", "expiresAt": 1_800_000_900]]]))
        XCTAssertTrue(buttons(in: family.view).contains { $0.accessibilityLabel == "Cancel invitation for Ana" }, "Caregiver mode on a phone keeps its own state, so it must take the one createInvite returns")
    }

    @MainActor func testFirstTapOnGearOpensCaregiverGate() async {
        let original = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: original.windowScene!)
        let clock = CallViewController(); window.rootViewController = clock; window.makeKeyAndVisible()
        defer { window.isHidden = true; original.makeKeyAndVisible() }
        let gear = buttons(in: clock.view).first { $0.accessibilityIdentifier == "clock.caregiver" }!
        gear.sendActions(for: .touchUpInside)
        // This iPad isn't set up, so the button starts setup rather than asking for a PIN.
        XCTAssertTrue((clock.presentedViewController as? UINavigationController)?.topViewController is BedsideSetupStep)
        await withCheckedContinuation { continuation in clock.dismiss(animated: false) { continuation.resume() } }
    }

    @MainActor func testEveryKeyIsOnTheKeypadGridWithDefaultControlsAndCanBeRemapped() throws {
        let home = FamilyAdminViewController(slots: CallSlots())
        let people = PeopleSettingsViewController(admin: home)
        let navigation = UINavigationController(rootViewController: people); people.loadViewIfNeeded()
        let keys = descendants(people.view).filter { $0.accessibilityIdentifier?.hasPrefix("keypad.key.") == true }
        XCTAssertEqual(keys.compactMap(\.accessibilityIdentifier), ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"].map { "keypad.key.\($0)" }, "Laid out as the keypad is")
        XCTAssertEqual(keys.first { $0.accessibilityIdentifier == "keypad.key.9" }?.accessibilityLabel, "Key 9, Turn video off / on")
        XCTAssertEqual(keys.first { $0.accessibilityIdentifier == "keypad.key.0" }?.accessibilityLabel, "Key 0, Answer / decline / hang up")
        XCTAssertEqual(keys.first { $0.accessibilityIdentifier == "keypad.key.0" }?.accessibilityValue, "Hold to decline")
        XCTAssertEqual(keys.first { $0.accessibilityIdentifier == "keypad.key.5" }?.accessibilityLabel, "Key 5, No action")
        try XCTUnwrap(keys.first { $0.accessibilityIdentifier == "keypad.key.5" } as? UIControl).sendActions(for: .touchUpInside)
        let empty = try XCTUnwrap(navigation.topViewController as? AddWhoViewController, "An empty key asks who goes on it")
        empty.loadViewIfNeeded()
        XCTAssertEqual(empty.title, "Key 5")
        navigation.popToRootViewController(animated: false)
        try XCTUnwrap(keys.first { $0.accessibilityIdentifier == "keypad.key.9" } as? UIControl).sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.topViewController is KeyActionViewController, "A key with a control on it opens what it does")
        let action = KeyActionViewController(admin: home, key: 4, offersSomeone: true)
        let actions = UINavigationController(rootViewController: people); actions.pushViewController(action, animated: false)
        action.loadViewIfNeeded()
        XCTAssertEqual(rows(in: action.view).compactMap(\.accessibilityIdentifier), ["keypad.action.person", "keypad.action.callControl", "keypad.action.toggleVideo", "keypad.action.messages", "keypad.action.unassigned"])
        rows(in: action.view).first { $0.accessibilityIdentifier == "keypad.action.callControl" }!.sendActions(for: .touchUpInside)
        buttons(in: action.view).first { $0.accessibilityIdentifier == "keypad.action.save" }!.sendActions(for: .touchUpInside)
        XCTAssertEqual(home.slots?.action(for: 4), .callControl, "A control can be saved on any digit without a person's name or phone number")
    }

    // MARK: Add someone

    @MainActor private func addSomeoneHome(people: [[String: Any]] = []) throws -> (FamilyAdminViewController, PeopleSettingsViewController, UINavigationController) {
        let home = FamilyAdminViewController(slots: CallSlots())
        let page = PeopleSettingsViewController(admin: home)
        let navigation = UINavigationController(rootViewController: page)
        page.loadViewIfNeeded(); home.loadViewIfNeeded()
        return (home, page, navigation)
    }
    @MainActor private func texts(_ view: UIView) -> [String] { labels(in: view).filter { !$0.isHidden && $0.superview?.isHidden != true }.compactMap(\.text) }

    @MainActor func testAddSomeoneStartsFromAnEmptyKeyOrFromPeopleOnTheFirstFreeKey() throws {
        let (_, page, navigation) = try addSomeoneHome()
        try XCTUnwrap(descendants(page.view).first { $0.accessibilityIdentifier == "keypad.key.5" } as? UIControl).sendActions(for: .touchUpInside)
        let fromKey = try XCTUnwrap(navigation.topViewController as? AddWhoViewController)
        fromKey.loadViewIfNeeded()
        XCTAssertEqual(fromKey.title, "Key 5")
        XCTAssertTrue(texts(fromKey.view).contains("Who goes on key 5?"))
        XCTAssertTrue(buttons(in: fromKey.view).contains { $0.accessibilityIdentifier == "add.somethingElse" && $0.configuration?.title == "Use key 5 for something else" })
        XCTAssertEqual(descendants(fromKey.view).first { $0.accessibilityIdentifier == "add.progress" }?.accessibilityLabel, "Step 1 of 3")
        navigation.popToRootViewController(animated: false)
        let add = try XCTUnwrap(buttons(in: page.view).first { $0.accessibilityIdentifier == "family.addSomeone" })
        XCTAssertEqual(add.configuration?.title, "Add someone", "The bedside adds people; only a phone invites")
        add.sendActions(for: .touchUpInside)
        let fromPeople = try XCTUnwrap(navigation.topViewController as? AddWhoViewController)
        fromPeople.loadViewIfNeeded()
        XCTAssertEqual(fromPeople.title, "Add someone")
        XCTAssertTrue(texts(fromPeople.view).contains("Who are you adding?"))
        XCTAssertEqual(fromPeople.draft.key, 1, "The first free key in keypad order")
        XCTAssertFalse(buttons(in: fromPeople.view).contains { $0.accessibilityIdentifier == "add.somethingElse" })
        var slots = CallSlots()
        for digit in [1, 2, 3, 4, 5, 6, 7, 8] { try slots.setAction(.messages, for: digit) }
        XCTAssertEqual(AddSomeoneDraft.firstFreeKey(slots), CallSlots.star, "After 9 comes *, then 0 and #, as the keypad reads")
        for digit in [CallSlots.star, CallSlots.pound] { try slots.setAction(.messages, for: digit) }
        XCTAssertNil(AddSomeoneDraft.firstFreeKey(slots))
    }

    @MainActor func testAddSomeoneAsksForANameThenHowToReachThemAndChecksTheNumber() throws {
        let (home, _, navigation) = try addSomeoneHome()
        let who = AddWhoViewController(admin: home, draft: AddSomeoneDraft(key: 5, fromKeyTile: true))
        navigation.pushViewController(who, animated: false); who.loadViewIfNeeded()
        let next = try XCTUnwrap(buttons(in: who.view).first { $0.accessibilityIdentifier == "add.next" })
        XCTAssertFalse(next.isEnabled, "A name comes first")
        let name = try XCTUnwrap(descendants(who.view).first { $0.accessibilityIdentifier == "add.name" } as? UITextField)
        name.text = "Linda Park"; name.sendActions(for: .editingChanged)
        XCTAssertTrue(next.isEnabled)
        next.sendActions(for: .touchUpInside)
        let reach = try XCTUnwrap(navigation.topViewController as? AddReachViewController)
        reach.loadViewIfNeeded()
        XCTAssertTrue(texts(reach.view).contains("How should your loved one reach Linda?"))
        XCTAssertTrue(texts(reach.view).contains("Video calls, photos and messages"))
        rows(in: reach.view).first { $0.accessibilityIdentifier == "add.viaPhone" }!.sendActions(for: .touchUpInside)
        let number = try XCTUnwrap(descendants(reach.view).first { $0.accessibilityIdentifier == "add.phoneNumber" } as? UITextField)
        number.text = "555"
        buttons(in: reach.view).first { $0.accessibilityIdentifier == "add.next" }!.sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.topViewController === reach, "A number Porch can't read stays on this step")
        XCTAssertTrue(texts(reach.view).contains("Check this number. For other countries, start with +."))
        number.text = "+1 415 555 0142"
        buttons(in: reach.view).first { $0.accessibilityIdentifier == "add.next" }!.sendActions(for: .touchUpInside)
        let check = try XCTUnwrap(navigation.topViewController as? AddCheckViewController)
        check.loadViewIfNeeded(); check.viewWillAppear(false)
        XCTAssertEqual(check.draft.numbers, ["+14155550142"])
        XCTAssertTrue(texts(check.view).contains("Check key 5"))
        XCTAssertTrue(texts(check.view).contains("Press 5"))
        XCTAssertEqual(rows(in: check.view).compactMap(\.accessibilityIdentifier), ["add.row.phone", "add.row.key"], "Porch app only shows when they're invited")
        XCTAssertEqual(buttons(in: check.view).first { $0.accessibilityIdentifier == "add.save" }?.configuration?.title, "Add to key 5")
        XCTAssertEqual(descendants(check.view).filter { $0.accessibilityIdentifier?.hasPrefix("add.color.") == true }.map(\.accessibilityLabel),
                       ["Default color", "Blue", "Teal", "Orange", "Red", "Purple"])
    }

    @MainActor func testAddSomeoneReachStepShowsNumbersChangedOnTheCheckScreen() throws {
        let (home, _, navigation) = try addSomeoneHome()
        let draft = AddSomeoneDraft(key: 5, fromKeyTile: true)
        draft.name = "Linda Park"; draft.numbers = ["+14155550142"]
        let reach = AddReachViewController(admin: home, draft: draft)
        navigation.pushViewController(reach, animated: false); reach.loadViewIfNeeded(); reach.viewWillAppear(false)
        // On Check's Phone screen they add another number and make it the one Porch calls, then come back here.
        draft.numbers = ["+14155550198", "+14155550142"]
        reach.viewWillAppear(false)
        let number = try XCTUnwrap(descendants(reach.view).first { $0.accessibilityIdentifier == "add.phoneNumber" } as? UITextField)
        XCTAssertEqual(try PhoneNumberNormalization.e164(number.text ?? ""), "+14155550198")
        buttons(in: reach.view).first { $0.accessibilityIdentifier == "add.next" }!.sendActions(for: .touchUpInside)
        XCTAssertEqual(draft.numbers, ["+14155550198", "+14155550142"], "Next without changes keeps both numbers and the one Porch calls")
    }

    @MainActor func testAddSomeoneInvitationShowsDropInOnItsRowAndPhoneNumbersCanBeReordered() throws {
        let (home, _, navigation) = try addSomeoneHome()
        let draft = AddSomeoneDraft(key: 5, fromKeyTile: true)
        draft.name = "Linda Park"; draft.viaApp = true; draft.numbers = ["+14155550142", "+14155550198"]
        let check = AddCheckViewController(admin: home, draft: draft)
        navigation.pushViewController(check, animated: false); check.loadViewIfNeeded(); check.viewWillAppear(false)
        XCTAssertEqual(rows(in: check.view).first { $0.accessibilityIdentifier == "add.row.app" }?.accessibilityLabel, "Porch app, Drop-in on")
        XCTAssertTrue(rows(in: check.view).first { $0.accessibilityIdentifier == "add.row.phone" }?.accessibilityLabel?.hasSuffix(" +1") == true)
        let numbers = AddPhoneNumbersViewController(admin: home, draft: draft)
        navigation.pushViewController(numbers, animated: false); numbers.loadViewIfNeeded()
        XCTAssertTrue(texts(numbers.view).contains("Porch calls"))
        XCTAssertTrue(texts(numbers.view).contains("All of these can call your loved one."))
        rows(in: numbers.view).first { $0.accessibilityIdentifier == "add.number.1" }!.sendActions(for: .touchUpInside)
        XCTAssertEqual(draft.numbers, ["+14155550198", "+14155550142"], "Tapping a number makes it the one Porch calls")
        let field = try XCTUnwrap(descendants(numbers.view).first { $0.accessibilityIdentifier == "add.newNumber" } as? UITextField)
        field.text = "+1 415 555 0198"
        buttons(in: numbers.view).first { $0.accessibilityIdentifier == "add.addNumber" }!.sendActions(for: .touchUpInside)
        XCTAssertTrue(texts(numbers.view).contains("That number is already saved for them."))
        let app = AddPorchAppViewController(admin: home, draft: draft)
        navigation.pushViewController(app, animated: false); app.loadViewIfNeeded()
        XCTAssertTrue(texts(app.view).contains("Connects without your loved one answering."))
        let audio = try XCTUnwrap(descendants(app.view).first { $0.accessibilityIdentifier == "add.audioDropIn" } as? UISwitch)
        audio.isOn = false; audio.sendActions(for: .valueChanged)
        XCTAssertEqual(AddSomeoneDraft.dropInSummary(audio: draft.dropInAudio, video: draft.dropInVideo), "Video drop-in")
        let key = AddKeyViewController(admin: home, draft: draft)
        navigation.pushViewController(key, animated: false); key.loadViewIfNeeded()
        XCTAssertFalse(buttons(in: key.view).contains { $0.accessibilityIdentifier == "add.noKey" }, "A phone number needs a key")
        XCTAssertFalse(try XCTUnwrap(descendants(key.view).first { $0.accessibilityIdentifier == "add.key.9" } as? UIControl).isEnabled, "Keys in use can't be chosen")
        draft.numbers = []
        let appOnly = AddKeyViewController(admin: home, draft: draft)
        navigation.pushViewController(appOnly, animated: false); appOnly.loadViewIfNeeded()
        buttons(in: appOnly.view).first { $0.accessibilityIdentifier == "add.noKey" }!.sendActions(for: .touchUpInside)
        XCTAssertNil(draft.key, "Someone only on the Porch app can be left off the keypad")
    }

    @MainActor func testAddSomeoneAlreadyOnPorchSkipsHowToReachThemAndGoesOnTheKey() async throws {
        let (home, _, navigation) = try addSomeoneHome()
        let person = try JSONDecoder().decode(FamilyPerson.self, from: JSONSerialization.data(withJSONObject: [
            "id": "6B1F7C3A-2D5E-4F8A-9C0B-1E2D3F4A5B6C", "name": "Tom Reyes", "role": "family", "permissions": ["audio": true, "video": true], "online": true]))
        let draft = AddSomeoneDraft(key: 5, fromKeyTile: true)
        draft.member = person; draft.name = person.name; draft.viaApp = true
        let check = AddCheckViewController(admin: home, draft: draft)
        navigation.pushViewController(check, animated: false); check.loadViewIfNeeded(); check.viewWillAppear(false)
        XCTAssertEqual(rows(in: check.view).first { $0.accessibilityIdentifier == "add.row.app" }?.accessibilityLabel, "Porch app, Connected")
        XCTAssertEqual(rows(in: check.view).first { $0.accessibilityIdentifier == "add.row.phone" }?.accessibilityLabel, "Phone, Add")
        XCTAssertFalse(buttons(in: check.view).contains { $0.accessibilityIdentifier == "add.photo" }, "Their own Porch photo is used")
        let link = try await AddCheckViewController.add(draft, admin: home)
        XCTAssertNil(link, "Someone already on Porch needs no invitation")
        let contact = try XCTUnwrap(home.slots?.contact(for: 5))
        XCTAssertEqual(home.slots?.action(for: 5), .person)
        XCTAssertEqual(contact.familyMemberID, person.id)
        XCTAssertEqual(contact.name, "Tom Reyes")
        XCTAssertEqual(contact.nativeCall?.mode, .video)
        XCTAssertNil(contact.phoneNumber)
    }

    @MainActor func testAnInvitationIsReusedOnlyForTheSamePersonAndDropIn() async throws {
        let (home, _, _) = try addSomeoneHome()
        let draft = AddSomeoneDraft(key: 5, fromKeyTile: true)
        draft.name = "Linda Park"
        draft.viaApp = true
        draft.dropInAudio = true
        draft.dropInVideo = false
        let link = URL(string: "https://helloporch.store/join#code=abc")!
        let id = "99999999-8888-4777-8666-555555555555"
        draft.invitation = .init(id: id, link: link, name: "Linda Park", audio: true, video: false)
        XCTAssertEqual(draft.reusableInvitation()?.id, id)
        draft.dropInVideo = true
        XCTAssertNil(draft.reusableInvitation(), "Drop-in is part of the invitation")
        draft.dropInVideo = false
        draft.name = "David"
        XCTAssertNil(draft.reusableInvitation(), "A different person needs their own invitation")
        draft.name = "Linda Park"
        draft.viaApp = false
        XCTAssertNil(draft.reusableInvitation(), "Phone only doesn't keep the invitation")
        draft.viaApp = true
        let returned = try await AddCheckViewController.add(draft, admin: home)
        XCTAssertEqual(returned, link, "The same name and drop-in reuse the invitation already made")
        XCTAssertEqual(home.slots?.contact(for: 5)?.invitationID, id)
        XCTAssertEqual(home.slots?.contact(for: 5)?.customName, "")

        let person = try JSONDecoder().decode(FamilyPerson.self, from: JSONSerialization.data(withJSONObject: [
            "id": "6B1F7C3A-2D5E-4F8A-9C0B-1E2D3F4A5B6C", "name": "Tom Reyes", "role": "family", "permissions": ["audio": true, "video": true], "online": true]))
        let member = AddSomeoneDraft(key: 4, fromKeyTile: true)
        member.member = person
        member.name = person.name
        member.viaApp = true
        member.invitation = draft.invitation
        let memberLink = try await AddCheckViewController.add(member, admin: home)
        XCTAssertNil(memberLink, "Someone already on Porch isn't shown an invitation made for someone else")
        let saved = try XCTUnwrap(home.slots?.contact(for: 4))
        XCTAssertEqual(saved.familyMemberID, person.id)
        XCTAssertNil(saved.invitationID)
        XCTAssertEqual(saved.name, "Tom Reyes")
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
        // Settings and the list of families are on the You tab, not behind a button on Call.
        XCTAssertNil(home.navigationItem.rightBarButtonItem)
        let pairing = FamilyPairingViewController(); pairing.loadViewIfNeeded()
        XCTAssertTrue(labels(pairing.view).contains("Your Porch invite"))
        let draft = AddSomeoneDraft(key: 1, fromKeyTile: true); draft.name = "David"; draft.viaApp = true
        let app = AddPorchAppViewController(admin: FamilyAdminViewController(slots: CallSlots()), draft: draft); app.loadViewIfNeeded()
        func segments(_ view: UIView) -> [UISegmentedControl] { (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap(segments) }
        let mode = segments(app.view).first { $0.accessibilityLabel == "Calls start with" }
        XCTAssertEqual(mode?.titleForSegment(at: 0), "Voice")
        XCTAssertEqual(mode?.selectedSegmentIndex, 1, "Calls in the app start with video")
    }

    @MainActor func testSomeoneOnlyOnTheKeypadKeepsTheNameSavedWithTheirKey() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "test", mode: .voice), phoneNumber: "+14155550123"), for: 2)
        let home = FamilyAdminViewController(slots: slots)
        var saved: CallSlots?
        home.onSaveSlots = { saved = $0 }
        let person = PersonViewController(admin: home, slot: 2)
        let navigation = UINavigationController(rootViewController: person); person.loadViewIfNeeded()
        func row(_ id: String) -> PorchListRow? { rows(in: person.view).first { $0.accessibilityIdentifier == id } }
        XCTAssertEqual(rows(in: person.view).compactMap(\.accessibilityIdentifier).filter { $0.hasPrefix("person.") },
                       ["person.row.name", "person.row.app", "person.phone", "person.key"], "One row for each thing about them")
        // The name is changed on a screen of its own, and Save goes back to their page.
        try XCTUnwrap(row("person.row.name")).sendActions(for: .touchUpInside)
        let nameScreen = try XCTUnwrap(navigation.topViewController as? PersonDetailViewController); nameScreen.loadViewIfNeeded()
        XCTAssertEqual(nameScreen.title, "Name")
        let name = try XCTUnwrap(descendants(nameScreen.view).compactMap { $0 as? UITextField }.first { $0.accessibilityIdentifier == "person.name" })
        XCTAssertEqual(name.text, "David")
        name.text = "David Chen"
        try XCTUnwrap(buttons(in: nameScreen.view).first { $0.accessibilityIdentifier == "person.saveName" }).sendActions(for: .touchUpInside)
        XCTAssertEqual(saved?.contact(for: 2)?.name, "David Chen")
        XCTAssertEqual(person.title, "David Chen")
        XCTAssertTrue(navigation.topViewController === person)
        XCTAssertEqual(row("person.row.name")?.accessibilityLabel, "Name, David Chen")
        nameScreen.render()
        XCTAssertEqual(name.constraints.filter { $0.firstAttribute == .height }.count, 1, "redrawing doesn't add to the name field's constraints")
        XCTAssertEqual(name.autocapitalizationType, .words, "and keeps names capitalized")
        // Someone not on Porch can be invited from the Porch app row.
        XCTAssertEqual(row("person.row.app")?.accessibilityLabel, "Porch app, Invite")
        try XCTUnwrap(row("person.row.app")).sendActions(for: .touchUpInside)
        let app = try XCTUnwrap(navigation.topViewController as? PersonDetailViewController); app.loadViewIfNeeded()
        XCTAssertEqual(app.title, "Porch app")
        XCTAssertTrue(buttons(in: app.view).contains { $0.configuration?.title == "Invite David" })
        XCTAssertFalse(descendants(app.view).contains { $0.accessibilityIdentifier == "person.callMode" }, "Calls start in the app only once they're on Porch")
        navigation.popToViewController(person, animated: false)
        XCTAssertFalse(descendants(person.view).contains { $0.accessibilityIdentifier == "person.caregiver" }, "Caregiver mode is for family members on Porch")
        XCTAssertEqual(buttons(in: person.view).filter { $0.configuration?.title == "Remove David" }.count, 1)
        // Their phone numbers open in the same Phone screen Add someone uses.
        XCTAssertEqual(row("person.phone")?.accessibilityLabel, "Phone, \(PhoneNumberNormalization.display("+14155550123"))")
        try XCTUnwrap(row("person.phone")).sendActions(for: .touchUpInside)
        let numbers = try XCTUnwrap(navigation.topViewController as? AddPhoneNumbersViewController)
        numbers.loadViewIfNeeded()
        XCTAssertEqual(numbers.title, "Phone")
        XCTAssertEqual(numbers.draft.numbers, ["+14155550123"])
        func visible(_ view: UIView) -> Bool { sequence(first: view, next: \.superview).allSatisfy { !$0.isHidden } }
        XCTAssertTrue(visible(try XCTUnwrap(buttons(in: numbers.view).first { $0.accessibilityIdentifier == "add.numberFromContacts" })))
        // Someone on the keypad only by phone can't be left without a number.
        buttons(in: numbers.view).first { $0.accessibilityLabel == "Remove (415) 555-0123" }!.sendActions(for: .touchUpInside)
        saved = nil
        buttons(in: numbers.view).first { $0.accessibilityIdentifier == "add.doneNumbers" }!.sendActions(for: .touchUpInside)
        XCTAssertTrue(texts(numbers.view).contains("Add a number so Porch can reach David."))
        XCTAssertNil(saved, "nothing is saved")
        XCTAssertTrue(navigation.topViewController === numbers)
    }

    /// Someone on Porch can have their numbers removed from their page; the rest of their key stays as it was.
    @MainActor func testSavingNumbersFromSomeonesPageKeepsTheRestOfTheirKey() async throws {
        let member = UUID().uuidString
        let contact = try CallContact(name: "", nativeCall: NativeCall(room: "contact-abc", mode: .voice), phoneNumber: "+14155550123",
                                      otherPhoneNumbers: ["+14155550199"], familyMemberID: member, memberName: "Tom", buttonColorHex: "1565C0")
        var slots = CallSlots(); try slots.setContact(contact, for: 4)
        let home = FamilyAdminViewController(slots: slots)
        try await AddPhoneNumbersViewController.save([], to: 4, replacing: contact, admin: home)
        let saved = try XCTUnwrap(home.slots?.contact(for: 4))
        XCTAssertEqual(saved.phoneNumbers, [])
        XCTAssertEqual(saved.familyMemberID, member)
        XCTAssertEqual(saved.name, "Tom")
        XCTAssertEqual(saved.nativeCall?.room, "contact-abc")
        XCTAssertEqual(saved.nativeCall?.mode, .voice)
        XCTAssertEqual(saved.buttonColorHex, "1565C0")
    }

    /// Moving someone to another key keeps their page open, now showing that key.
    @MainActor func testMovingSomeoneToAnotherKeyKeepsTheirPageOpen() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "test", mode: .voice), phoneNumber: "+14155550123"), for: 2)
        let home = FamilyAdminViewController(slots: slots)
        var saved: CallSlots?
        home.onSaveSlots = { saved = $0 }
        let navigation = UINavigationController(rootViewController: UIViewController())
        let person = PersonViewController(admin: home, slot: 2)
        navigation.pushViewController(person, animated: false); person.loadViewIfNeeded()
        func keyRow() -> UIControl? { rows(in: person.view).first { $0.accessibilityIdentifier == "person.key" } }
        XCTAssertEqual(keyRow()?.accessibilityLabel, "Key, 2")
        try XCTUnwrap(keyRow()).sendActions(for: .touchUpInside)
        let keys = try XCTUnwrap(navigation.topViewController as? AddKeyViewController); keys.loadViewIfNeeded()
        func tile(_ key: String) -> UIControl? { descendants(keys.view).compactMap { $0 as? UIControl }.first { $0.accessibilityIdentifier == "add.key.\(key)" } }
        XCTAssertEqual(tile("2")?.accessibilityValue, "Chosen", "Their own key is chosen to start with")
        XCTAssertTrue(buttons(in: keys.view).contains { $0.accessibilityIdentifier == "person.takeOffKeypad" })
        XCTAssertFalse(buttons(in: keys.view).contains { $0.accessibilityIdentifier == "add.noKey" })
        try XCTUnwrap(tile("3")).sendActions(for: .touchUpInside)
        try XCTUnwrap(buttons(in: keys.view).first { $0.accessibilityIdentifier == "add.doneKey" }).sendActions(for: .touchUpInside)
        XCTAssertNil(saved?.contact(for: 2))
        XCTAssertEqual(saved?.contact(for: 3)?.name, "David")
        XCTAssertTrue(navigation.topViewController === person, "their page stays open")
        XCTAssertEqual(keyRow()?.accessibilityLabel, "Key, 3")
        XCTAssertEqual(descendants(person.view).first { $0.accessibilityIdentifier == "person.preview" }?.accessibilityLabel, "David, press 3")
    }

    /// Someone removed while one of their screens is open, such as by another caregiver, takes their page with them, so
    /// Back doesn't land on an empty page.
    @MainActor func testRemovingSomeoneWhileTheirKeyScreenIsOpenClosesTheirPage() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "test", mode: .voice), phoneNumber: "+14155550123"), for: 2)
        let home = FamilyAdminViewController(slots: slots)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // Pushing and popping animate in a window, so each step waits for the last to finish.
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.8)) }
        let person = PersonViewController(admin: home, slot: 2)
        navigation.pushViewController(person, animated: false); settle()
        try XCTUnwrap(rows(in: person.view).first { $0.accessibilityIdentifier == "person.key" }).sendActions(for: .touchUpInside); settle()
        XCTAssertTrue(navigation.topViewController is AddKeyViewController)
        try home.saveSlots { try $0.setContact(nil, for: 2) }; settle()
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertFalse(navigation.viewControllers.contains(person))
    }

    /// An invitation's expiry reads after "Expires", so a relative day isn't capitalized.
    @MainActor func testInviteExpiryReadsAfterExpires() {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date().addingTimeInterval(86_400))!
        XCTAssertTrue(PersonViewController.expiry(noon.timeIntervalSince1970).hasPrefix("tomorrow"))
    }

    /// Someone on the keypad by phone who joined Porch another way can be linked to it, keeping their key's numbers and color.
    @MainActor func testLinkingAPhoneKeyToSomeoneOnPorchKeepsItsNumbers() throws {
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "test", mode: .video), phoneNumber: "+14155550123",
                                         otherPhoneNumbers: ["+14155550199"], buttonColorHex: "FFCC00"), for: 2)
        let home = FamilyAdminViewController(slots: slots)
        var saved: CallSlots?
        home.onSaveSlots = { saved = $0 }
        let person = PersonViewController(admin: home, slot: 2); person.loadViewIfNeeded()
        let id = UUID().uuidString
        person.link(to: try JSONDecoder().decode(FamilyPerson.self, from: JSONSerialization.data(withJSONObject: [
            "id": id, "name": "David Chen", "role": "family", "permissions": ["audio": false, "video": false], "online": true])))
        let key = try XCTUnwrap(saved?.contact(for: 2))
        XCTAssertEqual(key.familyMemberID, id)
        XCTAssertEqual(key.name, "David Chen", "they go by their Porch name")
        XCTAssertEqual(key.phoneNumbers, ["+14155550123", "+14155550199"])
        XCTAssertEqual(key.nativeCall?.room, "test")
        XCTAssertEqual(key.nativeCall?.mode, .video)
        XCTAssertEqual(key.buttonColorHex, "FFCC00")
    }

    /// On a caregiver's phone, a family member's photo shows on their page once it has downloaded.
    @MainActor func testRemoteCaregiverModeShowsAPhotoOnceItDownloads() throws {
        let photo = portraitData(), id = ContactPhotoStore.id(for: photo)
        let file = FamilyPhotos.shared.store.directoryURL.appendingPathComponent(id).appendingPathExtension("jpg")
        try? FileManager.default.removeItem(at: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let state = try JSONDecoder().decode(FamilyAdminState.self, from: JSONSerialization.data(withJSONObject: ["householdName": "Pat", "dropInEnabled": false, "people": [
            ["id": "sam", "name": "Sam", "role": "family", "photoID": id, "permissions": ["audio": false, "video": false], "online": true]]]))
        let remote = FamilyCredential(origin: URL(string: "https://porch.example")!, credential: "me.secret", role: .family)
        RemoteCaregiverSession.shared.begin(pin: "123456")
        defer { RemoteCaregiverSession.shared.end() }
        let admin = FamilyAdminViewController(remote: remote, state: state); admin.loadViewIfNeeded()
        let sam = PersonViewController(admin: admin, memberID: "sam"); sam.loadViewIfNeeded()
        func photoButton() -> String? { buttons(in: sam.view).first { $0.accessibilityIdentifier == "person.choosePhoto" }?.configuration?.title }
        XCTAssertEqual(photoButton(), "Photo")
        try FamilyPhotos.shared.store.add(photo)
        NotificationCenter.default.post(name: .porchFamilyChanged, object: nil)
        XCTAssertEqual(photoButton(), "Change photo")
    }

    @MainActor func testWideIPadShowsThePageBesideTheList() throws {
        let home = FamilyAdminViewController(slots: CallSlots())
        let split = CaregiverSplitViewController(home: home)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        window.rootViewController = split; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        // A phone always shows one page at a time.
        guard !split.isCollapsed else { return }
        func detail() -> UIViewController? { (split.viewController(for: .secondary) as? UINavigationController)?.topViewController ?? split.viewController(for: .secondary) }
        XCTAssertTrue(detail() is PeopleSettingsViewController)
        XCTAssertTrue(rows(in: home.view).first { $0.accessibilityIdentifier == "caregiver.page.people" }?.isCurrent == true)
        try XCTUnwrap(rows(in: home.view).first { $0.accessibilityIdentifier == "caregiver.page.calls" }).sendActions(for: .touchUpInside)
        XCTAssertTrue(detail() is CallSettingsViewController)
        XCTAssertEqual(rows(in: home.view).filter(\.isCurrent).map(\.accessibilityIdentifier), ["caregiver.page.calls"])
        XCTAssertTrue(home.navigationController?.viewControllers == [home], "The list stays beside the page")
    }

    /// Family mode is three tabs: calls, every family's messages, and this phone's families and settings.
    @MainActor func testFamilyModeHasCallMessagesAndYouTabs() {
        let tabs = FamilyTabBarController(); tabs.loadViewIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.map { $0.tabBarItem.title }, ["Call", "Messages", "You"])
        let roots = tabs.viewControllers?.compactMap { ($0 as? UINavigationController)?.viewControllers.first } ?? []
        roots.forEach { $0.loadViewIfNeeded() }
        XCTAssertEqual(roots.map { $0.navigationItem.title }, ["Porch", "Messages", "You"])
        // Loading the screens doesn't rename their tabs.
        XCTAssertEqual(tabs.viewControllers?.map { $0.tabBarItem.title }, ["Call", "Messages", "You"])
        XCTAssertTrue(tabs.isShowingTabRoot)
        if PorchDevice.families.isEmpty { XCTAssertNil(tabs.viewControllers?[FamilyTabBarController.messagesTab].tabBarItem.badgeValue) }
    }

    /// Each tab keeps its screens. Choosing another family closes the previous one's, such as a message being recorded
    /// on Messages, so nothing left open there sends or shows things for the wrong family.
    @MainActor func testChoosingAnotherFamilyClosesItsScreensOnTheOtherTabs() throws {
        try preservingPairings {
            let origin = URL(string: "https://example.invalid")!
            let first = FamilyCredential(origin: origin, credential: "first-device.first-secret", role: .family)
            let second = FamilyCredential(origin: origin, credential: "second-device.second-secret", role: .family)
            try PorchDevice.save(first); try PorchDevice.save(second)
            PorchDevice.select(first)
            let tabs = FamilyTabBarController(); tabs.loadViewIfNeeded()
            let messages = try XCTUnwrap(tabs.viewControllers?[FamilyTabBarController.messagesTab] as? UINavigationController)
            messages.pushViewController(MessageComposerViewController(recipient: "Mom"), animated: false)
            tabs.selectedIndex = FamilyTabBarController.youTab
            // The same family again leaves it open.
            NotificationCenter.default.post(name: .porchFamilyChanged, object: nil)
            XCTAssertEqual(messages.viewControllers.count, 2)
            PorchDevice.select(second)
            NotificationCenter.default.post(name: .porchFamilyChanged, object: nil)
            XCTAssertEqual(messages.viewControllers.count, 1, "the first family's recording closed")
        }
    }

    /// You has the families and this phone's own settings. What belongs to one family, such as caregiver mode and
    /// leaving it, is on that family's page instead.
    @MainActor func testYouTabKeepsOnlyThisPhonesSettings() {
        let you = FamilyYouViewController()
        let navigation = UINavigationController(rootViewController: you); you.loadViewIfNeeded()
        XCTAssertEqual(you.title, "You")
        let titles = buttons(in: you.view).compactMap { $0.configuration?.title }
        // The page's own buttons, without the keyboard choice under it.
        XCTAssertEqual(Array(buttons(in: you.form).compactMap { $0.configuration?.title }.suffix(2)), ["Privacy policy", "About Porch"], "Last, as on Android")
        let links = buttons(in: you.view).filter { ["family.privacy", "family.about"].contains($0.accessibilityIdentifier) }
        XCTAssertEqual(links.map(\.contentHorizontalAlignment), [.leading, .leading], "Left-aligned, as on Android")
        links.last?.sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.topViewController is AboutViewController)
        navigation.popToRootViewController(animated: false)
        XCTAssertTrue(titles.contains(PorchDevice.families.isEmpty ? "Join a family" : "Join another family") || PorchDevice.families.count >= FamilyNames.limit)
        let rowLabels = rows(in: you.view).compactMap(\.accessibilityLabel)
        // Only an iPad can become the bedside.
        XCTAssertEqual(rowLabels.contains("Use this iPad as the bedside Porch"), UIDevice.current.userInterfaceIdiom == .pad)
        XCTAssertFalse(rowLabels.contains("Use this iPhone as the bedside Porch"))
        XCTAssertFalse(rows(in: you.view).contains { $0.accessibilityIdentifier == "family.caregiverMode" }, "Caregiver mode is on a family's page")
        XCTAssertFalse(titles.contains { $0.hasPrefix("Leave") }, "Leaving is on a family's page")
    }

    /// Porch checks in every few seconds. One that changes nothing on the page leaves its controls in place, so a
    /// switch being flipped stays put and VoiceOver stays where it was.
    @MainActor func testYouTabStaysPutWhenACheckInChangesNothing() {
        let you = FamilyYouViewController(); you.loadViewIfNeeded()
        let before = buttons(in: you.view)
        NotificationCenter.default.post(name: .porchFamilyChanged, object: nil)
        let after = buttons(in: you.view)
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(after.count, before.count)
        XCTAssertTrue(zip(before, after).allSatisfy { $0 === $1 }, "the same buttons are still showing")
    }

    @MainActor func testFamilyNameAndPhotoPageIsOnlyTheNameAndPhoto() {
        let profile = FamilyProfileViewController(); profile.loadViewIfNeeded()
        XCTAssertEqual(profile.title, "Your name and photo")
        let titles = buttons(in: profile.view).compactMap { $0.configuration?.title }
        XCTAssertFalse(titles.contains("Privacy policy"))
        XCTAssertFalse(titles.contains("Join another family"))
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

    /// `foreground` at `alpha` drawn over an opaque `background`, as a tinted tag sits on the page.
    @MainActor private func blended(_ foreground: UIColor, alpha: CGFloat, over background: UIColor) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        foreground.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: fr * alpha + br * (1 - alpha), green: fg * alpha + bg * (1 - alpha), blue: fb * alpha + bb * (1 - alpha), alpha: 1)
    }

    @MainActor func testTextsAreReadInTheirOwnLanguageOnlyWhenPorchCouldntTranslateThem() {
        let restore = localizedBedside(.cantonese); defer { restore() }
        func text(_ words: String, translated: Bool = false, source: String? = nil) -> ReceivedText {
            ReceivedText(id: "t", from: "+14155550123", sentAt: 1, body: words, language: "yue-Hant", text: words, translated: translated, sourceLanguage: source)
        }
        XCTAssertNil(MessagePlayerViewController.otherLanguage(of: text("媽，我晚上六點到", source: "zh-Hant")))
        XCTAssertNil(MessagePlayerViewController.otherLanguage(of: text("媽，我晚上六點到，到時再打電話畀你。")), "any written Chinese is the Cantonese bedside's language")
        XCTAssertEqual(MessagePlayerViewController.otherLanguage(of: text("Hi Mom, I land at six tonight and will call you then.")), "en")
        XCTAssertNil(MessagePlayerViewController.otherLanguage(of: text("我六點到", translated: true, source: "en")))
        XCTAssertEqual(MessagePlayerViewController.pictureNote(2), "呢個短訊附咗 2 張相，Porch 暫時未顯示到。")
        XCTAssertEqual(MessagePlayerViewController.pictureNote(1), "呢個短訊附咗一張相，Porch 暫時未顯示到。")
        XCTAssertNil(MessagePlayerViewController.pictureNote(0))
        let card = ReceivedText(id: "t", from: "+14155550123", sentAt: 1, body: "", pictures: 1, attachments: 2, language: "yue-Hant", text: "", translated: false)
        XCTAssertEqual(MessagePlayerViewController.attachmentNotes(card), ["呢個短訊附咗一張相，Porch 暫時未顯示到。", "呢個短訊附咗啲 Porch 暫時未顯示到嘅嘢。"], "a contact card isn't called a picture")
        XCTAssertNil(MessagePlayerViewController.attachmentSentence(text("媽")))
        XCTAssertTrue(MessagePlayerViewController.translatedNote("en")?.hasPrefix("譯自") == true)
        XCTAssertNil(MessagePlayerViewController.translatedNote(nil))
        XCTAssertTrue(MessagePlayerViewController.announcement(forTextFrom: "72975", sentAt: 1, slots: CallSlots()).hasPrefix("72975嘅短訊"), "a short code is named as it is")
    }

    /// iPadOS has no Filipino voice to download, so Tagalog's note never sends a caregiver to iPad Settings for one.
    @MainActor func testMissingVoiceNoteOnlyOffersSettingsWhereAVoiceCanBeAdded() {
        for offered in [true, false] {
            let tagalog = PorchAnnouncementVoice.missingVoiceNote(for: .tagalog, naturalVoicesOffered: offered)
            XCTAssertFalse(tagalog.contains("iPad Settings"), tagalog)
            XCTAssertTrue(tagalog.contains("drop-ins must be answered"), tagalog)
            XCTAssertEqual(tagalog.contains("natural voice"), offered, tagalog)
            let cantonese = PorchAnnouncementVoice.missingVoiceNote(for: .cantonese, naturalVoicesOffered: offered)
            XCTAssertTrue(cantonese.contains("iPad Settings → Accessibility → Spoken Content → Voices"), cantonese)
            XCTAssertEqual(cantonese.contains("natural voice"), offered, cantonese)
        }
    }

    @MainActor func testTagalogTextsGoByTheLanguageTheServerNamed() {
        let restore = localizedBedside(.tagalog); defer { restore() }
        func text(_ words: String, source: String? = nil) -> ReceivedText {
            ReceivedText(id: "t", from: "+14155550123", sentAt: 1, body: words, language: "tl", text: words, translated: false, sourceLanguage: source)
        }
        let words = "Ma, darating ako mamayang alas-sais. Tatawagan kita pagdating ko."
        XCTAssertNil(MessagePlayerViewController.otherLanguage(of: text(words, source: "tl")))
        XCTAssertNil(MessagePlayerViewController.otherLanguage(of: text(words, source: "fil")), "Filipino is Tagalog")
        XCTAssertNil(MessagePlayerViewController.otherLanguage(of: text(words)), "Apple's recognizer doesn't know Tagalog, so it isn't asked")
        XCTAssertEqual(MessagePlayerViewController.otherLanguage(of: text("Hi Mom, I land at six.", source: "en")), "en")
        XCTAssertEqual(MessagePlayerViewController.translatedNote("en"), "Isinalin mula sa Ingles")
        XCTAssertEqual(MessagePlayerViewController.pictureNote(2), "May kasama itong 2 litrato na hindi pa maipakita ng Porch.")
    }

    func testCaregiverPhonesSayWhatNeedsTheirReview() {
        XCTAssertEqual(FamilyHomeViewController.reviewTitle(voicemails: 1, texts: 0), "1 phone voicemail needs your review")
        XCTAssertEqual(FamilyHomeViewController.reviewTitle(voicemails: 0, texts: 1), "1 text needs your review")
        XCTAssertEqual(FamilyHomeViewController.reviewTitle(voicemails: 0, texts: 2), "2 texts need your review")
        XCTAssertEqual(FamilyHomeViewController.reviewTitle(voicemails: 1, texts: 2), "3 messages need your review")
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
            let title = PorchStyle.systemLabel("David", size: 40, color: .white)
            let status = PorchStyle.systemLabel("Calling David…", size: 17, color: .white)
            let placeholder = PorchStyle.systemLabel("Voice call", size: 28, color: .white)
            let end = PorchStyle.systemButton("End call")
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
            let title = PorchStyle.systemLabel(String(String(repeating: "Family member ", count: 7).prefix(80)), size: 26)
            let status = PorchStyle.systemLabel("Trying your family on Porch…\nTheir phone will ring if Porch isn't answered.", size: 17)
            let hint = PorchStyle.systemLabel("Key 0: hang up · Key 9: video off / on", size: 16)
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
            let title = PorchStyle.systemLabel("Family", size: 26, color: .white)
            let status = PorchStyle.systemLabel("Video call connected", size: 17, color: .white)
            let buttons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
            for ((button, text), symbol) in zip(zip(buttons, ["Mute", "Camera off", "End call"]), ["mic.slash", "video", "phone.down.fill"]) {
                CallScreenLayout.configure(button, title: text, symbol: symbol, isEnd: button === buttons.last)
            }
            let hint = PorchStyle.systemLabel("Key 0: hang up · Key 9: video off / on", size: 16, color: .white)
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
                    XCTAssertEqual(preview.bounds.width < preview.bounds.height, scroll.bounds.width < scroll.bounds.height)
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

    @MainActor func testTranslateWrapsTheCallButtonsIntoEvenRowsWithoutBreakingWords() throws {
        let screen = UIViewController()
        let titles = ["Mute", "Camera off", "Translating", "Add someone", "End call"]
        let buttons = titles.map { _ in UIButton(type: .system) }
        for (button, text) in zip(buttons, titles) {
            CallScreenLayout.configure(button, title: text, symbol: "phone", isEnd: button === buttons.last)
        }
        CallScreenLayout.install(in: screen.view, video: VideoView(), title: PorchStyle.systemLabel("Mom", size: 26, color: .white),
                                 status: PorchStyle.systemLabel("Video call connected", size: 17, color: .white), buttons: buttons)
        func rows() -> [[String]] {
            screen.view.setNeedsLayout(); screen.view.layoutIfNeeded()
            // A hidden or shown button regroups the rows on the next turn of the run loop.
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            screen.view.layoutIfNeeded()
            let shown = buttons.filter { $0.window != nil && !$0.isHidden }
            let grouped = Dictionary(grouping: shown) { Int($0.convert($0.bounds, to: screen.view).minY.rounded()) }
            return grouped.keys.sorted().map { y in grouped[y]!.map { $0.configuration?.title ?? "" } }
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = screen; window.isHidden = false
        // A phone: Mute, Camera off and Translating, then Add someone and End call.
        XCTAssertEqual(rows(), [["Mute", "Camera off", "Translating"], ["Add someone", "End call"]])
        for button in buttons {
            let rect = button.convert(button.bounds, to: screen.view)
            XCTAssertGreaterThanOrEqual(rect.height, 64)
            XCTAssertTrue(screen.view.bounds.contains(rect))
            // Each word fits on its line: no button is narrower than its longest word.
            let longest = (button.configuration?.title ?? "").split(separator: " ")
                .map { (String($0) as NSString).size(withAttributes: [.font: PorchStyle.systemFont(16, weight: .semibold)]).width }.max() ?? 0
            XCTAssertGreaterThanOrEqual(rect.width, longest + 16)
        }
        // Translate isn't offered, such as when the bedside's app can't show translation: no gap is left for it.
        buttons[2].isHidden = true
        XCTAssertFalse(rows().joined().contains("Translating"))
        XCTAssertEqual(rows().joined().count, 4)
        buttons[2].isHidden = false
        XCTAssertEqual(rows().first, ["Mute", "Camera off", "Translating"])
        // A tablet has room for four in a row.
        buttons[3].isHidden = true
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        XCTAssertEqual(rows(), [["Mute", "Camera off", "Translating", "End call"]])
        window.isHidden = true
    }

    @MainActor func testEndingACallClosesWhatTheCallScreenPresented() throws {
        // Such as the translation sheet, open when the other person hangs up.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let home = UIViewController(), call = UIViewController(), sheet = UIViewController()
        window.rootViewController = home; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // Opening and closing screens takes a few turns of the run loop, more on a busy CI simulator.
        func wait(until done: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        wait { window.isKeyWindow && home.view.window != nil }
        home.present(call, animated: false)
        wait { home.presentedViewController === call && call.view.window != nil && !call.isBeingPresented }
        call.present(sheet, animated: false)
        wait { call.presentedViewController === sheet && sheet.view.window != nil && !sheet.isBeingPresented }
        XCTAssertTrue(home.presentedViewController === call)
        XCTAssertTrue(call.presentedViewController === sheet)
        call.closeCallScreen(animated: false)
        wait { home.presentedViewController == nil }
        XCTAssertNil(home.presentedViewController)
    }

    @MainActor func testSelfViewIsTheUsualSizeAndTurnsWithTheScreen() throws {
        // Like most calling apps: 30% of the short side, at most 200 points, upright on an upright screen.
        let screen = UIViewController(), remote = VideoView(), preview = VideoView()
        remote.backgroundColor = UIColor(white: 0.18, alpha: 1)
        preview.backgroundColor = UIColor(white: 0.55, alpha: 1)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
        }
        let photo = RecipientAppearance.photoView(image.jpegData(compressionQuality: 0.8))
        let placeholder = PorchStyle.systemLabel("Waiting for video", size: 28, color: .white)
        let buttons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
        for ((button, text), symbol) in zip(zip(buttons, ["Mute", "Camera off", "End call"]), ["mic.slash", "video.slash", "phone.down.fill"]) {
            CallScreenLayout.configure(button, title: text, symbol: symbol, isEnd: button === buttons.last)
        }
        CallScreenLayout.install(in: screen.view, video: remote, preview: preview, placeholder: placeholder,
                                 title: PorchStyle.systemLabel("David", size: 40, color: .white),
                                 status: PorchStyle.systemLabel("Video call connected", size: 17, color: .white),
                                 hint: PorchStyle.systemLabel("Key 0: hang up · Key 9: video off / on", size: 16, color: .white),
                                 photo: photo, buttons: buttons)
        let scroll = try XCTUnwrap(screen.view.subviews.first { $0.accessibilityIdentifier == "call.overlays" } as? UIScrollView)
        // The same screen turns between phone and iPad sizes, so the self view must follow each change. A nearly
        // square sideways window and the smallest phone sideways leave little room beside the photo; the smallest
        // phone also shrinks the self view to fit.
        for (size, expected) in [(CGSize(width: 393, height: 852), CGSize(width: 117.9, height: 157.2)),
                                 (CGSize(width: 852, height: 393), CGSize(width: 157.2, height: 117.9)),
                                 (CGSize(width: 1024, height: 768), CGSize(width: 266.7, height: 200)),
                                 (CGSize(width: 768, height: 1024), CGSize(width: 200, height: 266.7)),
                                 (CGSize(width: 800, height: 790), CGSize(width: 266.7, height: 200)),
                                 (CGSize(width: 375, height: 1024), CGSize(width: 112.5, height: 150)),
                                 (CGSize(width: 568, height: 320), nil),
                                 (CGSize(width: 393, height: 852), CGSize(width: 117.9, height: 157.2))] as [(CGSize, CGSize?)] {
            for waiting in [false, true] {
                photo.isHidden = !waiting; placeholder.isHidden = !waiting
                screen.view.frame = CGRect(origin: .zero, size: size)
                screen.view.setNeedsLayout(); screen.view.layoutIfNeeded()
                if let expected {
                    XCTAssertEqual(preview.bounds.width, expected.width, accuracy: 0.5, "\(size)")
                    XCTAssertEqual(preview.bounds.height, expected.height, accuracy: 0.5, "\(size)")
                }
                XCTAssertEqual(preview.bounds.width > preview.bounds.height, size.width > size.height, "\(size)")
                XCTAssertTrue(scroll.bounds.contains(preview.frame), "\(size): \(preview.frame)")
                XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 1, "\(size)")
                XCTAssertFalse(preview.hasAmbiguousLayout)
                if waiting {
                    // While the other person's video is missing, their photo and the words under it stay uncovered.
                    let selfView = preview.convert(preview.bounds, to: screen.view)
                    for view in [photo, placeholder] as [UIView] {
                        let rect = view.convert(view.bounds, to: screen.view)
                        if expected != nil { XCTAssertGreaterThan(rect.height, 20, "\(size)") }
                        let text = min(rect.width, placeholder.intrinsicContentSize.width)
                        let covered = view === placeholder ? rect.insetBy(dx: (rect.width - text) / 2, dy: 0) : rect
                        XCTAssertFalse(covered.intersects(selfView), "\(size): \(covered) under \(selfView)")
                    }
                }
                let attachment = XCTAttachment(image: UIGraphicsImageRenderer(size: size).image { screen.view.layer.render(in: $0.cgContext) })
                attachment.name = "Self view \(Int(size.width))x\(Int(size.height))\(waiting ? " waiting" : "")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor func testSelfViewStepsAsideWhenTheCallBecomesAPhoneCall() throws {
        // A video contact can end on the phone. The self view is gone for good then, so its hole has to go too.
        for size in [CGSize(width: 393, height: 852), CGSize(width: 800, height: 790)] {
            let screen = UIViewController(), remote = VideoView(), preview = VideoView()
            remote.backgroundColor = UIColor(white: 0.18, alpha: 1)
            preview.backgroundColor = UIColor(white: 0.55, alpha: 1)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
                UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
            }
            let photo = RecipientAppearance.photoView(image.jpegData(compressionQuality: 0.8))
            let placeholder = PorchStyle.systemLabel("Phone call\nCamera is off", size: 28, color: .white)
            let buttons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
            for ((button, text), symbol) in zip(zip(buttons, ["Mute", "Camera off", "End call"]), ["mic.slash", "video.slash", "phone.down.fill"]) {
                CallScreenLayout.configure(button, title: text, symbol: symbol, isEnd: button === buttons.last)
            }
            CallScreenLayout.install(in: screen.view, video: remote, preview: preview, placeholder: placeholder,
                                     title: PorchStyle.systemLabel("David", size: 40, color: .white),
                                     status: PorchStyle.systemLabel("Trying David's phone…", size: 17, color: .white),
                                     photo: photo, buttons: buttons)
            let scroll = try XCTUnwrap(screen.view.subviews.first { $0.accessibilityIdentifier == "call.overlays" } as? UIScrollView)
            screen.view.frame = CGRect(origin: .zero, size: size)
            screen.view.setNeedsLayout(); screen.view.layoutIfNeeded()
            let photoBefore = photo.convert(photo.bounds, to: screen.view)
            XCTAssertNotNil(preview.superview)
            CallScreenLayout.releaseSelfView(in: screen.view)
            screen.view.setNeedsLayout(); screen.view.layoutIfNeeded()
            XCTAssertNil(preview.superview, "\(size)")
            let photoAfter = photo.convert(photo.bounds, to: screen.view)
            if size.width > size.height {
                // Sideways, the photo was narrowed to the column beside the self view.
                XCTAssertGreaterThan(photoAfter.width, photoBefore.width + 40, "\(size)")
            } else {
                // Upright, the photo sat above the self view and moves down into that room.
                XCTAssertGreaterThan(photoAfter.maxY, photoBefore.maxY + 30, "\(size)")
            }
            XCTAssertGreaterThan(photoAfter.height, 20, "\(size)")
            XCTAssertFalse(photo.hasAmbiguousLayout)
            XCTAssertFalse(placeholder.hasAmbiguousLayout)
            XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 1, "\(size)")
            let turned = CGSize(width: size.height, height: size.width)
            screen.view.frame = CGRect(origin: .zero, size: turned)
            screen.view.setNeedsLayout(); screen.view.layoutIfNeeded()
            XCTAssertNil(preview.superview, "turned \(turned)")
            XCTAssertFalse(photo.hasAmbiguousLayout)
            XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 1, "turned \(turned)")
        }
        // A voice call never installed a self view. Releasing one must leave that layout alone.
        let voice = UIViewController()
        let photo = RecipientAppearance.photoView(UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }.jpegData(compressionQuality: 0.8))
        let placeholder = PorchStyle.systemLabel("Voice call", size: 28, color: .white)
        CallScreenLayout.install(in: voice.view, video: VideoView(), placeholder: placeholder,
                                 title: PorchStyle.systemLabel("David", size: 40, color: .white),
                                 status: PorchStyle.systemLabel("Voice call connected", size: 17, color: .white),
                                 photo: photo, buttons: [PorchStyle.systemButton("End call")])
        voice.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        CallScreenLayout.releaseSelfView(in: voice.view)
        voice.view.layoutIfNeeded()
        XCTAssertGreaterThan(photo.convert(photo.bounds, to: voice.view).height, 20)
        XCTAssertFalse(photo.hasAmbiguousLayout)
    }

}

/// The welcome screen and setting up a new bedside one screen at a time.
final class BedsideSetupTests: XCTestCase {
    @MainActor private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
    @MainActor private func buttons(in view: UIView) -> [UIButton] { descendants(view).compactMap { $0 as? UIButton } }
    @MainActor private func labels(in view: UIView) -> [UILabel] { descendants(view).compactMap { $0 as? UILabel } }

    @MainActor func testWelcomeOffersSettingUpThisIPadOrJoiningAFamily() throws {
        var chosen: [PorchExperience] = []
        let welcome = WelcomeViewController { chosen.append($0) }
        let navigation = UINavigationController(rootViewController: welcome); welcome.loadViewIfNeeded()
        try XCTUnwrap(buttons(in: welcome.view).first { $0.accessibilityIdentifier == "welcome.setUp" }).sendActions(for: .touchUpInside)
        try XCTUnwrap(buttons(in: welcome.view).first { $0.accessibilityIdentifier == "welcome.join" }).sendActions(for: .touchUpInside)
        // On an iPad, Set up makes this iPad the bedside. A phone explains that the bedside is the iPad instead.
        XCTAssertEqual(chosen, UIDevice.current.userInterfaceIdiom == .pad ? [.bedside, .family] : [.family])
        if UIDevice.current.userInterfaceIdiom == .phone { XCTAssertTrue(navigation.viewControllers.last is BedsideOnIPadViewController) }
        XCTAssertTrue(buttons(in: welcome.view).contains { $0.accessibilityIdentifier == "caregiver.privacy" })
    }

    /// A setup link opened on an iPhone, such as from the invitation email, leaves it a family device.
    @MainActor func testASetupLinkOnAnIPhoneExplainsTheBedsideIsTheIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let key = "porch.experience", saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        let activation = PorchDevice.bedsideActivation
        let link = try XCTUnwrap(URL(string: "https://helloporch.store/setup#code=\(String(repeating: "a", count: 64))"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for experience in [nil, "family"] {
            UserDefaults.standard.set(experience, forKey: key)
            let welcoming = PorchDevice.needsWelcome
            let container = PorchContainerViewController()
            let window = UIWindow(windowScene: scene)
            window.rootViewController = container; window.makeKeyAndVisible()
            defer { window.isHidden = true }
            container.openInvitation(link)
            XCTAssertEqual(PorchDevice.experience, .family)
            XCTAssertNotEqual(UserDefaults.standard.string(forKey: key), "bedside")
            XCTAssertEqual(PorchDevice.bedsideActivation, activation, "The link isn't saved for setup")
            if welcoming {
                XCTAssertTrue((container.children.first as? UINavigationController)?.viewControllers.last is BedsideOnIPadViewController)
            } else {
                XCTAssertTrue(container.presentedViewController is UIAlertController)
            }
        }
    }

    /// Runs `body` with an old household's bedside pairing on this iPad, then puts back what was there.
    @MainActor private func withOldBedside(_ body: () throws -> Void) throws {
        let accounts = ["porch.family.bedside", "porch.bedside.activation"]
        let saved = accounts.map { NativeCallSettings.readSecret($0) ?? Data() }
        defer {
            for (account, data) in zip(accounts, saved) {
                try? NativeCallSettings.writeSecret(data, account: account, accessibleAfterFirstUnlock: account == "porch.family.bedside")
            }
        }
        try PorchDevice.save(FamilyCredential(origin: try XCTUnwrap(URL(string: "https://example.invalid")), credential: "old-bedside.old-secret", role: .bedside))
        try body()
    }

    /// An iPad handed on to someone else: a setup link asks before replacing the Porch it already is, and keeps nothing
    /// until Replace.
    @MainActor func testASetupLinkOnABedsideAsksToReplaceIt() throws {
        guard PorchDevice.canBeBedside else { return }
        let key = "porch.experience", saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        // As a family device, so the clock doesn't start: the link checks the bedside pairing either way.
        UserDefaults.standard.set("family", forKey: key)
        try withOldBedside {
            let activation = PorchDevice.bedsideActivation
            let link = try XCTUnwrap(URL(string: "https://helloporch.store/setup#code=\(String(repeating: "b", count: 64))"))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let container = PorchContainerViewController()
            let window = UIWindow(windowScene: scene)
            window.rootViewController = container; window.makeKeyAndVisible()
            defer { window.isHidden = true }
            container.openInvitation(link)
            let alert = try XCTUnwrap(container.presentedViewController as? UIAlertController)
            XCTAssertEqual(alert.title?.hasPrefix("Replace "), true, alert.title ?? "")
            XCTAssertEqual(alert.actions.map(\.title), ["Cancel", "Replace"])
            XCTAssertEqual(alert.actions.last?.style, .destructive)
            XCTAssertEqual(PorchDevice.bedsideActivation, activation, "Nothing is saved until Replace")
            XCTAssertEqual(PorchDevice.credential(for: .bedside)?.credential, "old-bedside.old-secret")
        }
    }

    @MainActor func testReplacingKeepsCancelForTheOldPorchUntilThePIN() throws {
        try withOldBedside {
            for replacing in [false, true] {
                let setup = BedsideSetup(); setup.replacing = replacing
                let name = SetupNameViewController(setup)
                let navigation = UINavigationController(rootViewController: name); name.loadViewIfNeeded()
                // A set-up iPad's first setup screen has no Cancel, except when it's being replaced: Cancel keeps the old Porch.
                XCTAssertEqual(name.navigationItem.leftBarButtonItem != nil, replacing)
                // It's a bedside already, so it doesn't offer to become a family device here.
                XCTAssertEqual(buttons(in: name.view).contains { $0.configuration?.title == "Use this device as a family member" }, !replacing)
                withExtendedLifetime(navigation) {}
            }
        }
    }

    @MainActor func testReplacingForgetsTheOldHouseholdButNotTheIPadsOwnSettings() throws {
        let suite = "replace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let photos = ContactPhotoStore(directoryURL: directory)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        var slots = CallSlots()
        try slots.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "david", mode: .video), photoData: Data([1, 2, 3, 4])), for: 1)
        try slots.save(to: defaults, photoStore: photos)
        var preferences = BedsidePreferences(); preferences.language = .traditionalChinese; preferences.save(to: defaults)
        var autoplay = MessageAutoplay(); autoplay.enabled = false; autoplay.save(to: defaults)
        BedsideAttendance.setCameraEnabled(false, in: defaults)
        CallPreferences.saveStartVideoWithCamera(false, in: defaults)
        defaults.set(true, forKey: "porch.cell2jack.enabled"); defaults.set("family-pairing", forKey: "porch.family.current")

        PorchDevice.forgetBedsideHousehold(defaults: defaults, photoStore: photos)
        XCTAssertFalse(CallSlots.isSaved(in: defaults))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        XCTAssertEqual(BedsidePreferences.load(from: defaults), BedsidePreferences())
        XCTAssertEqual(MessageAutoplay.load(from: defaults), MessageAutoplay())
        XCTAssertTrue(BedsideAttendance.cameraEnabled(in: defaults), "Back to the default")
        XCTAssertTrue(CallPreferences.startVideoWithCamera(in: defaults))
        XCTAssertTrue(defaults.bool(forKey: "porch.cell2jack.enabled"), "The desk phone stays with the iPad")
        XCTAssertEqual(defaults.string(forKey: "porch.family.current"), "family-pairing", "So do families it's in as a family device")
    }

    @MainActor func testADeviceThatChoseItsModeNeverSeesTheWelcomeAgain() {
        let key = "porch.experience", saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        for experience in [PorchExperience.bedside, .family] {
            UserDefaults.standard.set(experience.rawValue, forKey: key)
            XCTAssertFalse(PorchDevice.needsWelcome)
        }
    }

    @MainActor func testTheNumberStepAsksForAnAreaCodeAndContinuesOnlyAfterATry() throws {
        let number = SetupNumberViewController(BedsideSetup()); number.loadViewIfNeeded()
        let all = descendants(number.view)
        let areaCode = try XCTUnwrap(all.compactMap { $0 as? UITextField }.first { $0.accessibilityIdentifier == "setup.areaCode" })
        XCTAssertEqual(areaCode.keyboardType, .numberPad)
        XCTAssertTrue(buttons(in: number.view).contains { $0.configuration?.title == "Get number" && !$0.isHidden })
        XCTAssertTrue(try XCTUnwrap(buttons(in: number.view).first { $0.configuration?.title == "Continue" }).isHidden, "The number can't be skipped")
    }

    private final class Connection: Cell2JackKeypadConnection {
        var starts = 0, stops = 0
        let update: (Cell2JackKeypadUpdate) -> Void
        init(_ update: @escaping (Cell2JackKeypadUpdate) -> Void) { self.update = update }
        func start() { starts += 1 }
        func stop() { stops += 1 }
    }
    /// Connect the phone on a build and iPad that also try the driver. `keyboard` says whether the iPad sees a keyboard,
    /// such as the phone adapter. `mChip` says whether the iPad is known to have an M chip.
    @MainActor private func phoneStep(mChip: Bool = true, keyboard: @escaping () -> Bool = { false }) throws
        -> (screen: SetupPhoneViewController, keypad: Cell2JackKeypad, connections: () -> [Connection], done: () -> Int) {
        let name = "setup-phone-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        var connections: [Connection] = [], finished = 0
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }, enqueueRetry: { _, _ in }) { update in
            let connection = Connection(update); connections.append(connection); return connection
        }
        keypad.activate()
        let setup = BedsideSetup(); setup.name = "Mom"
        let screen = SetupPhoneViewController(setup, keypad: keypad, tryDriver: true, mChip: mChip, keyboardConnected: keyboard)
        screen.onContinue = { finished += 1 }
        screen.loadViewIfNeeded(); screen.viewDidAppear(false)
        return (screen, keypad, { connections }, { finished })
    }
    @MainActor private func phoneStatus(_ screen: UIViewController) -> String? {
        labels(in: screen.view).first { $0.accessibilityIdentifier == "setup.phoneStatus" }?.text
    }

    @MainActor func testSetupGoesOnToEachScreenThatHasSomethingToDo() {
        let setup = BedsideSetup()
        XCTAssertTrue(setup.screen(from: .phone) is SetupCallingViewController, "Every build asks how they'll call")
        XCTAssertTrue(setup.screen(from: .yourPhone) is SetupYourPhoneViewController, "No caregiver's phone has joined")
        XCTAssertTrue(setup.screen(from: .done) is SetupDoneViewController)
    }

    @MainActor func testConnectingThePhoneTurnsItsKeypadOnThenChecksAKeyAndHangingUp() throws {
        let step = try phoneStep()
        XCTAssertEqual(phoneStatus(step.screen), "Waiting for the phone…")
        XCTAssertEqual(step.connections().count, 1, "The screen tries the Cell2Jack while the keypad is still off")
        let proceed = try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneDone" })
        let later = try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneLater" })
        XCTAssertTrue(proceed.isHidden); XCTAssertFalse(later.isHidden)
        step.connections()[0].update(.ready)
        XCTAssertTrue(step.keypad.enabled, "Porch turns the phone keypad on once the Cell2Jack answers")
        XCTAssertEqual(phoneStatus(step.screen), "The phone is connected. Lift the receiver and press a key.")
        XCTAssertEqual(step.screen.receiveCell2JackHangUp(), "setup: hang-up before a key")
        _ = step.screen.receiveCell2JackDigit(CallSlots.star)
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard *. Now put the receiver back.")
        XCTAssertTrue(proceed.isHidden)
        _ = step.screen.receiveCell2JackHangUp()
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard you hang up. The phone is ready.")
        XCTAssertFalse(proceed.isHidden); XCTAssertTrue(later.isHidden)
        proceed.sendActions(for: .touchUpInside)
        XCTAssertEqual(step.done(), 1)
        XCTAssertFalse(step.keypad.trying); XCTAssertTrue(step.keypad.enabled)
        XCTAssertEqual(step.connections()[0].stops, 0, "Switched on, the phone keypad stays connected")
    }

    @MainActor func testTheNewScreensUseTheWholeWidth() throws {
        let setup = BedsideSetup(); setup.name = "Mom"
        let titles: Set<String> = ["How will Mom call?", "Connect the phone", "Add your phone"]
        for screen in [SetupCallingViewController(setup), try phoneStep().screen, SetupYourPhoneViewController(setup)] as [UIViewController] {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 834, height: 1194))
            window.rootViewController = UINavigationController(rootViewController: screen); window.makeKeyAndVisible()
            screen.view.layoutIfNeeded()
            let card = try XCTUnwrap(labels(in: screen.view).first { titles.contains($0.text ?? "") }?.superview?.superview)
            // The form is the screen's width less its margins, up to 760 points: on an iPhone as on an iPad.
            XCTAssertEqual(card.bounds.width, min(760, screen.view.bounds.width - 48), accuracy: 1, "\(type(of: screen)) squeezed its card")
            window.isHidden = true
        }
    }

    @MainActor func testThePhoneDroppingBeforeTheHangUpGoesBackToWaiting() throws {
        let step = try phoneStep()
        step.connections()[0].update(.ready)
        _ = step.screen.receiveCell2JackDigit(3)
        step.connections()[0].update(.finished("Phone keypad stopped"))
        XCTAssertEqual(phoneStatus(step.screen), "Waiting for the phone…")
        XCTAssertEqual(step.screen.receiveCell2JackHangUp(), "setup: hang-up before a key")
    }

    @MainActor func testComingBackAfterADropDuringTheHangUpWaitsAgain() throws {
        let step = try phoneStep()
        step.connections()[0].update(.ready)
        _ = step.screen.receiveCell2JackDigit(3)
        step.screen.viewWillDisappear(false)
        // The driver stops while the screen is leaving, so that notice is ignored.
        step.keypad.pause()
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard 3. Now put the receiver back.")
        step.screen.viewDidAppear(false)
        XCTAssertEqual(phoneStatus(step.screen), "Waiting for the phone…")
        XCTAssertEqual(step.screen.receiveCell2JackHangUp(), "setup: hang-up before a key")
    }

    @MainActor func testWithoutHangingUpOnTheReceiverAKeyIsEnough() throws {
        let step = try phoneStep()
        step.keypad.setReceiverHangUp(false)
        step.connections()[0].update(.ready)
        _ = step.screen.receiveCell2JackDigit(3)
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard 3. The phone is ready.")
    }

    @MainActor func testDoThisLaterLeavesThePhoneKeypadOff() throws {
        let step = try phoneStep()
        try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneLater" }).sendActions(for: .touchUpInside)
        XCTAssertEqual(step.done(), 1)
        XCTAssertFalse(step.keypad.enabled); XCTAssertFalse(step.keypad.trying)
        XCTAssertEqual(step.connections()[0].stops, 1)
    }

    @MainActor func testDoThisLaterAfterThePhoneConnectsTurnsTheKeypadBackOff() throws {
        let step = try phoneStep()
        step.connections()[0].update(.ready)
        XCTAssertTrue(step.keypad.enabled)
        try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneLater" }).sendActions(for: .touchUpInside)
        XCTAssertEqual(step.done(), 1)
        XCTAssertFalse(step.keypad.enabled, "Do this later undoes the enable this screen just did")
        XCTAssertFalse(step.keypad.trying)
        XCTAssertEqual(step.connections()[0].stops, 1)
    }

    @MainActor func testDoThisLaterLeavesAKeypadThatWasAlreadyOn() throws {
        let step = try phoneStep()
        step.keypad.setEnabled(true)
        step.connections()[0].update(.ready)
        try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneLater" }).sendActions(for: .touchUpInside)
        XCTAssertTrue(step.keypad.enabled)
        XCTAssertFalse(step.keypad.trying)
        XCTAssertEqual(step.connections()[0].stops, 0, "It was already on, so the phone stays connected")
    }

    @MainActor func testLeavingThePhoneScreenStopsATrialThatHasNotTurnedTheKeypadOn() throws {
        let step = try phoneStep()
        step.screen.viewWillDisappear(false)
        XCTAssertFalse(step.keypad.trying)
        XCTAssertFalse(step.keypad.enabled)
        XCTAssertEqual(step.connections()[0].stops, 1, "Dismissing the screen must not leave the desk phone live")
    }

    @MainActor func testLeavingAfterThePhoneAnswersLeavesTheKeypadOn() throws {
        let step = try phoneStep()
        step.connections()[0].update(.ready)
        step.screen.viewWillDisappear(false)
        XCTAssertTrue(step.keypad.enabled, "Answering already turned the keypad on")
        XCTAssertFalse(step.keypad.trying)
        XCTAssertEqual(step.connections()[0].stops, 0)
    }

    @MainActor func testThePhoneScreenListensForTheAdapterWhileItTriesTheDriver() throws {
        var keyboard = false
        let step = try phoneStep { keyboard }
        XCTAssertNotNil(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneSettings" },
                        "A Cell2Jack plugged straight in needs the USB driver on in Settings")
        XCTAssertTrue(labels(in: step.screen.view).contains { $0.text == "This iPad doesn't need the adapter. Turn on the Cell2Jack's driver in Settings, then unplug the Cell2Jack for ten seconds and plug it back in." })
        XCTAssertEqual(step.connections().count, 1, "The screen tries the driver for a Cell2Jack plugged straight in")
        // The adapter comes in while the driver finds nothing, as on an iPad without an M chip.
        keyboard = true
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        XCTAssertEqual(phoneStatus(step.screen), "Lift the receiver and press a key.")
        step.connections()[0].update(.finished("No running Cell2Jack driver service"))
        XCTAssertEqual(phoneStatus(step.screen), "Lift the receiver and press a key.", "The driver giving up doesn't undo the adapter")
        step.screen.receiveKey(4)
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard 4. Now put the receiver back.")
        _ = step.screen.receiveCell2JackHangUp()
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard you hang up. The phone is ready.")
        XCTAssertFalse(step.keypad.enabled, "Only a Cell2Jack on the driver turns the phone keypad on")
        XCTAssertTrue(step.keypad.adapterHeard, "From now on This iPad takes a keyboard to be the adapter")
        try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneDone" }).sendActions(for: .touchUpInside)
        XCTAssertEqual(step.done(), 1)
        XCTAssertFalse(step.keypad.trying)
    }

    @MainActor func testTheDriverGivingUpDoesNotUndoAKeyFromTheAdapter() throws {
        var keyboard = false
        let step = try phoneStep { keyboard }
        keyboard = true
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        step.screen.receiveKey(4)
        step.connections()[0].update(.finished("No running Cell2Jack driver service"))
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard 4. Now put the receiver back.", "The driver giving up doesn't undo a key from the adapter")
        _ = step.screen.receiveCell2JackHangUp()
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard you hang up. The phone is ready.")
    }

    @MainActor func testTheDriverAnsweringAfterAKeyboardStillSaysThePhoneIsConnected() throws {
        var keyboard = true
        let step = try phoneStep { keyboard }
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        XCTAssertEqual(phoneStatus(step.screen), "Lift the receiver and press a key.")
        step.connections()[0].update(.ready)
        XCTAssertEqual(phoneStatus(step.screen), "The phone is connected. Lift the receiver and press a key.")
        XCTAssertTrue(step.keypad.enabled)
        _ = step.screen.receiveCell2JackDigit(3)
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard 3. Now put the receiver back.")
        // The keyboard case cannot send the hang-up, so unplugging the Cell2Jack means the key has to be heard again.
        step.connections()[0].update(.finished("Phone keypad stopped"))
        XCTAssertEqual(phoneStatus(step.screen), "Lift the receiver and press a key.")
        XCTAssertEqual(step.screen.receiveCell2JackHangUp(), "setup: hang-up before a key")
    }

    @MainActor func testUnpluggingTheAdapterDuringTheCheckKeepsADriverThatIsStillAnswering() throws {
        var keyboard = true
        let step = try phoneStep { keyboard }
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        step.connections()[0].update(.ready)
        step.screen.receiveKey(4)
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard 4. Now put the receiver back.")
        keyboard = false
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
        XCTAssertEqual(phoneStatus(step.screen), "The phone is connected. Lift the receiver and press a key.")
        XCTAssertEqual(step.screen.receiveCell2JackHangUp(), "setup: hang-up before a key")
        _ = step.screen.receiveCell2JackDigit(4)
        _ = step.screen.receiveCell2JackHangUp()
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard you hang up. The phone is ready.")
    }

    /// Every family has the adapter, so the screen says only that and links to the guide for the steps, the parts and the
    /// tips. Only an iPad known to have an M chip, in a build with the driver, says it doesn't need the adapter, with
    /// Open Settings for the USB driver. A model Porch doesn't know may still try the driver but says nothing.
    @MainActor func testConnectThePhoneLinksToTheGuideAndSaysOnlyAnMChipIPadDoesntNeedTheAdapter() throws {
        for (tryDriver, mChip) in [(false, false), (false, true), (true, false), (true, true)] {
            let name = "setup-phone-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { false }, enqueueRetry: { _, _ in }) { Connection($0) }
            let setup = BedsideSetup(); setup.name = "Mom"
            let screen = SetupPhoneViewController(setup, keypad: keypad, tryDriver: tryDriver, mChip: mChip) { false }
            screen.loadViewIfNeeded()
            let texts = labels(in: screen.view).compactMap(\.text)
            let case_ = "driver \(tryDriver), M chip \(mChip)"
            XCTAssertTrue(texts.contains("Plug the desk phone in with the Porch phone adapter."), case_)
            let guide = try XCTUnwrap(buttons(in: screen.view).first { $0.accessibilityIdentifier == "setup.phoneGuide" }, case_)
            XCTAssertEqual(guide.configuration?.title, "Step-by-step instructions", "A link, not the address")
            XCTAssertEqual(iPadGuideURL.absoluteString, "https://helloporch.store/pilot/ios#phone")
            XCTAssertFalse(texts.contains { $0.hasPrefix("1. ") || $0.hasPrefix("• ") || $0 == "Not working?" || $0.contains("You'll need") },
                           "The steps, parts and tips are on the guide: \(texts)")
            let note = texts.contains("This iPad doesn't need the adapter. Turn on the Cell2Jack's driver in Settings, then unplug the Cell2Jack for ten seconds and plug it back in.")
            let settings = buttons(in: screen.view).contains { $0.accessibilityIdentifier == "setup.phoneSettings" }
            XCTAssertEqual(note, tryDriver && mChip, case_); XCTAssertEqual(settings, tryDriver && mChip, case_)
        }
    }

    @MainActor func testCheckingThePhoneThroughTheAdapterTurnsOffADriverThatFindsNothing() throws {
        // An iPad whose Cell2Jack used to be plugged straight in, moved to the adapter: with the hang-up check and without.
        for hangUp in [true, false] {
            var keyboard = false
            let step = try phoneStep { keyboard }
            step.keypad.setEnabled(true); step.keypad.setReceiverHangUp(hangUp)
            step.connections()[0].update(.finished("No running Cell2Jack driver service"))
            keyboard = true
            NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
            step.screen.receiveKey(4)
            if hangUp { _ = step.screen.receiveCell2JackHangUp() }
            XCTAssertTrue(phoneStatus(step.screen)?.hasSuffix("The phone is ready.") == true, "\(hangUp)")
            XCTAssertFalse(step.keypad.enabled, "The phone answered without the driver, so the keypad setting goes off (\(hangUp))")
            try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneDone" }).sendActions(for: .touchUpInside)
            XCTAssertFalse(step.keypad.trying)
            XCTAssertEqual(step.connections().last?.stops, 1, "Leaving the screen stops looking for a Cell2Jack on the driver (\(hangUp))")
            step.connections().last?.update(.finished("Phone keypad stopped"))
            let tries = step.connections().count
            step.keypad.activate()
            XCTAssertEqual(step.connections().count, tries, "Back on the clock, Porch doesn't look again (\(hangUp))")
        }
    }

    @MainActor func testAnAdapterCheckWaitsForTheDriversFirstTryBeforeTurningTheKeypadOff() throws {
        // The keypad was already on, and the driver is still making its first try when the adapter's check finishes,
        // as for a few seconds after the screen opens: a Cell2Jack plugged straight in may yet answer.
        for hangUp in [true, false] {
            var keyboard = false
            let step = try phoneStep { keyboard }
            step.keypad.setEnabled(true); step.keypad.setReceiverHangUp(hangUp)
            keyboard = true
            NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
            step.screen.receiveKey(4)
            if hangUp { _ = step.screen.receiveCell2JackHangUp() }
            XCTAssertTrue(phoneStatus(step.screen)?.hasSuffix("The phone is ready.") == true, "\(hangUp)")
            XCTAssertTrue(step.keypad.connecting, "\(hangUp)")
            XCTAssertTrue(step.keypad.enabled, "The driver hasn't finished its first try (\(hangUp))")
            // That try finds nothing while the screen is still open: now the keypad goes off.
            step.connections()[0].update(.finished("No running Cell2Jack driver service"))
            XCTAssertFalse(step.keypad.enabled, "The driver found nothing, so the adapter is the phone's way in (\(hangUp))")
        }
    }

    @MainActor func testAnAdapterCheckThatSeesTheDriverAnswerLeavesTheKeypadOn() throws {
        // The first try was still open when the keyboard key arrived, then the Cell2Jack answered. Unplugging it
        // afterwards, as the note says to do for ten seconds, has to leave the keypad on.
        for hangUp in [true, false] {
            var keyboard = false
            let step = try phoneStep { keyboard }
            step.keypad.setEnabled(true); step.keypad.setReceiverHangUp(hangUp)
            keyboard = true
            NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
            step.screen.receiveKey(4)
            if hangUp { _ = step.screen.receiveCell2JackHangUp() }
            XCTAssertTrue(step.keypad.connecting, "\(hangUp)")
            step.connections()[0].update(.ready)
            XCTAssertTrue(step.keypad.enabled, "The Cell2Jack answered (\(hangUp))")
            step.connections()[0].update(.finished("Phone keypad stopped"))
            XCTAssertTrue(step.keypad.enabled, "That answer already decided it, so a later drop leaves the keypad on (\(hangUp))")
        }
    }

    @MainActor func testLeavingPorchDuringTheDriversFirstTryIsNotTheDriverFindingNothing() throws {
        // Open Settings, or switching apps, while the first try is still open: Porch stops that try itself, which
        // says nothing about whether a Cell2Jack is plugged straight in.
        for hangUp in [true, false] {
            var keyboard = false
            let step = try phoneStep { keyboard }
            step.keypad.setEnabled(true); step.keypad.setReceiverHangUp(hangUp)
            keyboard = true
            NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
            step.screen.receiveKey(4)
            if hangUp { _ = step.screen.receiveCell2JackHangUp() }
            XCTAssertTrue(step.keypad.connecting, "\(hangUp)")
            step.keypad.pause()
            step.connections()[0].update(.finished("Phone keypad stopped"))
            XCTAssertTrue(step.keypad.enabled, "Porch stopped the try, so it found nothing out (\(hangUp))")
            // Back in Porch, the next try finds nothing: that decides it.
            step.keypad.activate()
            XCTAssertEqual(step.connections().count, 2, "\(hangUp)")
            step.connections()[1].update(.finished("No running Cell2Jack driver service"))
            XCTAssertFalse(step.keypad.enabled, "\(hangUp)")
        }
    }

    @MainActor func testAKeyboardKeyWhileTheDriverAnswersLeavesThePhoneKeypadOn() throws {
        // A keyboard case on an iPad whose Cell2Jack is plugged straight in.
        let step = try phoneStep { true }
        step.keypad.setEnabled(true)
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        step.connections()[0].update(.ready)
        step.screen.receiveKey(4)
        _ = step.screen.receiveCell2JackHangUp()
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard you hang up. The phone is ready.")
        XCTAssertTrue(step.keypad.enabled, "The Cell2Jack on the driver still needs it")
        // The note says to unplug the Cell2Jack for ten seconds. That ends the connection the key already found answering.
        step.connections()[0].update(.finished("Phone keypad stopped"))
        XCTAssertTrue(step.keypad.enabled, "The driver had already answered, so unplugging it does not turn the keypad off")
    }

    @MainActor func testSetupAsksHowTheyCallWithTheTouchscreenToFallBackOn() throws {
        let setup = BedsideSetup(); setup.name = "Mom"
        let choice = SetupCallingViewController(setup)
        let navigation = UINavigationController(rootViewController: choice); choice.loadViewIfNeeded()
        XCTAssertTrue(labels(in: choice.view).contains { $0.text == "How will Mom call?" })
        // Every family has the adapter, which needs no driver, so every build offers the corded phone the same way.
        let corded = try XCTUnwrap(buttons(in: choice.view).first { $0.accessibilityIdentifier == "setup.cordedPhone" })
        XCTAssertEqual(corded.configuration?.subtitle, "Plugged in with the Porch phone adapter.")
        XCTAssertEqual(corded.configuration?.subtitle, SetupPhoneViewController.parts)
        XCTAssertEqual(corded.configuration?.subtitleLineBreakMode, .byWordWrapping, "A one-line subtitle could cut off the end")
        // A USB keypad was for testing: the corded phone is the only choice besides the touchscreen.
        XCTAssertEqual(buttons(in: choice.view).compactMap { $0.configuration?.subtitle == nil ? nil : $0.configuration?.title }, ["Corded phone"])
        corded.sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.viewControllers.last is SetupPhoneViewController)

        let again = SetupCallingViewController(setup)
        let shown = UINavigationController(rootViewController: again)
        let window = try showing(shown)
        defer { window.isHidden = true }
        try XCTUnwrap(buttons(in: again.view).first { $0.accessibilityIdentifier == "setup.touchscreen" }).sendActions(for: .touchUpInside)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(shown.viewControllers.count, 1)
        XCTAssertFalse(shown.viewControllers[0] is SetupCallingViewController, "The touchscreen needs nothing, so setup goes on")
    }

    /// In a window on the app's scene, so the screen appears and disappears as it does in the app.
    @MainActor private func showing(_ root: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root; window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return window
    }

    @MainActor func testGoingBackFromThePhoneToChooseAgainTurnsTheKeypadBackOff() throws {
        let step = try phoneStep()
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try showing(navigation)
        defer { window.isHidden = true }
        navigation.pushViewController(step.screen, animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        try XCTUnwrap(step.connections().last).update(.ready)
        XCTAssertTrue(step.keypad.enabled)
        navigation.popViewController(animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(step.keypad.enabled, "Going back to choose another way is like Do this later")
        XCTAssertFalse(step.keypad.trying)
    }

    /// Connect the phone on a build or device without the driver, so only the adapter can answer. Returns the screen in a
    /// window on the app's scene.
    @MainActor private func adapterStep(receiverHangUp: Bool = true) throws -> (screen: SetupPhoneViewController, keypad: Cell2JackKeypad,
                                                                             connected: (Bool) -> Void, done: () -> Int, window: UIWindow) {
        let name = "setup-adapter-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }, enqueueRetry: { _, _ in }) { update in
            XCTFail("The adapter needs no driver connection"); return Connection(update)
        }
        keypad.setReceiverHangUp(receiverHangUp)
        var connected = false, finished = 0
        let setup = BedsideSetup(); setup.name = "Mom"
        let screen = SetupPhoneViewController(setup, keypad: keypad, tryDriver: false) { connected }
        screen.onContinue = { finished += 1 }
        let navigation = UINavigationController(rootViewController: screen)
        let window = try showing(navigation)
        keypad.root = navigation; keypad.windowScene = window.windowScene
        keypad.activate()
        return (screen, keypad, { connected = $0; NotificationCenter.default.post(name: $0 ? .GCKeyboardDidConnect : .GCKeyboardDidDisconnect, object: nil) },
                { finished }, window)
    }

    @MainActor func testTheAdapterPhoneScreenChecksAKeyThenTheReceiverGoingBack() throws {
        let step = try adapterStep()
        defer { step.window.isHidden = true }
        let status = { self.phoneStatus(step.screen) }
        let proceed = try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneDone" })
        let later = try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneLater" })
        XCTAssertTrue(labels(in: step.screen.view).contains { $0.text == "Connect the phone" })
        XCTAssertFalse(buttons(in: step.screen.view).contains { $0.accessibilityIdentifier == "setup.phoneSettings" },
                       "Without the driver there's no USB driver to turn on")
        XCTAssertEqual(status(), "Waiting for the phone…")
        XCTAssertTrue(proceed.isHidden); XCTAssertFalse(later.isHidden)
        step.connected(true)
        XCTAssertEqual(status(), "Lift the receiver and press a key.")
        XCTAssertEqual(step.screen.receiveCell2JackHangUp(), "setup: hang-up before a key")
        step.screen.receiveKey(CallSlots.pound)
        XCTAssertEqual(status(), "Porch heard #. Now put the receiver back.")
        XCTAssertTrue(proceed.isHidden)
        // Unplugged before hanging up: the hang-up would go unheard, so the phone is checked again.
        step.connected(false)
        XCTAssertEqual(status(), "Waiting for the phone…")
        step.connected(true)
        step.screen.receiveKey(3)
        // The adapter's hang-up key comes the way PorchWindow sends it, through the router to the visible screen.
        step.keypad.receiveAdapterHangUp()
        XCTAssertEqual(status(), "Porch heard you hang up. The phone is ready.")
        XCTAssertFalse(proceed.isHidden); XCTAssertTrue(later.isHidden)
        step.screen.receiveKey(5)
        step.connected(false)
        XCTAssertEqual(status(), "Porch heard you hang up. The phone is ready.", "Nothing after the check undoes it")
        XCTAssertFalse(step.keypad.enabled, "The adapter never turns the driver's keypad on")
        proceed.sendActions(for: .touchUpInside)
        XCTAssertEqual(step.done(), 1)
    }

    @MainActor func testTheAdapterPhoneScreenNeedsOnlyAKeyWhenHangingUpIsOff() throws {
        let step = try adapterStep(receiverHangUp: false)
        defer { step.window.isHidden = true }
        step.connected(true)
        step.screen.receiveKey(1)
        XCTAssertEqual(phoneStatus(step.screen), "Porch heard 1. The phone is ready.")
        XCTAssertTrue(step.keypad.adapterHeard, "A key is the whole check, so it's the adapter heard")
        XCTAssertFalse(try XCTUnwrap(buttons(in: step.screen.view).first { $0.accessibilityIdentifier == "setup.phoneDone" }).isHidden)
        let skipped = try adapterStep()
        defer { skipped.window.isHidden = true }
        try XCTUnwrap(buttons(in: skipped.screen.view).first { $0.accessibilityIdentifier == "setup.phoneLater" }).sendActions(for: .touchUpInside)
        XCTAssertEqual(skipped.done(), 1, "Do this later goes on without the check")
    }

    @MainActor func testThisIPadConnectsTheDeskPhoneAndCanStopTheReceiverHangingUp() throws {
        let name = "device-phone-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }, enqueueRetry: { _, _ in }) { Connection($0) }
        let device = DeviceSettingsViewController(phoneKeypad: keypad)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = device; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // Every build has the switch: the adapter hangs up with the receiver without the driver.
        let receiver = try XCTUnwrap(descendants(device.view).compactMap { $0 as? UISwitch }.first { $0.accessibilityIdentifier == "device.cell2jackReceiverHangUp" })
        XCTAssertTrue(receiver.isOn)
        receiver.isOn = false; receiver.sendActions(for: .valueChanged)
        XCTAssertFalse(keypad.receiverHangUp)
        try XCTUnwrap(buttons(in: device.view).first { $0.accessibilityIdentifier == "device.connectPhone" }).sendActions(for: .touchUpInside)
        let phoneNav = try XCTUnwrap(device.presentedViewController as? UINavigationController)
        XCTAssertTrue(phoneNav.viewControllers.first is SetupPhoneViewController)
        XCTAssertEqual(phoneNav.viewControllers.first?.title, "Connect the phone", "The view loads before onContinue is set")
        XCTAssertFalse(buttons(in: device.view).contains { $0.accessibilityIdentifier == "device.connectCell2Jack" },
                       "Connect the phone covers a Cell2Jack on the driver too")
        // Connect the phone sets onContinue after building the navigation, which can load the view first. Whether
        // it does depends on timing, so load it here: that's the case the title has to survive.
        let driver = SetupPhoneViewController(BedsideSetup())
        driver.loadViewIfNeeded()
        XCTAssertEqual(driver.title, "Set up Porch")
        driver.onContinue = {}
        XCTAssertEqual(driver.title, "Connect the phone")
    }

    /// This iPad has one group for the phone. On an iPad without an M chip, or in a build without the driver, it has what
    /// the adapter needs. Where the driver can work it also has the way to the USB driver's switch. Connect the phone
    /// connects to the driver right away and turns the Cell2Jack keypad on itself, so there's no separate retry or
    /// switch, and the USB keypad, which was for testing, is gone.
    @MainActor func testThisIPadShowsTheDriversSettingsOnlyWhereTheDriverCanWork() throws {
        for (driver, mChip) in [(false, false), (false, true), (true, false), (true, true)] {
            let name = "device-groups-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { false }, enqueueRetry: { _, _ in }) { Connection($0) }
            let device = DeviceSettingsViewController(phoneKeypad: keypad, driver: driver, mChip: mChip)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
            window.rootViewController = device; window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let headings = labels(in: device.view).filter { $0.accessibilityTraits.contains(.header) }.compactMap(\.text)
            XCTAssertTrue(headings.contains("Connect the physical phone"), "\(headings)")
            for old in ["Desk phone", "Cell2Jack plugged into this iPad", "USB keypad"] { XCTAssertFalse(headings.contains(old), old) }
            XCTAssertTrue(labels(in: device.view).contains { $0.text == SetupPhoneViewController.parts })
            let phoneActions = ["Connect the phone", "Open app settings", "Retry phone connection", "Connect the USB keypad"]
            XCTAssertEqual(buttons(in: device.view).compactMap { $0.configuration?.title }.filter(phoneActions.contains),
                           driver ? ["Connect the phone", "Open app settings"] : ["Connect the phone"])
            XCTAssertEqual(descendants(device.view).compactMap { ($0 as? UISwitch)?.accessibilityLabel }, ["Hang up when the receiver is put back"])
            // Connect the phone mentions the M chip and the USB driver only on an iPad known to have one, with the driver.
            try XCTUnwrap(buttons(in: device.view).first { $0.accessibilityIdentifier == "device.connectPhone" }).sendActions(for: .touchUpInside)
            let phoneNav = try XCTUnwrap(device.presentedViewController as? UINavigationController)
            let phone = try XCTUnwrap(phoneNav.viewControllers.first as? SetupPhoneViewController)
            phone.loadViewIfNeeded()
            XCTAssertEqual(buttons(in: phone.view).contains { $0.accessibilityIdentifier == "setup.phoneSettings" }, driver && mChip)
            device.dismiss(animated: false)
        }
    }

    /// This iPad's phone group, with the status row's words if it has one and the way in.
    @MainActor private func deskPhoneRows(_ device: UIViewController) -> (status: String?, action: String?) {
        let status = descendants(device.view).first { $0.accessibilityIdentifier == "device.phoneStatus" }?.accessibilityLabel
        let action = buttons(in: device.view).first { $0.accessibilityIdentifier == "device.connectPhone" }?.configuration?.title
        return (status, action)
    }

    @MainActor func testThisIPadSaysTheCell2JackOnTheDriverIsConnectedAndChecksItAlreadyDone() throws {
        let name = "device-driver-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var connections: [Connection] = []
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }, enqueueRetry: { _, _ in }) { update in
            let connection = Connection(update); connections.append(connection); return connection
        }
        keypad.activate()
        let device = DeviceSettingsViewController(phoneKeypad: keypad, driver: true, mChip: true) { false }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = device; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        XCTAssertEqual(deskPhoneRows(device).status, nil, "Before the phone is set up, the group is as it was")
        XCTAssertEqual(deskPhoneRows(device).action, "Connect the phone")
        // Connect the phone turned the keypad on, and the Cell2Jack hasn't answered yet.
        keypad.setEnabled(true)
        XCTAssertEqual(deskPhoneRows(device).status, "The phone isn't connected")
        XCTAssertEqual(deskPhoneRows(device).action, "Connect the phone")
        connections[0].update(.ready)
        XCTAssertEqual(deskPhoneRows(device).status, "The phone is connected")
        XCTAssertEqual(deskPhoneRows(device).action, "Check the phone")
        XCTAssertEqual(descendants(device.view).compactMap { ($0 as? UISwitch)?.accessibilityLabel }, ["Hang up when the receiver is put back"])
        XCTAssertTrue(buttons(in: device.view).contains { $0.configuration?.title == "Open app settings" })

        try XCTUnwrap(buttons(in: device.view).first { $0.accessibilityIdentifier == "device.connectPhone" }).sendActions(for: .touchUpInside)
        let phoneNav = try XCTUnwrap(device.presentedViewController as? UINavigationController)
        let check = try XCTUnwrap(phoneNav.viewControllers.first as? SetupPhoneViewController)
        check.loadViewIfNeeded(); check.viewDidAppear(false)
        XCTAssertEqual(check.title, "Check the phone")
        XCTAssertEqual(phoneStatus(check), "The phone is connected.")
        XCTAssertTrue(labels(in: check.view).contains { $0.text == "Lift the receiver and press a key to try it." && !$0.isHidden })
        XCTAssertFalse(labels(in: check.view).contains { $0.text == "Plug the desk phone in with the Porch phone adapter." })
        XCTAssertFalse(buttons(in: check.view).contains { $0.accessibilityIdentifier == "setup.phoneSettings" },
                       "A Cell2Jack that answers needs nothing turned on")
        let done = try XCTUnwrap(buttons(in: check.view).first { $0.accessibilityIdentifier == "setup.phoneDone" })
        XCTAssertEqual(done.configuration?.title, "Done"); XCTAssertFalse(done.isHidden)
        XCTAssertTrue(try XCTUnwrap(buttons(in: check.view).first { $0.accessibilityIdentifier == "setup.phoneLater" }).isHidden)
        XCTAssertEqual(connections.count, 1, "Checking a connected phone doesn't connect again")
        // A key and hanging up still check it.
        XCTAssertEqual(check.receiveCell2JackDigit(7), "setup: heard 7")
        XCTAssertEqual(phoneStatus(check), "Porch heard 7. Now put the receiver back.")
        XCTAssertTrue(labels(in: check.view).contains { $0.text == "Lift the receiver and press a key to try it." && $0.isHidden })
        XCTAssertFalse(done.isHidden, "Done stays, with nothing to put off")
        _ = check.receiveCell2JackHangUp()
        XCTAssertEqual(phoneStatus(check), "Porch heard you hang up. The phone is ready.")
        done.sendActions(for: .touchUpInside)
        XCTAssertTrue(keypad.enabled, "Done leaves the keypad on")
        XCTAssertFalse(keypad.trying)

        connections[0].update(.finished("Phone keypad stopped"))
        XCTAssertEqual(deskPhoneRows(device).status, "The phone isn't connected", "Unplugged, the keypad stays on and This iPad says so")
        XCTAssertEqual(deskPhoneRows(device).action, "Connect the phone")
    }

    @MainActor func testThisIPadTakesAKeyboardForTheAdapterOnlyOnceTheAdapterHasBeenHeard() throws {
        let name = "device-adapter-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }, enqueueRetry: { _, _ in }) { Connection($0) }
        var keyboard = true
        let device = DeviceSettingsViewController(phoneKeypad: keypad, driver: false, mChip: false) { keyboard }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = device; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        XCTAssertEqual(deskPhoneRows(device).status, nil, "A keyboard alone may be a keyboard case")
        XCTAssertEqual(deskPhoneRows(device).action, "Connect the phone")
        keypad.noteAdapterHeard()
        XCTAssertEqual(deskPhoneRows(device).status, "The phone is connected")
        XCTAssertEqual(deskPhoneRows(device).action, "Check the phone")
        keyboard = false
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
        XCTAssertEqual(deskPhoneRows(device).status, "The phone isn't connected")
        XCTAssertEqual(deskPhoneRows(device).action, "Connect the phone")
        XCTAssertFalse(buttons(in: device.view).contains { $0.configuration?.title == "Open app settings" })
        keyboard = true
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)

        // Check the phone through the adapter: unplugged while it's open, it goes back to waiting, then checks as setup does.
        try XCTUnwrap(buttons(in: device.view).first { $0.accessibilityIdentifier == "device.connectPhone" }).sendActions(for: .touchUpInside)
        let phoneNav = try XCTUnwrap(device.presentedViewController as? UINavigationController)
        let check = try XCTUnwrap(phoneNav.viewControllers.first as? SetupPhoneViewController)
        check.loadViewIfNeeded()
        XCTAssertEqual(phoneStatus(check), "The phone is connected.")
        keyboard = false
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
        XCTAssertEqual(phoneStatus(check), "Waiting for the phone…")
        XCTAssertFalse(try XCTUnwrap(buttons(in: check.view).first { $0.accessibilityIdentifier == "setup.phoneDone" }).isHidden)
        keyboard = true
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        XCTAssertEqual(phoneStatus(check), "Lift the receiver and press a key.")
        check.receiveKey(2)
        XCTAssertEqual(phoneStatus(check), "Porch heard 2. Now put the receiver back.")
        device.dismiss(animated: false)
    }

    /// The adapter already counts as connected, so Check the phone is up, and a Cell2Jack on the driver answers while
    /// it's open. Done is showing the whole time and is the only way out, so it must not turn that keypad back off.
    @MainActor func testCheckThePhoneDoneLeavesACell2JackThatAnsweredOn() throws {
        let name = "device-check-done-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var connections: [Connection] = []
        let keypad = Cell2JackKeypad(defaults: defaults, isBedside: { true }, enqueueRetry: { _, _ in }) { update in
            let connection = Connection(update); connections.append(connection); return connection
        }
        keypad.activate()
        keypad.noteAdapterHeard()
        let device = DeviceSettingsViewController(phoneKeypad: keypad, driver: true, mChip: true) { true }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = device; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        XCTAssertFalse(keypad.enabled, "The adapter left the driver's keypad off")
        XCTAssertEqual(deskPhoneRows(device).action, "Check the phone")
        try XCTUnwrap(buttons(in: device.view).first { $0.accessibilityIdentifier == "device.connectPhone" }).sendActions(for: .touchUpInside)
        let phoneNav = try XCTUnwrap(device.presentedViewController as? UINavigationController)
        let check = try XCTUnwrap(phoneNav.viewControllers.first as? SetupPhoneViewController)
        check.loadViewIfNeeded(); check.viewDidAppear(false)
        XCTAssertEqual(connections.count, 1, "Check the phone still tries a Cell2Jack plugged straight in")
        XCTAssertFalse(keypad.enabled)
        connections[0].update(.ready)
        XCTAssertTrue(keypad.enabled, "A Cell2Jack that answers during the check turns the keypad on")
        let done = try XCTUnwrap(buttons(in: check.view).first { $0.accessibilityIdentifier == "setup.phoneDone" })
        XCTAssertFalse(done.isHidden)
        done.sendActions(for: .touchUpInside)
        XCTAssertTrue(keypad.enabled, "Done is not Do this later")
        XCTAssertFalse(keypad.trying)
        XCTAssertEqual(connections[0].stops, 0, "The keypad that just answered stays connected")
    }

    @MainActor func testAddYourPhoneAsksForTheirNameAndItsCodeReadsAsTheInvitation() throws {
        let setup = BedsideSetup(); setup.name = "Mom"
        let screen = SetupYourPhoneViewController(setup); screen.loadViewIfNeeded()
        let all = descendants(screen.view)
        XCTAssertNotNil(all.compactMap { $0 as? UITextField }.first { $0.accessibilityIdentifier == "setup.yourName" })
        XCTAssertFalse(try XCTUnwrap(buttons(in: screen.view).first { $0.accessibilityIdentifier == "setup.showCode" }).isHidden)
        XCTAssertFalse(try XCTUnwrap(buttons(in: screen.view).first { $0.accessibilityIdentifier == "setup.yourPhoneLater" }).isHidden, "Setup can go on without a phone")
        XCTAssertTrue(try XCTUnwrap(buttons(in: screen.view).first { $0.accessibilityIdentifier == "setup.yourPhoneDone" }).isHidden)
        XCTAssertTrue(try XCTUnwrap(all.first { $0.accessibilityIdentifier == "setup.code" }).superview?.isHidden == true)
        let link = "https://helloporch.store/join#code=" + String(repeating: "ab", count: 32)
        let image = try XCTUnwrap(SetupYourPhoneViewController.qrCode(link)?.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        XCTAssertEqual(detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }, [link])
    }

    @MainActor func testDoneExplainsWhoCanCallAndGoesOnToTheKeypad() {
        let setup = BedsideSetup(); setup.name = "Mom"
        let done = SetupDoneViewController(setup); done.loadViewIfNeeded()
        let text = labels(in: done.view).compactMap(\.text)
        XCTAssertTrue(text.contains("Mom's Porch is ready"))
        XCTAssertTrue(text.contains("Only people on the keypad and numbers you allow can call it."))
        XCTAssertTrue(buttons(in: done.view).contains { $0.configuration?.title == "Put people on the keypad" })
        XCTAssertTrue(done.navigationItem.hidesBackButton)
    }
}

final class ScreenAwakeTests: XCTestCase {
    /// A family phone keeps its screen on only while a call screen is open. The bedside clock always does.
    @MainActor func testCallScreensKeepAFamilyPhoneAwake() {
        let defaults = UserDefaults.standard, saved = defaults.object(forKey: "porch.experience")
        let call = UIViewController()
        defer { defaults.set(saved, forKey: "porch.experience"); ScreenAwake.callDisappeared(call); ScreenAwake.update(inFront: false) }
        defaults.set("family", forKey: "porch.experience")
        ScreenAwake.update(inFront: true)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        ScreenAwake.callShown(call, voice: true); ScreenAwake.update(inFront: true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        ScreenAwake.update(inFront: false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "In the background iOS dims and locks as usual")
        XCTAssertFalse(UIDevice.current.isProximityMonitoringEnabled)
        ScreenAwake.callDisappeared(call); ScreenAwake.update(inFront: true)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "The call screen closed")
        defaults.set("bedside", forKey: "porch.experience")
        ScreenAwake.update(inFront: true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled, "The bedside clock stays on")
    }

    /// Both call screens hold the screen on from appearing until they close, and doing so doesn't connect a call.
    @MainActor func testCallScreensHoldTheScreenUntilTheyClose() throws {
        let defaults = UserDefaults.standard, saved = defaults.object(forKey: "porch.experience")
        defer { defaults.set(saved, forKey: "porch.experience"); ScreenAwake.update(inFront: false) }
        defaults.set("family", forKey: "porch.experience")
        let call = try NativeCall(room: "awake-test", mode: .voice)
        let contact = try CallContact(name: "Family", nativeCall: call, phoneNumber: "+14155550123")
        let server = try NativeCallServer(url: "https://example.com", accessCode: "test-credential-no-network")
        let placed = try NativeCallViewController.phoneFallback(contact, server: server)
        placed.viewWillAppear(false)
        XCTAssertFalse(placed.isViewLoaded, "The appearance hook must not connect a call")
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        placed.viewDidDisappear(false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        // Answered through CallKit. Loading this view would build the call's controls.
        let answered = SystemCallViewController()
        answered.viewWillAppear(false)
        XCTAssertFalse(answered.isViewLoaded)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        answered.viewDidDisappear(false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    /// A screen over the call, such as the phone keypad, keeps the screen on. Closing the call screen doesn't.
    @MainActor func testOnlyClosingTheCallScreenLetsThePhoneSleep() async throws {
        let defaults = UserDefaults.standard, saved = defaults.object(forKey: "porch.experience")
        let original = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow })
        let window = UIWindow(windowScene: try XCTUnwrap(original.windowScene))
        let root = UIViewController(); window.rootViewController = root; window.makeKeyAndVisible()
        defer { defaults.set(saved, forKey: "porch.experience"); ScreenAwake.update(inFront: false); window.isHidden = true; original.makeKeyAndVisible() }
        defaults.set("family", forKey: "porch.experience")
        let call = CallScreenProbe(); call.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in root.present(call, animated: false) { done.resume() } }
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        let cover = UIViewController(); cover.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in call.present(cover, animated: false) { done.resume() } }
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled, "A screen over the call is still the call")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in cover.dismiss(animated: false) { done.resume() } }
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in call.dismiss(animated: false) { done.resume() } }
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled, "The call screen closed")
    }
}

/// The call screens' appear and disappear hooks, so a real present and dismiss can be checked without a call.
private final class CallScreenProbe: UIViewController {
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); ScreenAwake.callShown(self, voice: true) }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); ScreenAwake.callDisappeared(self) }
}
