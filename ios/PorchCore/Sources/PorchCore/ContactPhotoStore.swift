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
    /// Paired family members' own photos, downloaded from Porch. A separate folder, so saving the
    /// keypad never prunes them.
    public var familyMembers: ContactPhotoStore { ContactPhotoStore(directoryURL: directoryURL.appendingPathComponent("Family", isDirectory: true)) }
    /// A photo's identifier: the SHA-256 of its bytes, which Porch also uses for family members' photos.
    public static func id(for data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

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
    /// Whether a photo is saved, without reading it.
    public func contains(_ id: String) -> Bool { Self.validID(id) && FileManager.default.fileExists(atPath: url(for: id).path) }
    /// Saves a photo under its content identifier.
    public func add(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 1_000_000 else { throw CallContact.ValidationError.invalidAppearance }
        try save(data, id: Self.id(for: data))
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
    public func prune(keeping ids: Set<String>, olderThan cutoff: Date = Date().addingTimeInterval(-86_400)) {
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
        id = ContactPhotoStore.id(for: data)
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
