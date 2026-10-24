import UIKit
import AVFoundation
import ContactsUI
import SafariServices
import PorchCore

/// On the website, so the policy can change without an app update.
let privacyPolicyURL = URL(string: "https://helloporch.store/privacy")!
func showPrivacyPolicy(on controller: UIViewController) {
    controller.present(SFSafariViewController(url: privacyPolicyURL), animated: true)
}
func showPorchError(_ error: Error, on controller: UIViewController) {
    let alert = UIAlertController(title: "Couldn't complete that", message: error.localizedDescription, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    controller.present(alert, animated: true)
}
func offerExperienceChange(on controller: UIViewController) {
    let alert = UIAlertController(title: "Use this device as…", message: "Bedside mode shows the clock. Family mode lets you call a paired bedside device. Each mode keeps its own pairing.", preferredStyle: .alert)
    for (label, mode) in [("Bedside device", PorchExperience.bedside), ("Family member", .family)] {
        alert.addAction(UIAlertAction(title: label, style: .default) { _ in PorchDevice.experience = mode })
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); controller.present(alert, animated: true)
}

final class FamilyHomeViewController: CaregiverFormViewController {
    private let status = PorchStyle.label("", size: 17)
    private let people = UIStackView()
    private var starting = false
    private struct Presentation: Equatable {
        let household: String?
        let people: [FamilyPerson]
        let permissions: DropInPermissions?
        let dropIn: Bool?
        let autoDropIn: Bool?
        let busy: Bool?
        let error: String?
        let paired: Bool
        let starting: Bool
        let messages: Bool
        let held: Int
        let unheard: Int
        /// The photo Porch shows for this phone, once it's on this device.
        let photo: String?
    }
    private var displayed: Presentation?
    private lazy var invitationButton = UIBarButtonItem(title: "Invitation", style: .plain, target: self, action: #selector(newInvitation))
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Porch"
        navigationItem.leftBarButtonItem = invitationButton
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(showDeviceSettings))
        people.axis = .vertical; people.spacing = 20
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Device settings"
        form.addArrangedSubview(status); form.addArrangedSubview(people)
        hideKeyboardControl()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPushStatus), name: .porchSystemCallChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openReceivedMessages), name: .porchOpenReceivedMessages, object: nil)
        refresh()
    }
    @objc private func openReceivedMessages() {
        guard PorchDevice.credential(for: .family) != nil, let navigationController else { return }
        if navigationController.presentedViewController != nil { navigationController.dismiss(animated: false) }
        navigationController.popToRootViewController(animated: false)
        navigationController.pushViewController(ReceivedMessagesViewController(), animated: true)
    }
    @objc private func refreshPushStatus() { displayed = nil; refresh() }
    #if DEBUG
    private var previewShown = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !previewShown else { return }
        previewShown = true
        if ProcessInfo.processInfo.arguments.contains("--preview-received-messages") { openReceivedMessages() }
        if ProcessInfo.processInfo.arguments.contains("--preview-profile") { showProfile() }
    }
    #endif
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func newInvitation() { showPairing() }
    /// This phone's name and photo, as the bedside shows them.
    private func profileButton(photo: String?) -> UIBarButtonItem {
        let image = RecipientAppearance.cardPhoto(FamilyPhotos.shared.data(for: photo), width: 30) ?? UIImage(systemName: "person.crop.circle")
        let item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(showProfile))
        item.accessibilityLabel = "Your profile"
        item.accessibilityIdentifier = "family.profile"
        return item
    }
    @objc private func showProfile() { navigationController?.pushViewController(FamilyProfileViewController(), animated: true) }
    @objc private func showDeviceSettings() {
        let paired = PorchDevice.credential(for: .family) != nil
        let sheet = UIAlertController(title: "Device settings", message: nil, preferredStyle: .actionSheet)
        if paired {
            sheet.addAction(UIAlertAction(title: "Call settings", style: .default) { [weak self] _ in self?.navigationController?.pushViewController(FamilyCallSettingsViewController(), animated: true) })
            sheet.addAction(UIAlertAction(title: "Caregiver mode", style: .default) { [weak self] _ in self?.openCaregiverMode() })
            sheet.addAction(UIAlertAction(title: "Join a different family", style: .default) { [weak self] _ in self?.confirmNewFamily() })
        }
        sheet.addAction(UIAlertAction(title: "Use as the bedside Porch", style: .default) { [weak self] _ in self?.confirmBedside() })
        sheet.addAction(UIAlertAction(title: "Privacy policy", style: .default) { [weak self] _ in self?.openPrivacyPolicy() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }
    private func openPrivacyPolicy() { showPrivacyPolicy(on: self) }
    private func openCaregiverMode() {
        guard FamilyCoordinator.shared.state?.me.caregiver == true else {
            let alert = UIAlertController(title: "Caregiver mode isn't on for you", message: "Ask the caregiver to turn on Caregiver mode for you in Family & drop-in.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true); return
        }
        navigationController?.pushViewController(RemoteCaregiverPINViewController(), animated: true)
    }
    private func confirmNewFamily() {
        let current = FamilyCoordinator.shared.state?.householdName ?? "your current family"
        let alert = UIAlertController(title: "Join a different family?", message: "You'll need an invitation from the new family's caregiver. This phone stays in \(current) until you join the new family.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in self?.showPairing() })
        present(alert, animated: true)
    }
    private func confirmBedside() {
        let alert = UIAlertController(title: "Use this device as the bedside Porch?", message: "Only do this on the device next to your loved one. It doesn't open caregiver mode. Your family pairing stays saved, and the bedside setup screen can switch back.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Use as bedside", style: .default) { _ in PorchDevice.experience = .bedside })
        present(alert, animated: true)
    }
    func showPairing(invitation: URL? = nil) {
        let pairing = FamilyPairingViewController(); pairing.invitation = invitation
        navigationController?.pushViewController(pairing, animated: true)
    }
    @objc private func refresh() {
        guard isViewLoaded else { return }
        let coordinator = FamilyCoordinator.shared
        let state = coordinator.state
        let next = Presentation(household: state?.householdID, people: state?.people ?? [], permissions: state?.me.permissions, dropIn: state?.dropInEnabled, autoDropIn: state?.me.autoDropIn, busy: state?.busy, error: coordinator.error, paired: PorchDevice.credential(for: .family) != nil, starting: starting, messages: state?.messagesEnabled != false, held: state?.heldMessages ?? 0, unheard: state?.newMessages ?? 0,
                              photo: state?.me.photoID.flatMap { FamilyPhotos.shared.store.contains($0) ? $0 : nil })
        guard next != displayed else { return }
        displayed = next
        // Once paired, joining another family lives in Device settings so it isn't done by accident.
        navigationItem.leftBarButtonItem = next.paired ? profileButton(photo: next.photo) : invitationButton
        people.arrangedSubviews.forEach { people.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard next.paired else {
            status.text = "Ask the caregiver to invite you to the family Porch."
            let join = PorchStyle.button("Join a family", symbol: "person.badge.plus")
            join.addAction(UIAction { [weak self] _ in self?.showPairing() }, for: .touchUpInside)
            people.addArrangedSubview(join); return
        }
        status.text = coordinator.error ?? (SystemIncomingCalls.shared.pushReady ? "Incoming Porch calls can ring while your iPhone is locked." : "Keep Porch open to receive calls. Background ringing is connecting or unavailable.")
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied { status.text = "Allow microphone access in iPhone Settings → Porch to answer calls." }
        guard let state else { if coordinator.error == nil { status.text = "Connecting to your family…" }; return }
        // Phone voicemail from callers who aren't on the keypad waits for a caregiver.
        if next.held > 0 {
            let review = PorchStyle.button(next.held == 1 ? "1 phone voicemail needs your review" : "\(next.held) phone voicemails need your review", symbol: "exclamationmark.bubble.fill")
            review.accessibilityIdentifier = "family.heldVoicemail"
            review.addAction(UIAction { [weak self] _ in self?.openCaregiverMode() }, for: .touchUpInside)
            people.addArrangedSubview(review)
        }
        // Left by the bedside when its call to this phone wasn't answered.
        let from = state.people.first { $0.role == .bedside }?.name ?? state.householdName
        if next.unheard > 0 {
            let play = PorchStyle.button(next.unheard == 1 ? "New message from \(from)" : "\(next.unheard) new messages from \(from)", symbol: "envelope.badge.fill")
            play.accessibilityIdentifier = "family.newMessages"
            play.addAction(UIAction { [weak self] _ in self?.openReceivedMessages() }, for: .touchUpInside)
            people.addArrangedSubview(play)
        }
        for person in state.people {
            let availability = PorchStyle.label(person.online ? (state.busy ? "On a call" : "Porch is open") : "Porch isn't ready", size: 17)
            let audio = PorchStyle.button("Audio call", symbol: "phone.fill")
            let video = PorchStyle.button("Video call", symbol: "video.fill")
            let dropAudio = PorchStyle.button("Drop in with audio", symbol: "waveform", filled: false)
            let dropVideo = PorchStyle.button("Drop in with video", symbol: "video.badge.waveform", filled: false)
            for (button, mode, drop) in [(audio, NativeCall.Mode.voice, false), (video, .video, false), (dropAudio, .voice, true), (dropVideo, .video, true)] {
                button.isEnabled = coordinator.error == nil && person.online && !state.busy && !starting && (!drop || (state.dropInEnabled && (mode == .voice ? state.me.permissions.audio : state.me.permissions.video)))
                button.addAction(UIAction { [weak self] _ in self?.call(person, mode: mode, dropIn: drop) }, for: .touchUpInside)
            }
            var views: [UIView] = [availability, audio, video, dropAudio, dropVideo]
            // Messages wait on the bedside device, so they don't need it to be open right now.
            if next.messages {
                let message = PorchStyle.button("Send a message", symbol: "envelope.fill", filled: false)
                message.addAction(UIAction { [weak self] _ in self?.navigationController?.pushViewController(MessageComposerViewController(recipient: person.name), animated: true) }, for: .touchUpInside)
                views.append(message)
            }
            people.addArrangedSubview(section(person.name, views: views))
        }
        let received = PorchStyle.button("Messages from \(from)", symbol: "envelope.open", filled: false)
        received.accessibilityIdentifier = "family.receivedMessages"
        received.addAction(UIAction { [weak self] _ in self?.openReceivedMessages() }, for: .touchUpInside)
        people.addArrangedSubview(received)
        let sent = PorchStyle.button("Your messages", symbol: "tray.full", filled: false)
        sent.addAction(UIAction { [weak self] _ in self?.navigationController?.pushViewController(SentMessagesViewController(), animated: true) }, for: .touchUpInside)
        people.addArrangedSubview(sent)
        if !state.dropInEnabled { people.addArrangedSubview(PorchStyle.label("Drop-in is paused on the bedside device.")) }
        else if !state.me.permissions.audio && !state.me.permissions.video { people.addArrangedSubview(PorchStyle.label("The caregiver hasn't enabled drop-in for this device. You can still make an ordinary call.")) }
        // A caregiver set this phone's ordinary calls to drop in, so it says so before anyone taps Audio call.
        else if state.me.autoDropIn == true {
            let permissions = state.me.permissions
            people.addArrangedSubview(PorchStyle.label(permissions.audio && permissions.video ? "Your audio and video calls drop in while their Porch is open."
                : permissions.audio ? "Your audio calls drop in while their Porch is open. Video calls ring." : "Your video calls drop in while their Porch is open. Audio calls ring."))
        }
    }
    private func offerVoicemail(to name: String, title: String) {
        guard view.window != nil, presentedViewController == nil, FamilyCoordinator.shared.state?.messagesEnabled != false else {
            showPorchError(FamilyServiceError(message: title, status: 409), on: self); return
        }
        let alert = UIAlertController(title: title, message: "Leave a message? It waits on their Porch until they play it.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Leave a message", style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(MessageComposerViewController(recipient: name, kind: "voicemail", startAudioImmediately: true), animated: true)
        })
        present(alert, animated: true)
    }
    private func call(_ person: FamilyPerson, mode: NativeCall.Mode, dropIn: Bool) {
        guard !starting else { return }; starting = true; refresh()
        Task { [weak self] in
            guard let self else { return }
            defer { self.starting = false; self.refresh() }
            do {
                let microphone = await AVCaptureDevice.requestAccess(for: .audio)
                let camera = mode == .video ? await AVCaptureDevice.requestAccess(for: .video) : true
                guard microphone && camera else { throw FamilyServiceError(message: "Allow Porch to use the microphone and camera in Settings before calling.", status: 403) }
                let session = try await FamilyCoordinator.shared.startCall(to: person, mode: mode, dropIn: dropIn)
                guard self.view.window != nil, UIApplication.shared.applicationState == .active else { await session.end(); return }
                let screen = try NativeCallViewController.paired(session)
                screen.onUnanswered = { [weak self] in self?.offerVoicemail(to: person.name, title: "\(person.name) didn't answer") }
                self.present(screen, animated: true)
            } catch {
                if (error as? FamilyServiceError)?.code == "offline" { self.offerVoicemail(to: person.name, title: "\(person.name)'s Porch isn't available") }
                else { showPorchError(error, on: self) }
            }
        }
    }
}

/// Preferences kept on this phone for its own calls. Changes apply right away.
final class FamilyCallSettingsViewController: CaregiverFormViewController {
    private let camera = UISwitch()
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Call settings"
        camera.isOn = CallPreferences.startVideoWithCamera()
        camera.accessibilityIdentifier = "family.startVideoWithCamera"
        camera.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            CallPreferences.saveStartVideoWithCamera(self.camera.isOn)
        }, for: .valueChanged)
        form.addArrangedSubview(group("Video calls", footer: "When this is on, your camera turns on as soon as a video call connects. If you answer from the lock screen, it turns on when you open Porch. It never runs while Porch is closed or the screen is locked. You can turn the camera on or off during any call.", rows: [toggleRow("Start with my camera on", camera)]))
        hideKeyboardControl()
    }
}

