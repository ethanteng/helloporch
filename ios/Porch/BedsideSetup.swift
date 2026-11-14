import UIKit
import AVFoundation
import CoreImage.CIFilterBuiltins
import GameController
import PorchCore

/// The first screen on a device that isn't set up either way: setting Porch up for someone, or joining a family.
final class WelcomeViewController: CaregiverFormViewController {
    private let choose: (PorchExperience) -> Void
    init(choose: @escaping (PorchExperience) -> Void) { self.choose = choose; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(choose:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Porch"
        hideKeyboardControl()
        let setUp = PorchStyle.button("Set up Porch for someone", symbol: "ipad.landscape")
        setUp.accessibilityIdentifier = "welcome.setUp"
        setUp.addAction(UIAction { [weak self] _ in self?.setUp() }, for: .touchUpInside)
        let join = PorchStyle.button("I'm joining my family", symbol: "person.2.fill", filled: false)
        join.accessibilityIdentifier = "welcome.join"
        join.addAction(UIAction { [weak self] _ in self?.choose(.family) }, for: .touchUpInside)
        form.addArrangedSubview(section("Welcome to Porch", views: [setUp, join]))
        let privacy = textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } }
        privacy.accessibilityIdentifier = "caregiver.privacy"
        form.addArrangedSubview(privacy)
    }
    private func setUp() {
        guard !PorchDevice.canBeBedside else { choose(.bedside); return }
        navigationController?.pushViewController(BedsideOnIPadViewController(choose: choose), animated: true)
    }
}

/// On a phone: the bedside runs on the iPad that stays with them, so that's where setup happens.
final class BedsideOnIPadViewController: CaregiverFormViewController {
    private let choose: (PorchExperience) -> Void
    init(choose: @escaping (PorchExperience) -> Void) { self.choose = choose; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(choose:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Set up Porch"
        hideKeyboardControl()
        let join = PorchStyle.button("I'm joining my family", symbol: "person.2.fill", filled: false)
        join.addAction(UIAction { [weak self] _ in self?.choose(.family) }, for: .touchUpInside)
        form.addArrangedSubview(section("Set up Porch on their iPad", detail: "Open your setup link on the iPad that stays with your loved one.", views: [join]))
    }
}

/// Setting up a new bedside iPad, one screen at a time: the setup link, unless Porch was opened from it; who it's for;
/// the caregiver PIN, which sets the iPad up; its own phone number; the microphone and camera; how they'll call, with a
/// desk phone or the touchscreen; the caregiver's own phone; then Done. Until the iPad is set up, the clock's caregiver button opens this instead of
/// caregiver mode.
@MainActor final class BedsideSetup {
    /// Who this Porch is for, such as "Mom", once it's chosen.
    var name = ""
    /// Setting up a new Porch in place of the one this iPad already is, until the PIN step swaps them. Until then the old
    /// one stays as it was, and Cancel keeps it.
    var replacing = false
    /// Runs after Done: true goes on to put people on the keypad in caregiver mode.
    let onFinish: (Bool) -> Void
    init(onFinish: @escaping (Bool) -> Void = { _ in }) { self.onFinish = onFinish }

    static func start(replacing: Bool = false, onFinish: @escaping (Bool) -> Void) -> UINavigationController {
        SystemIncomingCalls.shared.holdsMicrophonePrompt = true
        let setup = BedsideSetup(onFinish: { keypad in releaseMicrophonePrompt(); onFinish(keypad) })
        setup.replacing = replacing
        return PorchStyle.navigation(needsLink ? SetupLinkViewController(setup) : SetupNameViewController(setup))
    }
    /// A setup that stopped after its PIN, such as when Porch was closed: no Porch number yet, and the microphone or camera
    /// never asked about. After the PIN, caregiver mode goes on from the number.
    static var unfinished: Bool {
        guard PorchDevice.credential(for: .bedside) != nil, let state = FamilyCoordinator.shared.state, state.porchNumber == nil else { return false }
        return [AVMediaType.audio, .video].contains { AVCaptureDevice.authorizationStatus(for: $0) == .notDetermined }
    }
    static func resume(onFinish: @escaping (Bool) -> Void) -> UINavigationController {
        SystemIncomingCalls.shared.holdsMicrophonePrompt = true
        let setup = BedsideSetup(onFinish: { keypad in releaseMicrophonePrompt(); onFinish(keypad) })
        return PorchStyle.navigation(SetupNumberViewController(setup))
    }
    /// Once setup is over, registering for calls may ask for the microphone, and does now if setup didn't get it.
    static func releaseMicrophonePrompt() {
        SystemIncomingCalls.shared.holdsMicrophonePrompt = false
        if PorchDevice.credential(for: .bedside) != nil { SystemIncomingCalls.shared.registerDevice() }
    }
    /// The setup link comes first, unless Porch was opened from it or this iPad has the operator's setup code instead.
    static var needsLink: Bool { PorchDevice.bedsideActivation == nil && NativeCallSettings.caregiverCode.count < 16 }
    /// The screens after the number, in order. Each is skipped when there's nothing to do on it.
    enum Stage: Int, Comparable {
        case permissions, phone, yourPhone, done
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }
    /// The first screen from `stage` on that has something to do.
    func screen(from stage: Stage) -> UIViewController {
        if stage <= .permissions, SetupPermissionsViewController.needed { return SetupPermissionsViewController(self) }
        if stage <= .phone { return SetupCallingViewController(self) }
        if stage <= .yourPhone, SetupYourPhoneViewController.needed { return SetupYourPhoneViewController(self) }
        return SetupDoneViewController(self)
    }
}

/// One screen of setup. Until the iPad is set up, the first screen can be cancelled and the others go back. Once it's
/// set up, each screen that's left replaces the last, so its number can't be skipped by going back.
class BedsideSetupStep: CaregiverFormViewController {
    let setup: BedsideSetup
    var task: Task<Void, Never>?
    init(_ setup: BedsideSetup) { self.setup = setup; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(_:)") }
    /// The name these screens use, such as Mom.
    var lovedOne: String {
        let chosen = setup.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return chosen.isEmpty ? FamilyCoordinator.shared.state?.householdName ?? "Your loved one" : chosen
    }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Set up Porch"
        if navigationController?.viewControllers.first === self, PorchDevice.credential(for: .bedside) == nil || setup.replacing {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if isMovingFromParent { task?.cancel() } }
    @objc private func cancel() { task?.cancel(); try? PorchDevice.saveActivation(nil); BedsideSetup.releaseMicrophonePrompt(); dismiss(animated: true) }
    /// For the first screen: this device can be a family member's instead, and anyone can read the privacy policy. An
    /// iPad being replaced is already a bedside, and This iPad in caregiver mode is where it becomes a family device.
    func addWayOut() {
        if !setup.replacing {
            form.addArrangedSubview(textLink("Use this device as a family member") { [weak self] in
                self?.task?.cancel(); try? PorchDevice.saveActivation(nil); BedsideSetup.releaseMicrophonePrompt()
                self?.dismiss(animated: true) { PorchDevice.experience = .family }
            })
        }
        let privacy = textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } }
        privacy.accessibilityIdentifier = "caregiver.privacy"
        form.addArrangedSubview(privacy)
    }
}

