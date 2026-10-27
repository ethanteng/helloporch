import UIKit
import PorchCore

final class PorchContainerViewController: UIViewController {
    private var content: UIViewController?
    private var incomingID: String?
    override var childForStatusBarHidden: UIViewController? { content }
    override var childForStatusBarStyle: UIViewController? { content }
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(changeExperience), name: .porchExperienceChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        FamilyCoordinator.shared.canReceive = { [weak self] in self?.readyForIncoming == true }
        NotificationCenter.default.addObserver(self, selector: #selector(systemCallChanged), name: .porchSystemCallChanged, object: nil)
        installExperience()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private var readyForIncoming: Bool {
        guard UIApplication.shared.applicationState == .active, presentedViewController == nil, view.window != nil else { return false }
        if let clock = content as? CallViewController {
            // The clock is about to present something else once the camera stops. Wait for that,
            // then familyChanged runs again, instead of covering the clock twice.
            if clock.isReleasingCamera { return false }
            return clock.presentedViewController == nil || clock.presentedViewController is PeoplePickerViewController || clock.presentedViewController is MessagePlayerViewController || clock.presentedViewController is BedsideVoicemailViewController
        }
        if let nav = content as? UINavigationController { return nav.topViewController is FamilyHomeViewController && nav.presentedViewController == nil }
        return false
    }
    private func installExperience() {
        content?.willMove(toParent: nil); content?.view.removeFromSuperview(); content?.removeFromParent()
        let child: UIViewController = PorchDevice.experience == .bedside ? CallViewController() : PorchStyle.navigation(FamilyHomeViewController())
        addChild(child); child.view.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child.view)
        NSLayoutConstraint.activate([child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), child.view.topAnchor.constraint(equalTo: view.topAnchor), child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        child.didMove(toParent: self); content = child; setNeedsStatusBarAppearanceUpdate()
        UIApplication.shared.isIdleTimerDisabled = PorchDevice.experience == .bedside && UIApplication.shared.applicationState == .active
    }
    @objc private func changeExperience() {
        SystemIncomingCalls.shared.registerDevice()
        if SystemIncomingCalls.shared.hasCall { SystemIncomingCalls.shared.requestEnd() }
        FamilyCoordinator.shared.pause()
        let finish = { [weak self] in
            guard let self else { return }
            let swap = {
                self.installExperience(); self.incomingID = nil
                Cell2JackKeypad.shared.refresh()
                if UIApplication.shared.applicationState == .active { FamilyCoordinator.shared.start() }
            }
            // Stop the bedside camera before the clock is removed and the next screen starts a call.
            if let clock = self.content as? CallViewController { clock.releaseCamera(then: swap) } else { swap() }
        }
        if presentedViewController != nil { dismiss(animated: false, completion: finish) }
        else if content?.presentedViewController != nil { content?.dismiss(animated: false, completion: finish) }
        else { finish() }
    }
    // Calls need the camera and the screen: the clock stops watching for someone first.
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        let presentNow: () -> Void = { [weak self] in self?.presentNow(viewControllerToPresent, animated: flag, completion: completion) }
        guard let clock = content as? CallViewController else { presentNow(); return }
        clock.releaseCamera(then: presentNow)
    }
    private func presentNow(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
    /// A call that arrived while the camera was stopping. Safe to call when nothing is pending.
    func reevaluateIncoming() { familyChanged(); systemCallChanged() }
    func resume() { (content as? CallViewController)?.resume(); FamilyCoordinator.shared.start(); systemCallChanged() }
    /// Calls `done` on the main queue once the bedside presence camera has stopped, so a Porch
    /// call can use the front camera. With no bedside clock, `done` runs on the next turn.
    func performWhenFrontCameraIsFree(_ done: @escaping () -> Void) {
        guard let clock = content as? CallViewController, SystemIncomingCalls.shared.hasCall else {
            DispatchQueue.main.async(execute: done); return
        }
        clock.stopPresenceCamera(then: done)
    }
    func pause() { (content as? CallViewController)?.pause(); FamilyCoordinator.shared.pause() }
    @objc private func familyChanged() {
        let coordinator = FamilyCoordinator.shared
        guard let credential = coordinator.credential, let state = coordinator.state else { return }
        guard let call = state.call, call.state == "pending", call.to == state.me.id else { if state.call?.state == "ended" || state.call == nil { incomingID = nil }; return }
        if call.kind == "call" {
            SystemIncomingCalls.shared.receive(call, credential: credential)
            if credential.role == .family { return }
        }
        guard incomingID != call.id, readyForIncoming else { return }
        incomingID = call.id
        let show = { [weak self] in
            guard let self, UIApplication.shared.applicationState == .active else { return }
            let incoming = IncomingFamilyCallViewController(call: call, credential: credential, snapshot: state)
            incoming.onDismiss = { [weak self] in (self?.content as? CallViewController)?.resume() }
            incoming.onAnswer = { [weak self] session in
                guard let self else { return }
                do { self.present(try NativeCallViewController.paired(session), animated: false) }
                catch { Task { await session.end() }; showPorchError(error, on: self) }
            }
            self.present(incoming, animated: true)
        }
        // Calls take over from the people picker and from message playback (an unfinished message stays queued).
        // Someone calling back while Mom leaves them a message interrupts it; what she said is still sent.
        if let picker = content?.presentedViewController as? PeoplePickerViewController { picker.dismiss(animated: false, completion: show) }
        else if let messages = content?.presentedViewController as? MessagePlayerViewController { messages.interrupt(then: show) }
        else if let recording = content?.presentedViewController as? BedsideVoicemailViewController { recording.interrupt(then: show) }
        else { show() }
    }
    @objc private func systemCallChanged() {
        if (content as? CallViewController)?.isReleasingCamera == true { return }
        let calls = SystemIncomingCalls.shared
        guard calls.answered, UIApplication.shared.applicationState == .active,
              !(presentedViewController is SystemCallViewController) else { return }
        let show = { [weak self] in
            guard let self, calls.answered, calls.hasCall else { return }
            let screen = SystemCallViewController()
            screen.modalPresentationStyle = .fullScreen
            self.present(screen, animated: false)
        }
        if presentedViewController != nil { dismiss(animated: false, completion: show) }
        else if content?.presentedViewController != nil { content?.dismiss(animated: false, completion: show) }
        else { show() }
    }
    func openInvitation(_ url: URL) {
        guard presentedViewController == nil, content?.presentedViewController == nil else { return }
        if (try? BedsideInvitation(url: url)) != nil {
            guard PorchDevice.credential(for: .bedside) == nil else { showPorchError(FamilyServiceError(message: "This iPad is already set up. Open the activation link on the new iPad instead.", status: 409), on: self); return }
            do { try PorchDevice.saveActivation(url) } catch { showPorchError(error, on: self); return }
            PorchDevice.experience = .bedside
            DispatchQueue.main.async { [weak self] in (self?.content as? CallViewController)?.showSetup() }
            return
        }
        guard (try? FamilyInvitation(url: url)) != nil else { return }
        PorchDevice.experience = .family
        guard let nav = content as? UINavigationController, let home = nav.viewControllers.first as? FamilyHomeViewController else { return }
        nav.popToRootViewController(animated: false); home.showPairing(invitation: url)
    }
}

final class CaregiverPINViewController: CaregiverFormViewController {
    var onUnlock: (() -> Void)?
    private let profile: FamilyCredential?
    init(profile: FamilyCredential? = PorchDevice.credential(for: .bedside)) {
        self.profile = profile; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(profile:)") }
    private let pin = UITextField(), confirmation = UITextField(), activation = UITextField(), bedsideName = UITextField()
    private let content = UIStackView()
    private let submit = PorchStyle.button("Continue", symbol: "lock.fill")
    private var creating = false
    private var task: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Caregiver mode"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        content.axis = .vertical; content.spacing = 20; form.addArrangedSubview(content)
        for field in [pin, confirmation] { field.isSecureTextEntry = true; field.keyboardType = .numberPad }
        pin.accessibilityIdentifier = "caregiver.pin"
        confirmation.accessibilityIdentifier = "caregiver.confirm"
        bedsideName.text = "Your loved one"; bedsideName.autocapitalizationType = .words
        activation.keyboardType = .URL; activation.text = PorchDevice.bedsideActivation?.absoluteString
        submit.addTarget(self, action: #selector(save), for: .touchUpInside)
        loadStatus()
    }
    private func loadStatus() {
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let profile else { creating = true; showForm(); return }
        content.addArrangedSubview(PorchStyle.label("Checking caregiver setup…"))
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                let result = try await FamilyService(profile).send("caregiverStatus")
                self.creating = result.pinConfigured != true; self.showForm()
            } catch {
                self.content.arrangedSubviews.forEach { self.content.removeArrangedSubview($0); $0.removeFromSuperview() }
                self.content.addArrangedSubview(PorchStyle.label("Connect to the internet to open caregiver mode."))
                let retry = PorchStyle.button("Try again", symbol: "arrow.clockwise")
                retry.addAction(UIAction { [weak self] _ in self?.loadStatus() }, for: .touchUpInside)
                self.content.addArrangedSubview(retry)
            }
        }
    }
    private func showForm() {
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        var fields: [UIView] = []
        if creating && profile == nil {
            fields.append(field(bedsideName, title: "Who is this Porch for?", placeholder: "Your loved one"))
            if NativeCallSettings.caregiverCode.count < 16 && PorchDevice.bedsideActivation == nil {
                fields.append(field(activation, title: "Bedside activation link", placeholder: "Paste your private activation link", helper: "Paste the private link you were sent for this iPad."))
            }
        }
        fields.append(field(pin, title: creating ? "Choose a six-digit PIN" : "Six-digit PIN", placeholder: "Enter six digits"))
        if creating { fields.append(field(confirmation, title: "Confirm your PIN", placeholder: "Repeat the six digits")) }
        submit.configuration?.title = creating ? "Save PIN and continue" : "Open caregiver mode"
        fields.append(submit)
        bedsideName.autocapitalizationType = .words
        content.addArrangedSubview(section(creating ? "Set your caregiver PIN" : "Your caregiver PIN", detail: creating ? "Caregivers also use it on their phones." : nil, views: fields))
        // Until this device is enrolled, caregiver mode (and its device-mode switch) can't open,
        // so offer the way back here.
        if creating && profile == nil {
            content.addArrangedSubview(textLink("Use this device as a family member") { [weak self] in self?.useAsFamily() })
        }
        // Reachable without the PIN, so anyone at the bedside can read it.
        let privacy = textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } }
        privacy.accessibilityIdentifier = "caregiver.privacy"
        content.addArrangedSubview(privacy)
    }
    private func useAsFamily() {
        task?.cancel(); try? PorchDevice.saveActivation(nil)
        dismiss(animated: true) { PorchDevice.experience = .family }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.isBeingDismissed == true { task?.cancel() }
    }
    @objc private func cancel() { task?.cancel(); try? PorchDevice.saveActivation(nil); dismiss(animated: true) }
    @objc private func save() {
        guard task == nil else { return }
        let value = pin.text ?? ""
        guard value.range(of: "^[0-9]{6}$", options: .regularExpression) != nil, !creating || value == confirmation.text else {
            showPorchError(FamilyServiceError(message: creating ? "Enter the same six digits in both PIN fields." : "Enter six digits.", status: 400), on: self); return
        }
        submit.isEnabled = false; view.endEditing(true)
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.submit.isEnabled = true }
            do {
                if let profile = self.profile {
                    _ = try await FamilyService(profile).send(self.creating ? "initializeCaregiverPIN" : "verifyPIN", self.creating ? ["pin": value] : [:], pin: self.creating ? nil : value)
                } else {
                    let linkText = self.activation.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let invitation = try linkText.isEmpty ? nil : BedsideInvitation(url: URL(string: linkText) ?? URL(fileURLWithPath: "/"))
                    let origin = invitation?.origin ?? URL(string: NativeCallSettings.savedURL) ?? PorchDevice.defaultOrigin
                    let pending = try PorchDevice.pending(role: .bedside, origin: origin, invitation: invitation?.code ?? "")
                    var registration = PorchDevice.registration(pending)
                    registration["name"] = self.bedsideName.text ?? "Your loved one"; registration["pin"] = value
                    if let invitation { registration["activation"] = invitation.code }
                    let response = try await FamilyService(origin: origin).send("enrollBedside", registration, pin: NativeCallSettings.caregiverCode.isEmpty ? nil : NativeCallSettings.caregiverCode)
                    guard let token = response.credential else { throw FamilyInvitation.InvitationError.invalid }
                    try PorchDevice.save(FamilyCredential(origin: origin, credential: token, role: .bedside))
                    FamilyCoordinator.shared.start(); FamilyCoordinator.shared.update(response)
                    try PorchDevice.saveActivation(nil)
                }
                try NativeCallSettings.writeSecret(Data(value.utf8), account: "porch.contact-setup-code")
                self.dismiss(animated: true, completion: self.onUnlock)
            } catch { if !Task.isCancelled { showPorchError(error, on: self) } }
        }
    }
}
