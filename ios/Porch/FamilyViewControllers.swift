import UIKit
import AVFoundation
import PorchCore

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
        let busy: Bool?
        let error: String?
        let paired: Bool
        let starting: Bool
        let messages: Bool
        let held: Int
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
        refresh()
    }
    @objc private func refreshPushStatus() { displayed = nil; refresh() }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func newInvitation() { showPairing() }
    @objc private func showDeviceSettings() {
        let paired = PorchDevice.credential(for: .family) != nil
        let sheet = UIAlertController(title: "Device settings", message: nil, preferredStyle: .actionSheet)
        if paired {
            sheet.addAction(UIAlertAction(title: "Caregiver mode", style: .default) { [weak self] _ in self?.openCaregiverMode() })
            sheet.addAction(UIAlertAction(title: "Join a different family", style: .default) { [weak self] _ in self?.confirmNewFamily() })
        }
        sheet.addAction(UIAlertAction(title: "Use as the bedside Porch", style: .default) { [weak self] _ in self?.confirmBedside() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }
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
        let next = Presentation(household: state?.householdID, people: state?.people ?? [], permissions: state?.me.permissions, dropIn: state?.dropInEnabled, busy: state?.busy, error: coordinator.error, paired: PorchDevice.credential(for: .family) != nil, starting: starting, messages: state?.messagesEnabled != false, held: state?.heldMessages ?? 0)
        guard next != displayed else { return }
        displayed = next
        // Once paired, joining another family lives in Device settings so it isn't done by accident.
        navigationItem.leftBarButtonItem = next.paired ? nil : invitationButton
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
        let sent = PorchStyle.button("Your messages", symbol: "tray.full", filled: false)
        sent.addAction(UIAction { [weak self] _ in self?.navigationController?.pushViewController(SentMessagesViewController(), animated: true) }, for: .touchUpInside)
        people.addArrangedSubview(sent)
        if !state.dropInEnabled { people.addArrangedSubview(PorchStyle.label("Drop-in is paused on the bedside device.")) }
        else if !state.me.permissions.audio && !state.me.permissions.video { people.addArrangedSubview(PorchStyle.label("The caregiver hasn't enabled drop-in for this device. You can still make an ordinary call.")) }
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

final class FamilyPairingViewController: CaregiverFormViewController {
    var invitation: URL?
    private let link = UITextField()
    private let join = PorchStyle.button("Join family", symbol: "person.badge.plus")
    private var task: Task<Void, Never>?
    override func viewDidLoad() {
        let replacing = PorchDevice.credential(for: .family) != nil
        super.viewDidLoad(); title = replacing ? "Join a different family" : "Join your family"
        link.text = invitation?.absoluteString; link.keyboardType = .URL
        form.addArrangedSubview(section("Your Porch invite", detail: "Ask the caregiver to invite you to the family Porch. It can be used once and expires after 15 minutes.", views: [field(link, title: "Porch invitation", placeholder: "Paste the complete invitation link"), join]))
        if replacing { form.addArrangedSubview(PorchStyle.label("Joining removes this phone from \(FamilyCoordinator.shared.state?.householdName ?? "your current family").", size: 17, color: PorchStyle.ink)) }
        form.addArrangedSubview(PorchStyle.label("Your invitation sets your name and access. Audio and video drop-in are approved separately by the caregiver. No calling code is needed."))
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
    private let remote: FamilyCredential?
    private var remoteState: FamilyAdminState?
    private let householdName = UITextField()
    private let details = UIStackView()
    private var busy = false
    private var appeared = false
    private var locked = false
    private var displayed: FamilyAdminState?
    private var credential: FamilyCredential? { remote ?? PorchDevice.credential(for: .bedside) }
    private var current: FamilyAdminState? {
        if remote != nil { return remoteState }
        return FamilyCoordinator.shared.state.map { FamilyAdminState(householdName: $0.householdName, dropInEnabled: $0.dropInEnabled, people: $0.people, messagesEnabled: $0.messagesEnabled, messages: $0.messages) }
    }
    init(remote: FamilyCredential? = nil, state: FamilyAdminState? = nil) {
        self.remote = remote; remoteState = state; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(remote:state:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = remote == nil ? "Family & drop-in" : "Caregiver mode"
        if remote != nil { navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Family mode", style: .done, target: self, action: #selector(leaveCaregiverMode)) }
        details.axis = .vertical; details.spacing = 20
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
        guard let credential else {
            details.addArrangedSubview(PorchStyle.label("Return to the clock and open caregiver mode to finish setting up this bedside device.")); return
        }
        let state = current
        displayed = state
        let myID = credential.credential.split(separator: ".").first.map { String($0) }
        householdName.text = state?.householdName ?? "Your loved one"
        householdName.autocapitalizationType = .words
        let saveName = PorchStyle.button("Save name", symbol: "checkmark")
        saveName.addAction(UIAction { [weak self] _ in
            guard let self else { return }; self.view.endEditing(true)
            Task { await self.perform("setHouseholdName", ["name": self.householdName.text ?? ""]) }
        }, for: .touchUpInside)
        details.addArrangedSubview(section("Who is this Porch for?", detail: "Family members will see this name when calling or dropping in.", views: [field(householdName, title: "Display name", placeholder: "Your loved one"), saveName]))
        householdName.autocapitalizationType = .words
        let master = UISwitch(); master.isOn = state?.dropInEnabled == true; master.onTintColor = PorchStyle.accent
        let masterRow = UIStackView(arrangedSubviews: [PorchStyle.label("Allow approved drop-ins", size: 18, color: PorchStyle.ink), master]); masterRow.alignment = .center; masterRow.spacing = 16
        master.addAction(UIAction { [weak self, weak master] _ in
            guard let self, let master else { return }
            Task {
                if master.isOn && self.remote == nil {
                    guard await self.requestMedia(video: state?.people.contains(where: { $0.permissions.video }) == true) else { master.isOn = false; return }
                }
                await self.perform("setDropIn", ["enabled": master.isOn])
            }
        }, for: .valueChanged)
        details.addArrangedSubview(section("Automatic answering", detail: remote == nil ? nil : "Drop-ins connect only if the bedside iPad allows microphone and camera access.", views: [masterRow]))
        let messagesOn = UISwitch(); messagesOn.isOn = state?.messagesEnabled != false; messagesOn.onTintColor = PorchStyle.accent
        messagesOn.addAction(UIAction { [weak self, weak messagesOn] _ in
            guard let self, let messagesOn else { return }
            Task { await self.perform("setMessages", ["enabled": messagesOn.isOn]) }
        }, for: .valueChanged)
        let messagesRow = UIStackView(arrangedSubviews: [PorchStyle.label("Allow family messages", size: 18, color: PorchStyle.ink), messagesOn]); messagesRow.alignment = .center; messagesRow.spacing = 16
        let waiting = state?.messages ?? []
        let held = waiting.filter { $0.held == true }.count
        let review = PorchStyle.button(waiting.isEmpty ? "No messages waiting" : held > 0 ? "Review waiting messages (\(waiting.count), \(held) need your OK)" : "Review waiting messages (\(waiting.count))", symbol: "tray.full", filled: held > 0)
        review.isEnabled = !waiting.isEmpty
        review.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let queue = MessageQueueViewController(remote: self.remote, messages: waiting)
            queue.onChange = { [weak self] admin in if self?.remote != nil { self?.remoteState = admin }; self?.refresh() }
            self.navigationController?.pushViewController(queue, animated: true)
        }, for: .touchUpInside)
        details.addArrangedSubview(section("Messages", detail: "Family members can send audio and video messages, or leave one when a call isn't answered. Phone callers who aren't answered can leave voicemail; if their number isn't saved on the keypad, it waits for a caregiver's OK. Messages wait here until played, and unplayed ones are removed after a week.", views: [messagesRow, review]))
        let invite = PorchStyle.button("Invite a family member", symbol: "person.badge.plus")
        invite.addAction(UIAction { [weak self] _ in self?.showInvite() }, for: .touchUpInside)
        details.addArrangedSubview(invite)
        for person in state?.people ?? [] {
            let isMe = person.id == myID
            let audio = UISwitch(); audio.isOn = person.permissions.audio; audio.onTintColor = PorchStyle.accent
            let video = UISwitch(); video.isOn = person.permissions.video; video.onTintColor = PorchStyle.accent
            let caregiver = UISwitch(); caregiver.isOn = person.caregiver == true; caregiver.onTintColor = PorchStyle.accent
            caregiver.isEnabled = !isMe
            func row(_ title: String, _ toggle: UISwitch) -> UIView {
                let row = UIStackView(arrangedSubviews: [PorchStyle.label(title, size: 17, color: PorchStyle.ink), toggle]); row.alignment = .center; row.spacing = 16; return row
            }
            for toggle in [audio, video] {
                toggle.addAction(UIAction { [weak self, weak audio, weak video] _ in
                    guard let self, let audio, let video else { return }
                    Task {
                        if self.remote == nil, audio.isOn || video.isOn { guard await self.requestMedia(video: video.isOn) else { self.refresh(); return } }
                        await self.perform("setPermissions", ["memberID": person.id, "permissions": ["audio": audio.isOn, "video": video.isOn]])
                    }
                }, for: .valueChanged)
            }
            caregiver.addAction(UIAction { [weak self, weak caregiver] _ in
                guard let self, let caregiver else { return }
                Task { await self.perform("setCaregiver", ["memberID": person.id, "enabled": caregiver.isOn]) }
            }, for: .valueChanged)
            var views = [row("Audio drop-in", audio), row("Video drop-in", video), row("Caregiver mode", caregiver)]
            if !isMe {
                let remove = PorchStyle.button("Remove access", symbol: "person.crop.circle.badge.minus", filled: false)
                remove.configuration?.baseForegroundColor = .systemRed
                remove.addAction(UIAction { [weak self] _ in
                    let alert = UIAlertController(title: "Remove \(person.name)'s access?", message: "Their device will need a new invitation to call this Porch again.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                    alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in Task { await self?.perform("revoke", ["memberID": person.id]) } })
                    self?.present(alert, animated: true)
                }, for: .touchUpInside)
                views.append(remove)
            }
            let status = person.online ? "Porch is open on their device" : person.canReceiveCalls == true ? "Porch calls can ring while their device is locked" : "Their device is offline"
            details.addArrangedSubview(section(isMe ? "\(person.name) (this phone)" : person.name, detail: isMe ? "\(status). Another caregiver can change your caregiver access." : status, views: views))
        }
        let cancel = PorchStyle.button("Cancel unused invitations", filled: false)
        cancel.addAction(UIAction { [weak self] _ in Task { await self?.perform("cancelInvites") } }, for: .touchUpInside)
        details.addArrangedSubview(cancel)
        if remote == nil {
            let changePIN = PorchStyle.button("Change caregiver PIN", symbol: "lock.rotation", filled: false)
            changePIN.addAction(UIAction { [weak self] _ in self?.navigationController?.pushViewController(ChangeCaregiverPINViewController(), animated: true) }, for: .touchUpInside)
            details.addArrangedSubview(changePIN)
            details.addArrangedSubview(PorchStyle.label("Caregiver mode lets a family member manage this page from their own phone with the PIN. To put a family member on a keypad number, edit that person and choose Link their Porch app. Ordinary incoming calls require Answer; only approved drop-ins answer automatically."))
        } else {
            details.addArrangedSubview(PorchStyle.label("Keypad numbers, contacts, photos, call preferences, the display and the caregiver PIN can only be changed on the bedside iPad."))
        }
    }
    private func requestMedia(video: Bool) async -> Bool {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        let camera = video ? await AVCaptureDevice.requestAccess(for: .video) : true
        guard microphone && camera else {
            showPorchError(FamilyServiceError(message: "Allow microphone\(video ? " and camera" : "") access in iPad Settings before enabling drop-in.", status: 403), on: self)
            return false
        }
        return true
    }
    private func perform(_ action: String, _ values: [String: Any] = [:]) async {
        guard !busy, let credential else { return }
        let pin: String
        if remote != nil {
            guard let active = RemoteCaregiverSession.shared.activePIN else { lock(nil); return }
            pin = active
        } else { pin = NativeCallSettings.caregiverCode }
        busy = true; defer { busy = false }
        do {
            let response = try await FamilyService(credential).send(action, values, pin: pin)
            FamilyCoordinator.shared.update(response)
            if let admin = response.admin { remoteState = admin }
            refresh()
        } catch {
            // A changed PIN, withdrawn approval or lockout ends a phone's caregiver session.
            if remote != nil, let failure = error as? FamilyServiceError, [401, 403, 429].contains(failure.status) { lock(error); return }
            if action != "setHouseholdName" { refresh() }; showPorchError(error, on: self)
        }
    }
    private func showInvite() {
        let invite = FamilyInviteViewController(); invite.remote = remote
        invite.onCreated = { [weak self] _, _ in self?.refresh() }
        navigationController?.pushViewController(invite, animated: true)
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
        let share = UIActivityViewController(activityItems: ["Join our Porch. This private invitation works once and expires in 15 minutes.", link], applicationActivities: nil)
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
            guard let key = press.key, let digit = CallTrigger.slot(for: Int(key.keyCode.rawValue)),
                  key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty,
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
        if RecipientAppearance.photo(callerContact?.photoData) != nil {
            let photo = RecipientAppearance.photoView(callerContact?.photoData)
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
        let digit = ((try? CallSlots.load()) ?? CallSlots()).digit(for: .callControl)
        keypadHint.text = digit.map { call.kind == "dropIn" && !requiresManualAnswer ? BedsideText.string("Press %d to stop this drop-in.", $0) : BedsideText.string("Tap %d to answer. Hold %d to decline.", $0, $0) } ?? ""
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
