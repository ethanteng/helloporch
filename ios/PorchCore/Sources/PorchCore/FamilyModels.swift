import Foundation

public enum PorchExperience: String, Codable { case bedside, family }
public struct DropInPermissions: Codable, Equatable {
    public var audio: Bool
    public var video: Bool
}
/// A family member's name and photo, as they chose them or as a caregiver chose them for them.
public struct FamilyProfile: Codable, Equatable {
    public let name: String?
    /// The SHA-256 of the photo's JPEG bytes.
    public let photoID: String?
    public init(name: String? = nil, photoID: String? = nil) { self.name = name; self.photoID = photoID }
}
public struct FamilyPerson: Codable, Equatable, Identifiable {
    public let id: String
    /// What Porch shows: a caregiver's choice first, then the family member's own, then the invitation's name.
    public let name: String
    /// The photo Porch shows (the SHA-256 of its JPEG), a caregiver's or the member's own. Older servers don't send it.
    public let photoID: String?
    /// Caregiver screens and the member's own snapshot: the parts behind `name` and `photoID`.
    public let invitedName: String?
    public let profile: FamilyProfile?
    public let override: FamilyProfile?
    public let role: PorchExperience
    public let permissions: DropInPermissions
    public let canReceiveCalls: Bool?
    public let online: Bool
    public let invitationID: String?
    /// Family devices only: approved to open caregiver mode with the PIN.
    public let caregiver: Bool?
}
public struct FamilyCallRecord: Codable, Equatable, Identifiable {
    public let id: String
    public let from: String
    public let to: String
    public let mode: NativeCall.Mode
    public let kind: String
    public let state: String
    public let createdAt: TimeInterval
    public let announcedAt: TimeInterval?
    public let acceptedAt: TimeInterval?
    public let expiresAt: TimeInterval
    public let callerName: String
    /// "phone" for a call to the household's telephone number. Telephone calls carry audio
    /// only and require an explicit answer, unless the server marks a carrier-verified,
    /// caregiver-approved number as a drop-in.
    public let source: String?
    /// The caller's telephone number, when caller ID is available. Display information only.
    public let callerNumber: String?
    public let reason: String?
}
/// A telephone number the caregiver approved for audio drop-in by calling the household's number.
public struct PhoneDropInApproval: Codable, Equatable {
    public let number: String
    public let name: String
    public init(number: String, name: String) { self.number = number; self.name = name }
}
/// A message waiting on the bedside device (only the bedside's snapshot carries the queue).
public struct FamilyMessage: Codable, Equatable, Identifiable {
    public let id: String
    public let from: String
    public let fromName: String
    /// "message" or "voicemail".
    public let kind: String
    /// "audio" or "video".
    public let mode: String
    public let contentType: String
    public let durationSeconds: Int
    public let sentAt: TimeInterval
    public let delivered: Bool
    /// Voicemail from a regular phone call: the caller's number, when caller ID was shown.
    public let callerNumber: String?
    /// The phone company verified the caller ID (STIR/SHAKEN full attestation). Caller ID alone is easy to fake.
    public let callerVerified: Bool?
    /// Phone voicemail waiting for a caregiver (or a matching keypad contact) before it plays.
    public let held: Bool?
    public var fromPhone: Bool { from == "phone" }
    public var fileExtension: String {
        switch contentType { case "video/quicktime": return "mov"; case "video/mp4": return "mp4"; case "audio/mpeg": return "mp3"; default: return "m4a" }
    }
}
/// A message this device sent. States: uploading, queued, played, expired, removed, unsent, failed.
public struct SentMessage: Codable, Equatable, Identifiable {
    public let id: String
    public let kind: String
    public let mode: String
    public let durationSeconds: Int
    public let createdAt: TimeInterval
    public let state: String
    public let sentAt: TimeInterval?
    public let deliveredAt: TimeInterval?
    public let playedAt: TimeInterval?
    public let endedAt: TimeInterval?
    /// The recording can still be played back (it's kept for 90 days after playback).
    public let replayable: Bool?
}
/// A message the bedside left for this family device after a missed call (family devices only).
/// States: queued (not played yet), played, expired (deleted after 90 days unplayed).
public struct ReceivedMessage: Codable, Equatable, Identifiable {
    public let id: String
    public let fromName: String
    public let kind: String
    /// "audio" or "video", matching the call that wasn't answered.
    public let mode: String
    public let durationSeconds: Int
    public let sentAt: TimeInterval
    public let state: String
    public let playedAt: TimeInterval?
    /// The recording is kept for 90 days after it was left, played or not.
    public let available: Bool
    public init(id: String, fromName: String, kind: String, mode: String, durationSeconds: Int, sentAt: TimeInterval, state: String, playedAt: TimeInterval?, available: Bool) {
        self.id = id; self.fromName = fromName; self.kind = kind; self.mode = mode; self.durationSeconds = durationSeconds
        self.sentAt = sentAt; self.state = state; self.playedAt = playedAt; self.available = available
    }
}
public struct PendingFamilyInvitation: Codable, Equatable {
    public let id: String
    /// The name the caregiver gave the invitation. Older servers don't send it.
    public let name: String?
    public let expiresAt: TimeInterval
}
public struct FamilySnapshot: Codable, Equatable {
    public let householdID: String
    public let householdName: String
    public let dropInEnabled: Bool
    public let me: FamilyPerson
    public let people: [FamilyPerson]
    public let invitations: [PendingFamilyInvitation]?
    public let call: FamilyCallRecord?
    public let busy: Bool
    public let serverTime: TimeInterval
    public let messagesEnabled: Bool?
    public let messages: [FamilyMessage]?
    /// For approved caregivers: phone voicemails waiting for review.
    public let heldMessages: Int?
    /// Bedside only: numbers approved for telephone drop-in.
    public let phoneDropIns: [PhoneDropInApproval]?
    /// How long calls to the bedside ring before the caller is offered voicemail. Older servers don't send it.
    public let ringSeconds: Int?
    /// Family devices: messages the bedside left for this device that haven't been played.
    public let newMessages: Int?
    /// Bedside only: natural announcement voices. Older servers, and ones without a speech service, don't send them.
    public let speech: NaturalVoices?
    /// Bedside only: the bedside language as the server last heard it; phone voicemail greets callers in it. Older servers don't send it.
    public let bedsideLanguage: String?