final class FamilyPairingViewController: CaregiverFormViewController {
    var invitation: URL?
    private let link = UITextField()
    private let join = PorchStyle.button("Join family", symbol: "person.badge.plus")
    private var task: Task<Void, Never>?
    override func viewDidLoad() {
        let replacing = PorchDevice.credential(for: .family) != nil
        super.viewDidLoad(); title = replacing ? "Join a different family" : "Join your family"
        link.text = invitation?.absoluteString; link.keyboardType = .URL
        form.addArrangedSubview(section("Your Porch invite", detail: "Ask the caregiver to invite you to the family Porch. It can be used once and expires after 24 hours.", views: [field(link, title: "Porch invitation", placeholder: "Paste the complete invitation link"), join]))
        if replacing { form.addArrangedSubview(PorchStyle.label("Joining removes this phone from \(FamilyCoordinator.shared.state?.householdName ?? "your current family").", size: 17, color: PorchStyle.ink)) }
        form.addArrangedSubview(PorchStyle.label("Your invitation sets your name and access. Once you've joined, you can choose your own name and photo under Your profile. Audio and video drop-in are approved separately by the caregiver. No calling code is needed."))
        join.addTarget(self, action: #selector(pair), for: .touchUpInside)
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if isMovingFromParent { task?.cancel() } }
    @objc private func pair() {
        guard task == nil else { return }
        do {
            guard let url = URL(string: link.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else { throw FamilyInvitation.InvitationError.invalid }
            let invite = try FamilyInvitation(url: url)
            join.isEnabled = false; view.endEditing(true)
            task = Task { [weak self] in
                guard let self else { return }; defer { self.task = nil; self.join.isEnabled = true }
                do {
                    let pending = try PorchDevice.pending(role: .family, origin: invite.origin, invitation: invite.code)
                    var registration = PorchDevice.registration(pending); registration["code"] = invite.code
                    let response = try await FamilyService(origin: invite.origin).send("claimInvite", registration)
                    guard let token = response.credential else { throw FamilyInvitation.InvitationError.invalid }
                    try await SystemIncomingCalls.shared.prepareForPairing()
                    // Leave the previous family only once the new one has accepted this phone. Reopening
                    // an invitation this phone already used returns the same identity, which must stay.
                    if let previous = PorchDevice.credential(for: .family), previous.credential != token {
                        do { _ = try await FamilyService(previous).send("leaveHousehold") }
                        // Already removed, or its household is gone: nothing is left to leave.
                        catch let failure as FamilyServiceError where [401, 404].contains(failure.status) {}
                        // Keep the old pairing so Join can retry; reclaiming this invitation returns the same identity.
                        catch { throw FamilyServiceError(message: "Couldn't leave your current family, so you haven't switched yet. Check the connection and tap Join family again.", status: 503) }
                    }
                    try PorchDevice.save(FamilyCredential(origin: invite.origin, credential: token, role: .family))
                    FamilyCoordinator.shared.start()
                    self.navigationController?.popToRootViewController(animated: true)
                } catch { if !Task.isCancelled { showPorchError(error, on: self) } }
            }
        } catch { showPorchError(error, on: self) }
    }
}

final class FamilyAdminViewController: CaregiverFormViewController {
    /// Set when caregiver mode was opened from a family phone; nil on the bedside iPad.
    fileprivate let remote: FamilyCredential?
    private var remoteState: FamilyAdminState?
    private let householdName = UITextField()
    private let details = UIStackView()
    private var busy = false
    private var appeared = false
    private var locked = false
    private var displayed: FamilyAdminState?
    private weak var personScreen: FamilyPersonViewController?
    private weak var blockedScreen: BlockedCallersViewController?
    private var credential: FamilyCredential? { remote ?? PorchDevice.credential(for: .bedside) }
    fileprivate var myID: String? { credential?.credential.split(separator: ".").first.map { String($0) } }
    fileprivate var current: FamilyAdminState? {
        if remote != nil { return remoteState }
        return FamilyCoordinator.shared.state.map { FamilyAdminState(householdName: $0.householdName, dropInEnabled: $0.dropInEnabled, people: $0.people, messagesEnabled: $0.messagesEnabled, messages: $0.messages, phoneDropIns: $0.phoneDropIns, invitations: $0.invitations, callScreening: $0.callScreening) }
    }
    init(remote: FamilyCredential? = nil, state: FamilyAdminState? = nil) {
        self.remote = remote; remoteState = state; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(remote:state:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = remote == nil ? "Family & drop-in" : "Caregiver mode"
        if remote != nil { navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Family mode", style: .done, target: self, action: #selector(leaveCaregiverMode)) }
        details.axis = .vertical; details.spacing = 28
        form.addArrangedSubview(details)
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(returnedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        refresh()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func familyChanged() {
        if remote != nil {
            // Polls every few seconds: withdrawn approval, a removed device or the idle timeout locks right away.
            let coordinator = FamilyCoordinator.shared
            if coordinator.accessRemoved || coordinator.state?.me.caregiver == false {
                lock(FamilyServiceError(message: "Caregiver mode is no longer available on this phone.", status: 403))
            } else if !RemoteCaregiverSession.shared.isActive { lock(nil) }
            return
        }
        guard !busy, !householdName.isFirstResponder, displayed == nil || householdName.text == displayed?.householdName else { return }
        if displayed != current { refresh() }
    }
    @objc private func returnedToForeground() { if remote != nil && !RemoteCaregiverSession.shared.isActive { lock(nil) } }
    @objc private func leaveCaregiverMode() { RemoteCaregiverSession.shared.end(); navigationController?.popToRootViewController(animated: true) }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if remote == nil && PorchDevice.credential(for: .bedside) != nil { refresh() }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard remote != nil else { return }
        guard RemoteCaregiverSession.shared.isActive else { lock(nil); return }
        // The unlock already returned fresh details; later returns (from an invitation) reload them.
        if appeared || remoteState == nil { Task { await self.perform("verifyPIN") } }
        appeared = true
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if remote != nil && isMovingFromParent { RemoteCaregiverSession.shared.end() }
    }
    /// Ends a phone's caregiver session and returns to family mode.
    private func lock(_ error: Error?) {
        RemoteCaregiverSession.shared.end()
        guard !locked, let navigation = navigationController, let home = navigation.viewControllers.first else { return }
        locked = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { if let error { showPorchError(error, on: home) } }
        navigation.popToRootViewController(animated: true)
        CATransaction.commit()
    }
    private func refresh() {
        details.arrangedSubviews.forEach { details.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard credential != nil else {
            details.addArrangedSubview(PorchStyle.label("Return to the clock and open caregiver mode to finish setting up this bedside device.")); return
        }
        let state = current
        displayed = state
        householdName.text = state?.householdName ?? "Your loved one"
        let saveName = PorchStyle.button("Save", symbol: "checkmark")
        saveName.accessibilityLabel = "Save name"
        saveName.addAction(UIAction { [weak self] _ in
            guard let self else { return }; self.view.endEditing(true)
            Task { await self.perform("setHouseholdName", ["name": self.householdName.text ?? ""]) }
        }, for: .touchUpInside)
        let nameRow = listRow(field(householdName, title: "Display name", placeholder: "Your loved one"), trailing: Self.singleLine(saveName), alignedToBottom: true)
        householdName.autocapitalizationType = .words
        details.addArrangedSubview(group("Who is this Porch for?", footer: "Family members see this name when calling or dropping in.", rows: [nameRow]))
        details.addArrangedSubview(familyGroup(state))
        details.addArrangedSubview(dropInGroup(state))
        details.addArrangedSubview(phoneCallsGroup(state))
        details.addArrangedSubview(messagesGroup(state))
        details.addArrangedSubview(caregiverGroup(state))
        personScreen?.render()
        blockedScreen?.render()
        #if DEBUG
        if !previewedPerson, ProcessInfo.processInfo.arguments.contains("--preview-family-person"), let person = state?.people.first {
            previewedPerson = true
            DispatchQueue.main.async { self.showPerson(person.id) }
        }
        #endif
    }
    #if DEBUG
    private var previewedPerson = false
    #endif
    /// Everyone with access and everyone invited, so a pending invitation sits beside the people it will join.
    private func familyGroup(_ state: FamilyAdminState?) -> UIView {
        var rows: [UIView] = (state?.people ?? []).map { person in
            let name = person.id == myID ? "\(person.name) (this phone)" : person.name
            let access = person.access ?? "Calls only"
            let text = UIStackView(arrangedSubviews: [
                PorchStyle.label(name, size: 18, color: PorchStyle.ink, weight: .medium),
                PorchStyle.label(person.shortStatus, size: 15),
                PorchStyle.label(access, size: 15, color: person.access == nil ? PorchStyle.secondary : PorchStyle.accent, weight: .medium),
            ])
            text.axis = .vertical; text.spacing = 2
            let row = PorchListRow([Self.avatar(person.name, photo: FamilyPhotos.shared.data(for: person.photoID)), text], label: "\(name). \(person.shortStatus). \(access).") { [weak self] in self?.showPerson(person.id) }
            row.accessibilityIdentifier = "family.person.\(person.id)"
            return row
        }
        // Invitations last a day, so the expiry needs its day ("Tomorrow, 3:14 PM").
        let time = DateFormatter(); time.dateStyle = .short; time.timeStyle = .short; time.doesRelativeDateFormatting = true
        rows += (state?.invitations ?? []).map { invitation in
            let name = invitation.name ?? "Invitation"
            let clock = Self.circle(size: 44)
            clock.backgroundColor = nil; clock.layer.borderWidth = 1.5; clock.layer.borderColor = PorchStyle.border.cgColor
            let icon = UIImageView(image: UIImage(systemName: "clock")); icon.tintColor = PorchStyle.secondary
            Self.center(icon, in: clock)
            let text = UIStackView(arrangedSubviews: [
                PorchStyle.label(name, size: 18, color: PorchStyle.ink, weight: .medium),
                PorchStyle.label("Invite pending · expires at \(time.string(from: Date(timeIntervalSince1970: invitation.expiresAt)))", size: 15),
            ])
            text.axis = .vertical; text.spacing = 2
            let cancel = PorchStyle.button("Cancel", filled: false)
            cancel.configuration?.baseForegroundColor = .systemRed
            cancel.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 4)
            cancel.accessibilityLabel = "Cancel invitation for \(name)"
            cancel.addAction(UIAction { [weak self] _ in Task { await self?.perform("cancelInvite", ["inviteID": invitation.id]) } }, for: .touchUpInside)
            let invited = UIStackView(arrangedSubviews: [clock, text]); invited.alignment = .center; invited.spacing = 12
            return listRow(invited, trailing: Self.singleLine(cancel))
        }
        rows.append(actionRow("Invite a family member", symbol: "person.badge.plus") { [weak self] in self?.showInvite() })
        let footer = remote == nil
            ? "Tap a person to change their name, photo, drop-in and caregiver access. To put someone on a keypad number, edit that keypad contact and choose Link their Porch app."
            : "Tap a person to change their name, photo, drop-in and caregiver access."
        return group("Family", footer: footer, rows: rows)
    }
    /// The master switch above everything it governs: family members' drop-in and approved phone numbers.
    private func dropInGroup(_ state: FamilyAdminState?) -> UIView {
        let enabled = state?.dropInEnabled == true
        let master = UISwitch(); master.isOn = enabled
        master.addAction(UIAction { [weak self, weak master] _ in
            guard let self, let master else { return }
            Task {
                if master.isOn && self.remote == nil {
                    guard await self.requestMedia(video: state?.people.contains(where: { $0.permissions.video }) == true) else { master.isOn = false; return }
                }
                await self.perform("setDropIn", ["enabled": master.isOn])
            }
        }, for: .valueChanged)
        var rows = [toggleRow("Allow approved drop-ins", detail: enabled ? "On for everyone listed below." : "Paused for everyone. Approvals are kept.", master)]
        let heading = PorchStyle.label("Who can drop in", size: 15, color: PorchStyle.secondary, weight: .semibold)
        heading.accessibilityTraits = .header
        let headingRow = UIStackView(arrangedSubviews: [heading])
        headingRow.isLayoutMarginsRelativeArrangement = true
        headingRow.directionalLayoutMargins = .init(top: 14, leading: 16, bottom: 6, trailing: 16)
        rows.append(headingRow)
        let ink = enabled ? PorchStyle.ink : PorchStyle.secondary
        let approved = (state?.people ?? []).filter { $0.permissions.audio || $0.permissions.video }
        let phones = state?.phoneDropIns ?? []
        rows += approved.map { person in
            let modes = (person.dropInModes ?? "") + (person.callsDropIn ? " · Calls drop in" : "")
            let text = UIStackView(arrangedSubviews: [PorchStyle.label(person.name, size: 18, color: ink), PorchStyle.label("Porch app · \(modes)", size: 15)])
            text.axis = .vertical; text.spacing = 2
            return PorchListRow([text], label: "\(person.name), Porch app, \(modes)") { [weak self] in self?.showPerson(person.id) }
        }
        rows += phones.map { approval in
            let remove = PorchStyle.button("Remove", symbol: "minus.circle", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 4)
            remove.accessibilityLabel = "Remove phone drop-in for \(approval.name)"
            remove.addAction(UIAction { [weak self] _ in
                Task { await self?.perform("setPhoneDropIn", ["number": approval.number, "enabled": false]) }
            }, for: .touchUpInside)
            let text = UIStackView(arrangedSubviews: [PorchStyle.label(approval.name, size: 18, color: ink), PorchStyle.label("\(approval.number) · Phone call, audio", size: 15)])
            text.axis = .vertical; text.spacing = 2
            return listRow(text, trailing: Self.singleLine(remove))
        }
        if approved.isEmpty && phones.isEmpty {
            rows.append(listRow([PorchStyle.label("No one yet. Turn on drop-in for a family member, or approve a phone number.", size: 16)]))
        }
        rows.append(actionRow("Approve a phone number", symbol: "phone.badge.plus") { [weak self] in self?.showPhoneDropIn() })
        let footer = "Only the people and numbers listed here connect without anyone answering, after a spoken announcement and five-second countdown. Ordinary calls ring for Answer, except Porch calls from people whose calls drop in, while this is on and Porch is open on the bedside iPad. Phone drop-ins work while Porch is open on the bedside iPad, for calls their phone company verifies."
        return group("Drop-in", footer: remote == nil ? footer : footer + " Drop-ins connect only if the bedside iPad allows microphone and camera access.", rows: rows)
    }
    /// Who can ring this Porch from a regular phone, beside the numbers that were turned away.
    private func phoneCallsGroup(_ state: FamilyAdminState?) -> UIView {
        let screening = state?.callScreening
        let block = UISwitch(); block.isOn = screening?.enabled == true
        block.isEnabled = screening != nil
        block.accessibilityIdentifier = "calls.blockUnknown"
        block.addAction(UIAction { [weak self, weak block] _ in
            guard let self, let block else { return }
            Task { await self.perform("setBlockUnknownCallers", ["enabled": block.isOn]) }
        }, for: .valueChanged)
        let detail = screening == nil ? "Not available on this Porch's server yet."
            : screening?.enabled == true ? "Only keypad contacts and numbers you allow can ring." : "Anyone with this Porch's phone number can ring it."
        let blocked = screening?.blocked ?? [], allowed = screening?.allowed ?? []
        let listText = UIStackView(arrangedSubviews: [PorchStyle.label("Blocked numbers", size: 18, color: PorchStyle.ink)])
        listText.axis = .vertical; listText.spacing = 2
        if !allowed.isEmpty { listText.addArrangedSubview(PorchStyle.label("\(allowed.count) allowed", size: 15)) }
        let count = PorchStyle.label(blocked.isEmpty ? "None" : "\(blocked.count)", size: 18)
        let list = PorchListRow([listText, Self.singleLine(count)], label: blocked.isEmpty ? "Blocked numbers, none" : "Blocked numbers, \(blocked.count)") { [weak self] in self?.showBlockedCallers() }
        list.accessibilityIdentifier = "calls.blockedNumbers"
        list.isEnabled = screening != nil
        let footer = "While it's on, other callers hear their phone company's message that the call can't be completed, and can't leave voicemail, and their numbers wait in Blocked numbers until you allow them. Keypad contacts with a phone number and numbers approved for phone drop-in can always ring. Withheld numbers are always blocked. Calls are matched by caller ID, which can be faked. Calls from the Porch app aren't affected."
        return group("Phone calls", footer: footer, rows: [toggleRow("Block unknown callers", detail: detail, block), list])
    }
    private func messagesGroup(_ state: FamilyAdminState?) -> UIView {
        let messagesOn = UISwitch(); messagesOn.isOn = state?.messagesEnabled != false
        messagesOn.addAction(UIAction { [weak self, weak messagesOn] _ in
            guard let self, let messagesOn else { return }
            Task { await self.perform("setMessages", ["enabled": messagesOn.isOn]) }
        }, for: .valueChanged)
        let waiting = state?.messages ?? []
        let held = waiting.filter { $0.held == true }.count
        let count = PorchStyle.label(waiting.isEmpty ? "None" : "\(waiting.count)", size: 18)
        let reviewText = UIStackView(arrangedSubviews: [PorchStyle.label("Review waiting messages", size: 18, color: PorchStyle.ink)])
        reviewText.axis = .vertical; reviewText.spacing = 2
        // Phone voicemail from numbers that aren't on the keypad waits for a caregiver's OK.
        if held > 0 { reviewText.addArrangedSubview(PorchStyle.label("\(held) need your OK", size: 15, color: PorchStyle.accent, weight: .semibold)) }
        let review = PorchListRow([reviewText, Self.singleLine(count)],
                                  label: waiting.isEmpty ? "No messages waiting" : held > 0 ? "Review waiting messages, \(waiting.count), \(held) need your OK" : "Review waiting messages, \(waiting.count)") { [weak self] in
            guard let self else { return }
            let queue = MessageQueueViewController(remote: self.remote, messages: waiting)
            queue.onChange = { [weak self] admin in if self?.remote != nil { self?.remoteState = admin }; self?.refresh() }
            self.navigationController?.pushViewController(queue, animated: true)
        }
        review.isEnabled = !waiting.isEmpty
        // Starting messages when someone sits down uses this iPad's camera, so it's set on the iPad itself.
        let autoplay = remote == nil ? [autoplayToggle(), autoplayHourRow("Starting at", \.startHour), autoplayHourRow("Until", \.endHour)] : []
        return group("Messages", footer: "Family members can send audio and video messages, or leave one when a call isn't answered. Phone callers who aren't answered can leave voicemail; if their number isn't saved on the keypad, it waits for a caregiver's OK. Messages wait here until played, and unplayed ones are removed after a week.", rows: [toggleRow("Allow family messages", messagesOn), review] + autoplay)
    }
    private func autoplayToggle() -> UIView {
        let on = UISwitch(); on.isOn = MessageAutoplay.load().enabled
        on.accessibilityIdentifier = "messages.autoplay"
        on.addAction(UIAction { [weak self, weak on] _ in
            guard let self, let on else { return }
            Task { @MainActor in
                if on.isOn, !(await AVCaptureDevice.requestAccess(for: .video)) {
                    on.setOn(false, animated: true)
                    showPorchError(FamilyServiceError(message: "Allow camera access in iPad Settings → Porch to start messages when someone is in front of the iPad.", status: 403), on: self.navigationController?.topViewController ?? self)
                    return
                }
                var settings = MessageAutoplay.load(); settings.enabled = on.isOn; settings.save()
                NotificationCenter.default.post(name: .porchMessageAutoplayChanged, object: nil)
            }
        }, for: .valueChanged)
        return toggleRow("Play when someone is in front of the iPad", detail: "The screen glows, says how many messages are waiting, then plays them. It uses the front camera only while messages are waiting, during the hours below; nothing is recorded or sent. After Not now or Stop, it waits 30 minutes unless a new message arrives.", on)
    }
    private func autoplayHourRow(_ title: String, _ hour: WritableKeyPath<MessageAutoplay, Int>) -> UIView {
        let stepper = UIStepper()
        stepper.minimumValue = Double(MessageAutoplay.hourRange.lowerBound); stepper.maximumValue = Double(MessageAutoplay.hourRange.upperBound)
        stepper.value = Double(MessageAutoplay.load()[keyPath: hour])
        stepper.accessibilityLabel = "Play messages \(title.lowercased())"
        let value = PorchStyle.label(Self.hourText(Int(stepper.value)), size: 18, color: PorchStyle.ink)
        stepper.accessibilityValue = value.text
        stepper.addAction(UIAction { [weak stepper, weak value] _ in
            guard let stepper else { return }
            var settings = MessageAutoplay.load(); settings[keyPath: hour] = Int(stepper.value); settings.save()
            value?.text = Self.hourText(Int(stepper.value)); stepper.accessibilityValue = value?.text
            NotificationCenter.default.post(name: .porchMessageAutoplayChanged, object: nil)
        }, for: .valueChanged)
        return listRow([PorchStyle.label(title, size: 18, color: PorchStyle.ink), UIView(), value, stepper])
    }
    private static func hourText(_ hour: Int) -> String {
        let formatter = DateFormatter(); formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date())
    }
    /// The caregiver PIN beside who can use it from their own phone.
    private func caregiverGroup(_ state: FamilyAdminState?) -> UIView {
        let caregivers = (state?.people ?? []).filter { $0.caregiver == true }.map(\.name)
        let text = UIStackView(arrangedSubviews: [
            PorchStyle.label("Family caregivers", size: 18, color: PorchStyle.ink),
            PorchStyle.label(caregivers.isEmpty ? "None yet" : ListFormatter.localizedString(byJoining: caregivers), size: 15),
        ])
        text.axis = .vertical; text.spacing = 2
        var rows: [UIView] = [listRow([text])]
        if remote == nil {
            let lock = UIImageView(image: UIImage(systemName: "lock.rotation")); lock.tintColor = PorchStyle.accent
            lock.setContentHuggingPriority(.required, for: .horizontal)
            rows.append(PorchListRow([lock, PorchStyle.label("Change caregiver PIN", size: 18, color: PorchStyle.ink)], label: "Change caregiver PIN") { [weak self] in
                self?.navigationController?.pushViewController(ChangeCaregiverPINViewController(), animated: true)
            })
        }
        let footer = remote == nil
            ? "The PIN opens caregiver settings on this iPad. Family caregivers also use it to manage this page from their own phone. Turn on caregiver mode for a person in Family."
            : "Keypad numbers and contacts, call preferences, the display and the caregiver PIN can only be changed on the bedside iPad."
        return group("Caregiver access", footer: footer, rows: rows)
    }
    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> UIView {
        let button = PorchStyle.button(title, symbol: symbol, filled: false)
        button.contentHorizontalAlignment = .leading
        button.configuration?.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    /// Keeps a short trailing label or button on one line at its natural width.
    static func singleLine<View: UIView>(_ view: View) -> View {
        (view as? UILabel)?.numberOfLines = 1
        (view as? UIButton)?.titleLabel?.numberOfLines = 1
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }
    /// Their photo, or initials, in a fixed circle. It never stretches, so a row's text column takes the spare width.
    static func avatar(_ name: String, photo: Data? = nil, size: CGFloat = 44) -> UIView {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let badge = circle(size: size)
        if let image = RecipientAppearance.photo(photo) {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill; view.clipsToBounds = true; view.layer.cornerRadius = size / 2
            view.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: badge.leadingAnchor), view.trailingAnchor.constraint(equalTo: badge.trailingAnchor),
                                         view.topAnchor.constraint(equalTo: badge.topAnchor), view.bottomAnchor.constraint(equalTo: badge.bottomAnchor)])
            return badge
        }
        let label = UILabel()
        label.text = initials
        label.font = .systemFont(ofSize: size * 0.36, weight: .semibold)
        label.textColor = PorchStyle.accent
        center(label, in: badge)
        return badge
    }
    private static func circle(size: CGFloat) -> UIView {
        let circle = UIView()
        circle.backgroundColor = PorchStyle.accent.withAlphaComponent(0.12)
        circle.layer.cornerRadius = size / 2
        circle.isAccessibilityElement = false
        NSLayoutConstraint.activate([circle.widthAnchor.constraint(equalToConstant: size), circle.heightAnchor.constraint(equalToConstant: size)])
        circle.setContentHuggingPriority(.required, for: .horizontal)
        return circle
    }
    private static func center(_ view: UIView, in circle: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(view)
        NSLayoutConstraint.activate([view.centerXAnchor.constraint(equalTo: circle.centerXAnchor), view.centerYAnchor.constraint(equalTo: circle.centerYAnchor)])
    }
    fileprivate func requestMedia(video: Bool) async -> Bool {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        let camera = video ? await AVCaptureDevice.requestAccess(for: .video) : true
        guard microphone && camera else {
            showPorchError(FamilyServiceError(message: "Allow microphone\(video ? " and camera" : "") access in iPad Settings before enabling drop-in.", status: 403), on: navigationController?.topViewController ?? self)
            return false
        }
        return true
    }
    /// The PIN for the next caregiver request; nil (and locked) once a phone's caregiver session has ended.
    private func caregiverPIN() -> String? {
        guard remote != nil else { return NativeCallSettings.caregiverCode }
        guard let active = RemoteCaregiverSession.shared.activePIN else { lock(nil); return nil }
        return active
    }
    @discardableResult fileprivate func perform(_ action: String, _ values: [String: Any] = [:]) async -> Bool {
        guard !busy, let credential, let pin = caregiverPIN() else { return false }
        busy = true; defer { busy = false }
        do {
            let response = try await FamilyService(credential).send(action, values, pin: pin)
            FamilyCoordinator.shared.update(response)
            if let admin = response.admin { remoteState = admin }
            refresh()
            return true
        } catch {
            // A changed PIN, withdrawn approval or lockout ends a phone's caregiver session.
            if remote != nil, let failure = error as? FamilyServiceError, [401, 403, 429].contains(failure.status) { lock(error); return false }
            if action != "setHouseholdName" { refresh() }; showPorchError(error, on: navigationController?.topViewController ?? self)
            return false
        }
    }
    /// Uploads a photo a caregiver chose for a family member, then shows it in place of theirs.
    fileprivate func chooseOverridePhoto(_ data: Data, for memberID: String) async {
        guard !busy, let credential, let pin = caregiverPIN() else { return }
        busy = true
        let photo: [String: String]
        do { photo = try await FamilyPhotos.shared.upload(data, action: "overridePhotoUpload", values: ["memberID": memberID], credential: credential, pin: pin); busy = false }
        catch {
            busy = false
            if remote != nil, let failure = error as? FamilyServiceError, [401, 403, 429].contains(failure.status) { lock(error) }
            else { showPorchError(error, on: navigationController?.topViewController ?? self) }
            return
        }
        await perform("setMemberOverride", ["memberID": memberID, "photo": photo])
    }
    /// The bedside downloads everyone's photo itself; a caregiver's phone fetches one when it's shown.
    fileprivate func loadPhoto(of person: FamilyPerson) {
        guard let remote, let id = person.photoID, !FamilyPhotos.shared.store.contains(id), let pin = RemoteCaregiverSession.shared.activePIN else { return }
        FamilyPhotos.shared.load(id, action: "caregiverProfilePhoto", values: ["memberID": person.id], credential: remote, pin: pin)
    }
    private func showInvite() {
        let invite = FamilyInviteViewController(); invite.remote = remote
        invite.onAdminChanged = { [weak self] admin in if self?.remote != nil, let admin { self?.remoteState = admin }; self?.refresh() }
        navigationController?.pushViewController(invite, animated: true)
    }
    private func showPhoneDropIn() {
        let approve = PhoneDropInViewController(); approve.remote = remote
        approve.onSaved = { [weak self] admin in if self?.remote != nil, let admin { self?.remoteState = admin }; self?.refresh() }
        navigationController?.pushViewController(approve, animated: true)
    }
    private func showBlockedCallers() {
        let screen = BlockedCallersViewController(admin: self)
        blockedScreen = screen
        navigationController?.pushViewController(screen, animated: true)
    }
    private func showPerson(_ id: String) {
        let screen = FamilyPersonViewController(personID: id, admin: self)
        personScreen = screen
        navigationController?.pushViewController(screen, animated: true)
    }
}

fileprivate extension FamilyPerson {
    var status: String { online ? "Porch is open on their device" : canReceiveCalls == true ? "Porch calls can ring while their device is locked" : "Their device is offline" }
    var shortStatus: String { online ? "Porch is open" : canReceiveCalls == true ? "Can ring while locked" : "Offline" }
    var dropInModes: String? {
        permissions.audio && permissions.video ? "Audio and video" : permissions.audio ? "Audio" : permissions.video ? "Video" : nil
    }
    /// Their ordinary calls drop in, as the drop-in types they're approved for.
    var callsDropIn: Bool { autoDropIn == true && dropInModes != nil }
    /// A one-line summary for the family list; nil when they can only make ordinary calls.
    var access: String? {
        let parts = [dropInModes.map { "\($0) drop-in" }, callsDropIn ? "Calls drop in" : nil, caregiver == true ? "Caregiver" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One family member's name, photo, drop-in and caregiver access, opened from Family & drop-in.
final class FamilyPersonViewController: CaregiverFormViewController {
    private let personID: String
    private weak var admin: FamilyAdminViewController?
    private let content = UIStackView()
    /// Kept across redraws, which happen whenever anything in the family changes.
    private let overrideName = UITextField()
    private var editedName: String?
    private var renderAfterEditing = false
    private var shownPhoto: String?
    private lazy var chooser = PhotoChooser(presenter: self) { [weak self] data in
        guard let self, let admin = self.admin else { return }
        guard let data else { showPorchError(FamilyServiceError(message: "That photo couldn't be opened. Please choose another photo.", status: 400), on: self); return }
        Task { await admin.chooseOverridePhoto(data, for: self.personID) }
    }
    init(personID: String, admin: FamilyAdminViewController) {
        self.personID = personID; self.admin = admin; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(personID:admin:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        content.axis = .vertical; content.spacing = 24
        form.addArrangedSubview(content)
        overrideName.autocapitalizationType = .words
        overrideName.accessibilityIdentifier = "person.overrideName"
        overrideName.addAction(UIAction { [weak self] _ in self?.editedName = self?.overrideName.text }, for: .editingChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(photoMayHaveLoaded), name: .porchFamilyChanged, object: nil)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func photoMayHaveLoaded() {
        let id = admin?.current?.people.first { $0.id == personID }?.photoID
        if let id, id != shownPhoto, FamilyPhotos.shared.store.contains(id) { render() }
    }
    override func textFieldDidEndEditing(_ textField: UITextField) {
        super.textFieldDidEndEditing(textField)
        if renderAfterEditing { renderAfterEditing = false; render() }
    }
    /// Redrawn after every change, including one another caregiver made.
    func render() {
        guard isViewLoaded else { return }
        // Waits while the caregiver types a name, so the keyboard doesn't close.
        guard !overrideName.isFirstResponder else { renderAfterEditing = true; return }
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let admin, let state = admin.current, let person = state.people.first(where: { $0.id == personID }) else {
            // Removed here or by another caregiver.
            if navigationController?.topViewController === self { navigationController?.popViewController(animated: true) }
            return
        }
        let isMe = person.id == admin.myID
        title = person.name
        let status = PorchStyle.label(isMe ? "\(person.status). You're using this phone." : person.status, size: 17)
        status.textAlignment = .center
        let photo = FamilyPhotos.shared.data(for: person.photoID)
        shownPhoto = photo == nil ? nil : person.photoID
        if photo == nil { admin.loadPhoto(of: person) }
        let header = UIStackView(arrangedSubviews: [FamilyAdminViewController.avatar(person.name, photo: photo, size: 96), status])
        header.axis = .vertical; header.alignment = .center; header.spacing = 10
        content.addArrangedSubview(header)
        content.addArrangedSubview(appearanceGroup(person, admin: admin))
        let audio = UISwitch(); audio.isOn = person.permissions.audio
        let video = UISwitch(); video.isOn = person.permissions.video
        for toggle in [audio, video] {
            toggle.addAction(UIAction { [weak self, weak admin, weak audio, weak video] _ in
                guard let self, let admin, let audio, let video else { return }
                Task {
                    if admin.remote == nil, audio.isOn || video.isOn { guard await admin.requestMedia(video: video.isOn) else { self.render(); return } }
                    await admin.perform("setPermissions", ["memberID": person.id, "permissions": ["audio": audio.isOn, "video": video.isOn]])
                }
            }, for: .valueChanged)
        }
        // Their Audio call and Video call drop in too, but only as the drop-ins approved above.
        // The switch stays usable when that approval is later removed, so a saved choice can be turned off.
        let callsApproved = person.permissions.audio || person.permissions.video
        let calls = UISwitch(); calls.isOn = person.autoDropIn == true
        calls.isEnabled = callsApproved || person.autoDropIn == true
        calls.accessibilityIdentifier = "person.autoDropIn"
        calls.addAction(UIAction { [weak self, weak admin, weak calls] _ in
            guard let self, let admin, let calls else { return }
            Task {
                if admin.remote == nil, calls.isOn { guard await admin.requestMedia(video: person.permissions.video) else { self.render(); return } }
                await admin.perform("setAutoDropIn", ["memberID": person.id, "enabled": calls.isOn])
            }
        }, for: .valueChanged)
        let callsDetail = person.permissions.audio && person.permissions.video ? "Their audio and video calls drop in too."
            : person.permissions.audio ? "Their audio calls drop in too. Video calls ring."
            : person.permissions.video ? "Their video calls drop in too. Audio calls ring."
            : person.autoDropIn == true ? "Saved. It applies once audio or video drop-in is on."
            : "Turn on audio or video drop-in first."
        let dropInFooter = state.dropInEnabled
            ? "Connects without anyone answering, after a spoken announcement and five-second countdown. Their ordinary calls ring for Answer, unless Drop in when they call is on and Porch is open on the bedside iPad."
            : "Drop-ins are paused for everyone. Turn on Allow approved drop-ins in Family and drop-in."
        content.addArrangedSubview(group("Drop-in", footer: dropInFooter, rows: [toggleRow("Audio drop-in", audio), toggleRow("Video drop-in", video), toggleRow("Drop in when they call", detail: callsDetail, calls)]))
        let caregiver = UISwitch(); caregiver.isOn = person.caregiver == true
        caregiver.isEnabled = !isMe
        caregiver.addAction(UIAction { [weak admin, weak caregiver] _ in
            guard let admin, let caregiver else { return }
            Task { await admin.perform("setCaregiver", ["memberID": person.id, "enabled": caregiver.isOn]) }
        }, for: .valueChanged)
        let caregiverFooter = isMe ? "Another caregiver can change your caregiver access." : "Lets them manage Family and drop-in from their own phone with the caregiver PIN."
        content.addArrangedSubview(group("Caregiver mode", footer: caregiverFooter, rows: [toggleRow("Caregiver mode", caregiver)]))
        guard !isMe else { return }
        let remove = PorchStyle.button("Remove access", symbol: "person.crop.circle.badge.minus", filled: false)
        remove.configuration?.baseForegroundColor = .systemRed
        remove.addAction(UIAction { [weak self, weak admin] _ in
            let alert = UIAlertController(title: "Remove \(person.name)'s access?", message: "Their device will need a new invitation to call this Porch again.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in Task { await admin?.perform("revoke", ["memberID": person.id]) } })
            self?.present(alert, animated: true)
        }, for: .touchUpInside)
        content.addArrangedSubview(remove)
    }
    /// A caregiver's name and photo for this person replace the ones they chose, everywhere Porch shows them.
    private func appearanceGroup(_ person: FamilyPerson, admin: FamilyAdminViewController) -> UIView {
        let theirs = person.profile?.name ?? person.invitedName ?? person.name
        overrideName.text = editedName ?? person.override?.name
        let saveName = PorchStyle.button("Save", symbol: "checkmark")
        saveName.accessibilityLabel = "Save name"
        saveName.addAction(UIAction { [weak self, weak admin] _ in
            guard let self, let admin else { return }
            self.view.endEditing(true)
            let name = self.overrideName.text ?? ""
            Task { if await admin.perform("setMemberOverride", ["memberID": person.id, "name": name]) { self.editedName = nil; self.render() } }
        }, for: .touchUpInside)
        let nameRow = listRow(field(overrideName, title: "Name on Porch", placeholder: theirs), trailing: FamilyAdminViewController.singleLine(saveName), alignedToBottom: true)
        let chosen = person.override?.photoID != nil
        let photoStatus = chosen ? "Showing a photo a caregiver chose." : person.profile?.photoID != nil ? "Showing the photo they chose." : "They haven't added a photo."
        let choose = rowButton(chosen ? "Choose a different photo" : "Choose a photo for them", symbol: "photo")
        chooser.attach(to: choose)
        var rows: [UIView] = [nameRow, listRow([PorchStyle.label(photoStatus, size: 16)]), choose]
        if chosen {
            let restore = rowButton(person.profile?.photoID != nil ? "Use their own photo" : "Remove this photo", symbol: "arrow.uturn.backward")
            restore.addAction(UIAction { [weak admin] _ in Task { await admin?.perform("setMemberOverride", ["memberID": person.id, "photo": NSNull()]) } }, for: .touchUpInside)
            rows.append(restore)
        }
        let footer = "Leave the name blank to use theirs (now “\(theirs)”). A name or photo you choose replaces theirs on the bedside Porch, for calls, drop-ins and messages."
        return group("Name and photo", footer: admin.remote == nil ? footer + " A name or photo saved on a keypad number still comes first on that key." : footer, rows: rows)
    }
    private func rowButton(_ title: String, symbol: String) -> UIButton {
        let button = PorchStyle.button(title, symbol: symbol, filled: false)
        button.contentHorizontalAlignment = .leading
        button.configuration?.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        return button
    }
}

/// The numbers turned away while unknown callers are blocked, and the ones a caregiver allowed, opened from Family & drop-in.
final class BlockedCallersViewController: CaregiverFormViewController {
    private weak var admin: FamilyAdminViewController?
    private let content = UIStackView()
    init(admin: FamilyAdminViewController) { self.admin = admin; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(admin:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Blocked numbers"
        hideKeyboardControl()
        content.axis = .vertical; content.spacing = 24
        form.addArrangedSubview(content)
        render()
    }
    /// Redrawn after every change, including calls blocked meanwhile and changes another caregiver made.
    func render() {
        guard isViewLoaded else { return }
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let admin, let screening = admin.current?.callScreening else { return }
        let time = DateFormatter(); time.dateStyle = .short; time.timeStyle = .short; time.doesRelativeDateFormatting = true
        let when = { (seconds: TimeInterval) in time.string(from: Date(timeIntervalSince1970: seconds)) }
        var blocked: [UIView] = screening.blocked.map { caller in
            let number = PhoneNumberNormalization.display(caller.number)
            let calls = caller.calls == 1 ? "Called \(when(caller.lastCallAt))" : "Called \(caller.calls) times · last \(when(caller.lastCallAt))"
            let allow = PorchStyle.button("Allow", symbol: "checkmark.circle", filled: false)
            allow.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 4)
            allow.accessibilityLabel = "Allow \(number)"
            allow.addAction(UIAction { [weak admin] _ in Task { await admin?.perform("setCallerAllowed", ["number": caller.number, "allowed": true]) } }, for: .touchUpInside)
            return listRow(Self.text(number, calls), trailing: FamilyAdminViewController.singleLine(allow))
        }
        if blocked.isEmpty {
            blocked.append(listRow([PorchStyle.label(screening.enabled ? "No blocked calls." : "Turn on Block unknown callers to block numbers that aren't on the keypad.", size: 16)]))
        } else {
            let clear = PorchStyle.button("Clear this list", symbol: "trash", filled: false)
            clear.configuration?.baseForegroundColor = .systemRed
            clear.contentHorizontalAlignment = .leading
            clear.configuration?.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
            clear.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
            clear.addAction(UIAction { [weak self, weak admin] _ in
                let alert = UIAlertController(title: "Clear blocked numbers?", message: "They stay blocked. A number that calls again is listed again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in Task { await admin?.perform("clearBlockedCallers") } })
                self?.present(alert, animated: true)
            }, for: .touchUpInside)
            blocked.append(clear)
        }
        content.addArrangedSubview(group("Blocked", footer: "Newest first. An allowed number rings Porch like a keypad contact, and can leave voicemail for your review.", rows: blocked))
        var allowed: [UIView] = screening.allowed.map { caller in
            let number = PhoneNumberNormalization.display(caller.number)
            let remove = PorchStyle.button("Remove", symbol: "minus.circle", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 4)
            remove.accessibilityLabel = "Remove \(number) from allowed numbers"
            remove.addAction(UIAction { [weak admin] _ in Task { await admin?.perform("setCallerAllowed", ["number": caller.number, "allowed": false]) } }, for: .touchUpInside)
            return listRow(Self.text(number, "Allowed \(when(caller.allowedAt))"), trailing: FamilyAdminViewController.singleLine(remove))
        }
        if allowed.isEmpty { allowed.append(listRow([PorchStyle.label("None yet. Allow a blocked number to let it ring.", size: 16)])) }
        content.addArrangedSubview(group("Allowed", footer: "These numbers can ring although they aren't on the keypad. A removed number is blocked again.", rows: allowed))
    }
    private static func text(_ title: String, _ detail: String) -> UIView {
        let text = UIStackView(arrangedSubviews: [PorchStyle.label(title, size: 18, color: PorchStyle.ink), PorchStyle.label(detail, size: 15)])
        text.axis = .vertical; text.spacing = 2
        return text
    }
}

/// Approves one telephone number for audio drop-in when it calls the household's Porch number.
final class PhoneDropInViewController: CaregiverFormViewController, CNContactPickerDelegate {
    static let explanation = "While approved drop-ins are on and Porch is open on the bedside iPad, these numbers can call this Porch's phone number and connect with audio after the spoken announcement and five-second countdown, without anyone answering. Only calls their phone company verifies drop in, which covers most US mobile numbers; other calls, including withheld numbers, ring for a normal answer."
    /// Set when approving from caregiver mode on a family phone.
    var remote: FamilyCredential?
    var onSaved: ((FamilyAdminState?) -> Void)?
    private let personName = UITextField(), phone = UITextField()
    private let save = PorchStyle.button("Approve audio drop-in", symbol: "phone.badge.plus")
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Phone drop-in"
        personName.autocapitalizationType = .words
        phone.keyboardType = .phonePad; phone.textContentType = .telephoneNumber
        let contacts = PorchStyle.button("Choose from Contacts", symbol: "person.crop.circle", filled: false)
        contacts.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        form.addArrangedSubview(section("Who can drop in by phone?", detail: Self.explanation, views: [
            field(personName, title: "Their name", placeholder: "For example, David"),
            field(phone, title: "Their phone number", placeholder: "+14158676937", helper: "Include + and the country code for international numbers. Other numbers use this device's region (\(PhoneNumberNormalization.deviceRegion)). The name is spoken in the announcement."),
            contacts, save,
        ]))
        save.addTarget(self, action: #selector(approve), for: .touchUpInside)
    }
    @objc private func pickContact() {
        view.endEditing(true)
        let picker = CNContactPickerViewController()
        picker.overrideUserInterfaceStyle = .light
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
        present(picker, animated: true)
    }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
        personName.text = CNContactFormatter.string(from: property.contact, style: .fullName)
        guard let number = property.value as? CNPhoneNumber else { return }
        do { phone.text = try PhoneNumberNormalization.e164(number.stringValue) }
        catch { picker.dismiss(animated: true) { [weak self] in if let self { showPorchError(error, on: self) } } }
    }
    @objc private func approve() {
        view.endEditing(true)
        guard let credential = remote ?? PorchDevice.credential(for: .bedside) else { return }
        let pin: String
        if remote != nil {
            guard let active = RemoteCaregiverSession.shared.activePIN else { navigationController?.popToRootViewController(animated: true); return }
            pin = active
        } else { pin = NativeCallSettings.caregiverCode }
        save.isEnabled = false
        Task { [weak self] in
            guard let self else { return }; defer { self.save.isEnabled = true }
            do {
                let number = try PhoneNumberNormalization.e164(self.phone.text ?? "")
                // A drop-in answers on the bedside iPad, so only it can grant its own microphone.
                if self.remote == nil {
                    let microphone = await AVCaptureDevice.requestAccess(for: .audio)
                    guard microphone else { throw FamilyServiceError(message: "Allow microphone access in iPad Settings before approving drop-in.", status: 403) }
                }
                let response = try await FamilyService(credential).send("setPhoneDropIn", ["number": number, "name": self.personName.text ?? "", "enabled": true], pin: pin)
                FamilyCoordinator.shared.update(response)
                self.onSaved?(response.admin)
                self.navigationController?.popViewController(animated: true)
            } catch { showPorchError(error, on: self) }
        }
    }
}

/// Opens caregiver mode on an approved family phone with the household's caregiver PIN.
final class RemoteCaregiverPINViewController: CaregiverFormViewController {
    private let pin = UITextField()
    private let submit = PorchStyle.button("Open caregiver mode", symbol: "lock.fill")
    private var task: Task<Void, Never>?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Caregiver mode"
        pin.isSecureTextEntry = true; pin.keyboardType = .numberPad
        pin.accessibilityIdentifier = "caregiver.pin"
        form.addArrangedSubview(section("Caregiver PIN", detail: "Enter the six-digit PIN set on the bedside iPad. Caregiver mode locks after ten idle minutes or when you leave Porch.", views: [field(pin, title: "Six-digit PIN", placeholder: "Enter six digits"), submit]))
        submit.addTarget(self, action: #selector(unlock), for: .touchUpInside)
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if isMovingFromParent { task?.cancel() } }
    @objc private func unlock() {
        guard task == nil, let credential = PorchDevice.credential(for: .family) else { return }
        let value = pin.text ?? ""
        guard value.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
            showPorchError(FamilyServiceError(message: "Enter six digits.", status: 400), on: self); return
        }
        submit.isEnabled = false; view.endEditing(true)
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.submit.isEnabled = true }
            do {
                let response = try await FamilyService(credential).send("verifyPIN", pin: value)
                FamilyCoordinator.shared.update(response)
                RemoteCaregiverSession.shared.begin(pin: value)
                self.pin.text = nil
                let admin = FamilyAdminViewController(remote: credential, state: response.admin)
                guard let navigation = self.navigationController else { return }
                navigation.setViewControllers(Array(navigation.viewControllers.dropLast()) + [admin], animated: true)
            } catch { if !Task.isCancelled { showPorchError(error, on: self) } }
        }
    }
}

final class FamilyInviteViewController: CaregiverFormViewController {
    var prefilledName: String?
    var returnsToPerson = false
    /// Set when inviting from caregiver mode on a family phone.
    var remote: FamilyCredential?
    var onCreated: ((String, String) -> Void)?
    /// The caregiver state returned with the new invitation; caregiver mode on a phone shows its own copy.
    var onAdminChanged: ((FamilyAdminState?) -> Void)?
    private let personName = UITextField()
    private let audio = UISwitch()
    private let video = UISwitch()
    private let caregiver = UISwitch()
    private let create = PorchStyle.button("Create invitation", symbol: "person.badge.plus")
    private var invitationLink: URL?
    private var invitationExpiry: TimeInterval = 0
    private let inviteHint = PorchStyle.label("", size: 17)
    @objc private func finishedInvite() { navigationController?.popViewController(animated: true) }
    private func shareInvite(_ link: URL) {
        let share = UIActivityViewController(activityItems: ["Join our Porch. This private invitation works once and expires in 24 hours.", link], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = create
        share.popoverPresentationController?.sourceRect = create.bounds
        present(share, animated: true)
    }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Invite someone"
        personName.text = prefilledName
        func row(_ title: String, _ toggle: UISwitch) -> UIView {
            toggle.onTintColor = PorchStyle.accent
            let row = UIStackView(arrangedSubviews: [PorchStyle.label(title, size: 18, color: PorchStyle.ink), toggle]); row.alignment = .center; row.spacing = 16; return row
        }
        form.addArrangedSubview(section("Who is this invitation for?", views: [field(personName, title: "Their name", placeholder: "For example, Ethan")]))
        form.addArrangedSubview(section("Approve drop-in", detail: "Both are off by default. Ordinary calls will still be available. You can change these permissions or remove access later.", views: [row("Audio drop-in", audio), row("Video drop-in", video)]))
        form.addArrangedSubview(section("Caregiver mode", detail: "Lets them manage family access from their own phone after entering the caregiver PIN. Off by default.", views: [row("Caregiver mode", caregiver)]))
        form.addArrangedSubview(inviteHint)
        form.addArrangedSubview(create); create.addTarget(self, action: #selector(createInvite), for: .touchUpInside)
    }
    @objc private func createInvite() {
        if let invitationLink, invitationExpiry > Date().timeIntervalSince1970 { shareInvite(invitationLink); return }
        guard let credential = remote ?? PorchDevice.credential(for: .bedside) else { return }
        let pin: String
        if remote != nil {
            guard let active = RemoteCaregiverSession.shared.activePIN else { navigationController?.popToRootViewController(animated: true); return }
            pin = active
        } else { pin = NativeCallSettings.caregiverCode }
        create.isEnabled = false; view.endEditing(true)
        Task { [weak self] in
            guard let self else { return }; defer { self.create.isEnabled = true }
            do {
                // Drop-in answers on the bedside iPad, so only it can grant its own camera and microphone.
                if self.remote == nil, self.audio.isOn || self.video.isOn {
                    let microphone = await AVCaptureDevice.requestAccess(for: .audio)
                    let camera = self.video.isOn ? await AVCaptureDevice.requestAccess(for: .video) : true
                    guard microphone && camera else {
                        throw FamilyServiceError(message: "Grant microphone and camera access before approving drop-in.", status: 403)
                    }
                }
                let response = try await FamilyService(credential).send("createInvite", ["name": self.personName.text ?? "", "permissions": ["audio": self.audio.isOn, "video": self.video.isOn], "caregiver": self.caregiver.isOn], pin: pin)
                guard let code = response.code, let invitationID = response.invitationID else { throw FamilyInvitation.InvitationError.invalid }
                FamilyCoordinator.shared.update(response); self.onCreated?(invitationID, self.personName.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                self.onAdminChanged?(response.admin)
                let link = FamilyInvitation.url(origin: credential.origin, code: code)
                self.invitationLink = link; self.invitationExpiry = response.expiresAt ?? 0
                self.personName.isEnabled = false; self.audio.isEnabled = false; self.video.isEnabled = false; self.caregiver.isEnabled = false
                self.create.configuration?.title = "Share invitation again"
                self.inviteHint.text = !self.returnsToPerson ? "Invitation ready. Share it, then tap Done." : "Invitation ready. Share it, tap Done, then save the person. Their app connects automatically when they accept."
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(self.finishedInvite))
                self.shareInvite(link)
            } catch { showPorchError(error, on: self) }
        }
    }
}

final class IncomingFamilyCallViewController: UIViewController {
    let session: FamilyCallSession
    var call: FamilyCallRecord { session.call }
    var credential: FamilyCredential { session.credential }
    var onAnswer: ((FamilyCallSession) -> Void)?
    var onDismiss: (() -> Void)?
    private let countdown = UILabel()
    private let callerContact: CallContact?
    private let callerPhoto: Data?
    private let answer = PorchStyle.button("Answer", symbol: "phone.fill")
    private let keypadHint = PorchStyle.label("", size: 18, color: PorchStyle.nightSecondary)
    private let audio: IncomingCallAudioPlaying
    private var timer: Timer?
    private var remaining = 5
    private var announcementFinished = false
    private var requiresManualAnswer = false
    private var alertStarted = false
    private var answering = false
    private var keypad = CallTrigger()
    private var callKey = IncomingCallKey()
    private var holdTimer: Timer?
    private var systemOwned: Bool { SystemIncomingCalls.shared.owns(call.id) }
    override var canBecomeFirstResponder: Bool { true }
    private func handle(_ decision: IncomingCallKey.Decision?) {
        guard !answering else { return }
        if decision == .answer { accept() } else if decision == .decline { reject() }
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let digit = key.keypadDigit,
                  (try? CallSlots.load())?.action(for: digit) == .callControl else { unhandled.insert(press); continue }
            let code = Int(key.keyCode.rawValue)
            guard keypad.keyDown(code), !answering else { continue }
            handle(callKey.begin(code, dropIn: call.kind == "dropIn" && !requiresManualAnswer))
            if !answering {
                holdTimer?.invalidate()
                holdTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                    guard let self else { return }; self.handle(self.callKey.held(code))
                }
            }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key {
                let code = Int(key.keyCode.rawValue)
                keypad.keyUp(code)
                if let decision = callKey.release(code) { holdTimer?.invalidate(); handle(decision) }
            }
        }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        holdTimer?.invalidate(); callKey.cancel(); keypad.resetKeys(); super.pressesCancelled(presses, with: event)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); audio.stop(); timer?.invalidate(); holdTimer?.invalidate(); callKey.cancel(); keypad.resetKeys(); resignFirstResponder()
    }
    init(call: FamilyCallRecord, credential: FamilyCredential, snapshot: FamilySnapshot? = nil, slots savedSlots: CallSlots? = nil, audio: IncomingCallAudioPlaying? = nil) {
        let slots = savedSlots ?? (try? CallSlots.load()) ?? CallSlots()
        let state = snapshot ?? FamilyCoordinator.shared.state
        callerContact = credential.role == .bedside ? state.flatMap { slots.incomingContact(for: call, in: $0) } : nil
        // Someone without a keypad number still shows the photo Porch has for them.
        callerPhoto = callerContact?.photoData ?? (credential.role == .bedside && call.source != "phone"
            ? FamilyPhotos.shared.data(for: state?.people.first { $0.id == call.from }?.photoID) : nil)
        let name = callerContact?.name ?? call.callerName
        session = FamilyCallSession(credential: credential, call: call, peerName: name, peerContact: callerContact)
        self.audio = audio ?? PorchIncomingAudio(); super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen; isModalInPresentation = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(call:credential:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); overrideUserInterfaceStyle = .dark; view.backgroundColor = PorchStyle.night
        let name = PorchStyle.label(session.peerName, size: 48, color: PorchStyle.nightText, weight: .semibold)
        name.textAlignment = .center
        countdown.font = PorchStyle.font(28); countdown.textColor = PorchStyle.nightText; countdown.numberOfLines = 0; countdown.textAlignment = .center
        answer.configuration?.title = BedsideText.string(call.mode == .video ? "Answer video call" : "Answer audio call")
        answer.addTarget(self, action: #selector(accept), for: .touchUpInside)
        let decline = PorchStyle.button(BedsideText.string(call.kind == "dropIn" ? "Don't connect" : "Decline"), symbol: "phone.down.fill")
        decline.configuration?.baseBackgroundColor = UIColor(red: 0.68, green: 0.19, blue: 0.19, alpha: 1)
        decline.addTarget(self, action: #selector(reject), for: .touchUpInside)
        answer.isHidden = call.kind == "dropIn"
        updateKeypadHint()
        let hint = keypadHint
        hint.textAlignment = .center
        var identity: [UIView] = [name, countdown, hint]
        if RecipientAppearance.photo(callerPhoto) != nil {
            let photo = RecipientAppearance.photoView(callerPhoto)
            let container = UIView()
            photo.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(photo)
            let width = photo.widthAnchor.constraint(equalTo: container.widthAnchor)
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                photo.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                photo.topAnchor.constraint(equalTo: container.topAnchor),
                photo.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                photo.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
                photo.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
                photo.heightAnchor.constraint(equalTo: photo.widthAnchor), width,
            ])
            identity.insert(container, at: 0)
        }
        let stack = UIStackView(arrangedSubviews: identity); stack.axis = .vertical; stack.spacing = 28
        let controls = UIStackView(arrangedSubviews: [answer, decline]); controls.axis = .vertical; controls.spacing = 16
        let scroll = UIScrollView()
        [stack, controls, scroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll); view.addSubview(controls); scroll.addSubview(stack)
        for button in [answer, decline] { button.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -24),
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24), controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24), controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        let centered = stack.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor); centered.priority = .defaultHigh; centered.isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(checkCall), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(checkSystemCall), name: .porchSystemCallChanged, object: nil)
        BedsideText.applyAccessibilityLanguage(to: view)
        updateCountdown()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keypad.resetKeys(); becomeFirstResponder()
        guard !alertStarted else { return }; alertStarted = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-incoming-video") || ProcessInfo.processInfo.arguments.contains("--preview-incoming-call") { announcementFinished = true; updateCountdown(); return }
        #endif
        if call.kind == "dropIn" {
            updateCountdown()
            audio.announce(name: session.peerName, video: call.mode == .video, language: BedsideText.language) { [weak self] success in
                guard let self, !self.answering, self.view.window != nil, UIApplication.shared.applicationState == .active else { return }
                if success {
                    self.announcementFinished = true; self.remaining = 5; self.updateCountdown()
                    self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.advanceCountdown() }
                } else {
                    self.requiresManualAnswer = true; self.updateKeypadHint()
                    self.answer.isHidden = false
                    self.countdown.text = BedsideText.string("The sound couldn't play. Tap Answer to connect.")
                }
            }
        } else if !systemOwned && !audio.ring() { countdown.text = BedsideText.string("The sound couldn't play. Tap Answer to connect.") }
    }
    deinit { holdTimer?.invalidate(); timer?.invalidate(); NotificationCenter.default.removeObserver(self) }
    func advanceCountdown() {
        guard announcementFinished, !answering else { return }
        remaining -= 1; updateCountdown()
        if remaining <= 0 { timer?.invalidate(); accept() }
    }
    private func updateKeypadHint() {
        let key = ((try? CallSlots.load()) ?? CallSlots()).digit(for: .callControl).map(CallSlots.symbol(for:))
        keypadHint.text = key.map { call.kind == "dropIn" && !requiresManualAnswer ? BedsideText.string("Press %@ to stop this drop-in.", $0) : BedsideText.string("Tap %@ to answer. Hold %@ to decline.", $0, $0) } ?? ""
    }
    private func updateCountdown() {
        if call.kind == "dropIn" {
            countdown.text = announcementFinished ? BedsideText.string(call.mode == .video ? "Video drop-in\nConnecting in %d…" : "Audio drop-in\nConnecting in %d…", max(0, remaining)) : BedsideText.string(call.mode == .video ? "Announcing video drop-in…" : "Announcing audio drop-in…")
        } else { countdown.text = BedsideText.string(call.mode == .video ? "Incoming video call" : "Incoming audio call") }
    }
    @objc private func checkCall() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-incoming-video") || ProcessInfo.processInfo.arguments.contains("--preview-incoming-call") { return }
        #endif
        guard !answering else { return }
        if let current = FamilyCoordinator.shared.state?.call, current.id == call.id && current.state != "ended" { return }
        timer?.invalidate(); audio.stop(); dismiss(animated: true, completion: onDismiss)
    }
    @objc private func accept() {
        guard !answering, UIApplication.shared.applicationState == .active, view.window != nil else { return }
        if systemOwned {
            answering = true; answer.isEnabled = false; audio.stop()
            SystemIncomingCalls.shared.requestAnswer()
            return
        }
        if call.kind == "dropIn" && (AVCaptureDevice.authorizationStatus(for: .audio) != .authorized || (call.mode == .video && AVCaptureDevice.authorizationStatus(for: .video) != .authorized)) { reject(); return }
        answering = true; answer.isEnabled = false; timer?.invalidate(); audio.stop()
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await FamilyService(self.credential).send("acceptCall", ["callID": self.call.id, "available": true])
                guard UIApplication.shared.applicationState == .active, self.view.window != nil else { await self.session.end(); return }
                FamilyCoordinator.shared.update(result)
                let session = FamilyCallSession(credential: self.credential, call: result.state?.call ?? self.call, peerName: self.session.peerName, peerContact: self.session.peerContact)
                self.dismiss(animated: false) { self.onAnswer?(session) }
            } catch { self.answering = false; self.answer.isEnabled = true; await self.session.end(); self.dismiss(animated: true, completion: self.onDismiss) }
        }
    }
    @objc private func reject() {
        timer?.invalidate(); audio.stop(); answering = true
        if systemOwned { SystemIncomingCalls.shared.requestEnd() }
        else { Task { await session.end() } }
        dismiss(animated: true, completion: onDismiss)
    }
    @objc private func enteredBackground() {
        if systemOwned { audio.stop(); dismiss(animated: false, completion: onDismiss) }
        else { reject() }
    }
    @objc private func checkSystemCall() {
        if call.kind == "call" && !SystemIncomingCalls.shared.hasCall {
            audio.stop(); dismiss(animated: false, completion: onDismiss)
        }
    }
}

