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
    /// Family devices only: their Audio call and Video call drop in, for the drop-in types they're approved for,
    /// while drop-ins are on and the bedside Porch is open. Older servers don't send it.
    public let autoDropIn: Bool?
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
    /// A regular phone a family caregiver added to this call, such as a bank. Older servers don't send it.
    public let phoneGuest: FamilyPhoneGuest?
    /// Family devices: the bedside hung up while the call went on without it.
    public let bedsideLeft: Bool?
    /// The family member rung into this call, as the call's two ends see them. Older servers don't send it.
    public let porchGuest: FamilyPorchGuest?
    /// This device was rung into someone else's call with the bedside: `from` rang it in, and `id` is its invitation.
    public let guest: Bool?
}
/// A family member rung into a call with the bedside, and how their invitation went.
public struct FamilyPorchGuest: Codable, Equatable {
    public let id: String
    public let memberID: String
    public let name: String
    /// "ringing", "joined", "declined", "missed", "cancelled" (they lost access while it rang) or "left".
    public let state: String
    public var isActive: Bool { state == "ringing" || state == "joined" }
}
/// Another family member on this Porch, who can be rung into a call with the bedside.
public struct FamilyRelative: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// Their Porch is open, or can ring while it's closed.
    public let canReceiveCalls: Bool
}
/// A regular phone on a Porch call. Its telephone leg joins the call's LiveKit room as `identity`.
public struct FamilyPhoneGuest: Codable, Equatable {
    public let id: String
    /// What the person who added it called it, such as "Bank". The bedside sees this, never the number.
    public let label: String
    public let addedBy: String
    /// Only the person who added it receives the number.
    public let number: String?
    public var identity: String { "phone-guest-\(id)" }
}
/// A telephone number the caregiver approved for audio drop-in by calling the household's number.
public struct PhoneDropInApproval: Codable, Equatable {
    public let number: String
    public let name: String
    public init(number: String, name: String) { self.number = number; self.name = name }
}
/// A caller ID that tried to ring the bedside while unknown callers were blocked.
public struct BlockedCaller: Codable, Equatable {
    public let number: String
    public let firstCallAt: TimeInterval
    public let lastCallAt: TimeInterval
    public let calls: Int
}
/// A number a caregiver allowed to ring the bedside although it isn't saved on the keypad.
public struct AllowedCaller: Codable, Equatable {
    public let number: String
    public let allowedAt: TimeInterval
}
/// Who can ring the bedside from a regular phone. Calls are matched by caller ID, which can be faked.
public struct CallScreening: Codable, Equatable {
    /// Only keypad contacts, approved phone drop-ins and allowed numbers ring; other numbers are listed in `blocked`.
    public let enabled: Bool
    /// The keypad's phone numbers as the server last heard them; nil until the bedside first reports them.
    public let keypadNumbers: [String]?
    public let allowed: [AllowedCaller]
    /// Newest first. Numbers saved or allowed since they called aren't listed.
    public let blocked: [BlockedCaller]
    /// The keypad's numbers to report, or nil when the server already has them.
    public func keypadNumbersToReport(_ slots: CallSlots) -> [String]? {
        let numbers = slots.phoneNumbers
        return keypadNumbers == numbers ? nil : numbers
    }
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
    /// Bedside only: who can ring by phone. Older servers don't send it.
    public let callScreening: CallScreening?
    /// Bedside only: family see when someone is at the iPad, unless a caregiver turned it off. The iPad reports it only
    /// when this is true; older servers don't send it, and don't take reports.
    public let shareAttendance: Bool?
    /// Family caregivers: this phone can add a regular phone number to its calls with the bedside.
    public let canAddPhoneGuests: Bool?
    /// Family devices: the rest of the family on this Porch, who can be rung into a call. Older servers don't send it.
    public let family: [FamilyRelative]?
    /// Family devices: when someone was last noticed at the bedside iPad, in server time (see `BedsideAttendance`).
    /// Older servers don't send it, nor does one that hasn't heard of anyone there yet.
    public let bedsideAttendedAt: TimeInterval?

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
    /// Who can ring by phone. Older servers don't send it.
    public let callScreening: CallScreening?
    /// Family see when someone is at the bedside iPad. Older servers don't send it.
    public let shareAttendance: Bool?
    public init(householdName: String, dropInEnabled: Bool, people: [FamilyPerson], messagesEnabled: Bool? = nil, messages: [FamilyMessage]? = nil, phoneDropIns: [PhoneDropInApproval]? = nil, invitations: [PendingFamilyInvitation]? = nil, callScreening: CallScreening? = nil, shareAttendance: Bool? = nil) {
        self.householdName = householdName; self.dropInEnabled = dropInEnabled; self.people = people
        self.messagesEnabled = messagesEnabled; self.messages = messages; self.phoneDropIns = phoneDropIns; self.invitations = invitations
        self.callScreening = callScreening; self.shareAttendance = shareAttendance
    }
}
/// One call to or from the bedside, as caregivers see it in Call history (`callHistory`).
/// `direction` is the bedside's: "incoming" rang the bedside and "outgoing" was placed from it. `via` is "porch", or
/// "phone": someone calling the household's Porch number, or the bedside calling a regular phone, including phone
/// fallback. `name` and `number` are as Porch showed them then; a phone caller is named by caller ID, which can be faked.
/// `outcome` is "answered", "missed", "declined", "unavailable" (Porch couldn't reach their app), "dialed" (the bedside
/// called a regular phone; the server can't tell whether it was answered), "ringing" or "ongoing".
public struct CallHistoryEntry: Codable, Equatable, Identifiable {
    public let id: String
    public let direction: String
    public let via: String
    public let name: String
    public let memberID: String?
    public let number: String?
    public let mode: NativeCall.Mode
    public let dropIn: Bool?
    public let startedAt: TimeInterval
    public let answeredAt: TimeInterval?
    /// When the bedside's part ended. Calls from before the server recorded it have none.
    public let endedAt: TimeInterval?
    public let outcome: String
    /// The bedside's unanswered Porch calls: whether the family phone showed the call. False means it never got
    /// there, rather than that it rang and nobody heard. Older servers don't send it.
    public let reached: Bool?