/// The private setup link from the invitation, when Porch wasn't opened from it.
final class SetupLinkViewController: BedsideSetupStep {
    private let link = UITextField()
    override func viewDidLoad() {
        super.viewDidLoad()
        link.keyboardType = .URL; link.accessibilityIdentifier = "setup.link"
        let next = PorchStyle.button("Continue", symbol: "arrow.right")
        next.addAction(UIAction { [weak self] _ in self?.save() }, for: .touchUpInside)
        form.addArrangedSubview(section("Your setup link", detail: "Paste the link from your Porch invitation.",
                                        views: [field(link, title: "Setup link", placeholder: "Paste your setup link"), next]))
        addWayOut()
    }
    private func save() {
        let text = link.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            guard let url = URL(string: text) else { throw FamilyInvitation.InvitationError.invalid }
            _ = try BedsideInvitation(url: url, defaultOrigin: PorchDevice.defaultOrigin)
            try PorchDevice.saveActivation(url)
            view.endEditing(true)
            navigationController?.pushViewController(SetupNameViewController(setup), animated: true)
        } catch { showPorchError(FamilyServiceError(message: "That isn't a Porch setup link. Copy the whole link from your invitation and paste it here.", status: 400), on: self) }
    }
}

final class SetupNameViewController: BedsideSetupStep {
    private let name = UITextField()
    override func viewDidLoad() {
        super.viewDidLoad()
        name.text = setup.name; name.accessibilityIdentifier = "setup.name"
        let next = PorchStyle.button("Continue", symbol: "arrow.right")
        next.addAction(UIAction { [weak self] _ in self?.save() }, for: .touchUpInside)
        form.addArrangedSubview(section("Who is this Porch for?",
                                        views: [field(name, title: "Their name", placeholder: "For example, Mom"), next]))
        // `field` resets capitalization; a name is capitalized word by word.
        name.autocapitalizationType = .words
        if navigationController?.viewControllers.first === self { addWayOut() }
    }
    private func save() {
        let chosen = name.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !chosen.isEmpty else { showPorchError(FamilyServiceError(message: "Enter who this Porch is for, such as Mom.", status: 400), on: self); return }
        setup.name = chosen; view.endEditing(true)
        navigationController?.pushViewController(SetupPINViewController(setup), animated: true)
    }
}

/// The caregiver PIN, chosen twice. Continuing sets the iPad up with the server.
final class SetupPINViewController: BedsideSetupStep {
    private let pin = UITextField(), confirmation = UITextField()
    private let proceed = PorchStyle.button("Continue", symbol: "lock.fill")
    override func viewDidLoad() {
        super.viewDidLoad()
        for field in [pin, confirmation] { field.isSecureTextEntry = true; field.keyboardType = .numberPad }
        pin.accessibilityIdentifier = "caregiver.pin"; confirmation.accessibilityIdentifier = "caregiver.confirm"
        proceed.addAction(UIAction { [weak self] _ in self?.enroll() }, for: .touchUpInside)
        form.addArrangedSubview(section("Choose a caregiver PIN",
                                        views: [field(pin, title: "Caregiver PIN", placeholder: "Six digits"), field(confirmation, title: "Enter it again", placeholder: "The same six digits"), proceed]))
    }
    private func enroll() {
        guard task == nil else { return }
        let value = pin.text ?? ""
        guard value.range(of: "^[0-9]{6}$", options: .regularExpression) != nil, value == confirmation.text else {
            showPorchError(FamilyServiceError(message: "Enter the same six digits in both PIN fields.", status: 400), on: self); return
        }
        proceed.isEnabled = false; view.endEditing(true)
        // Going back cancels this task. Once a replacement has stopped the old Porch ringing, that cancel has to put
        // its calls back, so its back button is off until this attempt finishes.
        let replacing = setup.replacing
        let allowSwipeBack = navigationController?.interactivePopGestureRecognizer?.isEnabled ?? true
        if replacing {
            navigationItem.hidesBackButton = true
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil; self.proceed.isEnabled = true
                if replacing {
                    self.navigationItem.hidesBackButton = false
                    self.navigationController?.interactivePopGestureRecognizer?.isEnabled = allowSwipeBack
                }
            }
            do {
                let invitation = try PorchDevice.bedsideActivation.map { try BedsideInvitation(url: $0, defaultOrigin: PorchDevice.defaultOrigin) }
                let origin = invitation?.origin ?? URL(string: NativeCallSettings.savedURL) ?? PorchDevice.defaultOrigin
                // The same identity on a retry, so a lost response doesn't use the link up.
                let pending = try PorchDevice.pending(role: .bedside, origin: origin, invitation: invitation?.code ?? "")
                var registration = PorchDevice.registration(pending)
                registration["name"] = self.setup.name; registration["pin"] = value
                if let invitation { registration["activation"] = invitation.code }
                // Only the operator's setup code: an iPad being replaced keeps its old household's PIN there.
                let operatorCode = NativeCallSettings.caregiverCode.count < 16 ? "" : NativeCallSettings.caregiverCode
                // Replacing: the old household stops ringing this iPad first, so its calls can't reach the new one.
                let previous = self.setup.replacing ? PorchDevice.credential(for: .bedside) : nil
                var stoppedRinging = false
                do {
                    if let previous { stoppedRinging = true; try await PorchDevice.leaveBedside(previous) }
                    let response = try await FamilyService(origin: origin).send("enrollBedside", registration, pin: operatorCode.isEmpty ? nil : operatorCode)
                    guard let token = response.credential else { throw FamilyInvitation.InvitationError.invalid }
                    // Store the new pairing and its PIN before forgetting the old keypad. A check-in reports whatever
                    // keypad is on the iPad, and the PIN write needs the device unlocked, so a lock during enrollment
                    // can store one and not the other. The old keypad stays until both are stored.
                    let enrolled = FamilyCredential(origin: origin, credential: token, role: .bedside)
                    try PorchDevice.save(enrolled)
                    do { try NativeCallSettings.writeSecret(Data(value.utf8), account: "porch.contact-setup-code") }
                    catch {
                        if let previous { try? PorchDevice.save(previous) }
                        throw error
                    }
                    if previous != nil { PorchDevice.forgetBedsideHousehold(); self.setup.replacing = false }
                    FamilyCoordinator.shared.start(); FamilyCoordinator.shared.update(response)
                    try PorchDevice.saveActivation(nil)
                    self.navigationController?.setViewControllers([SetupNumberViewController(self.setup)], animated: true)
                } catch {
                    // The attempt didn't finish, and this iPad is still the old bedside. Its calls were cleared
                    // first; register them again before Continue can try once more.
                    if stoppedRinging, let previous, PorchDevice.credential(for: .bedside)?.credential == previous.credential {
                        SystemIncomingCalls.shared.registerDevice()
                        if !Task.isCancelled { await SystemIncomingCalls.shared.waitForRegistration() }
                    }
                    throw error
                }
            } catch { if !Task.isCancelled { showPorchError(error, on: self) } }
        }
    }
}

