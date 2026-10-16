import UIKit
import PorchCore

final class CallViewController: UIViewController {
    private var slots = CallSlots()
    private var trigger = CallTrigger()
    private var opening = false
    private var loadError: String?
    private let weekdayLabel = UILabel()
    private let timeLabel = UILabel()
    private let dateLabel = UILabel()
    private let statusLabel = UILabel()
    private let callButton = PorchStyle.button("Call someone", symbol: "phone.fill")
    private var clockTimer: Timer?
    private var timeFormatter = DateFormatter()
    private var weekdayFormatter = DateFormatter()
    private var dateFormatter = DateFormatter()
    private var typographySize = CGSize.zero
    #if DEBUG
    private var previewShown = false
    #endif

    override var canBecomeFirstResponder: Bool { presentedViewController == nil }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = PorchStyle.night
        do { slots = try CallSlots.load() } catch { loadError = error.localizedDescription }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-contact") || ProcessInfo.processInfo.arguments.contains("--preview-six") {
            slots = CallSlots()
            let names = ProcessInfo.processInfo.arguments.contains("--preview-six") ? ["David", "Maria", "James", "Sarah", "Michael", "Anna"] : ["David"]
            for (index, name) in names.enumerated() {
                try? slots.setContact(CallContact(name: name, nativeCall: NativeCall(room: "family-\(name.lowercased())", mode: .video)), for: index + 1)
            }
        }
        #endif
        weekdayLabel.font = PorchStyle.font(72, weight: .medium)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 360, weight: .regular)
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.28
        timeLabel.numberOfLines = 1
        timeLabel.accessibilityIdentifier = "clock.time"
        weekdayLabel.accessibilityIdentifier = "clock.weekday"
        dateLabel.accessibilityIdentifier = "clock.date"
        dateLabel.font = PorchStyle.font(58)
        for label in [weekdayLabel, dateLabel] {
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
        }
        for label in [weekdayLabel, timeLabel, dateLabel] {
            label.textColor = label === timeLabel ? PorchStyle.nightText : PorchStyle.nightSecondary
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
        }
        timeLabel.accessibilityTraits.insert(.updatesFrequently)
        let clock = UIStackView(arrangedSubviews: [weekdayLabel, timeLabel, dateLabel])
        clock.axis = .vertical
        clock.spacing = 24
        clock.isAccessibilityElement = false
        clock.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clock)

        var callConfig = callButton.configuration!
        callConfig.baseBackgroundColor = PorchStyle.nightSurface
        callConfig.baseForegroundColor = PorchStyle.nightText
        callConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes; attributes.font = PorchStyle.font(19, weight: .medium); return attributes
        }
        callButton.configuration = callConfig
        callButton.accessibilityIdentifier = "clock.call"
        callButton.addTarget(self, action: #selector(showPeople), for: .touchUpInside)
        let caregiver = UIButton(type: .system)
        caregiver.setImage(UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)), for: .normal)
        caregiver.tintColor = PorchStyle.nightSecondary
        caregiver.accessibilityLabel = "Caregiver mode"
        caregiver.accessibilityHint = "Tap or hold to manage contacts and settings."
        caregiver.accessibilityIdentifier = "clock.caregiver"
        caregiver.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Open caregiver mode", target: self, selector: #selector(accessibleSetup))]
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(heldSetup(_:)))
        hold.minimumPressDuration = 0.5
        hold.allowableMovement = 30
        caregiver.addGestureRecognizer(hold)
        caregiver.addTarget(self, action: #selector(tappedSetup), for: .touchUpInside)
        statusLabel.font = PorchStyle.font(17)
        statusLabel.textColor = PorchStyle.nightSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        [callButton, caregiver, statusLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            clock.centerYAnchor.constraint(equalTo: guide.centerYAnchor, constant: -32),
            clock.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            clock.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 32),
            clock.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -32),
            caregiver.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            caregiver.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            caregiver.widthAnchor.constraint(equalToConstant: 64),
            caregiver.heightAnchor.constraint(equalToConstant: 64),
            callButton.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            callButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -36),
            callButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),
            statusLabel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
            statusLabel.bottomAnchor.constraint(equalTo: callButton.topAnchor, constant: -16)
        ])
        let width = clock.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -64)
        width.priority = .defaultHigh; width.isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(resetClock), name: UIApplication.significantTimeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetClock), name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        resetClock()
    }

    deinit { clockTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resume()
        if let error = loadError { loadError = nil; showError("Couldn't load your people", message: error) }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard !previewShown, presentedViewController == nil else { return }
        previewShown = true
        if args.contains("--preview-phone-setup") {
            let person = try? CallContact(name: "David", nativeCall: NativeCall(room: "family-david", mode: .video), phoneNumber: "+14155550123")
            present(PorchStyle.navigation(SetupViewController(slot: 1, contact: person)), animated: false)

        } else if args.contains("--preview-caregiver") { showUnlockedSetup() }
        else if args.contains("--preview-family-settings") { present(PorchStyle.navigation(FamilyAdminViewController()), animated: false) }
        else if args.contains("--preview-pin-setup") { present(PorchStyle.navigation(CaregiverPINViewController(profile: nil)), animated: false) }
        else if args.contains("--preview-setup") { showSetup() }
        else if args.contains("--preview-people") { showPeople() }
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clockTimer?.invalidate(); clockTimer = nil
        resignFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.safeAreaLayoutGuide.layoutFrame.size
        guard size != typographySize, size.width > 0, size.height > 0 else { return }
        typographySize = size
        // Fit the clock to the iPad, rather than capping it at phone-sized text.
        // Reserve the bottom area for calling and allow long localized dates to fit.
        let width = max(200, size.width - 64)
        let height = max(240, size.height - 200)
        weekdayLabel.font = .systemFont(ofSize: min(width * 0.075, height * 0.13), weight: .medium)
        dateLabel.font = .systemFont(ofSize: min(width * 0.061, height * 0.11))
        timeLabel.font = .monospacedDigitSystemFont(ofSize: min(width * 0.43, height * 0.48), weight: .medium)
        updateClock()
    }

    func resume() {
        trigger.resetKeys()
        // Permission dialogs, app switching and keyboard changes must never take focus
        // from a caregiver's text field or from an active call.
        guard isViewLoaded, presentedViewController == nil else { return }
        opening = false
        statusLabel.text = nil
        refreshCallButton()
        resetClock()
        if clockTimer == nil {
            let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in self?.updateClock() }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            clockTimer = timer
        }
        becomeFirstResponder()
    }

    func pause() { trigger.resetKeys(); clockTimer?.invalidate(); clockTimer = nil }

    @objc private func resetClock() {
        for formatter in [timeFormatter, weekdayFormatter, dateFormatter] {
            formatter.timeZone = .autoupdatingCurrent
            formatter.calendar = .autoupdatingCurrent
        }
        timeFormatter.locale = .autoupdatingCurrent
        timeFormatter.dateStyle = .none; timeFormatter.timeStyle = .short
        weekdayFormatter.locale = .autoupdatingCurrent
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEEE")
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMMdyyyy")
        updateClock()
        clockTimer?.fireDate = nextMinute
    }

    private var nextMinute: Date {
        Date(timeIntervalSinceNow: 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60) + 0.05)
    }

    private func updateClock() {
        let now = Date()
        let time = timeFormatter.string(from: now).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        let text = NSMutableAttributedString(string: time, attributes: [.font: timeLabel.font ?? UIFont.systemFont(ofSize: 172), .foregroundColor: PorchStyle.nightText])
        for symbol in [timeFormatter.amSymbol, timeFormatter.pmSymbol] {
            guard let symbol, !symbol.isEmpty, let range = time.range(of: symbol, options: .caseInsensitive) else { continue }
            text.addAttributes([.font: UIFont.systemFont(ofSize: timeLabel.font.pointSize * 0.25, weight: .medium)], range: NSRange(range, in: time))
        }
        timeLabel.attributedText = text
        weekdayLabel.text = weekdayFormatter.string(from: now)
        dateLabel.text = dateFormatter.string(from: now)
    }

    private func refreshCallButton() { callButton.isEnabled = !opening }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard presentedViewController == nil, let key = press.key,
                  let slot = CallTrigger.slot(for: Int(key.keyCode.rawValue)),
                  key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty else {
                unhandled.insert(press); continue
            }
            if trigger.keyDown(Int(key.keyCode.rawValue)) { call(slot: slot) }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { trigger.keyUp(Int(key.keyCode.rawValue)) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        trigger.resetKeys(); super.pressesCancelled(presses, with: event)
    }

    @objc private func showPeople() {
        guard presentedViewController == nil else { return }
        let picker = PeoplePickerViewController(slots: slots)
        picker.onCall = { [weak self, weak picker] number in
            picker?.dismiss(animated: true) { self?.call(slot: number) }
        }
        present(picker, animated: true)
    }

    private func call(slot: Int) {
        guard !opening, presentedViewController == nil,
              view.window?.windowScene?.activationState == .foregroundActive else { return }
        guard let contact = slots.contact(for: slot) else {
            statusLabel.text = "No one is assigned to \(slot).\nPlease choose another number."
            return
        }
        guard let native = contact.nativeCall else {
            showError("Finish Porch setup", message: "Open caregiver mode and link this person's Porch app or add their phone number."); return
        }
        startFamilyCall(contact, memberID: contact.familyMemberID, mode: native.mode)
    }

    private func startFamilyCall(_ contact: CallContact, memberID: String?, mode: NativeCall.Mode) {
        guard PorchDevice.credential(for: .bedside) != nil, !opening else {
            showError("Porch isn't ready", message: "Check Family & drop-in in caregiver mode, then try again."); return
        }
        guard trigger.allowLaunch(at: ProcessInfo.processInfo.systemUptime) else { return }
        opening = true; refreshCallButton()
        Task { [weak self] in
            guard let self else { return }
            defer { self.opening = false; self.refreshCallButton() }
            do {
                let session = try await FamilyCoordinator.shared.startCall(targetID: memberID, name: contact.name, mode: mode, dropIn: false, waitSeconds: contact.phoneNumber == nil ? 45 : CallPreferences.fallbackSeconds())
                guard self.presentedViewController == nil, UIApplication.shared.applicationState == .active else { await session.end(); return }
                self.present(try NativeCallViewController.paired(session, contact: contact), animated: true)
            } catch {
                // A lost response may still have created a Porch call. Only a
                // confirmed offline result permits an unpaired phone handoff.
                if contact.phoneNumber != nil, (error as? FamilyServiceError)?.code == "offline", UIApplication.shared.applicationState == .active, self.presentedViewController == nil {
                    do { self.present(try NativeCallViewController.phoneFallback(contact), animated: true) }
                    catch { self.showError("Couldn't call \(contact.name)", message: error.localizedDescription) }
                } else { self.showError("Couldn't call \(contact.name)", message: error.localizedDescription) }
            }
        }
    }

    @objc private func heldSetup(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { UIImpactFeedbackGenerator(style: .light).impactOccurred(); showSetup() }
    }
    @objc private func tappedSetup() { showSetup() }
    @objc private func accessibleSetup() -> Bool { showSetup(); return true }

    func showSetup() {
        guard presentedViewController == nil else { return }
        trigger.resetKeys(); resignFirstResponder()
        let gate = CaregiverPINViewController()
        gate.onUnlock = { [weak self] in self?.showUnlockedSetup() }
        present(PorchStyle.navigation(gate), animated: true)
    }

    private func showUnlockedSetup() {
        guard presentedViewController == nil else { return }
        trigger.resetKeys()
        resignFirstResponder()
        let setup = SlotsViewController(slots: slots)
        setup.onSave = { [weak self] updated in
            try updated.save()
            self?.slots = updated
        }
        present(PorchStyle.navigation(setup), animated: true)
    }

    private func showError(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

final class PeoplePickerViewController: UIViewController {
    var onCall: ((Int) -> Void)?
    private let slots: CallSlots
    private let grid = UIStackView()
    private var trigger = CallTrigger()
    private var columns = 0
    private var choosing = false
    init(slots: CallSlots) {
        self.slots = slots
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("Use init(slots:)") }
    override var canBecomeFirstResponder: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = PorchStyle.night
        let heading = PorchStyle.label("Who would you like to call?", size: 36, color: PorchStyle.nightText, weight: .semibold)
        let hint = PorchStyle.label("Tap a name or press their number on the keypad.", size: 20, color: PorchStyle.nightSecondary)
        heading.textAlignment = .center; hint.textAlignment = .center
        let back = PorchStyle.button("Back to clock", symbol: "clock", filled: false)
        back.configuration?.baseForegroundColor = PorchStyle.nightText
        back.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        grid.axis = .vertical; grid.spacing = 16
        let scroll = UIScrollView()
        let stack = UIStackView(arrangedSubviews: [heading, hint, grid])
        stack.axis = .vertical; stack.spacing = 24
        [stack, scroll, back].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll); view.addSubview(back); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: back.topAnchor, constant: -16),
            back.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            back.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -64)
        ])
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let count = traitCollection.preferredContentSizeCategory.isAccessibilityCategory || view.bounds.width < 600 ? 1 : view.bounds.width > view.bounds.height ? 3 : 2
        guard columns != count else { return }
        columns = count
        grid.arrangedSubviews.forEach { grid.removeArrangedSubview($0); $0.removeFromSuperview() }
        let people = (1...CallSlots.count).compactMap { index in slots.contact(for: index).map { (index, $0) } }
        if people.isEmpty {
            grid.addArrangedSubview(PorchStyle.label("Your caregiver can add people using the settings icon on the clock screen.", size: 24, color: PorchStyle.nightText))
        }
        for start in stride(from: 0, to: people.count, by: columns) {
            let row = UIStackView(); row.spacing = 16; row.distribution = .fillEqually
            for index in start..<min(start + columns, people.count) {
                let (number, person) = people[index]
                let button = PorchStyle.button(person.name)
                button.configuration?.subtitle = "Press \(number)"
                button.configuration?.image = UIImage(systemName: "phone.fill")
                button.configuration?.imagePlacement = .top
                button.configuration?.imagePadding = 16
                button.configuration?.baseBackgroundColor = PorchStyle.nightSurface
                button.configuration?.baseForegroundColor = PorchStyle.nightText
                button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = attributes; attributes.font = PorchStyle.font(30, weight: .semibold); return attributes
                }
                button.accessibilityLabel = "Call \(person.name), key \(number)"
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
                button.addAction(UIAction { [weak self] _ in self?.choose(number) }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            for _ in row.arrangedSubviews.count..<columns { row.addArrangedSubview(UIView()) }
            grid.addArrangedSubview(row)
        }
    }
    private func choose(_ number: Int) {
        guard !choosing, slots.contact(for: number) != nil else { return }
        choosing = true; view.isUserInteractionEnabled = false; onCall?(number)
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let number = CallTrigger.slot(for: Int(key.keyCode.rawValue)),
                key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty else { unhandled.insert(press); continue }
            if trigger.keyDown(Int(key.keyCode.rawValue)) { choose(number) }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { trigger.keyUp(Int(key.keyCode.rawValue)) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        trigger.resetKeys(); super.pressesCancelled(presses, with: event)
    }
}
