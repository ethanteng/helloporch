import UIKit

@main
final class Cell2JackPOCApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Cell2Jack test", sessionRole: session.role)
        configuration.delegateClass = Cell2JackPOCScene.self
        return configuration
    }
}

final class Cell2JackPOCScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(rootViewController: Cell2JackVersionViewController())
        window.makeKeyAndVisible(); self.window = window
    }
}

final class Cell2JackVersionViewController: UIViewController {
    private let status = UILabel()
    private let output = UITextView()
    private let read = UIButton(type: .system)
    private let worker = DispatchQueue(label: "com.ethanteng.helloporch.cell2jack.version")
    private var busy = false
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cell2Jack USB Test · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")"
        view.backgroundColor = .systemBackground
        let instructions = UILabel()
        instructions.text = "Connect Cell2Jack directly to this iPad using a USB data cable. Tap Open app settings and enable its driver if listed. You can also look for Drivers under Settings → Privacy & Security or General. Then read its version."
        instructions.numberOfLines = 0; instructions.font = .preferredFont(forTextStyle: .title3)
        let detail = UILabel()
        detail.text = "This test sends only /v at 2,000,000 baud. It does not enable debug logging or place a call."
        detail.numberOfLines = 0; detail.font = .preferredFont(forTextStyle: .body)
        status.text = "Ready to test"; status.numberOfLines = 0
        status.accessibilityIdentifier = "cell2jack.status"
        read.setTitle("Read Cell2Jack version", for: .normal)
        read.titleLabel?.font = .preferredFont(forTextStyle: .title2)
        read.accessibilityIdentifier = "cell2jack.readVersion"
        read.addTarget(self, action: #selector(readVersion), for: .touchUpInside)
        let settings = UIButton(type: .system)
        settings.setTitle("Open app settings", for: .normal)
        settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        let copy = UIButton(type: .system)
        copy.setTitle("Copy test result", for: .normal)
        copy.addTarget(self, action: #selector(copyResult), for: .touchUpInside)
        output.isEditable = false; output.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        output.accessibilityIdentifier = "cell2jack.output"
        output.text = "No request sent.\nUSB VID:PID 1A86:7523 • Interface 0 • 8N1"
        let stack = UIStackView(arrangedSubviews: [instructions, detail, read, settings, status, output, copy])
        stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            read.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            output.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        worker.async { [weak self] in
            let snapshot = Cell2JackBridge.usbDiagnostics()
            self?.saveDiagnostics(snapshot)
            DispatchQueue.main.async {
                guard let self, !self.busy else { return }
                self.output.text += "\n\n" + snapshot
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--read-cell2jack-version") {
            readVersion()
        }
    }
    private func saveDiagnostics(_ text: String, filename: String = "usb-diagnostics.txt") {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let stamped = "\(ISO8601DateFormatter().string(from: Date()))\n" + text
        try? stamped.write(to: folder.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }
    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    @objc private func copyResult() { UIPasteboard.general.string = output.text }
    @objc private func readVersion() {
        guard !busy else { return }
        busy = true; read.isEnabled = false; status.text = "Reading Cell2Jack…"
        output.text = "Request started: \(ISO8601DateFormatter().string(from: Date()))\n"
        worker.async { [weak self] in
            var result: String
            var title: String
            do {
                let data = try Cell2JackBridge.readVersionReply()
                let reply = data.withUnsafeBytes { $0.loadUnaligned(as: PorchC2JReply.self) }
                var packet = reply.bytes
                let bytes = withUnsafeBytes(of: &packet) { Data($0.prefix(Int(reply.count))) }
                let report = Cell2JackVersionResult(bytes: bytes)
                let stage = ["ready", "USB chip identification", "USB serial initialization", "baud setup", "8N1 setup", "control-line setup", "writing /v", "reading reply", "complete"]
                let stageName = Int(reply.stage) < stage.count ? stage[Int(reply.stage)] : "unknown"
                result = "USB stage: \(stageName)\nUSB result: \(String(format: "0x%08x", reply.usbStatus))\nSerial-chip revision: \(String(format: "0x%02x", reply.chipVersion))\nReceived: \(reply.count) bytes\n\n\(report.displayText)\n\nHex:\n\(report.hex)"
                if let version = report.version, reply.usbStatus == 0 {
                    title = "Cell2Jack version: \(version)"
                } else { title = reply.usbStatus == 0 ? "Reply received; version not recognized" : "USB test did not complete" }
            } catch {
                result = error.localizedDescription + "\n\n" + Cell2JackBridge.usbDiagnostics()
                self?.saveDiagnostics(result)
                title = "Could not read Cell2Jack"
            }
            self?.saveDiagnostics(title + "\n" + result, filename: "version-result.txt")
            DispatchQueue.main.async {
                guard let self else { return }
                self.output.text += result
                self.status.text = title
                self.busy = false; self.read.isEnabled = true
                UIAccessibility.post(notification: .announcement, argument: title)
            }
        }
    }
}