/// The household's own phone number. Porch fills in an area code near the iPad, so it's one tap; another can be chosen
/// first. Setup can't go on without trying for a number, but once Porch has tried, Continue works whether the number
/// is ready or not: Porch keeps trying by itself. Caregiver mode opens this screen too, for a number that isn't set up.
final class SetupNumberViewController: BedsideSetupStep {
    /// Where Continue goes. Setup goes on to the microphone and camera.
    var onContinue: (() -> Void)?
    private let areaCode = UITextField()
    private let nearby = UIStackView()
    private let get = PorchStyle.button("Get number", symbol: "phone.fill")
    /// What the number step says, if anything. It takes no room when it has nothing to say.
    private let message = CollapsingLabel.make(size: 17)
    private let number = PorchStyle.label("", size: 34, color: PorchStyle.ink, weight: .bold)
    private let proceed = PorchStyle.button("Continue", symbol: "arrow.right")
    private var choosing: [UIView] = []
    /// The area code and the ones near it, shown when there's no suggestion or the caregiver wants another.
    private var areaChoice: [UIView] = []
    private var different: UIButton?
    override func viewDidLoad() {
        super.viewDidLoad()
        if onContinue != nil { title = "Porch number" }
        areaCode.keyboardType = .numberPad; areaCode.accessibilityIdentifier = "setup.areaCode"
        nearby.spacing = 10; nearby.distribution = .fillEqually
        number.textAlignment = .center; number.isHidden = true; number.accessibilityIdentifier = "setup.number"
        message.accessibilityIdentifier = "setup.numberMessage"
        proceed.isHidden = true
        get.addAction(UIAction { [weak self] _ in self?.assign() }, for: .touchUpInside)
        proceed.addAction(UIAction { [weak self] _ in self?.goOn() }, for: .touchUpInside)
        let areaField = field(areaCode, title: "Area code", placeholder: "For example, 510")
        let different = textLink("Use a different area code") { [weak self] in self?.chooseAreaCode() }
        different.isHidden = true; self.different = different
        areaChoice = [areaField, nearby]
        choosing = [areaField, nearby, get, different]
        form.addArrangedSubview(section("\(lovedOne)'s Porch number",
                                        views: [number, message, areaField, nearby, get, different, proceed]))
        if let existing = FamilyCoordinator.shared.state?.porchNumber { show(existing) } else { loadOptions() }
    }
    private func goOn() {
        if let onContinue { onContinue(); return }
        navigationController?.setViewControllers([setup.screen(from: .permissions)], animated: true)
    }
    private func loadOptions() {
        guard let credential = PorchDevice.credential(for: .bedside) else { return }
        let setUp = FamilyCoordinator.shared.state?.phoneSetup
        areaCode.text = setUp?.areaCode
        message.text = setUp?.needsChoice == true ? setUp?.error : "Finding an area code near this iPad…"
        if setUp?.needsChoice != true { showAreaChoice(false) }
        get.isEnabled = false
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.get.isEnabled = true }
            // Without a suggestion, such as outside the US, the caregiver types one.
            let options = try? await FamilyService(credential).send("phoneNumberOptions", pin: NativeCallSettings.caregiverCode)
            if Task.isCancelled { return }
            // The reply carries the household, including a number a background try already bought.
            if let options { FamilyCoordinator.shared.update(options) }
            if let existing = options?.porchNumber { self.show(existing); return }
            if self.areaCode.text?.isEmpty != false { self.areaCode.text = options?.areaCode }
            for code in options?.nearby ?? [] {
                let choice = PorchStyle.button(code, filled: false)
                choice.accessibilityLabel = "Area code \(code)"
                choice.addAction(UIAction { [weak self] _ in self?.areaCode.text = code }, for: .touchUpInside)
                self.nearby.addArrangedSubview(choice)
            }
            guard setUp?.needsChoice != true else { return }
            // With an area code near the iPad, getting the number is one tap.
            if let suggested = self.areaCode.text, PorchNumber.isAreaCode(suggested) {
                self.showAreaChoice(false); self.different?.isHidden = false
                self.message.text = "Porch will get a number in area code \(suggested)."
            } else {
                self.showAreaChoice(true)
                self.message.text = nil
            }
        }
    }
    /// The area code field, and the keyboard choices that go with it, only when there's an area code to type.
    private func showAreaChoice(_ shown: Bool) {
        areaChoice.forEach { $0.isHidden = !shown }; setKeyboardControlVisible(shown)
    }
    private func chooseAreaCode() {
        showAreaChoice(true); different?.isHidden = true
        message.text = nil
        areaCode.becomeFirstResponder()
    }
    private func assign() {
        let code = areaCode.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard PorchNumber.isAreaCode(code) else {
            showPorchError(FamilyServiceError(message: "Enter a three-digit US area code, such as 510.", status: 400), on: self); return
        }
        guard task == nil, let credential = PorchDevice.credential(for: .bedside) else { return }
        let offeredAnother = different?.isHidden == false
        get.isEnabled = false; areaCode.isEnabled = false; different?.isHidden = true; view.endEditing(true)
        message.text = "Getting a number in area code \(code)…"
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil; self.get.isEnabled = true; self.areaCode.isEnabled = true
                // Without a number yet, another area code can still be chosen the way it could before.
                if self.number.isHidden, self.areaChoice.first?.isHidden == true { self.different?.isHidden = !offeredAnother }
            }
            do {
                // The first number Porch buys also sets up its phone line, which takes longer than most requests.
                let response = try await FamilyService(credential).send("assignPhoneNumber", ["areaCode": code], pin: NativeCallSettings.caregiverCode, timeout: 45)
                FamilyCoordinator.shared.update(response)
                if let assigned = response.porchNumber { self.show(assigned) }
                else { self.waiting("Still getting \(self.lovedOne)'s number. Caregiver mode shows it when it's ready.") }
            } catch {
                if Task.isCancelled { return }
                let failure = error as? FamilyServiceError
                // Another area code is up to the caregiver. Porch's own limit clears by itself, and it keeps trying.
                if failure?.code == "noNumbers" || failure?.status == 400 {
                    self.showAreaChoice(true)
                    self.message.text = error.localizedDescription
                    UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
                }
                else if failure?.code == "numberLimit" { self.waiting("\(error.localizedDescription) Porch keeps trying.") }
                else { self.waiting("\(error.localizedDescription) You can get it later in caregiver mode.") }
            }
        }
    }
    private func waiting(_ text: String) {
        message.text = text; proceed.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
    }
    private func show(_ assigned: String) {
        choosing.forEach { $0.isHidden = true }; setKeyboardControlVisible(false)
        number.text = PorchNumber.display(assigned); number.isHidden = false
        message.text = nil
        proceed.isHidden = false
        UIAccessibility.post(notification: .screenChanged, argument: number)
    }
}