    /// The language to report after a caregiver saves `language`, or nil when the server already has it or can't keep it.
    public func languageToReport(_ language: BedsideLanguage) -> BedsideLanguage? {
        guard let bedsideLanguage, bedsideLanguage != language.rawValue else { return nil }
        return language
    }
}
/// The natural voices a caregiver can choose for each bedside language, and the household's choice.
public struct NaturalVoices: Codable, Equatable {
    public struct Voice: Codable, Equatable, Identifiable {
        public let id: String
        public let name: String
        /// How it sounds, such as "Steady, calm and grounded · female".
        public let detail: String
    }
    public struct Choices: Codable, Equatable {
        /// The household's voice for this language; nil means the iPad's built-in voice.
        public let selected: String?
        public let defaultVoice: String
        public let voices: [Voice]
    }
    /// Keyed by `BedsideLanguage.rawValue`.
    public let languages: [String: Choices]
    public func choices(for language: BedsideLanguage) -> Choices? { languages[language.rawValue] }
}
/// Returned with caregiver actions after a PIN check. Lists every family device, which a
/// family device's own snapshot doesn't include.
public struct FamilyAdminState: Codable, Equatable {
    public let householdName: String
    public let dropInEnabled: Bool
    public let people: [FamilyPerson]
    public let messagesEnabled: Bool?
    /// Messages waiting on the bedside device, for caregiver review.
    public let messages: [FamilyMessage]?
    public let phoneDropIns: [PhoneDropInApproval]?
    /// Unclaimed invitations, so a caregiver can see who hasn't joined yet and cancel one.
    public let invitations: [PendingFamilyInvitation]?
    public init(householdName: String, dropInEnabled: Bool, people: [FamilyPerson], messagesEnabled: Bool? = nil, messages: [FamilyMessage]? = nil, phoneDropIns: [PhoneDropInApproval]? = nil, invitations: [PendingFamilyInvitation]? = nil) {
        self.householdName = householdName; self.dropInEnabled = dropInEnabled; self.people = people
        self.messagesEnabled = messagesEnabled; self.messages = messages; self.phoneDropIns = phoneDropIns; self.invitations = invitations
    }
}
public struct FamilyCredential: Codable {
    public let origin: URL
    public let credential: String
    public let role: PorchExperience
    public init(origin: URL, credential: String, role: PorchExperience) {
        self.origin = origin; self.credential = credential; self.role = role
    }
}
public struct FamilyInvitation {
    public let origin: URL
    public let code: String
    public init(url: URL) throws { try self.init(url: url, host: "pair") }
    fileprivate init(url: URL, host: String) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "porch", parts.host == host, parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 2,
              items.filter({ $0.name == "server" }).count == 1,
              items.filter({ $0.name == "code" }).count == 1,
              let server = items.first(where: { $0.name == "server" })?.value,
              let code = items.first(where: { $0.name == "code" })?.value,
              code.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw InvitationError.invalid }
        self.origin = try NativeCallServer(url: server, accessCode: "invitation-validation-only").baseURL
        self.code = code
    }
    public static func url(origin: URL, code: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "porch"; parts.host = "pair"
        parts.queryItems = [URLQueryItem(name: "server", value: origin.absoluteString), URLQueryItem(name: "code", value: code)]
        return parts.url!
    }
    public enum InvitationError: LocalizedError {
        case invalid
        public var errorDescription: String? { "Paste the complete Porch invitation link from your caregiver." }
    }
}

public struct BedsideInvitation {
    public let origin: URL
    public let code: String
    public init(url: URL) throws {
        let invitation = try FamilyInvitation(url: url, host: "activate")
        origin = invitation.origin; code = invitation.code
    }
}
