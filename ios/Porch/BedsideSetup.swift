import UIKit
import AVFoundation
import CoreImage.CIFilterBuiltins
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
/// the caregiver PIN, which sets the iPad up; its own phone number; the microphone and camera; the desk phone; the
/// caregiver's own phone; then Done. Until the iPad is set up, the clock's caregiver button opens this instead of
/// caregiver mode.
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
        if stage <= .phone, SetupPhoneViewController.offered { return SetupPhoneViewController(self) }
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
                    UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
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
            self.navigationController?.setViewControllers([self.setup.screen(from: .phone)], animated: true)
        }
    }
}

/// Connect the phone: the desk phone by the bed, through the Cell2Jack, becomes Porch's keypad. Porch tries the Cell2Jack
/// while this screen is open and turns the phone keypad on itself once it answers, then has the caregiver press a key and
/// hang up to check the phone. Do this later leaves the phone keypad off; This iPad in caregiver mode opens this screen
/// again. An iPad without an M chip can't use the Cell2Jack, so it says to call from the touchscreen.
final class SetupPhoneViewController: BedsideSetupStep, Cell2JackDigitReceiving {
    /// Builds without the Cell2Jack, and iPhones, never show this screen.
    static var offered: Bool { Cell2JackKeypad.supportsDriverPlatform }
    /// This iPad's model identifier, such as "iPad14,8". The simulator gives the one it imitates.
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
    /// Where Continue and Do this later go. Setup goes on to adding the caregiver's phone.
    var onContinue: (() -> Void)?
    private enum Progress: Equatable { case waiting, connected, heard(String), done(String) }
    private var progress = Progress.waiting
    private let keypad: Cell2JackKeypad
    private let mayWork: Bool
    /// This screen turned the keypad on. Do this later undoes that; one that was already on stays on.
    private var enabledHere = false
    /// Leaving, so a stop callback doesn't put the waiting text back up.
    private var leaving = false
    private let status = PorchStyle.label("", size: 20, color: PorchStyle.ink, weight: .semibold)
    private let help = UIStackView()
    private let proceed = PorchStyle.button("Continue", symbol: "arrow.right")
    private var later: UIButton?
    private var helpTimer: Timer?
    init(_ setup: BedsideSetup, keypad: Cell2JackKeypad = .shared, model: String = SetupPhoneViewController.model) {
        self.keypad = keypad; mayWork = Cell2JackModels.mayWork(model: model)
        super.init(setup)
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:keypad:model:)") }
    deinit { helpTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }
    override func viewDidLoad() {
        super.viewDidLoad(); hideKeyboardControl()
        if onContinue != nil { title = "Connect the phone" }
        proceed.accessibilityIdentifier = "setup.phoneDone"
        proceed.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        guard mayWork else {
            form.addArrangedSubview(section("Connect the phone", detail: "A desk phone works with Porch only on an iPad with an M chip. On this iPad, \(lovedOne) calls from the touchscreen, or from a USB keypad.", views: [proceed]))
            return
        }
        let steps = ["Plug the phone into the Cell2Jack, and the Cell2Jack into this iPad.", "In Settings → Porch, turn on the USB driver.",
                     "Unplug the Cell2Jack for ten seconds, then plug it back in."].enumerated().map { index, text -> UIView in
            PorchStyle.label("\(index + 1). \(text)", size: 17, color: PorchStyle.ink)
        }
        let settings = PorchStyle.button("Open Settings", symbol: "gearshape", filled: false)
        settings.addAction(UIAction { _ in if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }, for: .touchUpInside)
        status.textAlignment = .center; status.accessibilityIdentifier = "setup.phoneStatus"
        help.axis = .vertical; help.spacing = 8; help.isHidden = true
        help.addArrangedSubview(PorchStyle.label("Not working?", size: 17, color: PorchStyle.ink, weight: .semibold))
        for tip in ["Check that the USB driver is on in Settings → Porch. Then unplug the Cell2Jack for ten seconds and plug it back in.",
                    "Set the phone to tone dialing. Porch can't hear pulse dialing.",
                    "The keys work only while the receiver is lifted.",
                    "If the Cell2Jack says the phone isn't connected when you lift the receiver, press a key and it stops."] {
            help.addArrangedSubview(PorchStyle.label("• " + tip, size: 17))
        }
        let later = textLink("Do this later") { [weak self] in self?.finish() }
        later.accessibilityIdentifier = "setup.phoneLater"; self.later = later
        form.addArrangedSubview(section("Connect the phone", detail: "\(lovedOne) can call by pressing a key on the desk phone. You'll need the phone and the Cell2Jack.",
                                        views: Array(steps[..<2]) + [settings, steps[2], status, help, proceed, later]))
        NotificationCenter.default.addObserver(self, selector: #selector(keypadChanged), name: .cell2JackKeypadChanged, object: nil)
        progress = keypad.isReady ? .connected : .waiting
        render(announce: false)
    }
    @objc private func keypadChanged() {
        if leaving { return }
        if keypad.isReady {
            // Turned on for them: from now on the phone is Mom's keypad, here and on the clock.
            if !keypad.enabled { keypad.setEnabled(true); enabledHere = true }
            if progress == .waiting { progress = .connected; render() }
        } else {
            switch progress {
            // Unplugged, or the driver turned off, before the check finished: a hang-up meanwhile went unheard.
            case .connected, .heard: progress = .waiting; render()
            case .waiting, .done: break
            }
        }
    }
    /// Shows the key the phone sent, without acting on it.
    func receiveCell2JackDigit(_ digit: Int) -> String {
        let symbol = CallSlots.symbol(for: digit)
        switch progress {
        case .done: return "setup: phone already checked"
        case .waiting, .connected, .heard:
            // Without hanging up on the receiver, there's no hang-up to check.
            progress = keypad.receiverHangUp ? .heard(symbol) : .done("Porch heard \(symbol). The phone is ready.")
        }
        render()
        return "setup: heard \(symbol)"
    }
    func receiveCell2JackHangUp() -> String {
        guard case .heard = progress else { return "setup: hang-up before a key" }
        progress = .done("Porch heard you hang up. The phone is ready.")
        render()
        return "setup: heard hang-up"
    }
    private func render(announce: Bool = true) {
        switch progress {
        case .waiting: status.text = "Waiting for the phone…"
        case .connected: status.text = "The phone is connected. Lift the receiver and press a key."
        case .heard(let symbol): status.text = "Porch heard \(symbol). Now put the receiver back."
        case .done(let text): status.text = text
        }
        let done: Bool
        if case .done = progress { done = true } else { done = false }
        proceed.isHidden = !done; later?.isHidden = done
        // Help waits until about 30 seconds go by with nothing happening.
        help.isHidden = true; helpTimer?.invalidate()
        if !done { helpTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.help.isHidden = false } }
        if announce { UIAccessibility.post(notification: .announcement, argument: status.text) }
    }
    private func finish() {
        // Do this later is the way out before the check finishes, and it leaves the keypad off.
        let checked: Bool
        if case .done = progress { checked = true } else { checked = false }
        leaveTrial(turnOff: enabledHere && !checked)
        if let onContinue { onContinue(); return }
        navigationController?.setViewControllers([setup.screen(from: .yourPhone)], animated: true)
    }
    /// The screen is going away. A trial that is still running would keep the desk phone live with the keypad off.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        leaveTrial(turnOff: false)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Coming back, such as after a cover, tries again. Opening Settings does not come through here.
        leaving = false
        guard mayWork else { return }
        keypad.beginTrial()
        if !keypad.isReady, progress == .connected { progress = .waiting; render(announce: false) }
    }
    /// Stops the trial. `turnOff` undoes an enable this screen just did, which Do this later asks for.
    private func leaveTrial(turnOff: Bool) {
        leaving = true
        helpTimer?.invalidate()
        guard mayWork else { return }
        if turnOff { keypad.setEnabled(false) }
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
    private let caption = PorchStyle.label("Open the Camera on your iPhone and point it at this code. If Porch isn't on your phone yet, the link shows how to get it.", size: 17)
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
        form.addArrangedSubview(section("Add your phone", detail: "Call \(lovedOne), send messages and change settings from your iPhone. Your name tells \(lovedOne) who's calling.",
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
        let calls = PorchStyle.label("Only people on the keypad and numbers you allow can call this number. Anyone else is turned away and listed under Blocked numbers, where you can allow them.", size: 17)
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
