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
    private let start = UIButton(type: .system)
    private let stop = UIButton(type: .system)
    private let digits = UILabel()
    private var digitTail: [String] = []
    private var capture: Cell2JackLogCapture?
    private var captureID: UUID?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let worker = DispatchQueue(label: "com.ethanteng.helloporch.cell2jack.version")
    private var busy = false
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cell2Jack USB Test · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")"
        view.backgroundColor = .systemBackground
        let instructions = UILabel()
        instructions.text = "Connect Cell2Jack to this iPad with a USB data cable and enable its driver in Open app settings. Start the keypad test, lift the handset, then press one key at a time."
        instructions.numberOfLines = 0; instructions.font = .preferredFont(forTextStyle: .body)
        let detail = UILabel()
        detail.text = "Start sends /v and /d; Stop sends /q. Keep this app open. The test stops after two minutes. Phone keys still have their usual Cell2Jack behavior."
        detail.numberOfLines = 0; detail.font = .preferredFont(forTextStyle: .footnote)
        status.text = "Ready to test"; status.numberOfLines = 0
        status.accessibilityIdentifier = "cell2jack.status"
        read.setTitle("Read Cell2Jack version", for: .normal)
        read.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        read.accessibilityIdentifier = "cell2jack.readVersion"
        read.addTarget(self, action: #selector(readVersion), for: .touchUpInside)
        let settings = UIButton(type: .system)
        settings.setTitle("Open app settings", for: .normal)
        settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        start.setTitle("Start keypad test", for: .normal)
        start.accessibilityIdentifier = "cell2jack.startKeypad"
        start.addTarget(self, action: #selector(startKeypad), for: .touchUpInside)
        stop.setTitle("Stop", for: .normal)
        stop.accessibilityIdentifier = "cell2jack.stopKeypad"
        stop.isEnabled = false
        stop.addTarget(self, action: #selector(stopKeypad), for: .touchUpInside)
        digits.text = "Digits will appear here"
        digits.numberOfLines = 0
        digits.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .monospacedSystemFont(ofSize: 36, weight: .semibold))
        digits.adjustsFontForContentSizeCategory = true
        digits.accessibilityIdentifier = "cell2jack.digits"
        let versionRow = UIStackView(arrangedSubviews: [read, settings])
        versionRow.distribution = .fillEqually; versionRow.spacing = 12
        let keypadRow = UIStackView(arrangedSubviews: [start, stop])
        keypadRow.distribution = .fillEqually; keypadRow.spacing = 12
        let copy = UIButton(type: .system)
        copy.setTitle("Copy test result", for: .normal)
        copy.addTarget(self, action: #selector(copyResult), for: .touchUpInside)
        output.isEditable = false; output.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        output.accessibilityIdentifier = "cell2jack.output"
        output.text = "No request sent.\nUSB VID:PID 1A86:7523 • Interface 0 • 8N1"
        let stack = UIStackView(arrangedSubviews: [instructions, detail, versionRow, keypadRow, digits, status, output, copy])
        stack.axis = .vertical; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
            versionRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            keypadRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            copy.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            output.heightAnchor.constraint(equalToConstant: 240)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(leavingForeground),
            name: UIApplication.willResignActiveNotification, object: nil)
        worker.async { [weak self] in
            let snapshot = Cell2JackBridge.usbDiagnostics()
            self?.saveDiagnostics(snapshot)
            DispatchQueue.main.async {
                guard let self, !self.busy else { return }
                self.output.text += "\n\n" + snapshot
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--read-cell2jack-version") { readVersion() }
        if ProcessInfo.processInfo.arguments.contains("--start-keypad-test") { startKeypad() }
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
    private func appendOutput(_ text: String) {
        output.text = String((output.text + text).suffix(32000))
        if !output.text.isEmpty { output.scrollRangeToVisible(NSRange(location: output.text.utf16.count - 1, length: 1)) }
    }
    @objc private func startKeypad() {
        guard !busy else { return }
        busy = true; read.isEnabled = false; start.isEnabled = false; stop.isEnabled = true
        digitTail = []; digits.text = "Waiting for keys…"
        status.text = "Starting device logs…"
        output.text = "Keypad test started: \(ISO8601DateFormatter().string(from: Date()))\n"
        UIApplication.shared.isIdleTimerDisabled = true
        let id = UUID(); captureID = id
        let capture = Cell2JackLogCapture { [weak self] update in
            guard let self, self.captureID == id else { return }
            self.status.text = update.message
            if update.kind == .packet {
                self.appendOutput(Cell2JackVersionResult(bytes: update.bytes).displayText)
                for event in update.digits where event.kind == .digit {
                    self.digitTail.append(event.digit)
                }
                self.digitTail = Array(self.digitTail.suffix(32))
                if !self.digitTail.isEmpty { self.digits.text = self.digitTail.joined(separator: " ") }
            } else {
                self.appendOutput("\n[" + update.message + "]\n")
            }
            if update.kind == .finished {
                self.capture = nil; self.captureID = nil; self.busy = false
                self.read.isEnabled = true; self.start.isEnabled = true; self.stop.isEnabled = false
                UIApplication.shared.isIdleTimerDisabled = false
                if self.backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid
                }
            }
        }
        self.capture = capture
        capture.start()
    }
    @objc private func stopKeypad() {
        stop.isEnabled = false
        status.text = "Stopping device logs…"
        capture?.stop()
    }
    @objc private func leavingForeground() {
        guard let capture else { return }
        stop.isEnabled = false
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Stop Cell2Jack logs") { [weak self] in
                guard let self else { return }
                self.capture?.stop(reason: "App left the foreground")
                if self.backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid
                }
            }
        }
        capture.stop(reason: "App left the foreground")
    }
    @objc private func readVersion() {
        guard !busy else { return }
        busy = true; read.isEnabled = false; start.isEnabled = false; status.text = "Reading Cell2Jack…"
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
                self.busy = false; self.read.isEnabled = true; self.start.isEnabled = true
                UIAccessibility.post(notification: .announcement, argument: title)
            }
        }
    }
}