final class ChangeCaregiverPINViewController: CaregiverFormViewController {
    private let current = UITextField(), newPIN = UITextField(), confirm = UITextField()
    private let save = PorchStyle.button("Save new PIN", symbol: "lock.fill")
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Change caregiver PIN"
        for field in [current, newPIN, confirm] { field.isSecureTextEntry = true; field.keyboardType = .numberPad }
        form.addArrangedSubview(section("Your six-digit PIN", views: [field(current, title: "Current PIN", placeholder: "Six digits"), field(newPIN, title: "New PIN", placeholder: "Six digits"), field(confirm, title: "Confirm new PIN", placeholder: "Repeat the new PIN"), save]))
        save.addTarget(self, action: #selector(change), for: .touchUpInside)
    }
    @objc private func change() {
        let value = newPIN.text ?? ""
        guard value.range(of: "^[0-9]{6}$", options: .regularExpression) != nil, value == confirm.text else { showPorchError(FamilyServiceError(message: "Enter the same six digits in both new PIN fields.", status: 400), on: self); return }
        guard let profile = PorchDevice.credential(for: .bedside) else { return }
        save.isEnabled = false
        Task { [weak self] in
            guard let self else { return }; defer { self.save.isEnabled = true }
            do {
                _ = try await FamilyService(profile).send("setCaregiverPIN", ["pin": value], pin: self.current.text ?? "")
                try NativeCallSettings.writeSecret(Data(value.utf8), account: "porch.contact-setup-code")
                self.navigationController?.popViewController(animated: true)
            } catch { showPorchError(error, on: self) }
        }
    }
}

extension IncomingFamilyCallViewController: Cell2JackDigitReceiving {
    func receiveCell2JackDigit(_ digit: Int) -> String {
        guard !answering, (try? CallSlots.load())?.action(for: digit) == .callControl else { return "incoming key ignored" }
        // A serial DTMF report is a tap, never an inferred long press.
        if call.kind == "dropIn" && !requiresManualAnswer { reject(); return "drop-in cancelled" }
        accept(); return "answer requested"
    }
}
