import Foundation
import CryptoKit

/// Slot records keep only a content identifier. Image bytes are read when a
/// screen displays the person, never while polling or handling a keypad digit.
public struct ContactPhotoStore: Equatable {
    public let directoryURL: URL
    public init(directoryURL: URL) { self.directoryURL = directoryURL }
    public static let standard = ContactPhotoStore(directoryURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Porch/ContactPhotos", isDirectory: true))
    static let codingKey = CodingUserInfoKey(rawValue: "porch.contactPhotoStore")!

    static func validID(_ id: String) -> Bool {
        id.count == 64 && id.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
    private func url(for id: String) -> URL { directoryURL.appendingPathComponent(id).appendingPathExtension("jpg") }

    public func data(for id: String) -> Data? {
        guard Self.validID(id), let size = try? url(for: id).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 1_000_000,
              let data = try? Data(contentsOf: url(for: id)), data.count <= 1_000_000 else { return nil }
        return data
    }
    func save(_ data: Data, id: String) throws {
        guard Self.validID(id) else { throw CallContact.ValidationError.invalidAppearance }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: url(for: id), options: options)
    }

    /// Keep recently written files available to in-flight edits. Prune old,
    /// unreferenced files only after a successful settings save.
    func prune(keeping ids: Set<String>, olderThan cutoff: Date = Date().addingTimeInterval(-86_400)) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.pathExtension == "jpg" {
            let id = file.deletingPathExtension().lastPathComponent
            guard Self.validID(id), !ids.contains(id),
                  let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}

struct ContactPhoto: Equatable {
    let id: String
    let inlineData: Data?
    let store: ContactPhotoStore
    var data: Data? { inlineData ?? store.data(for: id) }

    init(data: Data, store: ContactPhotoStore = .standard) throws {
        guard !data.isEmpty, data.count <= 1_000_000 else { throw CallContact.ValidationError.invalidAppearance }
        id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        inlineData = data; self.store = store
    }
    init(id: String, store: ContactPhotoStore) throws {
        guard ContactPhotoStore.validID(id) else { throw CallContact.ValidationError.invalidAppearance }
        self.id = id; inlineData = nil; self.store = store
    }
    func persist(to destination: ContactPhotoStore) throws {
        if let inlineData { try destination.save(inlineData, id: id) }
        else if destination != store, let data = store.data(for: id) { try destination.save(data, id: id) }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
