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
    private var slots = CallSlots()
    private var trigger = CallTrigger()
    private var opening = false
    private var loadError: String?
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let grid = UIStackView()
    private let setupButton = UIButton(type: .system)
    private var renderedColumns = 0
    #if DEBUG
    private var previewSetupShown = false
    #endif

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = PorchStyle.cream
        do {
            slots = try CallSlots.load()
        } catch {
            loadError = error.localizedDescription
        }
        #if DEBUG
        // Previews are fictional and never saved to the device's preferences.
        if ProcessInfo.processInfo.arguments.contains("--preview-contact") {
            slots = CallSlots()
            try? slots.setContact(CallContact(name: "David", shortcutName: "Call David"), for: 1)
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-six") {
            slots = CallSlots()
            for (index, name) in ["David", "Maria", "James", "Sarah", "Michael", "Anna"].enumerated() {
                let contact = try? CallContact(name: name, shortcutName: "Call \(name)")
                try? slots.setContact(contact, for: index + 1)
            }
        }
        #endif

        let brand = UILabel()
        brand.text = "Porch."
        brand.font = PorchStyle.font(32, weight: .medium)
        brand.textColor = PorchStyle.ink
        brand.textAlignment = .center
        brand.adjustsFontForContentSizeCategory = true

        titleLabel.font = PorchStyle.font(36, weight: .semibold)
        hintLabel.font = PorchStyle.font(24)
        for label in [titleLabel, hintLabel] {
            label.textColor = PorchStyle.ink
            label.textAlignment = .center
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }

        grid.axis = .vertical
        grid.spacing = 20

        setupButton.setTitle("Hold here to set up", for: .normal)
        setupButton.setTitleColor(PorchStyle.ink, for: .normal)
        setupButton.titleLabel?.font = PorchStyle.font(18)
        setupButton.titleLabel?.adjustsFontForContentSizeCategory = true
        setupButton.accessibilityLabel = "Contact setup"
        setupButton.accessibilityHint = "Press and hold for two seconds to configure people for keys 1 to 6."
        setupButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Open contact setup", target: self, selector: #selector(accessibleSetup))]
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(heldSetup(_:)))
        hold.minimumPressDuration = 2
        setupButton.addGestureRecognizer(hold)

        // The grid scrolls when large accessibility text needs additional space.
        let scroll = UIScrollView()
        let content = UIView()
        let stack = UIStackView(arrangedSubviews: [brand, titleLabel, hintLabel, grid, setupButton])
        stack.axis = .vertical
        stack.spacing = 24
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
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 1000),
            setupButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        let preferredWidth = stack.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48)
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
        render()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if renderedColumns != columnCount { render() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            render()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        opening = false
        trigger.resetKeys()
        render()
        becomeFirstResponder()
        if let message = loadError {
            loadError = nil
            showError("Couldn't load your people", message: message)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-phone-setup"), !previewSetupShown, presentedViewController == nil {
            previewSetupShown = true
            // Fictional contact for visual QA; no settings are saved or calls placed.
            let contact = try? CallContact(name: "David", nativeCall: NativeCall(room: "family-david", mode: .video), phoneNumber: "+14155550123")
            let editor = SetupViewController(slot: 1, contact: contact)
            let navigation = UINavigationController(rootViewController: editor)
            navigation.modalPresentationStyle = .fullScreen
            present(navigation, animated: false)
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-setup"), !previewSetupShown, presentedViewController == nil {
            previewSetupShown = true
            showSetup()
        }
        #endif
    }

    func resume() {
        trigger.resetKeys()
        opening = false
        if isViewLoaded { render(); becomeFirstResponder() }
    }

    func pause() { trigger.resetKeys() }

    private var columnCount: Int {
        let count = slots.contacts.compactMap { $0 }.count
        if count <= 1 || traitCollection.preferredContentSizeCategory.isAccessibilityCategory || view.bounds.width < 600 {
            return 1
        }
        return view.bounds.width > view.bounds.height ? 3 : 2
    }

    private func render() {
        let people = (1...CallSlots.count).compactMap { number in
            slots.contact(for: number).map { (number, $0) }
        }
        titleLabel.text = people.isEmpty ? "Let's set up your calls"
            : people.count == 1 ? "Call \(people[0].1.name)" : "Who would you like to call?"
        hintLabel.text = people.isEmpty ? "Hold the setup button below to choose people."
            : people.count == 1 ? "Press \(people[0].0) on the keypad\nor tap the button below."
            : "Press their number on the keypad\nor tap their name."

        renderedColumns = columnCount
        for row in grid.arrangedSubviews {
            grid.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        if people.isEmpty {
            let button = makeButton(title: "Choose people", number: 0)
            grid.addArrangedSubview(button)
        } else {
            for start in stride(from: 0, to: people.count, by: renderedColumns) {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 20
                row.distribution = .fillEqually
                for index in start..<min(start + renderedColumns, people.count) {
                    let (number, contact) = people[index]
                    let button = makeButton(title: "\(number)   \(contact.name)", number: number)
                    button.accessibilityLabel = "Key \(number), call \(contact.name)"
                    row.addArrangedSubview(button)
                }
                // Keep the last row aligned with the columns above.
                for _ in row.arrangedSubviews.count..<min(renderedColumns, people.count) {
                    row.addArrangedSubview(UIView())
                }
                grid.addArrangedSubview(row)
            }
        }
    }

    private func makeButton(title: String, number: Int) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = PorchStyle.terracotta
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 28, leading: 20, bottom: 28, trailing: 20)
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = PorchStyle.font(36, weight: .semibold)
            return attributes
        }
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.tag = number
        button.isEnabled = !opening
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        button.addTarget(self, action: #selector(tappedCall(_:)), for: .touchUpInside)
        return button
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key,
                  let slot = CallTrigger.slot(for: Int(key.keyCode.rawValue)),
                  key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty,
                  presentedViewController == nil else {
                unhandled.insert(press)
                continue
            }
            if trigger.keyDown(Int(key.keyCode.rawValue)) { call(slot: slot) }
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

    @objc private func tappedCall(_ sender: UIButton) {
        if sender.tag == 0 { showSetup() } else { call(slot: sender.tag) }
    }

    private func call(slot: Int) {
        guard !opening, presentedViewController == nil,
              view.window?.windowScene?.activationState == .foregroundActive else { return }
        guard let contact = slots.contact(for: slot) else {
            hintLabel.text = "No one is assigned to \(slot).\nChoose another number."
            return
        }
        if let native = contact.nativeCall {
            do {
                let server = try NativeCallSettings.load()
                guard trigger.allowLaunch(at: ProcessInfo.processInfo.systemUptime) else { return }
                opening = true
                render()
                present(NativeCallViewController(contact: contact, call: native, server: server), animated: true)
            } catch {
                showError("Set up native calling", message: error.localizedDescription)
            }
            return
        }
        guard !UIAccessibility.isGuidedAccessEnabled else {
            showError("Exit Guided Access", message: "Porch needs to open Shortcuts or FaceTime. Guided Access keeps this iPad in one app, so a caregiver must exit it before calling.")
            return
        }
        guard trigger.allowLaunch(at: ProcessInfo.processInfo.systemUptime) else { return }
        opening = true
        render()
        let appName = contact.shortcutName == nil ? "FaceTime" : "Shortcuts"
        hintLabel.text = "Opening \(appName)…"
        UIApplication.shared.open(contact.launchURL, options: [:]) { [weak self] opened in
            guard let self else { return }
            self.opening = false
            self.render()
            if !opened {
                self.showError("Couldn't open \(appName)", message: "Check that \(appName) is installed and enabled, then try again.")
            }
            // URL handoff doesn't report shortcut execution or call status.
        }
    }

    @objc private func heldSetup(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { showSetup() }
    }

    @objc private func accessibleSetup() -> Bool { showSetup(); return true }

    private func showSetup() {
        guard presentedViewController == nil else { return }
        trigger.resetKeys()
        let setup = SlotsViewController(slots: slots)
        setup.onSave = { [weak self] updated in
            guard let self else { return }
            try updated.save()
            self.slots = updated
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
