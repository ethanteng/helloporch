import UIKit
import Security
import CryptoKit
import PorchCore

enum NativeCallSettings {
    private static let serverKey = "porch.native.server"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.ethanteng.helloporch",
         kSecAttrAccount as String: account]
    }

    static var savedURL: String { UserDefaults.standard.string(forKey: serverKey) ?? PorchDevice.defaultOrigin.absoluteString }

    static func readSecret(_ account: String) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static var caregiverCode: String {
        readSecret("porch.contact-setup-code").flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func writeSecret(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let query = query(account)
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SettingsError.keychainFailure }
    }

    static func loadForPhone() throws -> NativeCallServer {
        if let paired = PorchDevice.credential(for: .bedside) {
            return try NativeCallServer(url: paired.origin.absoluteString, accessCode: paired.credential)
        }
        throw SettingsError.missingConfiguration
    }

    private struct PhoneApproval: Codable { let authorization: String; let expiresAt: TimeInterval }
    private struct ServerError: Decodable, LocalizedError {
        let error: String
        var errorDescription: String? { error }
    }

    static func authorizePhone(_ number: String, server: NativeCallServer, refresh: Bool = false) async throws -> String {
        let scope = try JSONSerialization.data(withJSONObject: [server.baseURL.absoluteString, server.accessCode, caregiverCode, number])
        let digest = SHA256.hash(data: scope).map { String(format: "%02x", $0) }.joined()
        let account = "porch.phone-approval.\(digest)"
        let now = Date().timeIntervalSince1970
        if !refresh, let data = readSecret(account), let cached = try? JSONDecoder().decode(PhoneApproval.self, from: data),
           cached.expiresAt > now + 300 { return cached.authorization }
        guard !caregiverCode.isEmpty else { throw SettingsError.missingCaregiverCode }
        var request = URLRequest(url: server.baseURL.appendingPathComponent("api/calls/contacts/authorize"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(server.accessCode)", forHTTPHeaderField: "Authorization")
        request.setValue(caregiverCode, forHTTPHeaderField: "X-Porch-Setup-Code")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["phoneNumber": number])
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw (try? JSONDecoder().decode(ServerError.self, from: data)) ?? ServerError(error: "Couldn't approve this contact. Check the internet connection and caregiver PIN, then save again.")
        }
        let approval = try JSONDecoder().decode(PhoneApproval.self, from: data)
        guard !approval.authorization.isEmpty, approval.authorization.count <= 1000,
              approval.expiresAt > now + 300, approval.expiresAt <= now + 31 * 24 * 60 * 60 else {
            throw ServerError(error: "The calling server returned an invalid phone approval.")
        }
        try writeSecret(try JSONEncoder().encode(approval), account: account)
        return approval.authorization
    }

    enum SettingsError: LocalizedError {
        case missingConfiguration, keychainFailure, missingCaregiverCode
        var errorDescription: String? {
            switch self {
            case .missingConfiguration: return "Open caregiver mode to finish setting up this bedside device."
            case .keychainFailure: return "Couldn't securely save caregiver settings. Unlock the iPad and try again."
            case .missingCaregiverCode: return "Open caregiver mode and set your six-digit PIN before adding phone contacts."
            }
        }
    }
}