/// The microphone and camera, asked for now so the first call doesn't stop at a prompt. One Continue asks for both,
/// and setup skips this screen when they're already allowed.
final class SetupPermissionsViewController: BedsideSetupStep {
    static var needed: Bool { [AVMediaType.audio, .video].contains { AVCaptureDevice.authorizationStatus(for: $0) != .authorized } }
    override func viewDidLoad() {
        super.viewDidLoad(); hideKeyboardControl()
        let proceed = PorchStyle.button("Continue", symbol: "arrow.right")
        proceed.accessibilityIdentifier = "setup.allow"
        proceed.addAction(UIAction { [weak self] _ in self?.allow() }, for: .touchUpInside)
        form.addArrangedSubview(section("Microphone and camera", detail: "Porch needs these for calls.", views: [proceed]))
    }
    private func allow() {
        guard task == nil else { return }
        task = Task { [weak self] in
            for kind in [AVMediaType.audio, .video] where AVCaptureDevice.authorizationStatus(for: kind) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: kind)
            }
            guard let self else { return }
            self.task = nil
            // Ringing waited for the microphone; it registers now.
            BedsideSetup.releaseMicrophonePrompt()
            // Turned off before, or just now: Porch goes on, and Settings can still turn them on.
            self.navigationController?.setViewControllers([self.setup.screen(from: .phone)], animated: true)
        }
    }
}

/// How they'll call: the desk phone through the Porch phone adapter, which every family gets, with a screen to connect
/// and check it, or just the touchscreen, which needs nothing. The adapter needs no driver, so every build and every iPad
/// offers the desk phone.
final class SetupCallingViewController: BedsideSetupStep {
    override func viewDidLoad() {
        super.viewDidLoad(); hideKeyboardControl()
        let options = [
            option("Corded phone", detail: SetupPhoneViewController.parts,
                   symbol: "phone.fill", identifier: "setup.cordedPhone") { SetupPhoneViewController($0) },
        ]
        let touchscreen = textLink("Just the touchscreen") { [weak self] in
            guard let self else { return }
            self.navigationController?.setViewControllers([self.setup.screen(from: .yourPhone)], animated: true)
        }
        touchscreen.contentHorizontalAlignment = .center
        touchscreen.accessibilityIdentifier = "setup.touchscreen"
        form.addArrangedSubview(section("How will \(lovedOne) call?",
                                        views: options + [touchscreen]))
    }
    /// A choice, which opens the screen for connecting it. That screen can come back here to choose another.
    private func option(_ title: String, detail: String, symbol: String, identifier: String, screen: @escaping (BedsideSetup) -> UIViewController) -> UIButton {
        let button = PorchStyle.button(title, symbol: symbol)
        button.configuration?.subtitle = detail
        button.configuration?.titlePadding = 4
        // The card is at most 760 points wide, so a one-line subtitle could cut off the end.
        button.configuration?.titleLineBreakMode = .byWordWrapping
        button.configuration?.subtitleLineBreakMode = .byWordWrapping
        button.configuration?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(15); return attributes
        }
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(screen(self.setup), animated: true)
        }, for: .touchUpInside)
        return button
    }
}

