import UIKit
import Security
import CryptoKit
import PorchCore

enum NativeCallSettings {
    private static let serverKey = "porch.native.server"
    private static let account = "porch.prototype-access-code"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.ethanteng.helloporch",
         kSecAttrAccount as String: account]
    }

    static var savedURL: String { UserDefaults.standard.string(forKey: serverKey) ?? "" }

    private static func readSecret(_ account: String) -> Data? {
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

    static func load() throws -> NativeCallServer {
        guard let data = readSecret(account), let code = String(data: data, encoding: .utf8) else {
            throw SettingsError.missingConfiguration
        }
        return try NativeCallServer(url: savedURL, accessCode: code)
    }

    private static func writeSecret(_ data: Data, account: String) throws {
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

    static func save(_ server: NativeCallServer, caregiverCode: String = "") throws {
        let code = caregiverCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.isEmpty || (code.count >= 16 && code.count <= 256 && code != server.accessCode &&
            code.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7E })) else {
            throw SettingsError.invalidCaregiverCode
        }
        try writeSecret(Data(server.accessCode.utf8), account: account)
        try writeSecret(Data(code.utf8), account: "porch.contact-setup-code")
        UserDefaults.standard.set(server.baseURL.absoluteString, forKey: serverKey)
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
            throw (try? JSONDecoder().decode(ServerError.self, from: data)) ?? ServerError(error: "Couldn't approve this contact. Check the internet connection and caregiver setup code, then save again.")
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
        case missingConfiguration, keychainFailure, invalidCaregiverCode, missingCaregiverCode
        var errorDescription: String? {
            switch self {
            case .missingConfiguration: return "A caregiver needs to open setup → Native calling server and save the server address and prototype access code."
            case .keychainFailure: return "Couldn't securely save the access code. Unlock the iPad and try again."
            case .invalidCaregiverCode: return "Use a separate caregiver setup code: 16–256 characters with no spaces, different from the calling access code."
            case .missingCaregiverCode: return "A caregiver needs to enter the caregiver setup code in Native calling server before adding phone contacts."
            }
        }
    }
}

final class NativeCallSettingsViewController: UIViewController {
    private let serverField = UITextField()
    private let codeField = UITextField()
    private let caregiverField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Native calling server"
        view.backgroundColor = PorchStyle.cream
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        serverField.placeholder = "https://your-porch-server.com"
        serverField.text = NativeCallSettings.savedURL
        serverField.keyboardType = .URL
        serverField.accessibilityLabel = "Porch server address"
        codeField.placeholder = "Prototype access code"
        codeField.text = try? NativeCallSettings.load().accessCode
        codeField.isSecureTextEntry = true
        codeField.accessibilityLabel = "Prototype access code"
        caregiverField.placeholder = "Caregiver setup code (for phone contacts)"
        caregiverField.text = NativeCallSettings.caregiverCode
        caregiverField.isSecureTextEntry = true
        caregiverField.accessibilityLabel = "Caregiver setup code for phone contacts"
        for field in [serverField, codeField, caregiverField] {
            field.borderStyle = .roundedRect
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        let instructions = UILabel()
        instructions.text = "Enter your Porch server's address and calling access code.\n\nTo add phone contacts, enter the separate caregiver setup code once. Saving a phone contact approves its number automatically. Both codes and phone approvals are saved securely on this iPad. Share only the calling code with other call participants.\n\nPorch tries the shared room first, then rings their regular phone after 20 seconds without an answer if fallback is enabled. Telephone calls are voice only and incur carrier charges.\n\nThe other person joins /call on this server or another iPad in the same room and mode. App notifications aren't included yet."
        instructions.numberOfLines = 0
        instructions.font = .preferredFont(forTextStyle: .body)
        instructions.adjustsFontForContentSizeCategory = true
        instructions.textColor = PorchStyle.ink
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .onDrag
        let stack = UIStackView(arrangedSubviews: [serverField, codeField, caregiverField, instructions])
        stack.axis = .vertical
        stack.spacing = 20
        [scroll, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
        ])
    }

    @objc private func save() {
        do {
            let server = try NativeCallServer(url: serverField.text ?? "", accessCode: codeField.text ?? "")
            try NativeCallSettings.save(server, caregiverCode: caregiverField.text ?? "")
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Check the server settings", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
