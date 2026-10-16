import Foundation

public struct NativeCall: Codable, Equatable {
    public enum Mode: String, Codable, CaseIterable {
        case voice, video
    }

    public let room: String
    public let mode: Mode

    public init(room: String, mode: Mode) throws {
        let room = room.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard room.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil else {
            throw ValidationError.invalidRoom
        }
        self.room = room
        self.mode = mode
    }

    public enum ValidationError: LocalizedError {
        case invalidRoom
        public var errorDescription: String? {
            "Use a room name with 1–64 lowercase letters, numbers, or hyphens, starting with a letter or number."
        }
    }
}

public struct NativeCallServer: Equatable {
    public let baseURL: URL
    public let accessCode: String
    public var tokenURL: URL { baseURL.appendingPathComponent("api/calls/token") }

    public init(url: String, accessCode: String) throws {
        let input = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: input),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.scheme == "https" || (components.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)),
              let baseURL = components.url else { throw ValidationError.invalidURL }
        let code = accessCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count >= 16, code.count <= 256,
              code.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7E }) else {
            throw ValidationError.invalidAccessCode
        }
        self.baseURL = baseURL
        self.accessCode = code
    }

    public enum ValidationError: LocalizedError {
        case invalidURL, invalidAccessCode
        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Enter your Porch server's HTTPS address, without a path, query, or login. HTTP localhost is allowed for simulator testing."
            case .invalidAccessCode: return "Enter the server's prototype access code: 16–256 characters with no spaces."
            }
        }
    }
}
