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
    /// A device that has never been set up either way, and hasn't been told which it is: Porch asks first. Anything
    /// that says otherwise, such as a pairing or a keypad, counts. Before the first unlock the keychain can't be read, so
    /// a set-up bedside could look new; Porch doesn't ask then.
    static var needsWelcome: Bool {
        guard UIApplication.shared.isProtectedDataAvailable, UserDefaults.standard.string(forKey: "porch.experience") == nil else { return false }
        return credential(for: .bedside) == nil && families.isEmpty && NativeCallSettings.caregiverCode.isEmpty && !CallSlots.isSaved()
            && bedsideActivation == nil
    }
    /// Writes down the mode a set-up device has been using all along, which older versions worked out from the device,
    /// so it never looks new to `needsWelcome`.
    static func rememberExperience() {
        guard UserDefaults.standard.string(forKey: "porch.experience") == nil, credential(for: .bedside) != nil || !families.isEmpty else { return }
        UserDefaults.standard.set(experience.rawValue, forKey: "porch.experience")
    }
    /// The bedside's pairing, or on a family phone the family its screens are showing (see `families`).
    static func credential(for role: PorchExperience) -> FamilyCredential? {
        role == .family ? currentFamily : stored("porch.family.bedside")
    }
    private static func stored(_ account: String) -> FamilyCredential? {
        NativeCallSettings.readSecret(account).flatMap { try? JSONDecoder().decode(FamilyCredential.self, from: $0) }
    }
    private static let familiesAccount = "porch.family.families"
    private static let currentFamilyKey = "porch.family.current"
    private static let nicknamesKey = "porch.family.nicknames"
    private static let householdsKey = "porch.family.households"
    /// Every family this phone has joined, such as both sets of parents, in the order it joined them. Each is its own
    /// pairing: the families never learn about each other. A phone paired before Porch allowed more than one family
    /// keeps its pairing under the old single-family account until the list is first saved.
    static var families: [FamilyCredential] {
        guard let data = NativeCallSettings.readSecret(familiesAccount) else { return [stored("porch.family.family")].compactMap { $0 } }
        return (try? JSONDecoder().decode([FamilyCredential].self, from: data)) ?? []
    }
    /// The family whose messages, profile and caregiver mode the phone's screens are showing.
    static var currentFamily: FamilyCredential? {
        let all = families, current = UserDefaults.standard.string(forKey: currentFamilyKey)
        return all.first { $0.deviceID == current } ?? all.first
    }
    static func select(_ credential: FamilyCredential) { UserDefaults.standard.set(credential.deviceID, forKey: currentFamilyKey) }
    /// The pairing a call or message for `memberID` belongs to. Each family knows this phone by a different ID.
    static func family(memberID: String?) -> FamilyCredential? { memberID.flatMap { id in families.first { $0.deviceID == id } } }
    /// Readable after the first unlock, so a call can ring on a locked phone that just restarted.
    private static func saveFamilies(_ families: [FamilyCredential]) throws {
        try NativeCallSettings.writeSecret(try JSONEncoder().encode(families), account: familiesAccount, accessibleAfterFirstUnlock: true)
        // The old single-family copy is in the list now. Left behind, a removed family would come back.
        if NativeCallSettings.readSecret("porch.family.family")?.isEmpty == false { try? NativeCallSettings.writeSecret(Data(), account: "porch.family.family") }
    }
    /// Takes a family off this phone, with what the phone called it. Leaving it on the server is up to the caller.
    static func removeFamily(_ credential: FamilyCredential) throws {
        try saveFamilies(families.filter { $0.deviceID != credential.deviceID })
        for key in [nicknamesKey, householdsKey] {
            var names = UserDefaults.standard.dictionary(forKey: key) ?? [:]
            names[credential.deviceID] = nil
            UserDefaults.standard.set(names, forKey: key)
        }
    }
    /// What this phone calls a family, shown only once it's in more than one: the name chosen here, or its household's,
    /// numbered when a family it joined earlier has the same one.
    static func familyName(_ credential: FamilyCredential) -> String? {
        let all = families
        guard let index = all.firstIndex(where: { $0.deviceID == credential.deviceID }) else { return unnumberedName(credential) }
        return FamilyNames.distinct(all.map(unnumberedName))[index]
    }
    /// The name chosen here, or its household's, before any number that tells it from another family's.
    static func unnumberedName(_ credential: FamilyCredential) -> String? {
        FamilyNames.family(nickname: nickname(credential), householdName: (UserDefaults.standard.dictionary(forKey: householdsKey)?[credential.deviceID] as? [String: String])?["name"])
    }
    static func nickname(_ credential: FamilyCredential) -> String? { UserDefaults.standard.dictionary(forKey: nicknamesKey)?[credential.deviceID] as? String }
    static func setNickname(_ nickname: String?, for credential: FamilyCredential) {
        var names = UserDefaults.standard.dictionary(forKey: nicknamesKey) ?? [:]
        if let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty { names[credential.deviceID] = String(trimmed.prefix(80)) }
        else { names[credential.deviceID] = nil }
        UserDefaults.standard.set(names, forKey: nicknamesKey)
    }
    /// The household a family's pairing belongs to, as it last checked in: so a call that rings before Porch has
    /// checked in can still say which family it's from, and a second invitation to the same family replaces the first.
    static func noteHousehold(_ state: FamilySnapshot, for credential: FamilyCredential) {
        let household = ["id": state.householdID, "name": state.householdName]
        var households = UserDefaults.standard.dictionary(forKey: householdsKey) ?? [:]
        guard households[credential.deviceID] as? [String: String] != household else { return }
        households[credential.deviceID] = household
        UserDefaults.standard.set(households, forKey: householdsKey)
    }
    static func householdID(_ credential: FamilyCredential) -> String? {
        (UserDefaults.standard.dictionary(forKey: householdsKey)?[credential.deviceID] as? [String: String])?["id"]
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
        if fixture.profile.role == .family { select(fixture.profile) }
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
    /// Saves the bedside's pairing, or adds a family to the ones this phone is in. A family already here (the same
    /// device identity) keeps its place. Both are readable after the first unlock, so a call can ring on a locked phone.
    static func save(_ credential: FamilyCredential) throws {
        guard credential.role == .family else {
            try NativeCallSettings.writeSecret(try JSONEncoder().encode(credential), account: "porch.family.bedside", accessibleAfterFirstUnlock: true); return
        }
        var all = families
        if let index = all.firstIndex(where: { $0.deviceID == credential.deviceID }) { all[index] = credential } else { all.append(credential) }
        try saveFamilies(all)
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
    let admin: FamilyAdminState?
    /// Family devices only: this device's sent messages (`listMessages`).
    let messages: [SentMessage]?
    /// Family devices only: messages the bedside left for this device (`listMessages`).
    let received: [ReceivedMessage]?
    let alertsReady: Bool?
    let message: SentMessage?
    let upload: MessageUploadTarget?
    let media: MessageMediaURL?
    /// Where an uploaded profile photo goes (`profilePhotoUpload`, `overridePhotoUpload`).
    let pathname: String?
    /// A family member's photo (`profilePhoto`, `caregiverProfilePhoto`).
    let photo: ProfilePhotoURL?
    /// A sentence read in the household's natural voice (`speech`).
    let clip: SpeechClip?
    /// The phone this caregiver just added to their call (`addPhoneGuest`).
    let phoneGuest: FamilyPhoneGuest?
    /// The family member just rung into the call (`addPorchGuest`).
    let porchGuest: FamilyPorchGuest?
    /// Calls to and from the bedside, newest first (`callHistory`).
    let calls: [CallHistoryEntry]?
    /// The household's number once it's set up (`assignPhoneNumber`), or `pending` while Porch keeps trying.
    let porchNumber: String?
    let pending: Bool?
    /// The area code suggested from where the iPad is, and others near it (`phoneNumberOptions`). None outside the US.
    let areaCode: String?
    let nearby: [String]?
}
/// A short-lived link to an announcement clip, and the voice that read it.
struct SpeechClip: Decodable { let voiceID: String; let url: String; let expiresAt: TimeInterval }
/// A presigned upload: send the file as the body with exactly these headers.
struct MessageUploadTarget: Decodable { let url: String; let method: String; let headers: [String: String]; let expiresAt: TimeInterval }
/// A short-lived link to one message's audio or video.
struct MessageMediaURL: Decodable { let url: String; let expiresAt: TimeInterval; let contentType: String }
struct FamilyServiceError: LocalizedError { let message: String; let status: Int; var code: String? = nil; var errorDescription: String? { message } }
struct FamilyService {
    let origin: URL
    let credential: String?
    init(_ credential: FamilyCredential) { origin = credential.origin; self.credential = credential.credential }
    init(origin: URL) { self.origin = origin; credential = nil }

    func send(_ action: String, _ values: [String: Any] = [:], pin: String? = nil, timeout: TimeInterval = 12) async throws -> FamilyResponse {
        var body = values; body["action"] = action
        var request = URLRequest(url: origin.appendingPathComponent("api/family"))
        request.httpMethod = "POST"; request.timeoutInterval = timeout
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

/// Caregiver mode opened from a family phone. The PIN is kept in memory only and is
/// forgotten after ten idle minutes or when the app leaves the foreground.
@MainActor final class RemoteCaregiverSession {
    static let shared = RemoteCaregiverSession()
    private var pin: String?
    private var expiresAt = Date.distantPast
    private static let idleSeconds: TimeInterval = 600
    func begin(pin: String) { self.pin = pin; expiresAt = Date().addingTimeInterval(Self.idleSeconds) }
    func end() { pin = nil; expiresAt = .distantPast }
    var isActive: Bool { pin != nil && expiresAt > Date() }
    /// The PIN for the next request; using it counts as activity.
    var activePIN: String? {
        guard isActive, let pin else { end(); return nil }
        expiresAt = Date().addingTimeInterval(Self.idleSeconds)
        return pin
    }
}

struct FamilyCallSession {
    let credential: FamilyCredential
    let call: FamilyCallRecord
    let peerName: String
    var peerContact: CallContact? = nil
    /// How long this caller rings before giving up. Family phones use the household's voicemail wait.
    var waitSeconds = CallPreferences.defaultVoicemailSeconds
    var service: FamilyService { FamilyService(credential) }
    /// The other device on this call.
    var peerID: String { call.from == credential.credential.split(separator: ".").first.map(String.init) ? call.to : call.from }
    func end() async { _ = try? await service.send("endCall", ["callID": call.id]) }
    func endConfirmed() async throws {
        do { _ = try await service.send("endCall", ["callID": call.id]) }
        catch let error as FamilyServiceError where error.status == 404 {
            // A newer call replaced this one; the server has already released it.
        }
    }
}

/// Numbers this launch's polls. Two can reach the server out of order, such as the one sent as Porch closes overtaking
/// the last one sent while it was open, and the server keeps the newest one's availability.
@MainActor enum PollOrder {
    private static let launch = UUID().uuidString.lowercased()
    private static var sequence = 0
    static func next(_ values: [String: Any]) -> [String: Any] {
        sequence += 1
        return values.merging(["launch": launch, "sequence": sequence]) { current, _ in current }
    }
}

@MainActor final class FamilyCoordinator {
    static let shared = FamilyCoordinator()
    /// One household this device belongs to, and what it last heard from it. The bedside has one; a family phone has
    /// one for each family it joined, and checks in with all of them so any of them can reach it.
    final class Link {
        let credential: FamilyCredential
        fileprivate(set) var state: FamilySnapshot?
        fileprivate(set) var error: String?
        /// The server no longer recognizes this device (a caregiver removed it, or it left).
        fileprivate(set) var accessRemoved = false
        fileprivate var task: Task<Void, Never>?
        init(_ credential: FamilyCredential) { self.credential = credential }
    }
    private(set) var links: [Link] = []
    /// The device ID of the family the screens are showing (see `PorchDevice.currentFamily`).
    private var currentID: String?
    private var current: Link? { links.first { $0.credential.deviceID == currentID } ?? links.first }
    var state: FamilySnapshot? { current?.state }
    var error: String? { current?.error }
    var accessRemoved: Bool { current?.accessRemoved ?? false }
    var credential: FamilyCredential? { current?.credential }
    var canReceive: () -> Bool = { false }
    private var generation = UUID()
    var isActive = false
    private var reportingKeypad = false
    /// When a failed report may be retried, for that device and those numbers.
    private var keypadRetry: (credential: String, numbers: [String], after: Date)?

    func link(for credential: FamilyCredential) -> Link? { links.first { $0.credential.credential == credential.credential } }
    /// What one family last said. A call keeps following its own family, whichever one the screens show.
    func state(for credential: FamilyCredential) -> FamilySnapshot? { link(for: credential)?.state }

    func start() {
        pause()
        isActive = true
        let credentials = PorchDevice.experience == .family ? PorchDevice.families : [PorchDevice.credential(for: .bedside)].compactMap { $0 }
        currentID = PorchDevice.credential(for: PorchDevice.experience)?.deviceID
        links = credentials.map(Link.init)
        FamilyMessageAlerts.shared.register()
        guard !links.isEmpty else { changed(); return }
        SystemIncomingCalls.shared.registerDevice()
        let generation = UUID(); self.generation = generation
        for link in links {
            let credential = link.credential
            link.task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.isActive, self.generation == generation else { return }
                    do {
                        var values: [String: Any] = ["available": self.canReceive()]
                        // How long ago someone was at the bedside iPad, so family can tell whether to call now. Never before
                        // this launch's first poll says that's on. While a caregiver has it off, nothing is kept to report later.
                        if credential.role == .bedside, link.state?.shareAttendance == false { AttendanceTracker.shared.forget() }
                        else if credential.role == .bedside, link.state?.shareAttendance == true, let seconds = AttendanceTracker.shared.secondsSince { values["attendedSeconds"] = seconds }
                        let result = try await FamilyService(credential).send("poll", PollOrder.next(values))
                        guard !Task.isCancelled, self.generation == generation else { return }
                        link.state = result.state; link.error = nil; link.accessRemoved = false; self.changed()
                    } catch {
                        if Task.isCancelled { return }
                        link.error = error.localizedDescription
                        // A dropped connection isn't the family putting the phone back. Only a later successful
                        // check-in clears the removal, so the card doesn't fill back in with calls that fail.
                        if (error as? FamilyServiceError)?.status == 401 { link.accessRemoved = true }
                        self.changed()
                    }
                    let seconds: UInt64 = link.state?.call.map { $0.state != "ended" } == true ? 1 : credential.role == .family ? 3 : 2
                    do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
                }
            }
        }
    }
    func pause() {
        isActive = false; generation = UUID()
        // An in-flight keypad report belongs to the session that started it. A failed report's wait is kept:
        // Porch pauses whenever it stops being active, and a wrong PIN mustn't be retried on every return.
        reportingKeypad = false
        for link in links {
            link.task?.cancel(); link.task = nil
            // Numbered now, after any poll still in flight.
            let values = PollOrder.next(["available": false]), credential = link.credential
            Task { _ = try? await FamilyService(credential).send("poll", values) }
        }
    }
    /// Shows a family phone's screens for one of its families. Caregiver mode was opened for the other one, so it ends.
    func select(_ credential: FamilyCredential) {
        guard credential.role == .family, credential.deviceID != current?.credential.deviceID else { return }
        PorchDevice.select(credential); currentID = credential.deviceID
        RemoteCaregiverSession.shared.end()
        changed()
    }
    /// Takes a family off this phone once it has left it, or the family removed it. The others keep ringing.
    func forget(_ credential: FamilyCredential) throws {
        try PorchDevice.removeFamily(credential)
        if isActive { start() }
        else { link(for: credential)?.task?.cancel(); links.removeAll { $0.credential.credential == credential.credential }; changed() }
    }
    /// Leaves a family on the server, then takes it off this phone.
    func leave(_ credential: FamilyCredential) async throws {
        do { _ = try await FamilyService(credential).send("leaveHousehold") }
        // Already removed, or its household is gone: nothing is left to leave.
        catch let failure as FamilyServiceError where [401, 404].contains(failure.status) {}
        try forget(credential)
    }
    /// A response's snapshot belongs to the family that knows this device by its member ID.
    func update(_ response: FamilyResponse) {
        guard let state = response.state, let link = links.first(where: { $0.credential.deviceID == state.me.id }) else { return }
        link.state = state; link.error = nil; changed()
    }
    /// A family member's photo finished downloading: keypad contacts and open screens can show it.
    func photoLoaded() { changed() }
    private func changed() {
        let known = links.compactMap { link in link.state.map { (state: $0, credential: link.credential) } }
        FamilyPhotos.shared.sync(known, everyFamily: known.count == links.count)
        for family in known where family.credential.role == .family { PorchDevice.noteHousehold(family.state, for: family.credential) }
        if let state, state.me.role == .bedside {
            do {
                var slots = try CallSlots.load()
                let previous = slots
                try slots.reconcile(with: state)
                if slots != previous { try slots.save() }
                PorchNaturalVoice.prefetch(state, slots: slots)
                reportKeypad(slots)
            } catch { current?.error = error.localizedDescription }
        }
        NotificationCenter.default.post(name: .porchFamilyChanged, object: self)
    }
    /// Keypad contacts live on this iPad. The server needs their numbers to let them ring while unknown callers are blocked,
    /// so they're reported whenever they differ from its copy.
    func reportKeypad(_ slots: CallSlots) {
        guard !reportingKeypad, let state, state.me.role == .bedside, let credential,
              let numbers = state.callScreening?.keypadNumbersToReport(slots) else { return }
        if let retry = keypadRetry, retry.credential == credential.credential, retry.numbers == numbers, retry.after > Date() { return }
        // Readable only while the iPad is unlocked; the next poll tries again.
        let pin = NativeCallSettings.caregiverCode
        guard !pin.isEmpty else { return }
        reportingKeypad = true
        let generation = self.generation
        let credentialID = credential.credential
        Task { [weak self] in
            do {
                let response = try await FamilyService(credential).send("setKeypadNumbers", ["numbers": numbers], pin: pin)
                // Leaving bedside mode, or pairing a different household, starts a new session. Its snapshot
                // must not be replaced by this one, and its own report must not be cancelled.
                guard let self, self.generation == generation, self.credential?.credential == credentialID else { return }
                self.keypadRetry = nil; self.reportingKeypad = false
                self.update(response)
            } catch {
                guard let self else { return }
                // A wrong PIN or a lockout waits longer, so retries can't use up the caregivers' PIN attempts.
                // The wait is kept even if Porch paused meanwhile; it only applies to this device's credential.
                let status = (error as? FamilyServiceError)?.status
                self.keypadRetry = (credentialID, numbers, Date().addingTimeInterval(status == 403 || status == 429 ? 600 : 30))
                if self.generation == generation { self.reportingKeypad = false }
            }
        }
    }
    /// `family`: which of a family phone's families to call in; the one its screens show if not given.
    func startCall(to person: FamilyPerson, mode: NativeCall.Mode, dropIn: Bool, in family: FamilyCredential? = nil) async throws -> FamilyCallSession {
        try await startCall(targetID: person.id, name: person.name, mode: mode, dropIn: dropIn, in: family)
    }
    func startCall(targetID: String?, name: String, mode: NativeCall.Mode, dropIn: Bool, waitSeconds: Int = 45, in family: FamilyCredential? = nil) async throws -> FamilyCallSession {
        guard let credential = family ?? credential else { throw FamilyServiceError(message: "Pair this device first.", status: 401) }
        var values: [String: Any] = ["mode": mode.rawValue, "kind": dropIn ? "dropIn" : "call", "waitSeconds": waitSeconds]
        if let targetID { values["targetID"] = targetID } else { values["unlinked"] = true }
        let result = try await FamilyService(credential).send("startCall", values)
        update(result)
        guard let call = result.state?.call else { throw FamilyServiceError(message: "Couldn't start the call.", status: 503) }
        // The server decides whether an ordinary call drops in, from this phone's caregiver setting.
        let wait = credential.role != .family ? waitSeconds : call.kind == "dropIn" ? CallPreferences.dropInWaitSeconds : result.state?.ringSeconds ?? CallPreferences.defaultVoicemailSeconds
        return FamilyCallSession(credential: credential, call: call, peerName: name, waitSeconds: wait)
    }
}