    public var isIncoming: Bool { direction == "incoming" }
    /// A missed call to the bedside, which caregivers may want to follow up.
    public var isMissed: Bool { isIncoming && outcome == "missed" }
    /// What kind of call it was: "Incoming video call", "Audio drop-in", "Called their phone".
    public var kindText: String {
        if via == "phone" { return isIncoming ? "Phone call" : "Called their phone" }
        let media = mode == .video ? "video" : "audio"
        if dropIn == true { return "\(media.prefix(1).uppercased())\(media.dropFirst()) drop-in" }
        return "\(isIncoming ? "Incoming" : "Outgoing") \(media) call"
    }
    /// How it went, or nil for a phone the bedside dialed: "Talked 12 min", "Missed", "No answer".
    public var outcomeText: String? {
        switch outcome {
        case "answered":
            guard let answeredAt, let endedAt, endedAt >= answeredAt else { return "Answered" }
            return "Talked \(Self.duration(endedAt - answeredAt))"
        case "missed":
            guard !isIncoming else { return "Missed" }
            return reached.map { $0 ? "No answer · Their phone showed the call" : "No answer · Didn't reach their phone" } ?? "No answer"
        case "declined": return "Declined"
        case "unavailable": return "Couldn't reach their Porch"
        case "ringing": return "Ringing now"
        case "ongoing": return "On the call now"
        default: return nil
        }
    }
    /// "45 sec", "12 min", "1 hr 5 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) sec" }
        let minutes = (total + 30) / 60
        return minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }
}

public struct FamilyCredential: Codable, Equatable {
    public let origin: URL
    public let credential: String
    public let role: PorchExperience
    public init(origin: URL, credential: String, role: PorchExperience) {
        self.origin = origin; self.credential = credential; self.role = role
    }
    /// This device's ID in its household, which is also its member ID there. A phone in several families has a
    /// different one in each, so calls and messages can say which family they're for.
    public var deviceID: String { String(credential.split(separator: ".").first ?? "") }
}

/// What a phone in more than one family shows to tell them apart, such as two sets of parents who are both "Mom" and
/// "Dad" on their own Porch.
public enum FamilyNames {
    /// Each family can have several phones; a phone can be in up to this many families.
    public static let limit = 4
    /// What each of a phone's families is called, in the order it joined them, numbered where two would read the same:
    /// two families that are both "Mom" are "Mom" and "Mom 2" until the phone names one.
    public static func distinct(_ names: [String?]) -> [String?] {
        var used = Set<String>()
        return names.map { name in
            guard let name else { return nil }
            var distinct = name, number = 1
            while used.contains(distinct.lowercased()) { number += 1; distinct = "\(name) \(number)" }
            used.insert(distinct.lowercased())
            return distinct
        }
    }
    /// The name this phone gave the family, or else the one its caregiver did.
    public static func family(nickname: String?, householdName: String?) -> String? {
        [nickname, householdName].lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
    /// Who's calling, with their family when the phone is in more than one: "Mom · Lee family". A family named after
    /// the person calling adds nothing.
    public static func caller(_ name: String, family: String?) -> String {
        guard let family, !family.isEmpty, family.caseInsensitiveCompare(name) != .orderedSame else { return name }
        return "\(name) · \(family)"
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
