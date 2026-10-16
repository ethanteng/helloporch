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
        installExperience()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private var readyForIncoming: Bool {
        guard UIApplication.shared.applicationState == .active, presentedViewController == nil, view.window != nil else { return false }
        if let clock = content as? CallViewController { return clock.presentedViewController == nil || clock.presentedViewController is PeoplePickerViewController }
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
        FamilyCoordinator.shared.pause()
        let finish = { [weak self] in
            self?.installExperience(); self?.incomingID = nil
            if UIApplication.shared.applicationState == .active { FamilyCoordinator.shared.start() }
        }
        if presentedViewController != nil { dismiss(animated: false, completion: finish) }
        else if content?.presentedViewController != nil { content?.dismiss(animated: false, completion: finish) }
        else { finish() }
    }
    func resume() { (content as? CallViewController)?.resume(); FamilyCoordinator.shared.start() }
    func pause() { (content as? CallViewController)?.pause(); FamilyCoordinator.shared.pause() }
    @objc private func familyChanged() {
        let coordinator = FamilyCoordinator.shared
        guard let credential = coordinator.credential, let state = coordinator.state else { return }
        guard let call = state.call, call.state == "pending", call.to == state.me.id else { if state.call?.state == "ended" || state.call == nil { incomingID = nil }; return }
        guard incomingID != call.id, readyForIncoming else { return }
        incomingID = call.id
        let show = { [weak self] in
            guard let self, UIApplication.shared.applicationState == .active else { return }
            let incoming = IncomingFamilyCallViewController(call: call, credential: credential)
            incoming.onDismiss = { [weak self] in (self?.content as? CallViewController)?.resume() }
            incoming.onAnswer = { [weak self] session in
                guard let self else { return }
                do { self.present(try NativeCallViewController.paired(session), animated: false) }
                catch { Task { await session.end() }; showPorchError(error, on: self) }
            }
            self.present(incoming, animated: true)
        }
        if let picker = content?.presentedViewController as? PeoplePickerViewController { picker.dismiss(animated: false, completion: show) }
        else { show() }
    }
    func openInvitation(_ url: URL) {
        guard (try? FamilyInvitation(url: url)) != nil else { return }
        guard presentedViewController == nil, content?.presentedViewController == nil else { return }
        PorchDevice.experience = .family
        guard let nav = content as? UINavigationController, let home = nav.viewControllers.first as? FamilyHomeViewController else { return }
        nav.popToRootViewController(animated: false); home.showPairing(invitation: url)
    }
}

final class CaregiverPINViewController: CaregiverFormViewController {
    var onUnlock: (() -> Void)?
    private let pin = UITextField()
    private let unlock = PorchStyle.button("Open caregiver mode", symbol: "lock.open")
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Caregiver mode"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        pin.isSecureTextEntry = true; pin.keyboardType = .numberPad
        form.addArrangedSubview(section("Your caregiver PIN", detail: "Enter the six-digit PIN to manage this bedside device.", views: [field(pin, title: "Six-digit PIN", placeholder: "••••••"), unlock]))
        unlock.addTarget(self, action: #selector(check), for: .touchUpInside)
    }
    @objc private func cancel() { dismiss(animated: true) }
    @objc private func check() {
        guard let credential = PorchDevice.credential(for: .bedside) else { return }
        let value = pin.text ?? ""
        guard value.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else { showPorchError(FamilyServiceError(message: "Enter six digits.", status: 400), on: self); return }
        unlock.isEnabled = false
        Task { [weak self] in
            guard let self else { return }; defer { self.unlock.isEnabled = true }
            do {
                _ = try await FamilyService(credential).send("verifyPIN", pin: value)
                try NativeCallSettings.writeSecret(Data(value.utf8), account: "porch.contact-setup-code")
                self.view.endEditing(true); self.dismiss(animated: true, completion: self.onUnlock)
            } catch { self.pin.text = ""; showPorchError(error, on: self) }
        }
    }
}
