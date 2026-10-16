import UIKit
import Security
import PorchCore

enum NativeCallSettings {
    private static let serverKey = "porch.native.server"
    private static let account = "porch.prototype-access-code"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.ethanteng.helloporch",
         kSecAttrAccount as String: account]
    }

    static var savedURL: String { UserDefaults.standard.string(forKey: serverKey) ?? "" }

    static func load() throws -> NativeCallServer {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let code = String(data: data, encoding: .utf8) else {
            throw SettingsError.missingConfiguration
        }
        return try NativeCallServer(url: savedURL, accessCode: code)
    }

    static func save(_ server: NativeCallServer) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(server.accessCode.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SettingsError.keychainFailure }
        UserDefaults.standard.set(server.baseURL.absoluteString, forKey: serverKey)
    }

    enum SettingsError: LocalizedError {
        case missingConfiguration, keychainFailure
        var errorDescription: String? {
            switch self {
            case .missingConfiguration: return "A caregiver needs to open setup → Native calling server and save the server address and prototype access code."
            case .keychainFailure: return "Couldn't securely save the access code. Unlock the iPad and try again."
            }
        }
    }
}

final class NativeCallSettingsViewController: UIViewController {
    private let serverField = UITextField()
    private let codeField = UITextField()

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
        for field in [serverField, codeField] {
            field.borderStyle = .roundedRect
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        let instructions = UILabel()
        instructions.text = "Use the address of your Porch website and its prototype access code. LiveKit API credentials belong on that server, never on this iPad.\n\nThe access code is stored in this device's Keychain. Share it only with your testers.\n\nPorch tries the shared room first. The other person joins /call on this server or another iPad in the same room and mode. App notifications aren't included yet.\n\nIf you enable phone fallback for a person, Porch tries their regular phone after 20 seconds without an answer. Configure the outbound SIP trunk and approved numbers on the server first. Telephone calls are voice only and incur carrier charges."
        instructions.numberOfLines = 0
        instructions.font = .preferredFont(forTextStyle: .body)
        instructions.adjustsFontForContentSizeCategory = true
        instructions.textColor = PorchStyle.ink
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .onDrag
        let stack = UIStackView(arrangedSubviews: [serverField, codeField, instructions])
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
            try NativeCallSettings.save(server)
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Check the server settings", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}
