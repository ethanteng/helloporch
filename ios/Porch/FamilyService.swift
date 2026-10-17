import Foundation
import UIKit
import CryptoKit
import Security
import PorchCore

extension Notification.Name {
    static let porchFamilyChanged = Notification.Name("porch.family.changed")
    static let porchExperienceChanged = Notification.Name("porch.experience.changed")
}

enum PorchDevice {
    static var experience: PorchExperience {
        get { PorchExperience(rawValue: UserDefaults.standard.string(forKey: "porch.experience") ?? "") ?? (UIDevice.current.userInterfaceIdiom == .phone ? .family : .bedside) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "porch.experience"); NotificationCenter.default.post(name: .porchExperienceChanged, object: nil) }
    }
    static var defaultOrigin: URL { URL(string: Bundle.main.object(forInfoDictionaryKey: "PorchServerURL") as? String ?? "https://porch-calling-prototype.vercel.app")! }
    static func credential(for role: PorchExperience) -> FamilyCredential? {
        NativeCallSettings.readSecret("porch.family.\(role.rawValue)").flatMap { try? JSONDecoder().decode(FamilyCredential.self, from: $0) }
    }
    static var bedsideActivation: URL? {
        NativeCallSettings.readSecret("porch.bedside.activation").flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }
    static func saveActivation(_ url: URL?) throws {
        try NativeCallSettings.writeSecret(Data((url?.absoluteString ?? "").utf8), account: "porch.bedside.activation")
    }
    private struct Pending: Codable { let profile: FamilyCredential; let scope: String }
    static func pending(role: PorchExperience, origin: URL, invitation: String = "") throws -> FamilyCredential {
        let account = "porch.family.pending.\(role.rawValue)"
        let scope = SHA256.hash(data: Data((origin.absoluteString + invitation).utf8)).map { String(format: "%02x", $0) }.joined()
        if let data = NativeCallSettings.readSecret(account), let saved = try? JSONDecoder().decode(Pending.self, from: data), saved.scope == scope { return saved.profile }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw NativeCallSettings.SettingsError.keychainFailure }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        let profile = FamilyCredential(origin: origin, credential: "\(UUID().uuidString.lowercased()).\(secret)", role: role)
        try NativeCallSettings.writeSecret(try JSONEncoder().encode(Pending(profile: profile, scope: scope)), account: account)
        return profile
    }
    static func registration(_ profile: FamilyCredential) -> [String: Any] {
        let pieces = profile.credential.split(separator: ".")
        return ["deviceID": String(pieces[0]), "deviceSecret": String(pieces[1])]
    }
    #if DEBUG
    static func installPreviewFixture() {
        guard ProcessInfo.processInfo.arguments.contains("--family-fixture") else { return }
        struct Fixture: Decodable { let profile: FamilyCredential; let pin: String?; let contacts: [String: CallContact]? }
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: folder.appendingPathComponent("PorchDebugFamily.json")),
              let fixture = try? JSONDecoder().decode(Fixture.self, from: data) else { return }
        try? save(fixture.profile)
        if let contacts = fixture.contacts {
            var slots = CallSlots()
            for (digit, contact) in contacts { if let digit = Int(digit) { try? slots.setContact(contact, for: digit) } }
            try? slots.save()
        }
        if let pin = fixture.pin { try? NativeCallSettings.writeSecret(Data(pin.utf8), account: "porch.contact-setup-code") }
        UserDefaults.standard.set(fixture.profile.role.rawValue, forKey: "porch.experience")
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("PorchDebugFamily.json"))
    }
    #endif
    static func save(_ credential: FamilyCredential) throws {
        try NativeCallSettings.writeSecret(try JSONEncoder().encode(credential), account: "porch.family.\(credential.role.rawValue)", accessibleAfterFirstUnlock: credential.role == .family)
    }
}