/// Connect the phone: the desk phone by the bed, through a Cell2Jack, becomes Porch's keypad. Every family gets the Porch
/// phone adapter (phone-adapter/README.md), which types the phone's keys into any iPad as a USB keypad does, and F24 when
/// the receiver goes back, so the screen says only that, and the guide at helloporch.store/pilot/ios has the steps, the
/// parts and the tips. Builds with the driver also try a Cell2Jack plugged straight in, which needs an M chip, on any
/// iPad not known to lack one (`IPadChip`). There the screen listens for both and goes on with whichever answers; a
/// Cell2Jack on the driver turns the phone keypad on. On an iPad known to have an M chip, a footnote says the adapter
/// isn't needed. Then the caregiver presses a key and hangs up, and neither acts.
/// Do this later, or going back to choose another way, leaves the phone keypad off; This iPad in caregiver mode opens
/// this screen again. The phone checked through the adapter, with no Cell2Jack on the driver, turns the phone keypad
/// off: an iPad that moves from a Cell2Jack plugged straight in to the adapter stops looking for it.
final class SetupPhoneViewController: BedsideSetupStep, Cell2JackDigitReceiving {
    /// Builds without the Cell2Jack driver, iPhones, and iPads without an M chip listen only for the adapter.
    static var offered: Bool { Cell2JackKeypad.supportsDriverPlatform }
    /// The desk phone, for setup's choice and This iPad. Every family has the adapter, whatever the iPad.
    static let parts = "Plugged in with the Porch phone adapter."
    /// Where Continue and Do this later go. Setup goes on to adding the caregiver's phone.
    /// This iPad sets this after `PorchStyle.navigation` has already loaded the view, so the title
    /// can't wait for `viewDidLoad`.
    var onContinue: (() -> Void)? { didSet { if onContinue != nil { title = "Connect the phone" } } }
    private enum Progress: Equatable { case waiting, connected, heard(String), done(String) }
    /// Which path sent the key. The hang-up has to come back the same way: the adapter's
    /// hang-up key is a keyboard key, and the driver's hang-up is not.
    private enum HeardFrom { case keyboard, driver }
    private var progress = Progress.waiting
    private var heardFrom: HeardFrom?
    /// The connected wording named the driver. A retry that doesn't change this must not render:
    /// rendering announces the status again.
    private var showedDriverReady = false
    private var checked: Bool { if case .done = progress { return true } else { return false } }
    private let keypad: Cell2JackKeypad
    /// Also tries a Cell2Jack plugged straight into the iPad, on the driver.
    private let tryDriver: Bool
    /// The iPad is known to have an M chip (`IPadChip.hasMChip`). With the driver, it doesn't need the adapter.
    private let mChip: Bool
    /// The adapter is a keyboard to the iPad. Any keyboard counts, such as a keyboard case, so a key is the check.
    private let keyboardConnected: () -> Bool
    private var keys = CallTrigger()
    /// This screen turned the keypad on. Do this later undoes that; one that was already on stays on.
    private var enabledHere = false
    /// The phone was checked through the adapter, and the driver's first try was still open. That try may yet answer,
    /// so the keypad is left alone until it does or that try ends. Cleared once the driver is ready or the try ends:
    /// a later disconnect, such as the ten-second unplug, must not turn a working keypad off.
    private var checkedThroughAdapter = false
    /// Leaving, so a stop callback doesn't put the waiting text back up.
    private var leaving = false
    private let status = PorchStyle.label("", size: 20, color: PorchStyle.ink, weight: .semibold)
    /// The step the check is on, as a picture over the status: plug in, press a key, put the receiver back, done.
    private let badge = UIView()
    private let statusIcon = UIImageView()
    private let proceed = PorchStyle.button("Continue", symbol: "arrow.right")
    private var later: UIButton?
    init(_ setup: BedsideSetup, keypad: Cell2JackKeypad = .shared, tryDriver: Bool = SetupPhoneViewController.offered,
         mChip: Bool = IPadChip.hasMChip(model: PorchDevice.model),
         keyboardConnected: @escaping () -> Bool = { GCKeyboard.coalesced != nil }) {
        self.keypad = keypad; self.tryDriver = tryDriver; self.mChip = mChip; self.keyboardConnected = keyboardConnected
        super.init(setup)
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:keypad:tryDriver:mChip:keyboardConnected:)") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidLoad() {
        super.viewDidLoad(); hideKeyboardControl()
        if onContinue != nil { title = "Connect the phone" }
        proceed.accessibilityIdentifier = "setup.phoneDone"
        proceed.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        status.textAlignment = .center; status.accessibilityIdentifier = "setup.phoneStatus"
        // The steps, the parts and the tips are on the website, which can change without an update.
        let guide = textLink("Step-by-step instructions") { [weak self] in if let self { showIPadGuide(on: self) } }
        guide.configuration?.image = UIImage(systemName: "arrow.up.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        guide.configuration?.imagePlacement = .trailing; guide.configuration?.imagePadding = 6
        guide.contentHorizontalAlignment = .center
        guide.accessibilityHint = "Opens the iPad setup guide on helloporch.store."
        guide.accessibilityIdentifier = "setup.phoneGuide"
        let later = textLink("Do this later") { [weak self] in self?.finish() }
        later.contentHorizontalAlignment = .center
        later.accessibilityIdentifier = "setup.phoneLater"; self.later = later
        var views: [UIView] = [guide, progressPanel(), proceed, later]
        if tryDriver && mChip { views.append(mChipNote()) }
        let card = section("Connect the phone", detail: "Plug the desk phone in with the Porch phone adapter.",
                           views: views)
        if let stack = card.subviews.first as? UIStackView, let detail = stack.arrangedSubviews.dropFirst().first {
            // The link reads as part of the explanation above it, and the panel stands apart from both.
            stack.setCustomSpacing(4, after: detail); stack.setCustomSpacing(24, after: guide)
        }
        form.addArrangedSubview(card)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: .GCKeyboardDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: .GCKeyboardDidDisconnect, object: nil)
        if tryDriver { NotificationCenter.default.addObserver(self, selector: #selector(keypadChanged), name: .cell2JackKeypadChanged, object: nil) }
        progress = connected ? .connected : .waiting
        render(announce: false)
    }
    /// The status, under a round badge whose icon shows the step it's on. It's the part of the screen that changes, so
    /// it sits apart on the page colour.
    private func progressPanel() -> UIView {
        statusIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        statusIcon.isAccessibilityElement = false
        badge.layer.cornerRadius = 36
        let row = UIView()
        for view in [badge, statusIcon] { view.translatesAutoresizingMaskIntoConstraints = false }
        row.addSubview(badge); badge.addSubview(statusIcon)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 72), badge.heightAnchor.constraint(equalToConstant: 72),
            badge.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            badge.topAnchor.constraint(equalTo: row.topAnchor), badge.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            statusIcon.centerXAnchor.constraint(equalTo: badge.centerXAnchor), statusIcon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        let panel = UIStackView(arrangedSubviews: [row, status])
        panel.axis = .vertical; panel.spacing = 16
        panel.isLayoutMarginsRelativeArrangement = true
        panel.directionalLayoutMargins = .init(top: 28, leading: 24, bottom: 28, trailing: 24)
        panel.backgroundColor = PorchStyle.page; panel.layer.cornerRadius = 16
        return panel
    }
    /// A footnote under a rule, for an iPad known to have an M chip: the Cell2Jack can plug straight in, with the USB
    /// driver turned on in Settings. Porch can't tell that the driver is off, since a Cell2Jack plugged in then looks
    /// like no Cell2Jack at all, so the note says when Open Settings is needed, and the replug that loads the driver.
    private func mChipNote() -> UIView {
        let rule = UIView()
        rule.backgroundColor = PorchStyle.border
        rule.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)).isActive = true
        let note = PorchStyle.label("This iPad doesn't need the adapter. Turn on the Cell2Jack's driver in Settings, then unplug the Cell2Jack for ten seconds and plug it back in.", size: 15)
        note.textAlignment = .center
        note.accessibilityIdentifier = "setup.phoneMChip"
        let settings = textLink("Open Settings", size: 15) {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
        settings.contentHorizontalAlignment = .center
        settings.accessibilityIdentifier = "setup.phoneSettings"
        let stack = UIStackView(arrangedSubviews: [rule, note, settings])
        stack.axis = .vertical; stack.spacing = 2
        stack.setCustomSpacing(18, after: rule)
        return stack
    }
    /// The Cell2Jack is answering on the driver, as opposed to a keyboard the iPad can see.
    private var driverReady: Bool { tryDriver && keypad.isReady }
    /// The phone can be heard: through the adapter, or on the driver.
    private var connected: Bool { keyboardConnected() || driverReady }
    /// The path that sent the key is still up, so its hang-up can still arrive.
    private var heardPathIsUp: Bool {
        switch heardFrom {
        case .keyboard: return keyboardConnected()
        case .driver: return driverReady
        case nil: return false
        }
    }
    @objc private func keyboardChanged() {
        // Leaving, so a disconnect while the screen is going away doesn't put the waiting text back up.
        // Appearing checks the keyboard again.
        if leaving { return }
        connectionChanged()
    }
    @objc private func keypadChanged() {
        if leaving { return }
        // Turned on for them: from now on the phone is Mom's keypad, here and on the clock.
        if keypad.isReady, !keypad.enabled { keypad.setEnabled(true); enabledHere = true }
        // The first try ended after the adapter checked the phone. A driver that already answered is left alone.
        if checkedThroughAdapter { checkedWithoutDriver() }
        connectionChanged()
    }
    /// The driver retries every few seconds while nothing answers on it, so only a change of state renders: rendering
    /// announces the status again. A keyboard that is still attached does not keep a driver key's hang-up, and the
    /// driver staying up does not keep an adapter key's hang-up.
    private func connectionChanged(announce: Bool = true) {
        switch progress {
        case .done: break
        case .waiting: if connected { progress = .connected; render(announce: announce) }
        case .connected:
            if !connected {
                progress = .waiting
                render(announce: announce)
            } else if showedDriverReady != driverReady {
                // A keyboard was already enough to leave waiting. The driver answering, or dropping while that
                // keyboard remains, still changes what we tell them.
                render(announce: announce)
            }
        case .heard:
            // Unplugged, or the driver turned off, before the check finished: a hang-up meanwhile went unheard.
            if !heardPathIsUp {
                heardFrom = nil
                progress = connected ? .connected : .waiting
                render(announce: announce)
            }
        }
    }
    // Keys come here while the screen is open, so pressing one never calls anyone.
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); keys.resetKeys(); becomeFirstResponder()
        // Coming back, such as after a cover, tries again. Opening Settings does not come through here.
        leaving = false
        if tryDriver { keypad.beginTrial() }
        // A drop while this screen was leaving never got to change the check: the stop notice is ignored then.
        // The phone has to be heard again, including a key that was already heard.
        connectionChanged(announce: false)
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let digit = key.keypadDigit else { unhandled.insert(press); continue }
            if keys.keyDown(Int(key.keyCode.rawValue)) { receiveKey(digit) }
        }
        // The hang-up key (F24) isn't a keypad key, so it goes on up the responder chain. PorchWindow.sendEvent has
        // already sent it here as the key went down, through Cell2JackDigitRouter to receiveCell2JackHangUp.
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { keys.keyUp(Int(key.keyCode.rawValue)) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        keys.resetKeys(); super.pressesCancelled(presses, with: event)
    }
    /// Shows the key the phone sent, without acting on it.
    func receiveKey(_ digit: Int, fromDriver: Bool = false) {
        guard !checked else { return }
        let symbol = CallSlots.symbol(for: digit)
        // Without hanging up on the receiver, there's no hang-up to check.
        if keypad.receiverHangUp {
            progress = .heard(symbol)
            heardFrom = fromDriver ? .driver : .keyboard
        } else {
            heardFrom = nil
            progress = .done("Porch heard \(symbol). The phone is ready.")
            if !fromDriver { checkedThroughAdapter = true; checkedWithoutDriver() }
        }
        render()
    }
    /// A Cell2Jack on the driver checks the phone here as well.
    func receiveCell2JackDigit(_ digit: Int) -> String {
        if checked { return "setup: phone already checked" }
        receiveKey(digit, fromDriver: true)
        return "setup: heard \(CallSlots.symbol(for: digit))"
    }
    func receiveCell2JackHangUp() -> String {
        guard case .heard = progress else { return "setup: hang-up before a key" }
        progress = .done("Porch heard you hang up. The phone is ready.")
        if heardFrom == .keyboard { checkedThroughAdapter = true; checkedWithoutDriver() }
        render()
        return "setup: heard hang-up"
    }
    /// The phone was checked through the adapter while no Cell2Jack answers on the driver, so the driver isn't needed.
    /// A phone keypad left on, such as from a Cell2Jack that used to be plugged straight in, would keep Porch looking
    /// for one every 15 seconds and fill the call log with the tries, so it goes off. A keyboard case on an iPad whose
    /// Cell2Jack is on the driver leaves it on, and a Cell2Jack that answers while this screen is open turns it back on.
    /// A connection still making its first try, as for a few seconds after the screen opens, is the same: the keypad
    /// goes off only if that try finds nothing. Once the driver has answered, a later disconnect is not another check.
    private func checkedWithoutDriver() {
        // Ready, or nothing was on: the decision is made. A later drop must not be treated as the adapter replacing it.
        guard keypad.enabled, !keypad.isReady else { checkedThroughAdapter = false; return }
        // Still the first try. `keypadChanged` calls this again when that try finishes. One that Porch stopped itself,
        // such as for Open Settings or switching apps, found nothing out: the next try, back in Porch, decides.
        if keypad.connecting || !keypad.lastTryFoundNothing { return }
        checkedThroughAdapter = false
        keypad.record(["kind": "phoneKeypadOff", "reason": "phone checked through the adapter"])
        keypad.setEnabled(false); enabledHere = false
    }
    private func render(announce: Bool = true) {
        switch progress {
        case .waiting:
            showedDriverReady = false
            status.text = "Waiting for the phone…"
        // A keyboard may be something else, such as a keyboard case, so only the driver says the phone is connected.
        case .connected:
            showedDriverReady = driverReady
            status.text = driverReady ? "The phone is connected. Lift the receiver and press a key." : "Lift the receiver and press a key."
        case .heard(let symbol): status.text = "Porch heard \(symbol). Now put the receiver back."
        case .done(let text): status.text = text
        }
        let symbol: String
        switch progress {
        case .waiting: symbol = "phone.connection"
        case .connected: symbol = "circle.grid.3x3.fill"
        case .heard: symbol = "phone.down.fill"
        case .done: symbol = "checkmark"
        }
        statusIcon.image = UIImage(systemName: symbol)
        // Done fills the badge in. Waiting is grey until the phone is there.
        badge.backgroundColor = checked ? PorchStyle.accent : PorchStyle.surface
        statusIcon.tintColor = checked ? .white : progress == .waiting ? PorchStyle.secondary : PorchStyle.accent
        proceed.isHidden = !checked; later?.isHidden = checked
        if announce { UIAccessibility.post(notification: .announcement, argument: status.text) }
    }
    private func finish() {
        // Do this later is the way out before the check finishes, and it leaves the keypad off.
        leaveTrial(turnOff: enabledHere && !checked)
        if let onContinue { onContinue(); return }
        navigationController?.setViewControllers([setup.screen(from: .yourPhone)], animated: true)
    }
    /// The screen is going away. A trial that is still running would keep the desk phone live with the keypad off.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        leaveTrial(turnOff: false)
    }
    /// Going back to choose another way is like Do this later. Only now has it happened: a back swipe can still be
    /// cancelled until it's over, and the keypad stays on for when the screen comes back.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent, enabledHere, !checked { keypad.setEnabled(false); enabledHere = false }
    }
    /// Stops the trial. `turnOff` undoes an enable this screen just did, which Do this later asks for.
    private func leaveTrial(turnOff: Bool) {
        leaving = true
        if turnOff { keypad.setEnabled(false); enabledHere = false }
        if keypad.trying { keypad.endTrial() }
    }
}

