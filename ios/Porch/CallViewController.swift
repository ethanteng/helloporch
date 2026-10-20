import UIKit
import PorchCore

extension UIKey {
    /// The keypad key this press means, if any: a digit, * or #. Command, Control and Option presses never are.
    var keypadDigit: Int? {
        guard modifierFlags.isDisjoint(with: [.command, .control, .alternate]) else { return nil }
        return CallTrigger.slot(for: Int(keyCode.rawValue), characters: characters, shift: modifierFlags.contains(.shift))
    }
}

final class CallViewController: UIViewController {
    private var slots = CallSlots()
    private var trigger = CallTrigger()
    private var opening = false
    private var cancelOpening = false
    /// Plays waiting messages when someone sits down in front of the iPad, if a caregiver turned it on.
    private let presence = BedsidePresence()
    private var notice: MessageNoticeView?
    /// True while the camera is being released before something covers the clock. Presence must not
    /// start again until that present has either appeared or been abandoned.
    private var presenceSuppressed = false
    private var cameraReleaseWaiters: [() -> Void] = []
    /// The container skips a new incoming call until this is false, then checks again.
    var isReleasingCamera: Bool { presenceSuppressed }
    /// After Not now or Stop: the messages that were waiting, left alone until then unless a new one arrives.
    private var snooze: (until: Date, ids: Set<String>)?
    private let phoneKeypadStatus = UILabel()
    private var phoneKeypadStatusTimer: Timer?
    private var displayedPhoneKeypadStatus: String?
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
    private var statusTimer: Timer?
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
        phoneKeypadStatus.font = PorchStyle.font(16)
        phoneKeypadStatus.textColor = PorchStyle.nightSecondary
        phoneKeypadStatus.textAlignment = .center
        phoneKeypadStatus.numberOfLines = 1
        phoneKeypadStatus.adjustsFontSizeToFitWidth = true
        phoneKeypadStatus.minimumScaleFactor = 0.75
        phoneKeypadStatus.accessibilityIdentifier = "clock.cell2jack"
        phoneKeypadStatus.isHidden = true
        NotificationCenter.default.addObserver(self, selector: #selector(updatePhoneKeypadStatus), name: .cell2JackKeypadChanged, object: nil)
        updatePhoneKeypadStatus()
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
        statusLabel.accessibilityIdentifier = "clock.feedback"
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
        [callButton, caregiver, statusLabel, messagesButton, phoneKeypadStatus].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
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
            phoneKeypadStatus.topAnchor.constraint(equalTo: callButton.bottomAnchor, constant: 8),
            phoneKeypadStatus.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            phoneKeypadStatus.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            phoneKeypadStatus.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
            phoneKeypadStatus.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor, constant: -2),
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
        BedsideOutbox.shared.start()
        presence.onPresent = { [weak self] in self?.presenceDetected() }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPresence), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPresence), name: .porchMessageAutoplayChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        updateDisplay(); resetClock()
    }

    deinit { statusTimer?.invalidate(); phoneKeypadStatusTimer?.invalidate(); clockTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }

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
        else if args.contains("--preview-voicemail"), let person = slots.contact(for: 1) {
            present(BedsideVoicemailViewController(contact: person, memberID: UUID().uuidString, mode: args.contains("--preview-video") ? .video : .voice, reason: .unanswered, staticPreview: true), animated: false)
        }
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clockTimer?.invalidate(); clockTimer = nil
        displayStatus(nil)
        // The present that covered us already waited for the camera. A removal just stops it.
        presence.stop()
        notice?.end(); notice = nil
        resignFirstResponder()
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // The camera's frames follow the iPad's orientation.
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.refreshPresence() }
    }
    // Calls, the message player and recording all need the camera or the screen.
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        releaseCamera { [weak self] in self?.presentNow(viewControllerToPresent, animated: flag, completion: completion) }
    }
    private func presentNow(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        super.present(viewControllerToPresent, animated: flag, completion: completion)
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
        updateDisplay()
        displayStatus(nil)
        refreshCallButton()
        resetClock()
        if clockTimer == nil {
            let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in self?.updateClock(); self?.refreshPresence() }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            clockTimer = timer
        }
        becomeFirstResponder()
        refreshPresence()
    }

    func pause() {
        displayStatus(nil)
        // Leaving the foreground. Stopping the camera waits on its own queue so this can return.
        presence.stop()
        notice?.end(); notice = nil
        trigger.resetKeys(); clockTimer?.invalidate(); clockTimer = nil
        if opening { cancelOpening = true }
    }

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
                statusLabel.textColor = palette.controlForeground
                statusLabel.backgroundColor = config.baseBackgroundColor
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
        defer { refreshPresence() }
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
        guard !presenceSuppressed, presentedViewController == nil, !opening, view.window?.windowScene?.activationState == .foregroundActive else { return }
        let ready = BedsideMessages.shared.ready
        guard !ready.isEmpty else { displayStatus(BedsideText.string("No new messages."), temporary: true); return }
        displayStatus(nil)
        let player = MessagePlayerViewController(messages: ready, slots: slots)
        player.onFinish = { [weak self, weak player] in
            // Stop leaves what was already waiting. A message that arrived during playback still
            // starts on its own, and a call that takes over is not Stop.
            if player?.interrupted != true {
                let deferred = MessageAutoplay.deferredMessageIDs(startedWith: ready.map(\.id), stillReady: BedsideMessages.shared.ready.map(\.id))
                if !deferred.isEmpty { self?.snooze = (Date().addingTimeInterval(MessageAutoplay.snoozeSeconds), deferred) }
            }
            self?.resume()
        }
        present(player, animated: true)
    }

    /// The camera runs only while it could start messages right away: the clock is showing and idle,
    /// downloaded messages are waiting, it's within the caregiver's hours, and Mom hasn't just said not now.
    private var presenceAllowed: Bool {
        let ready = BedsideMessages.shared.ready
        guard !presenceSuppressed, isViewLoaded, view.window != nil, presentedViewController == nil, parent?.presentedViewController == nil,
              notice == nil, !opening, !ready.isEmpty, UIApplication.shared.applicationState == .active,
              PorchDevice.experience == .bedside, FamilyCoordinator.shared.state?.busy != true,
              ProcessInfo.processInfo.thermalState != .serious, ProcessInfo.processInfo.thermalState != .critical,
              MessageAutoplay.load().allows(Date()) else { return false }
        if let snooze, Date() < snooze.until, ready.allSatisfy({ snooze.ids.contains($0.id) }) { return false }
        return true
    }
    @objc private func refreshPresence() {
        if presenceAllowed { presence.start(orientation: view.window?.windowScene?.interfaceOrientation ?? .landscapeLeft) }
        else { presence.stop() }
    }
    /// Posted off the main thread on some iOS versions. Presence state is main-thread only.
    @objc private func thermalStateChanged() {
        if Thread.isMainThread { refreshPresence() } else { DispatchQueue.main.async { [weak self] in self?.refreshPresence() } }
    }
    /// Before anything else covers the clock or needs the camera. Nothing is snoozed.
    /// `done` runs on the main thread after the capture session has stopped, without blocking
    /// until then: blocking here deadlocks start and stop, which need the main thread themselves.
    func releaseCamera(then done: @escaping () -> Void) {
        presenceSuppressed = true
        notice?.end(); notice = nil
        cameraReleaseWaiters.append(done)
        guard cameraReleaseWaiters.count == 1 else { return }
        presence.stopThen { [weak self] in
            guard let self else { return }
            let waiters = self.cameraReleaseWaiters
            self.cameraReleaseWaiters = []
            waiters.forEach { $0() }
            guard self.cameraReleaseWaiters.isEmpty else { return }
            self.presenceSuppressed = false
            guard self.view.window != nil, self.parent != nil else { return }
            (self.parent as? PorchContainerViewController)?.reevaluateIncoming()
            guard self.cameraReleaseWaiters.isEmpty, !self.presenceSuppressed else { return }
            self.refreshPresence()
        }
    }
    private func presenceDetected() {
        presence.stop()
        guard presenceAllowed else { return }
        let notice = MessageNoticeView(count: BedsideMessages.shared.ready.count)
        notice.onNotNow = { [weak self] in self?.declineNotice() }
        notice.onFinished = { [weak self] in self?.notice = nil; self?.playMessages() }
        notice.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(notice)
        NSLayoutConstraint.activate([notice.leadingAnchor.constraint(equalTo: view.leadingAnchor), notice.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                     notice.topAnchor.constraint(equalTo: view.topAnchor), notice.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        self.notice = notice
        notice.begin()
    }
    private func declineNotice() {
        notice?.end(); notice = nil
        snooze = (Date().addingTimeInterval(MessageAutoplay.snoozeSeconds), Set(BedsideMessages.shared.ready.map(\.id)))
        refreshPresence()
    }
    @objc private func restyleDisplay() { appliedDisplayStyle = nil; updateClock() }
    @objc private func reloadSlots() {
        do { slots = try CallSlots.load() } catch { displayStatus(error.localizedDescription) }
    }
    private func refreshCallButton() { callButton.isEnabled = !opening }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard presentedViewController == nil, let key = press.key, let slot = key.keypadDigit else {
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
        guard !presenceSuppressed, presentedViewController == nil else { return }
        let picker = PeoplePickerViewController(slots: slots)
        picker.onCall = { [weak self, weak picker] number in
            picker?.dismiss(animated: true) { self?.call(slot: number) }
        }
        present(picker, animated: true)
    }

    private func call(slot: Int) {
        // The camera is still stopping for a screen that's about to appear. Ignore the key until it does.
        guard !presenceSuppressed else { return }
        // Any key answers the messages notice: the messages and call keys mean Not now; a person's key calls them instead.
        if let notice {
            let action = slots.action(for: slot)
            notice.notNow()
            if action == .messages || action == .callControl { return }
        }
        guard !opening, presentedViewController == nil,
              view.window?.windowScene?.activationState == .foregroundActive else { return }
        if slots.action(for: slot) == .messages { playMessages(); return }
        guard slots.action(for: slot) == .person else {
            displayStatus(BedsideText.string(slots.action(for: slot) == .callControl ? "Use this key to answer or end a call." : "Use this key to turn your camera off or on during a video call."), temporary: true)
            return
        }
        guard let contact = slots.contact(for: slot) else {
            displayStatus(BedsideText.string("No one is assigned to %@.\nPlease choose another number.", CallSlots.symbol(for: slot)), temporary: true)
            return
        }
        guard let native = contact.nativeCall else {
            showError("Finish Porch setup", message: "Open caregiver mode and invite this person to Porch or add their phone number."); return
        }
        startFamilyCall(contact, memberID: contact.familyMemberID, mode: native.mode)
    }

    private func displayStatus(_ text: String?, temporary: Bool = false) {
        statusTimer?.invalidate(); statusTimer = nil
        statusLabel.text = text
        guard temporary, text != nil else { return }
        statusLabel.accessibilityLanguage = BedsideText.language.speechLanguage
        UIAccessibility.post(notification: .announcement, argument: text)
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] timer in
            guard let self, self.statusTimer === timer else { return }
            self.statusLabel.text = nil
            self.statusTimer = nil
        }
        statusTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startFamilyCall(_ contact: CallContact, memberID: String?, mode: NativeCall.Mode) {
        guard PorchDevice.credential(for: .bedside) != nil, !opening else {
            showError("Porch isn't ready", message: "Check Family & drop-in in caregiver mode, then try again."); return
        }
        guard trigger.allowLaunch(at: ProcessInfo.processInfo.systemUptime) else { return }
        cancelOpening = false
        Cell2JackKeypad.shared.record(["kind": "callStartRequested", "digitSource": "shared touch/keyboard/USB handler"])
        opening = true; refreshCallButton(); refreshPresence()
        Task { [weak self] in
            guard let self else { return }
            defer { self.opening = false; self.refreshCallButton(); self.refreshPresence() }
            do {
                let session = try await FamilyCoordinator.shared.startCall(targetID: memberID, name: contact.name, mode: mode, dropIn: false, waitSeconds: contact.phoneNumber == nil ? 45 : CallPreferences.fallbackSeconds())
                if self.cancelOpening {
                    await session.end()
                    Cell2JackKeypad.shared.record(["kind": "pendingCallCancelled"])
                    return
                }
                Cell2JackKeypad.shared.record(["kind": "callSessionCreated"])
                guard self.presentedViewController == nil, UIApplication.shared.applicationState == .active else { await session.end(); return }
                let screen = try NativeCallViewController.paired(session, contact: contact)
                if let memberID { screen.onUnanswered = { [weak self] in self?.leaveMessage(for: contact, memberID: memberID, mode: mode, reason: .unanswered) } }
                self.present(screen, animated: true)
            } catch {
                if self.cancelOpening { return }
                Cell2JackKeypad.shared.record(["kind": "callStartFailed", "error": error.localizedDescription])
                // A lost response may still have created a Porch call. Only a
                // confirmed offline result permits an unpaired phone handoff.
                if contact.phoneNumber != nil, (error as? FamilyServiceError)?.code == "offline", UIApplication.shared.applicationState == .active, self.presentedViewController == nil {
                    do { self.present(try NativeCallViewController.phoneFallback(contact), animated: true) }
                    catch { self.showError(BedsideText.string("Couldn't call %@", contact.name), message: error.localizedDescription) }
                } else if let memberID, (error as? FamilyServiceError)?.code == "offline", CallPreferences.leaveMessageWhenUnanswered() {
                    // Their Porch app can't ring and there's no phone to try: leave a message, as for a missed call.
                    self.leaveMessage(for: contact, memberID: memberID, mode: mode, reason: .unavailable)
                } else { self.showError(BedsideText.string("Couldn't call %@", contact.name), message: error.localizedDescription) }
            }
        }
    }

    /// A Porch call that wasn't answered, and didn't ring through to a regular phone, records a message.
    private func leaveMessage(for contact: CallContact, memberID: String, mode: NativeCall.Mode, reason: BedsideVoicemailViewController.Reason) {
        guard !presenceSuppressed, CallPreferences.leaveMessageWhenUnanswered(), presentedViewController == nil,
              view.window?.windowScene?.activationState == .foregroundActive else { return }
        let screen = BedsideVoicemailViewController(contact: contact, memberID: memberID, mode: mode, reason: reason)
        screen.onFinish = { [weak self] in self?.resume() }
        present(screen, animated: true)
    }

    @objc private func heldSetup(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { UIImpactFeedbackGenerator(style: .light).impactOccurred(); showSetup() }
    }
    @objc private func tappedSetup() { showSetup() }
    @objc private func accessibleSetup() -> Bool { showSetup(); return true }

    func showSetup() {
        guard !presenceSuppressed, presentedViewController == nil else { return }
        trigger.resetKeys(); resignFirstResponder()
        let gate = CaregiverPINViewController()
        gate.onUnlock = { [weak self] in self?.showUnlockedSetup() }
        present(PorchStyle.navigation(gate), animated: true)
    }

    private func showUnlockedSetup() {
        guard !presenceSuppressed, presentedViewController == nil else { return }
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
                button.configuration?.subtitle = BedsideText.string("Press %@", CallSlots.symbol(for: number))
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
                button.accessibilityIdentifier = "people.person.\(CallSlots.symbol(for: number))"
                button.accessibilityLanguage = BedsideText.language.speechLanguage
                button.accessibilityLabel = BedsideText.string("Call %@, key %@", person.name, CallSlots.symbol(for: number))
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
            guard let key = press.key, let number = key.keypadDigit else { unhandled.insert(press); continue }
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

extension CallViewController: Cell2JackDigitReceiving {
    @objc private func updatePhoneKeypadStatus() {
        displayPhoneKeypadStatus(Cell2JackKeypad.shared.status, enabled: Cell2JackKeypad.shared.enabled)
    }
    func displayPhoneKeypadStatus(_ status: String, enabled: Bool) {
        // Only the brief success confirmation belongs in the app UI.
        // Connection diagnostics stay in the local diagnostic files.
        let visibleStatus = enabled && status == "Phone keypad ready" ? status : nil
        // Duplicate status notifications must not restart the ready confirmation.
        guard visibleStatus != displayedPhoneKeypadStatus else { return }
        displayedPhoneKeypadStatus = visibleStatus
        phoneKeypadStatusTimer?.invalidate()
        phoneKeypadStatusTimer = nil
        phoneKeypadStatus.text = visibleStatus
        phoneKeypadStatus.isHidden = visibleStatus == nil
        if visibleStatus == "Phone keypad ready" {
            phoneKeypadStatusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                self?.phoneKeypadStatus.isHidden = true
                self?.phoneKeypadStatusTimer = nil
            }
        }
    }
    func receiveCell2JackDigit(_ digit: Int) -> String {
        guard presentedViewController == nil else { return "clock covered" }
        if opening {
            if slots.action(for: digit) == .callControl {
                cancelOpening = true
                displayStatus(BedsideText.string("Ending call…"))
                return "cancel pending call requested"
            }
            return "call already opening"
        }
        call(slot: digit)
        return "clock key dispatched"
    }
}
extension PeoplePickerViewController: Cell2JackDigitReceiving {
    func receiveCell2JackDigit(_ digit: Int) -> String {
        choose(digit)
        return "people picker key dispatched"
    }
}
