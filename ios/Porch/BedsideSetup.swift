import UIKit
import AVFoundation
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
        form.addArrangedSubview(section("Welcome to Porch", detail: "Set up Porch on the iPad that stays with your loved one, or join your family's Porch from your phone.", views: [setUp, join]))
        let privacy = textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } }
        privacy.accessibilityIdentifier = "caregiver.privacy"
        form.addArrangedSubview(privacy)
    }
    private func setUp() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { choose(.bedside); return }
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
        form.addArrangedSubview(section("Set up Porch on their iPad", detail: "Porch runs on the iPad that stays with your loved one. Open your setup link on that iPad: it opens Porch there, or shows how to get it. Once it's set up, you can add your phone from the iPad.", views: [join]))
    }
}

/// Setting up a new bedside iPad, one screen at a time: the setup link, unless Porch was opened from it; who it's for;
/// the caregiver PIN, which sets the iPad up; its own phone number; the microphone and camera; then Done. Until the
/// iPad is set up, the clock's caregiver button opens this instead of caregiver mode.
@MainActor final class BedsideSetup {
    /// Who this Porch is for, such as "Mom", once it's chosen.
    var name = ""
    /// Runs after Done: true goes on to put people on the keypad in caregiver mode.
    let onFinish: (Bool) -> Void
    init(onFinish: @escaping (Bool) -> Void = { _ in }) { self.onFinish = onFinish }

    static func start(onFinish: @escaping (Bool) -> Void) -> UINavigationController {
        SystemIncomingCalls.shared.holdsMicrophonePrompt = true
        let setup = BedsideSetup(onFinish: { keypad in releaseMicrophonePrompt(); onFinish(keypad) })
        return PorchStyle.navigation(needsLink ? SetupLinkViewController(setup) : SetupNameViewController(setup))
    }
    /// Once setup is over, registering for calls may ask for the microphone, and does now if setup didn't get it.
    static func releaseMicrophonePrompt() {
        SystemIncomingCalls.shared.holdsMicrophonePrompt = false
        if PorchDevice.credential(for: .bedside) != nil { SystemIncomingCalls.shared.registerDevice() }
    }
    /// The setup link comes first, unless Porch was opened from it or this iPad has the operator's setup code instead.
    static var needsLink: Bool { PorchDevice.bedsideActivation == nil && NativeCallSettings.caregiverCode.count < 16 }
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
        if navigationController?.viewControllers.first === self, PorchDevice.credential(for: .bedside) == nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if isMovingFromParent { task?.cancel() } }
    @objc private func cancel() { task?.cancel(); try? PorchDevice.saveActivation(nil); BedsideSetup.releaseMicrophonePrompt(); dismiss(animated: true) }
    /// For the first screen: this device can be a family member's instead, and anyone can read the privacy policy.
    func addWayOut() {
        form.addArrangedSubview(textLink("Use this device as a family member") { [weak self] in
            self?.task?.cancel(); try? PorchDevice.saveActivation(nil); BedsideSetup.releaseMicrophonePrompt()
            self?.dismiss(animated: true) { PorchDevice.experience = .family }
        })
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
        form.addArrangedSubview(section("Your setup link", detail: "Paste the private link from your Porch invitation. If you don't have one, ask whoever invited you for your setup link.",
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
        form.addArrangedSubview(section("Who is this Porch for?", detail: "Family see this name, and you can change it later.",
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
        form.addArrangedSubview(section("Choose a caregiver PIN", detail: "Six digits. Caregivers use it to change Porch's settings, here and on their phones.",
                                        views: [field(pin, title: "Caregiver PIN", placeholder: "Six digits"), field(confirmation, title: "Enter it again", placeholder: "The same six digits"), proceed]))
    }
    private func enroll() {
        guard task == nil else { return }
        let value = pin.text ?? ""
        guard value.range(of: "^[0-9]{6}$", options: .regularExpression) != nil, value == confirmation.text else {
            showPorchError(FamilyServiceError(message: "Enter the same six digits in both PIN fields.", status: 400), on: self); return
        }
        proceed.isEnabled = false; view.endEditing(true)
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.proceed.isEnabled = true }
            do {
                let invitation = try PorchDevice.bedsideActivation.map { try BedsideInvitation(url: $0, defaultOrigin: PorchDevice.defaultOrigin) }
                let origin = invitation?.origin ?? URL(string: NativeCallSettings.savedURL) ?? PorchDevice.defaultOrigin
                // The same identity on a retry, so a lost response doesn't use the link up.
                let pending = try PorchDevice.pending(role: .bedside, origin: origin, invitation: invitation?.code ?? "")
                var registration = PorchDevice.registration(pending)
                registration["name"] = self.setup.name; registration["pin"] = value
                if let invitation { registration["activation"] = invitation.code }
                let operatorCode = NativeCallSettings.caregiverCode
                let response = try await FamilyService(origin: origin).send("enrollBedside", registration, pin: operatorCode.isEmpty ? nil : operatorCode)
                guard let token = response.credential else { throw FamilyInvitation.InvitationError.invalid }
                try PorchDevice.save(FamilyCredential(origin: origin, credential: token, role: .bedside))
                try NativeCallSettings.writeSecret(Data(value.utf8), account: "porch.contact-setup-code")
                FamilyCoordinator.shared.start(); FamilyCoordinator.shared.update(response)
                try PorchDevice.saveActivation(nil)
                self.navigationController?.setViewControllers([SetupNumberViewController(self.setup)], animated: true)
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
    private let message = PorchStyle.label("", size: 17)
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
        form.addArrangedSubview(section("\(lovedOne)'s Porch number", detail: "People can call \(lovedOne)'s Porch from any phone.",
                                        views: [number, message, areaField, nearby, get, different, proceed]))
        if let existing = FamilyCoordinator.shared.state?.porchNumber { show(existing) } else { loadOptions() }
    }
    private func goOn() {
        if let onContinue { onContinue(); return }
        navigationController?.setViewControllers([SetupPermissionsViewController.needed ? SetupPermissionsViewController(setup) : SetupDoneViewController(setup)], animated: true)
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
                self.message.text = "Porch will get a number in area code \(suggested), near this iPad."
            } else {
                self.showAreaChoice(true)
                self.message.text = "Type the area code you'd like, such as 510."
            }
        }
    }
    /// The area code field, and the keyboard choices that go with it, only when there's an area code to type.
    private func showAreaChoice(_ shown: Bool) {
        areaChoice.forEach { $0.isHidden = !shown }; setKeyboardControlVisible(shown)
    }
    private func chooseAreaCode() {
        showAreaChoice(true); different?.isHidden = true
        message.text = "Choose an area code near this iPad, or type another."
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
        message.text = "Getting a number in area code \(code). This can take a little while."
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
                else { self.waiting("Porch is still getting \(self.lovedOne)'s number. It keeps trying, and caregiver mode shows the number once it's ready.") }
            } catch {
                if Task.isCancelled { return }
                let failure = error as? FamilyServiceError
                // Another area code is up to the caregiver. Porch's own limit clears by itself, and it keeps trying.
                if failure?.code == "noNumbers" || failure?.status == 400 {
                    self.showAreaChoice(true)
                    self.message.text = error.localizedDescription
                }
                else if failure?.code == "numberLimit" { self.waiting("\(error.localizedDescription) Porch keeps trying, and caregiver mode shows the number once it's ready.") }
                else { self.waiting("\(error.localizedDescription) You can go on and get the number in caregiver mode later.") }
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
        message.text = "Anyone can call \(lovedOne)'s Porch on this number. When \(lovedOne) calls a regular phone, it shows this number too."
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
        form.addArrangedSubview(section("Microphone and camera", detail: "Porch uses them for calls, so family can hear and see \(lovedOne). The iPad asks once for each.", views: [proceed]))
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
            self.navigationController?.setViewControllers([SetupDoneViewController(self.setup)], animated: true)
        }
    }
}

