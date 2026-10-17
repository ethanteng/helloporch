import UIKit
import PorchCore

final class CallViewController: UIViewController {
    private var slots = CallSlots()
    private var trigger = CallTrigger()
    private var opening = false
    private var loadError: String?
    private let sceneView = BedsideSceneView()
    private let clock = UIStackView()
    private let clockArea = UILayoutGuide()
    private var callHeight: NSLayoutConstraint!
    private let contextLabel = UILabel()
    private let weekdayLabel = UILabel()
    private let timeLabel = UILabel()
    private var clockFont = UIFont.monospacedDigitSystemFont(ofSize: 360, weight: .regular)
    private let dateLabel = UILabel()
    private let statusLabel = UILabel()
    private let caregiver = UIButton(type: .system)
    private let callButton = PorchStyle.button("Call someone", symbol: "phone.fill")
    /// A quiet notice when family messages are waiting; tapping it plays them.
    private let messagesButton = PorchStyle.button("", symbol: "envelope.fill")
    private var clockTop: NSLayoutConstraint!
    private var clockTimer: Timer?
    private var timeFormatter = DateFormatter()
    private var weekdayFormatter = DateFormatter()
    private var dateFormatter = DateFormatter()
    private var typographySize = CGSize.zero
    private var appliedDisplayStyle: Int?
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
            let names: [String]
            switch BedsideText.language {
            case .traditionalChinese, .cantonese: names = ["家人", "陳先生", "林小姐", "王阿姨", "李叔叔", "朋友"]
            case .simplifiedChinese: names = ["家人", "陈先生", "林小姐", "王阿姨", "李叔叔", "朋友"]
            case .spanish: names = ["María", "José", "Ana", "Carlos", "Isabel", "David"]
            case .english: names = ProcessInfo.processInfo.arguments.contains("--preview-six") ? ["David", "Maria", "James", "Sarah", "Michael", "Anna"] : ["David"]
            }
            for (index, name) in names.enumerated() {
                let colors = ["D8AD58", "8ABBC8", "B8A0CE", "91B49C", "D49C87", "9FAEC6"]
                var photo: Data?
                if ProcessInfo.processInfo.arguments.contains("--preview-photos") {
                    photo = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
                        RecipientAppearance.color(hex: colors[index]).setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                        UIImage(systemName: "person.crop.square.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 450))?.withTintColor(PorchStyle.ink, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 50, y: 50, width: 500, height: 500))
                    }.jpegData(compressionQuality: 0.8)
                }
                try? slots.setContact(CallContact(name: name, nativeCall: NativeCall(room: "preview-person-\(index + 1)", mode: .video), familyMemberID: String(format: "00000000-0000-4000-8000-%012d", index + 1), buttonColorHex: photo == nil ? nil : colors[index], photoData: photo), for: index + 1)
            }
        }
        #endif
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor), sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor), sceneView.topAnchor.constraint(equalTo: view.topAnchor), sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        contextLabel.textColor = PorchStyle.nightText; contextLabel.textAlignment = .center
        contextLabel.font = PorchStyle.font(32, weight: .semibold)
        contextLabel.accessibilityIdentifier = "clock.context"
        contextLabel.adjustsFontSizeToFitWidth = true; contextLabel.minimumScaleFactor = 0.5
        weekdayLabel.font = PorchStyle.font(72, weight: .medium)
        timeLabel.font = clockFont
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
        [contextLabel, weekdayLabel, timeLabel, dateLabel].forEach { clock.addArrangedSubview($0) }
        clock.axis = .vertical
        clock.spacing = 24
        clock.isAccessibilityElement = false
        clock.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clock)

        var callConfig = callButton.configuration!
        callConfig.baseBackgroundColor = PorchStyle.nightSurface
        callConfig.baseForegroundColor = PorchStyle.nightText
        callConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(UIDevice.current.userInterfaceIdiom == .pad ? 48 : 32, weight: .semibold); return attributes
        }
        callConfig.contentInsets = .init(top: 24, leading: 24, bottom: 24, trailing: 24)
        callConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 28, weight: .semibold)
        callConfig.imagePadding = 20
        callConfig.titleAlignment = .center
        callConfig.titleLineBreakMode = .byWordWrapping
        callButton.configuration = callConfig
        callButton.accessibilityIdentifier = "clock.call"
        callButton.addTarget(self, action: #selector(showPeople), for: .touchUpInside)
        caregiver.layer.cornerRadius = 32
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
        var messageConfig = messagesButton.configuration!
        messageConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(26, weight: .semibold); return attributes
        }
        messageConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        messageConfig.cornerStyle = .capsule
        messagesButton.configuration = messageConfig
        messagesButton.accessibilityIdentifier = "clock.messages"
        messagesButton.isHidden = true
        messagesButton.addTarget(self, action: #selector(playMessages), for: .touchUpInside)
        [callButton, caregiver, statusLabel, messagesButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        let guide = view.safeAreaLayoutGuide
        view.addLayoutGuide(clockArea)
        clockTop = clockArea.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16)
        callHeight = callButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 124)
        callHeight.isActive = true
        NSLayoutConstraint.activate([
            clockArea.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            clockArea.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            clockTop,
            messagesButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            messagesButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            messagesButton.trailingAnchor.constraint(lessThanOrEqualTo: caregiver.leadingAnchor, constant: -16),
            messagesButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            clockArea.bottomAnchor.constraint(equalTo: callButton.topAnchor, constant: -48),
            clock.centerYAnchor.constraint(equalTo: clockArea.centerYAnchor),
            clock.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            clock.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 32),
            clock.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -32),
            caregiver.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            caregiver.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            caregiver.widthAnchor.constraint(equalToConstant: 64),
            caregiver.heightAnchor.constraint(equalToConstant: 64),
            callButton.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            callButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -36),
            callButton.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            callButton.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
            callButton.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            statusLabel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
            statusLabel.bottomAnchor.constraint(equalTo: callButton.topAnchor, constant: -16)
        ])
        let callWidth = callButton.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -48)
        callWidth.priority = .defaultHigh; callWidth.isActive = true
        let width = clock.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -64)
        width.priority = .defaultHigh; width.isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(resetClock), name: UIApplication.significantTimeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetClock), name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateDisplay), name: .porchBedsideDisplayChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadSlots), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(restyleDisplay), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMessages), name: .porchMessagesReady, object: nil)
        BedsideMessages.shared.start()
        updateDisplay(); resetClock()
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
        if args.contains("--preview-phone-setup") || args.contains("--preview-recipient-appearance") {
            let person = args.contains("--preview-recipient-appearance") ? slots.contact(for: 1) : try? CallContact(name: "David", nativeCall: NativeCall(room: "family-david", mode: .video), phoneNumber: "+14155550123")
            present(PorchStyle.navigation(SetupViewController(slot: 1, contact: person)), animated: false)

        } else if args.contains("--preview-outgoing-call"), let person = slots.contact(for: 1), let call = person.nativeCall {
            let server = try! NativeCallServer(url: "https://example.invalid", accessCode: "static-preview-only")
            present(NativeCallViewController(contact: person, call: call, server: server), animated: false)
        } else if args.contains("--preview-incoming-call"), let person = slots.contact(for: 1), let caller = person.familyMemberID {
            let data = try! JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "from": caller, "to": "preview-bedside", "mode": "video", "kind": "call", "state": "pending", "createdAt": 1, "expiresAt": 90, "callerName": person.name])
            let call = try! JSONDecoder().decode(FamilyCallRecord.self, from: data)
            let snapshotData = try! JSONSerialization.data(withJSONObject: ["householdID": "preview", "householdName": "Preview", "dropInEnabled": false,
                "me": ["id": "preview-bedside", "name": "Pat", "role": "bedside", "permissions": ["audio": false, "video": false], "online": true],
                "people": [["id": caller, "name": person.name, "role": "family", "permissions": ["audio": false, "video": false], "online": true]], "busy": false, "serverTime": 1])
            let snapshot = try! JSONDecoder().decode(FamilySnapshot.self, from: snapshotData)
            present(IncomingFamilyCallViewController(call: call, credential: FamilyCredential(origin: URL(string: "https://example.invalid")!, credential: "preview", role: .bedside), snapshot: snapshot, slots: slots), animated: false)
        } else if args.contains("--preview-incoming-video") {
            let id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
            let data = try! JSONSerialization.data(withJSONObject: ["id": id, "from": id, "to": id, "mode": "video", "kind": "dropIn", "state": "pending", "createdAt": 1, "expiresAt": 90, "callerName": BedsideText.string("A family member")])
            let call = try! JSONDecoder().decode(FamilyCallRecord.self, from: data)
            present(IncomingFamilyCallViewController(call: call, credential: FamilyCredential(origin: URL(string: "https://example.invalid")!, credential: "preview", role: .bedside)), animated: false)
        } else if args.contains("--preview-caregiver") { showUnlockedSetup() }
        else if args.contains("--preview-family-settings") { present(PorchStyle.navigation(FamilyAdminViewController()), animated: false) }
        else if args.contains("--preview-pin-setup") { present(PorchStyle.navigation(CaregiverPINViewController(profile: nil)), animated: false) }
        else if args.contains("--preview-setup") { showSetup() }
        else if args.contains("--preview-people") { showPeople() }
        else if args.contains("--preview-display-settings") { present(PorchStyle.navigation(BedsideDisplaySettingsViewController()), animated: false) }
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
        let large = size.width >= 600 && size.height >= 500
        let fontSize: CGFloat = large ? 48 : size.width < 400 ? 28 : 32
        callHeight.constant = large ? 124 : size.height < 500 ? 80 : 96
        callButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(fontSize, weight: .semibold); return attributes
        }
        callButton.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: large ? 40 : 24, weight: .semibold)
        callButton.configuration?.contentInsets = .init(top: 20, leading: 16, bottom: 20, trailing: 16)
        callButton.configuration?.imagePadding = large ? 20 : 12
        // Fit the clock to the iPad, rather than capping it at phone-sized text.
        // Reserve the bottom area for calling and allow long localized dates to fit.
        let width = max(200, size.width - 64)
        let height = max(80, size.height - callHeight.constant - 132 - clockTop.constant + 16)
        clock.spacing = min(24, height * 0.025)
        contextLabel.font = PorchStyle.font(max(18, min(32, height * 0.07)), weight: .semibold)
        weekdayLabel.font = .systemFont(ofSize: min(width * 0.075, height * 0.13), weight: .medium)
        dateLabel.font = .systemFont(ofSize: min(width * 0.061, height * 0.11))
        clockFont = .monospacedDigitSystemFont(ofSize: min(width * 0.43, height * 0.48), weight: .medium)
        timeLabel.font = clockFont
        updateClock()
    }

    func resume() {
        trigger.resetKeys()
        // Permission dialogs, app switching and keyboard changes must never take focus
        // from a caregiver's text field or from an active call.
        guard isViewLoaded, presentedViewController == nil else { return }
        opening = false
        updateDisplay()
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
            formatter.locale = BedsideText.language.locale
        }
        timeFormatter.dateStyle = .none; timeFormatter.timeStyle = .short
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEEE")
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMMdyyyy")
        updateClock()
        clockTimer?.fireDate = nextMinute
    }

    private var nextMinute: Date {
        Date(timeIntervalSinceNow: 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60) + 0.05)
    }

    private func updateClock() {
        var now = Date()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--preview-hour"), args.count > i + 1, let hour = Int(args[i + 1]) {
            now = Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: now) ?? now
        }
        #endif
        var clockColor = PorchStyle.nightText
        if !sceneView.isHidden {
            let scene = BedsideScene(date: now, preferences: BedsidePreferences.load())
            let palette = BedsideScenePalette(scene: scene)
            clockColor = palette.foreground
            let style = scene.isDay ? 1 : 2
            if appliedDisplayStyle != style {
                for label in [contextLabel, weekdayLabel, dateLabel] { label.textColor = palette.foreground }
                caregiver.tintColor = palette.controlForeground; caregiver.backgroundColor = palette.controlBackground
                // Let the hills and tree show through; Reduce Transparency keeps it solid.
                var config = callButton.configuration!
                config.baseBackgroundColor = palette.controlBackground.withAlphaComponent(UIAccessibility.isReduceTransparencyEnabled ? 1 : 0.6)
                config.baseForegroundColor = palette.controlForeground
                callButton.configuration = config
                messagesButton.configuration?.baseBackgroundColor = config.baseBackgroundColor
                messagesButton.configuration?.baseForegroundColor = config.baseForegroundColor
                statusLabel.textColor = palette.controlForeground; statusLabel.backgroundColor = palette.controlBackground
                statusLabel.layer.cornerRadius = 10; statusLabel.clipsToBounds = true
                appliedDisplayStyle = style
            }
            contextLabel.text = "\(BedsideText.string(scene.period.rawValue)) · \(BedsideText.string(scene.season.rawValue))"
            // Switch the complete contrast treatment at a schedule boundary;
            // a crossfade between light and dark text would briefly lose contrast.
            if sceneView.window != nil && !UIAccessibility.isReduceMotionEnabled && sceneView.scene.isDay == scene.isDay && sceneView.scene != scene {
                UIView.transition(with: sceneView, duration: 1.5, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.sceneView.scene = scene }
            } else { sceneView.scene = scene }
        } else if appliedDisplayStyle != 0 {
            appliedDisplayStyle = 0
            contextLabel.textColor = PorchStyle.nightText
            for label in [weekdayLabel, dateLabel] { label.textColor = PorchStyle.nightSecondary }
            caregiver.tintColor = PorchStyle.nightSecondary; caregiver.backgroundColor = .clear
            var config = callButton.configuration!
            config.baseBackgroundColor = PorchStyle.nightSurface; config.baseForegroundColor = PorchStyle.nightText
            callButton.configuration = config
            messagesButton.configuration?.baseBackgroundColor = PorchStyle.nightSurface
            messagesButton.configuration?.baseForegroundColor = PorchStyle.nightText
            statusLabel.textColor = PorchStyle.nightSecondary; statusLabel.backgroundColor = .clear
        }
        let time = timeFormatter.string(from: now).replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        let text = NSMutableAttributedString(string: time, attributes: [.font: clockFont, .foregroundColor: clockColor])
        // Flexible Chinese periods include 中午/凌晨, beyond the AM/PM symbols.
        let periods = try? NSRegularExpression(pattern: "[\\p{L}\\p{M}]+")
        for match in periods?.matches(in: time, range: NSRange(time.startIndex..., in: time)) ?? [] {
            text.addAttributes([.font: UIFont.systemFont(ofSize: clockFont.pointSize * 0.25, weight: .medium)], range: match.range)
        }
        timeLabel.attributedText = text
        weekdayLabel.text = weekdayFormatter.string(from: now)
        dateLabel.text = dateFormatter.string(from: now)
    }

    @objc private func updateDisplay() {
        guard isViewLoaded else { return }
        var dynamic = BedsidePreferences.load().appearance == .dynamic
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-dynamic") { dynamic = true }
        #endif
        sceneView.isHidden = !dynamic; contextLabel.isHidden = !dynamic
        callButton.configuration?.title = BedsideText.string("Call someone")
        caregiver.accessibilityLabel = BedsideText.string("Caregiver mode")
        caregiver.accessibilityHint = BedsideText.string("Tap or hold to manage contacts and settings.")
        updateMessages()
        BedsideText.applyAccessibilityLanguage(to: view)
        resetClock()
    }
    @objc private func updateMessages() {
        guard isViewLoaded else { return }
        let count = BedsideMessages.shared.ready.count
        messagesButton.configuration?.title = count == 1 ? BedsideText.string("Play 1 message") : BedsideText.string("Play %d messages", count)
        messagesButton.accessibilityLanguage = BedsideText.language.speechLanguage
        guard messagesButton.isHidden != (count == 0) else { return }
        messagesButton.isHidden = count == 0
        // Keep the clock clear of the notice; the typography refits on the next layout.
        clockTop.constant = count == 0 ? 16 : 92
        typographySize = .zero; view.setNeedsLayout()
    }
    @objc private func playMessages() {
        guard presentedViewController == nil, !opening, view.window?.windowScene?.activationState == .foregroundActive else { return }
        let ready = BedsideMessages.shared.ready
        guard !ready.isEmpty else { statusLabel.text = BedsideText.string("No new messages."); return }
        statusLabel.text = nil
        let player = MessagePlayerViewController(messages: ready, slots: slots)
        player.onFinish = { [weak self] in self?.resume() }
        present(player, animated: true)
    }
    @objc private func restyleDisplay() { appliedDisplayStyle = nil; updateClock() }
    @objc private func reloadSlots() {
        do { slots = try CallSlots.load() } catch { statusLabel.text = error.localizedDescription }
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
        if slots.action(for: slot) == .messages { playMessages(); return }
        guard slots.action(for: slot) == .person else {
            statusLabel.text = BedsideText.string(slots.action(for: slot) == .callControl ? "Use this key to answer or end a call." : "Use this key to turn your camera off or on during a video call.")
            return
        }
        guard let contact = slots.contact(for: slot) else {
            statusLabel.text = BedsideText.string("No one is assigned to %d.\nPlease choose another number.", slot)
            return
        }
        guard let native = contact.nativeCall else {
            showError("Finish Porch setup", message: "Open caregiver mode and invite this person to Porch or add their phone number."); return
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
                    catch { self.showError(BedsideText.string("Couldn't call %@", contact.name), message: error.localizedDescription) }
                } else { self.showError(BedsideText.string("Couldn't call %@", contact.name), message: error.localizedDescription) }
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
        let alert = UIAlertController(title: BedsideText.string(title), message: BedsideText.error(message), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: BedsideText.string("OK"), style: .default))
        present(alert, animated: true)
    }
}

