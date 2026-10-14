import UIKit
import PorchCore

enum PorchStyle {
    static let cream = UIColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1)
    static let ink = UIColor(red: 0.22, green: 0.16, blue: 0.12, alpha: 1)
    static let terracotta = UIColor(red: 0.60, green: 0.26, blue: 0.16, alpha: 1)
    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }
}

final class CallViewController: UIViewController {
    private let storageKey = "porch.contact.v1"
    private var contact: CallContact?
    private var trigger = CallTrigger()
    private var opening = false
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let callButton = UIButton(type: .system)
    private let setupButton = UIButton(type: .system)

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = PorchStyle.cream
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(CallContact.self, from: data) {
            contact = try? CallContact(name: saved.name, address: saved.address)
        }
        #if DEBUG
        // CI screenshots use a fictional recipient, without altering storage.
        if ProcessInfo.processInfo.arguments.contains("--preview-contact") {
            contact = try? CallContact(name: "David", address: "david@example.com")
        }
        #endif

        let brand = UILabel()
        brand.text = "Porch."
        brand.font = PorchStyle.font(32, weight: .medium)
        brand.textColor = PorchStyle.ink
        brand.textAlignment = .center
        brand.adjustsFontForContentSizeCategory = true

        titleLabel.font = PorchStyle.font(42, weight: .semibold)
        titleLabel.textColor = PorchStyle.ink
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        hintLabel.font = PorchStyle.font(24)
        hintLabel.textColor = PorchStyle.ink
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.adjustsFontForContentSizeCategory = true

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = PorchStyle.terracotta
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 40, leading: 32, bottom: 40, trailing: 32)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = PorchStyle.font(44, weight: .semibold)
            return attributes
        }
        callButton.configuration = configuration
        callButton.titleLabel?.numberOfLines = 0
        callButton.addTarget(self, action: #selector(call), for: .touchUpInside)

        setupButton.setTitle("Hold here to set up", for: .normal)
        setupButton.setTitleColor(PorchStyle.ink, for: .normal)
        setupButton.titleLabel?.font = PorchStyle.font(18)
        setupButton.titleLabel?.adjustsFontForContentSizeCategory = true
        setupButton.accessibilityLabel = "Contact setup"
        setupButton.accessibilityHint = "Press and hold for two seconds to change the saved contact."
        setupButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Open contact setup", target: self, selector: #selector(accessibleSetup))]
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(heldSetup(_:)))
        hold.minimumPressDuration = 2
        setupButton.addGestureRecognizer(hold)

        // Scrolling keeps all controls reachable with large accessibility text.
        let scroll = UIScrollView()
        let content = UIView()
        let stack = UIStackView(arrangedSubviews: [brand, titleLabel, hintLabel, callButton, setupButton])
        stack.axis = .vertical
        stack.spacing = 28
        [scroll, content, stack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll)
        scroll.addSubview(content)
        content.addSubview(stack)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: guide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            callButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            setupButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        let preferredWidth = stack.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48)
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    func resume() {
        trigger.resetKeys()
        opening = false
        if isViewLoaded { render(); becomeFirstResponder() }
    }

    func pause() { trigger.resetKeys() }

    private func render() {
        titleLabel.text = contact.map { "Call \($0.name)" } ?? "Let's set up your call"
        hintLabel.text = contact == nil ? "Hold the setup button below to choose someone." : "Press 1 on the keypad\nor tap the button below."
        var configuration = callButton.configuration
        configuration?.title = contact == nil ? "Choose a contact" : "1   Call \(contact!.name)"
        callButton.configuration = configuration
        callButton.accessibilityLabel = contact.map { "Video call \($0.name)" } ?? "Choose a contact"
        callButton.isEnabled = !opening
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key,
                  CallTrigger.supports(Int(key.keyCode.rawValue)),
                  key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty,
                  presentedViewController == nil else {
                unhandled.insert(press)
                continue
            }
            if trigger.keyDown(Int(key.keyCode.rawValue)) { call() }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key { trigger.keyUp(Int(key.keyCode.rawValue)) }
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        trigger.resetKeys()
        super.pressesCancelled(presses, with: event)
    }

    @objc private func call() {
        guard !opening, presentedViewController == nil,
              view.window?.windowScene?.activationState == .foregroundActive else { return }
        guard let contact else { showSetup(); return }
        guard !UIAccessibility.isGuidedAccessEnabled else {
            showError("Exit Guided Access", message: "Porch needs to open the FaceTime app. Guided Access keeps this iPad in one app, so a caregiver must exit it before calling.")
            return
        }
        guard trigger.allowLaunch(at: ProcessInfo.processInfo.systemUptime) else { return }
        opening = true
        render()
        hintLabel.text = "Opening FaceTime…"
        UIApplication.shared.open(contact.faceTimeURL, options: [:]) { [weak self] opened in
            guard let self else { return }
            self.opening = false
            self.render()
            if !opened {
                self.showError("Couldn't open FaceTime", message: "Check that FaceTime is installed and enabled, then try again.")
            }
            // opened only means the URL was handed off. It does not report
            // ringing, connection, cancellation, or the end of the call.
        }
    }

    @objc private func heldSetup(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { showSetup() }
    }

    @objc private func accessibleSetup() -> Bool { showSetup(); return true }

    private func showSetup() {
        guard presentedViewController == nil else { return }
        trigger.resetKeys()
        let setup = SetupViewController(contact: contact)
        setup.onSave = { [weak self] contact in
            guard let self, let data = try? JSONEncoder().encode(contact) else { return }
            UserDefaults.standard.set(data, forKey: self.storageKey)
            self.contact = contact
            self.render()
        }
        let navigation = UINavigationController(rootViewController: setup)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func showError(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