final class SetupDoneViewController: BedsideSetupStep {
    private let numberViews = UIStackView()
    override func viewDidLoad() {
        super.viewDidLoad(); hideKeyboardControl()
        navigationItem.hidesBackButton = true
        numberViews.axis = .vertical; numberViews.spacing = 6
        let keypad = PorchStyle.button("Put people on the keypad", symbol: "square.grid.3x3.fill")
        keypad.addAction(UIAction { [weak self] _ in self?.finish(keypad: true) }, for: .touchUpInside)
        let clock = textLink("Back to the clock") { [weak self] in self?.finish(keypad: false) }
        let calls = PorchStyle.label("Only people on the keypad and numbers you allow can call this number. Anyone else is turned away and listed under Blocked numbers, where you can allow them.", size: 17)
        form.addArrangedSubview(section("\(lovedOne)'s Porch is ready", views: [numberViews, calls, keypad, clock]))
        NotificationCenter.default.addObserver(self, selector: #selector(renderNumber), name: .porchFamilyChanged, object: nil)
        renderNumber()
    }
    /// A number that was still being set up appears here once it's ready.
    @objc private func renderNumber() {
        numberViews.arrangedSubviews.forEach { numberViews.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let assigned = FamilyCoordinator.shared.state?.porchNumber else {
            numberViews.addArrangedSubview(PorchStyle.label("Porch is still getting \(lovedOne)'s phone number. Caregiver mode shows it once it's ready.", size: 17, color: PorchStyle.ink))
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