final class PeoplePickerViewController: UIViewController {
    var onCall: ((Int) -> Void)?
    private let slots: CallSlots
    private let grid = UIStackView()
    private var trigger = CallTrigger()
    private var columns = 0
    private var gridWidth: CGFloat = 0
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
        let heading = PorchStyle.label(BedsideText.string("Who would you like to call?"), size: UIDevice.current.userInterfaceIdiom == .pad ? 60 : 40, color: PorchStyle.nightText, weight: .semibold)
        let hint = PorchStyle.label(BedsideText.string("Tap a name or press their number on the keypad."), size: UIDevice.current.userInterfaceIdiom == .pad ? 34 : 28, color: PorchStyle.nightText)
        heading.textAlignment = .center; hint.textAlignment = .center
        let back = PorchStyle.button(BedsideText.string("Back to clock"), symbol: "clock", filled: false)
        back.configuration?.baseForegroundColor = PorchStyle.nightText
        back.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30, weight: .semibold); return attributes
        }
        back.configuration?.baseBackgroundColor = PorchStyle.nightSurface
        back.configuration?.background.backgroundColor = PorchStyle.nightSurface
        back.configuration?.contentInsets = .init(top: 20, leading: 24, bottom: 20, trailing: 24)
        back.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 32)
        back.accessibilityIdentifier = "people.back"
        back.heightAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
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
            back.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            back.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            back.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -64)
        ])
        BedsideText.applyAccessibilityLanguage(to: view)
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let count = traitCollection.preferredContentSizeCategory.isAccessibilityCategory || view.bounds.width < 600 ? 1 : 2
        guard columns != count || abs(gridWidth - view.bounds.width) > 1 else { return }
        columns = count; gridWidth = view.bounds.width
        let cardWidth = (view.bounds.width - 64 - CGFloat(count - 1) * 16) / CGFloat(count)
        let nameSize = max(54, min(88, cardWidth * 0.18))
        let numberSize = max(36, min(48, cardWidth * 0.10))
        grid.arrangedSubviews.forEach { grid.removeArrangedSubview($0); $0.removeFromSuperview() }
        let people = CallSlots.digits.compactMap { index in slots.contact(for: index).map { (index, $0) } }
        if people.isEmpty {
            grid.addArrangedSubview(PorchStyle.label(BedsideText.string("Your caregiver can add people using the settings icon on the clock screen."), size: 24, color: PorchStyle.nightText))
        }
        for start in stride(from: 0, to: people.count, by: columns) {
            let row = UIStackView(); row.spacing = 16; row.distribution = .fillEqually
            for index in start..<min(start + columns, people.count) {
                let (number, person) = people[index]
                let button = PorchStyle.button(person.name)
                button.configuration?.subtitle = BedsideText.string("Press %d", number)
                button.configuration?.image = RecipientAppearance.cardPhoto(person.photoData, width: cardWidth - 40)
                button.configuration?.imagePlacement = .top
                button.configuration?.imagePadding = 20
                button.configuration?.titleAlignment = .center
                button.configuration?.titleLineBreakMode = .byWordWrapping
                button.configuration?.subtitleLineBreakMode = .byWordWrapping
                button.configuration?.titlePadding = 12
                button.configuration?.contentInsets = .init(top: 28, leading: 20, bottom: 28, trailing: 20)
                let color = RecipientAppearance.color(hex: person.buttonColorHex)
                let foreground = RecipientAppearance.foreground(on: color)
                button.configuration?.cornerStyle = .fixed
                button.configuration?.background.cornerRadius = 24
                button.configuration?.baseBackgroundColor = color
                button.configuration?.baseForegroundColor = foreground
                button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(nameSize, weight: .semibold); return attributes
                }
                button.configuration?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(numberSize, weight: .medium); attributes.foregroundColor = foreground; return attributes
                }
                button.accessibilityIdentifier = "people.person.\(number)"
                button.accessibilityLanguage = BedsideText.language.speechLanguage
                button.accessibilityLabel = BedsideText.string("Call %@, key %d", person.name, number)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: max(200, nameSize * 3.5)).isActive = true
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