/// Add your phone: a QR code of a one-use invitation with caregiver mode, for the caregiver's iPhone camera, or the same
/// invitation sent another way. It has their name, so Porch can say who's calling, and drop-in approved as other
/// invitations do once the iPad can use its microphone and camera.
final class SetupYourPhoneViewController: BedsideSetupStep {
    /// A caregiver's phone has already joined, such as on a setup that was resumed, so there's no need.
    static var needed: Bool { !(FamilyCoordinator.shared.state?.people.contains { $0.role == .family && $0.caregiver == true } ?? false) }
    private let name = UITextField()
    private var nameField: UIView?
    private let show = PorchStyle.button("Show QR code", symbol: "qrcode")
    private let code = UIImageView()
    private let codeFrame = UIView()
    private let caption = PorchStyle.label("Scan it with your phone's camera.", size: 17)
    private var send: UIButton?
    private let status = PorchStyle.label("", size: 20, color: PorchStyle.ink, weight: .semibold)
    /// Going on without a phone is quieter than showing the code, until a phone has joined.
    private let skip = PorchStyle.button("Continue", symbol: "arrow.right", filled: false)
    private let proceed = PorchStyle.button("Continue", symbol: "arrow.right")
    /// The invitation the code is for, and when it stops working.
    private var invitation: (id: String, link: URL, expiresAt: TimeInterval)?
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidLoad() {
        super.viewDidLoad()
        name.accessibilityIdentifier = "setup.yourName"
        show.accessibilityIdentifier = "setup.showCode"
        show.addAction(UIAction { [weak self] _ in self?.createInvitation() }, for: .touchUpInside)
        skip.accessibilityIdentifier = "setup.yourPhoneLater"; proceed.accessibilityIdentifier = "setup.yourPhoneDone"
        for button in [skip, proceed] { button.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside) }
        proceed.isHidden = true
        // Black on white, whatever the appearance, so any camera reads it.
        codeFrame.backgroundColor = .white; codeFrame.layer.cornerRadius = 16
        code.layer.magnificationFilter = .nearest; code.contentMode = .scaleAspectFit
        code.isAccessibilityElement = true; code.accessibilityLabel = "QR code for your phone's invitation"
        code.accessibilityIdentifier = "setup.code"
        codeFrame.addSubview(code); code.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            code.topAnchor.constraint(equalTo: codeFrame.topAnchor, constant: 16), code.bottomAnchor.constraint(equalTo: codeFrame.bottomAnchor, constant: -16),
            code.centerXAnchor.constraint(equalTo: codeFrame.centerXAnchor), code.widthAnchor.constraint(equalToConstant: 240), code.heightAnchor.constraint(equalTo: code.widthAnchor),
        ])
        caption.textAlignment = .center; status.textAlignment = .center
        status.accessibilityIdentifier = "setup.yourPhoneStatus"
        let send = textLink("Send the invitation instead") { [weak self] in self?.share() }
        self.send = send
        let nameField = field(name, title: "Your name", placeholder: "For example, Ethan"); self.nameField = nameField
        // `field` resets these; a name is capitalized word by word, and Return shows the code.
        name.autocapitalizationType = .words; name.returnKeyType = .done
        for view in [codeFrame, caption, send, status] { view.isHidden = true }
        form.addArrangedSubview(section("Add your phone",
                                        views: [nameField, show, codeFrame, caption, send, status, skip, proceed]))
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(returnedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    override func textFieldShouldReturn(_ textField: UITextField) -> Bool { createInvitation(); return false }
    private func createInvitation() {
        let chosen = name.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !chosen.isEmpty else { showPorchError(FamilyServiceError(message: "Enter your name, so \(lovedOne)'s Porch can say who's calling.", status: 400), on: self); return }
        guard task == nil, let credential = PorchDevice.credential(for: .bedside) else { return }
        show.isEnabled = false; view.endEditing(true)
        // Drop-in answers on this iPad, so it's approved only once the iPad can use what it needs.
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let camera = microphone && AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        // Replacing an expired code. A phone that joins with it, including via this reply, already counted.
        let replacing = invitation != nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.show.isEnabled = true }
            do {
                let response = try await FamilyService(credential).send("createInvite", ["name": chosen, "permissions": ["audio": microphone, "video": camera], "caregiver": true], pin: NativeCallSettings.caregiverCode)
                guard let code = response.code, let id = response.invitationID else { throw FamilyInvitation.InvitationError.invalid }
                FamilyCoordinator.shared.update(response)
                if replacing, self.invitation == nil { return }
                self.showCode(id: id, link: FamilyInvitation.url(origin: credential.origin, code: code, defaultOrigin: PorchDevice.defaultOrigin), expiresAt: response.expiresAt ?? 0)
            } catch {
                if Task.isCancelled { return }
                if replacing, self.invitation == nil { return }
                if let shown = self.invitation, shown.expiresAt <= Date().timeIntervalSince1970 { self.codeExpired() }
                showPorchError(error, on: self)
            }
        }
    }
    private func showCode(id: String, link: URL, expiresAt: TimeInterval) {
        invitation = (id, link, expiresAt)
        code.image = Self.qrCode(link.absoluteString)
        nameField?.isHidden = true; show.isHidden = true; setKeyboardControlVisible(false)
        for view in [codeFrame, caption, send, status] { view?.isHidden = false }
        status.text = "Waiting for your phone…"
        UIAccessibility.post(notification: .screenChanged, argument: code)
    }
    /// Their phone joined with the invitation.
    @objc private func familyChanged() {
        guard let invitation, FamilyCoordinator.shared.state?.people.contains(where: { $0.invitationID == invitation.id }) == true else { return }
        self.invitation = nil
        for view in [codeFrame, caption, send, skip] { view?.isHidden = true }
        proceed.isHidden = false
        status.text = "Your phone joined \(lovedOne)'s Porch."
        UIAccessibility.post(notification: .announcement, argument: status.text)
    }
    /// An invitation lasts a day. One that ran out while Porch was away is replaced, for the same name. It stays until
    /// the new one is ready, so a phone that joins meanwhile still counts.
    @objc private func returnedToForeground() {
        guard let invitation, invitation.expiresAt <= Date().timeIntervalSince1970 else { return }
        createInvitation()
    }
    /// The code ran out and a new one couldn't be made, such as while the iPad is offline: Show QR code tries again.
    private func codeExpired() {
        invitation = nil; code.image = nil
        for view in [codeFrame, caption, send] { view?.isHidden = true }
        show.isHidden = false
        status.text = "That code ran out. Tap Show QR code for a new one."
        UIAccessibility.post(notification: .announcement, argument: status.text)
    }
    private func share() {
        // An expired code is being replaced; its link would only say it ran out.
        guard let invitation, invitation.expiresAt > Date().timeIntervalSince1970 else { return }
        let share = UIActivityViewController(activityItems: FamilyInviteViewController.shareItems(invitation.link), applicationActivities: nil)
        share.popoverPresentationController?.sourceView = send
        share.popoverPresentationController?.sourceRect = send?.bounds ?? .zero
        present(share, animated: true)
    }
    private func finish() {
        task?.cancel(); view.endEditing(true)
        navigationController?.setViewControllers([setup.screen(from: .done)], animated: true)
    }
    /// A QR code of `text`, drawn a few pixels to a module and scaled up without smoothing.
    static func qrCode(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

final class SetupDoneViewController: BedsideSetupStep {
    private let numberViews = UIStackView()
    /// The number last drawn, so a poll that doesn't change it doesn't rebuild the labels.
    private var shownNumber: String?
    private var didRenderNumber = false
    override func viewDidLoad() {
        super.viewDidLoad(); hideKeyboardControl()
        navigationItem.hidesBackButton = true
        numberViews.axis = .vertical; numberViews.spacing = 6
        let keypad = PorchStyle.button("Put people on the keypad", symbol: "square.grid.3x3.fill")
        keypad.addAction(UIAction { [weak self] _ in self?.finish(keypad: true) }, for: .touchUpInside)
        let clock = textLink("Back to the clock") { [weak self] in self?.finish(keypad: false) }
        let calls = PorchStyle.label("Only people on the keypad and numbers you allow can call it.", size: 17)
        form.addArrangedSubview(section("\(lovedOne)'s Porch is ready", views: [numberViews, calls, keypad, clock]))
        NotificationCenter.default.addObserver(self, selector: #selector(renderNumber), name: .porchFamilyChanged, object: nil)
        renderNumber()
    }
    /// A number that was still being set up appears here once it's ready.
    @objc private func renderNumber() {
        let assigned = FamilyCoordinator.shared.state?.porchNumber
        guard !didRenderNumber || assigned != shownNumber else { return }
        didRenderNumber = true; shownNumber = assigned
        numberViews.arrangedSubviews.forEach { numberViews.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let assigned else {
            numberViews.addArrangedSubview(PorchStyle.label("Still getting \(lovedOne)'s number. Caregiver mode shows it when it's ready.", size: 17, color: PorchStyle.ink))
            return
        }
        let heading = PorchStyle.label("\(lovedOne)'s Porch number", size: 17)
        let number = PorchStyle.label(PorchNumber.display(assigned), size: 34, color: PorchStyle.ink, weight: .bold)
        for label in [heading, number] { label.textAlignment = .center }
        numberViews.addArrangedSubview(heading); numberViews.addArrangedSubview(number)
    }
    private func finish(keypad: Bool) {
        let done = setup.onFinish
        dismiss(animated: true) { done(keypad) }
    }
}

/// A label that takes no room in a stack while it has no text.
final class CollapsingLabel: UILabel {
    static func make(size: CGFloat) -> CollapsingLabel {
        let label = CollapsingLabel()
        label.font = PorchStyle.font(size); label.textColor = PorchStyle.secondary
        label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = true
        label.isHidden = true
        return label
    }
    override var text: String? { didSet { isHidden = text?.isEmpty ?? true } }
}
