import Foundation
import XCTest
@testable import PorchCore

final class ContactPhotoStoreTests: XCTestCase {
    private func fixture(_ body: (UserDefaults, ContactPhotoStore) throws -> Void) throws {
        let suite = "photo-store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        try body(defaults, ContactPhotoStore(directoryURL: directory))
    }

    func testTenLargePhotosKeepSettingsSmallAndLoadWithoutOpeningImages() throws {
        try fixture { defaults, store in
            var slots = CallSlots()
            let call = try NativeCall(room: "test", mode: .video)
            for (index, digit) in CallSlots.digits.enumerated() {
                try slots.setContact(CallContact(name: "Person \(digit)", nativeCall: call,
                    buttonColorHex: "FFCC00", photoData: Data(repeating: UInt8(index), count: 900_000)), for: digit)
            }
            try slots.save(to: defaults, photoStore: store)
            let encoded = try XCTUnwrap(defaults.data(forKey: "porch.slots.v2"))
            XCTAssertLessThan(encoded.count, 10_000, "Frequent polling/keypad reads must only decode metadata")
            XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("photoData"))
            let restored = try CallSlots.load(from: defaults, photoStore: store)
            XCTAssertEqual(restored, slots, "Inline and file-backed contacts compare by stable photo identity")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directoryURL.path).count, 10)
            XCTAssertEqual(restored.contact(for: 1)?.photoData?.count, 900_000)

            let moved = store.directoryURL.appendingPathExtension("unavailable")
            try FileManager.default.moveItem(at: store.directoryURL, to: moved)
            defer { try? FileManager.default.removeItem(at: moved) }
            // Files unavailable: metadata and validation still work, photos load
            // lazily and fall back to the name when a screen asks for an image.
            for _ in 0..<10 {
                var reloaded = try CallSlots.load(from: defaults, photoStore: store)
                XCTAssertEqual(reloaded, slots)
                for digit in CallSlots.digits { try reloaded.setContact(reloaded.contact(for: digit), for: digit) }
                XCTAssertEqual(reloaded, slots)
                XCTAssertNil(reloaded.contact(for: 1)?.photoData)
            }
        }
    }

    func testInlinePhotoRecordsMigrateOnceWithoutLosingColorOrCallingDetails() throws {
        try fixture { defaults, store in
            try CallSlots().save(to: defaults, photoStore: store)
            var records = try XCTUnwrap(JSONSerialization.jsonObject(with: defaults.data(forKey: "porch.slots.v2")!) as? [[String: Any]])
            let photo = Data(repeating: 23, count: 900_000)
            records[0]["contact"] = ["name": "David", "address": "", "nativeCall": ["room": "test", "mode": "video"],
                "phoneNumber": "+14155550123", "buttonColorHex": "FFCC00", "photoData": photo.base64EncodedString()]
            defaults.set(try JSONSerialization.data(withJSONObject: records), forKey: "porch.slots.v2")
            XCTAssertGreaterThan(defaults.data(forKey: "porch.slots.v2")!.count, 1_000_000)
            let migrated = try CallSlots.load(from: defaults, photoStore: store)
            let person = try XCTUnwrap(migrated.contact(for: 1))
            XCTAssertEqual(person.photoData, photo)
            XCTAssertEqual(person.buttonColorHex, "FFCC00"); XCTAssertEqual(person.phoneNumber, "+14155550123")
            XCTAssertLessThan(defaults.data(forKey: "porch.slots.v2")!.count, 10_000)
            let reloaded = try CallSlots.load(from: defaults, photoStore: store)
            XCTAssertFalse(try XCTUnwrap(reloaded.contact(for: 1)).hasInlinePhoto)
            XCTAssertEqual(reloaded, migrated)
            XCTAssertEqual(reloaded.contact(for: 1)?.photoData, photo)
        }
    }

    func testFailedMigrationKeepsExistingInlineContactsUsable() throws {
        try fixture { defaults, store in
            try CallSlots().save(to: defaults, photoStore: store)
            var records = try XCTUnwrap(JSONSerialization.jsonObject(with: defaults.data(forKey: "porch.slots.v2")!) as? [[String: Any]])
            let photo = Data([1, 2, 3])
            records[0]["contact"] = ["name": "David", "address": "", "nativeCall": ["room": "test", "mode": "voice"], "photoData": photo.base64EncodedString()]
            let legacy = try JSONSerialization.data(withJSONObject: records)
            defaults.set(legacy, forKey: "porch.slots.v2")
            try Data([1]).write(to: store.directoryURL)
            let loaded = try CallSlots.load(from: defaults, photoStore: store)
            XCTAssertEqual(loaded.contact(for: 1)?.name, "David")
            XCTAssertEqual(loaded.contact(for: 1)?.photoData, photo)
            XCTAssertEqual(defaults.data(forKey: "porch.slots.v2"), legacy)
        }
    }

    func testPhotoWriteFailureDoesNotReplaceSavedSettings() throws {
        try fixture { defaults, store in
            try CallSlots().save(to: defaults, photoStore: store)
            let original = defaults.data(forKey: "porch.slots.v2")
            // A file in place of the directory simulates an unwritable store.
            try Data([1]).write(to: store.directoryURL)
            var changed = CallSlots()
            try changed.setContact(CallContact(name: "David", nativeCall: NativeCall(room: "test", mode: .voice), photoData: Data([1, 2, 3])), for: 1)
            XCTAssertThrowsError(try changed.save(to: defaults, photoStore: store))
            XCTAssertEqual(defaults.data(forKey: "porch.slots.v2"), original)
        }
    }

    func testInvalidReferencesCannotReadOutsidePhotoDirectory() throws {
        try fixture { defaults, store in
            for id in ["../private", String(repeating: "a", count: 63), String(repeating: "z", count: 64)] {
                XCTAssertNil(store.data(for: id))
                XCTAssertThrowsError(try ContactPhoto(id: id, store: store))
            }
        }
    }

    func testPruningRetainsReferencedAndRecentlyReplacedPhotos() throws {
        try fixture { _, store in
            let active = try ContactPhoto(data: Data([1]), store: store)
            let orphan = try ContactPhoto(data: Data([2]), store: store)
            let recent = try ContactPhoto(data: Data([3]), store: store)
            for photo in [active, orphan, recent] { try photo.persist(to: store) }
            for photo in [active, orphan] {
                let file = store.directoryURL.appendingPathComponent(photo.id).appendingPathExtension("jpg")
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-172_800)], ofItemAtPath: file.path)
            }
            store.prune(keeping: [active.id])
            XCTAssertNotNil(store.data(for: active.id)); XCTAssertNotNil(store.data(for: recent.id))
            XCTAssertNil(store.data(for: orphan.id))
        }
    }
}
