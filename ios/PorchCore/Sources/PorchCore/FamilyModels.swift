import Foundation

public enum PorchExperience: String, Codable { case bedside, family }
public struct DropInPermissions: Codable, Equatable {
    public var audio: Bool
    public var video: Bool
}
public struct FamilyPerson: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let role: PorchExperience
    public let permissions: DropInPermissions
    public let canReceiveCalls: Bool?
    public let online: Bool
    public let invitationID: String?
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
    /// Telephone calls always require an explicit answer and carry audio only.
    public let source: String?
    public let reason: String?
}
public struct PendingFamilyInvitation: Codable, Equatable {
    public let id: String
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