struct FamilyResponse: Decodable {
    let pushReady: Bool?
    let pinConfigured: Bool?
    let state: FamilySnapshot?
    let credential: String?
    let role: PorchExperience?
    let code: String?
    let invitationID: String?
    let expiresAt: TimeInterval?
    let token: String?
    let serverUrl: String?
}
struct FamilyServiceError: LocalizedError { let message: String; let status: Int; var code: String? = nil; var errorDescription: String? { message } }
struct FamilyService {
    let origin: URL
    let credential: String?
    init(_ credential: FamilyCredential) { origin = credential.origin; self.credential = credential.credential }
    init(origin: URL) { self.origin = origin; credential = nil }

    func send(_ action: String, _ values: [String: Any] = [:], pin: String? = nil) async throws -> FamilyResponse {
        var body = values; body["action"] = action
        var request = URLRequest(url: origin.appendingPathComponent("api/family"))
        request.httpMethod = "POST"; request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let credential { request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization") }
        if let pin { request.setValue(pin, forHTTPHeaderField: "X-Porch-Setup-Code") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            struct Failure: Decodable { let error: String; let errorCode: String? }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw FamilyServiceError(message: (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "Couldn't reach Porch. Check the connection and try again.", status: status, code: failure?.errorCode)
        }
        return try JSONDecoder().decode(FamilyResponse.self, from: data)
    }
}

struct FamilyCallSession {
    let credential: FamilyCredential
    let call: FamilyCallRecord
    let peerName: String
    var peerContact: CallContact? = nil
    var service: FamilyService { FamilyService(credential) }
    func end() async { _ = try? await service.send("endCall", ["callID": call.id]) }
}

@MainActor final class FamilyCoordinator {
    static let shared = FamilyCoordinator()
    private(set) var state: FamilySnapshot?
    private(set) var error: String?
    private(set) var credential: FamilyCredential?
    var canReceive: () -> Bool = { false }
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var isActive = false

    func start() {
        pause()
        isActive = true
        credential = PorchDevice.credential(for: PorchDevice.experience)
        state = nil; error = nil
        guard let credential else { changed(); return }
        SystemIncomingCalls.shared.registerDevice()
        let generation = UUID(); self.generation = generation
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isActive, self.generation == generation else { return }
                do {
                    let result = try await FamilyService(credential).send("poll", ["available": self.canReceive()])
                    guard !Task.isCancelled, self.generation == generation else { return }
                    self.state = result.state; self.error = nil; self.changed()
                } catch {
                    if Task.isCancelled { return }
                    self.error = error.localizedDescription; self.changed()
                }
                let seconds: UInt64 = self.state?.call.map { $0.state != "ended" } == true ? 1 : credential.role == .family ? 3 : 8
                do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            }
        }
    }
    func pause() {
        isActive = false; task?.cancel(); task = nil; generation = UUID()
        if let credential {
            Task { _ = try? await FamilyService(credential).send("poll", ["available": false]) }
        }
    }
    func update(_ response: FamilyResponse) {
        if let state = response.state { self.state = state; error = nil; changed() }
    }
    private func changed() {
        if let state, state.me.role == .bedside {
            do {
                var slots = try CallSlots.load()
                let previous = slots
                try slots.reconcile(with: state)
                if slots != previous { try slots.save() }
            } catch { self.error = error.localizedDescription }
        }
        NotificationCenter.default.post(name: .porchFamilyChanged, object: self)
    }
    func startCall(to person: FamilyPerson, mode: NativeCall.Mode, dropIn: Bool) async throws -> FamilyCallSession {
        try await startCall(targetID: person.id, name: person.name, mode: mode, dropIn: dropIn)
    }
    func startCall(targetID: String?, name: String, mode: NativeCall.Mode, dropIn: Bool, waitSeconds: Int = 45) async throws -> FamilyCallSession {
        guard let credential else { throw FamilyServiceError(message: "Pair this device first.", status: 401) }
        var values: [String: Any] = ["mode": mode.rawValue, "kind": dropIn ? "dropIn" : "call", "waitSeconds": waitSeconds]
        if let targetID { values["targetID"] = targetID } else { values["unlinked"] = true }
        let result = try await FamilyService(credential).send("startCall", values)
        update(result)
        guard let call = result.state?.call else { throw FamilyServiceError(message: "Couldn't start the call.", status: 503) }
        return FamilyCallSession(credential: credential, call: call, peerName: name)
    }
}
