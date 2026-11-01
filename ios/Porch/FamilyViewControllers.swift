import UIKit
import AVFoundation
import ContactsUI
import MessageUI
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
final class FamilyHomeViewController: CaregiverFormViewController, CNContactViewControllerDelegate, MFMessageComposeViewControllerDelegate {
    private let status = PorchStyle.label("", size: 17)
    /// Under each bedside's name: someone is at the iPad, or how long ago someone was. It changes by the minute,
    /// so it's updated in place rather than rebuilding the screen. One for each family, by this phone's ID there.
    private var attendance: [String: UILabel] = [:]
    private let people = UIStackView()
    private var starting = false
    /// One family as this screen shows it. A phone in more than one, such as both sets of parents, shows each under its
    /// name; with only one, the screen looks as it always has.
    private struct Family: Equatable {
        let id: String
        let name: String?
        let household: String?
        let people: [FamilyPerson]
        let permissions: DropInPermissions?
        let dropIn: Bool?
        let busy: Bool?
        let error: String?
        let removed: Bool
        let messages: Bool
        let held: Int
        let unheard: Int
        /// The bedside's own phone number, which anyone can call it on.
        let number: String?
    }
    private struct Presentation: Equatable {
        let families: [Family]
        let starting: Bool
        /// The photo Porch shows for this phone, once it's on this device.
        let photo: String?
    }
    private var displayed: Presentation?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Porch"
        people.axis = .vertical; people.spacing = 20
        status.textAlignment = .center
        form.addArrangedSubview(status); form.addArrangedSubview(people)
        navigationItem.rightBarButtonItem = settingsButton(photo: nil)
        hideKeyboardControl()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPushStatus), name: .porchSystemCallChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openReceivedMessages(_:)), name: .porchOpenReceivedMessages, object: nil)
        refresh()
    }
    /// A message notification says which family it's from: each family knows this phone by its own ID.
    @objc private func openReceivedMessages(_ notification: Notification) {
        if let family = PorchDevice.family(memberID: notification.userInfo?["recipientID"] as? String) { FamilyCoordinator.shared.select(family) }
        openMessages()
    }
    @objc private func openMessages() {
        guard PorchDevice.credential(for: .family) != nil, let navigationController else { return }
        if navigationController.presentedViewController != nil { navigationController.dismiss(animated: false) }
        navigationController.popToRootViewController(animated: false)
        navigationController.pushViewController(MessageThreadViewController(), animated: true)
    }
    /// The screens past this one show the family chosen last.
    private func choose(_ family: FamilyCredential, then show: () -> Void) {
        FamilyCoordinator.shared.select(family); show()
    }
    @objc private func refreshPushStatus() { displayed = nil; refresh() }
    #if DEBUG
    private var previewShown = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !previewShown else { return }
        previewShown = true
        if ProcessInfo.processInfo.arguments.contains("--preview-messages") { openMessages() }
        if ProcessInfo.processInfo.arguments.contains("--preview-profile") { showSettings() }
    }
    #endif
    deinit { NotificationCenter.default.removeObserver(self) }
    /// This phone's photo, as the bedside shows it. It opens this phone's settings.
    private func settingsButton(photo: String?) -> UIBarButtonItem {
        let image = RecipientAppearance.cardPhoto(FamilyPhotos.shared.data(for: photo), width: 32) ?? UIImage(systemName: "person.crop.circle")
        let item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(showSettings))
        item.accessibilityLabel = "Settings"
        item.accessibilityIdentifier = "family.profile"
        return item
    }
    @objc private func showSettings() { navigationController?.pushViewController(FamilyProfileViewController(), animated: true) }
    func openCaregiverMode() {
        guard FamilyCoordinator.shared.state?.me.caregiver == true else {
            let alert = UIAlertController(title: "Caregiver mode isn't on for you", message: "Ask the caregiver to turn it on for you.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true); return
        }
        navigationController?.pushViewController(RemoteCaregiverPINViewController(), animated: true)
    }
    func showPairing(invitation: URL? = nil) {
        let pairing = FamilyPairingViewController(); pairing.invitation = invitation
        navigationController?.pushViewController(pairing, animated: true)
    }
    private func attendanceLabel(for family: FamilyCredential) -> UILabel {
        if let label = attendance[family.deviceID] { return label }
        let label = PorchStyle.label("", size: 17, weight: .semibold)
        label.textAlignment = .center
        attendance[family.deviceID] = label
        return label
    }
    @objc private func refresh() {
        guard isViewLoaded else { return }
        let coordinator = FamilyCoordinator.shared
        let credentials = PorchDevice.families
        let several = credentials.count > 1
        let families = credentials.map { credential -> Family in
            let link = coordinator.link(for: credential), state = link?.state
            return Family(id: credential.deviceID, name: several ? PorchDevice.familyName(credential) ?? "Family" : nil, household: state?.householdID, people: state?.people ?? [],
                          permissions: state?.me.permissions, dropIn: state?.dropInEnabled, busy: state?.busy, error: link?.error, removed: link?.accessRemoved == true,
                          messages: state?.messagesEnabled != false, held: state?.heldMessages ?? 0, unheard: state?.newMessages ?? 0, number: state?.porchNumber)
        }
        let next = Presentation(families: families, starting: starting, photo: coordinator.state?.me.photoID.flatMap { FamilyPhotos.shared.store.contains($0) ? $0 : nil })
        for credential in credentials {
            let link = coordinator.link(for: credential), label = attendanceLabel(for: credential)
            // Without a fresh check-in the last one's time stands still, so it would look current forever.
            let attended = link?.error != nil ? nil : link?.state.flatMap { BedsideAttendance.text(attendedAt: $0.bedsideAttendedAt, now: $0.serverTime) }
            label.text = attended; label.isHidden = attended == nil
            label.textColor = link?.state.map { BedsideAttendance.isPresent(attendedAt: $0.bedsideAttendedAt, now: $0.serverTime) } == true ? PorchStyle.accent : PorchStyle.secondary
        }
        guard next != displayed else { return }
        displayed = next
        navigationItem.rightBarButtonItem = settingsButton(photo: next.photo)
        people.arrangedSubviews.forEach { people.removeArrangedSubview($0); $0.removeFromSuperview() }
        attendance = attendance.filter { id, _ in credentials.contains { $0.deviceID == id } }
        guard !credentials.isEmpty else {
            status.text = "Ask the caregiver to invite you."; status.isHidden = false
            let join = PorchStyle.button("Join a family", symbol: "person.badge.plus")
            join.addAction(UIAction { [weak self] _ in self?.showPairing() }, for: .touchUpInside)
            people.addArrangedSubview(join); return
        }
        people.spacing = several ? 40 : 20
        // Ringing while locked is what's expected, so only its absence is mentioned. With one family its problems show
        // here too; with several, each shows its own.
        let push = SystemIncomingCalls.shared.pushReady ? nil : "Keep Porch open so you don't miss calls."
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .denied ? "Allow microphone access in iPhone Settings → Porch to answer calls." : nil
        status.text = microphone ?? (several ? push : families[0].error ?? push)
        status.isHidden = status.text == nil
        for (credential, family) in zip(credentials, families) {
            let block = UIStackView(); block.axis = .vertical; block.spacing = 20
            people.addArrangedSubview(block)
            if let name = family.name {
                let heading = PorchStyle.label(name, size: 26, color: PorchStyle.ink, weight: .bold)
                heading.accessibilityTraits = .header
                block.addArrangedSubview(heading)
                if let error = family.error { block.addArrangedSubview(PorchStyle.label(error, size: 17)) }
            }
            // A family that removed this phone can't reach it again, so what it last showed, such as its messages, is
            // left out. Taking it off leaves the others as they are.
            if family.removed {
                let remove = PorchStyle.button(several ? "Remove \(family.name ?? "this family") from this phone" : "Remove this family from this phone", symbol: "minus.circle", filled: false)
                remove.configuration?.baseForegroundColor = .systemRed
                remove.addAction(UIAction { [weak self] _ in self?.confirmRemoval(of: credential, named: family.name) }, for: .touchUpInside)
                block.addArrangedSubview(remove)
                continue
            }
            guard let state = coordinator.link(for: credential)?.state else {
                if family.error == nil {
                    if several { block.addArrangedSubview(PorchStyle.label("Connecting…", size: 17)) }
                    else { status.text = "Connecting to your family…"; status.isHidden = false }
                }
                continue
            }
            // Phone voicemail from callers who aren't on the keypad waits for a caregiver.
            if family.held > 0 {
                let review = PorchStyle.button(family.held == 1 ? "1 phone voicemail needs your review" : "\(family.held) phone voicemails need your review", symbol: "exclamationmark.bubble.fill")
                review.accessibilityIdentifier = "family.heldVoicemail"
                review.addAction(UIAction { [weak self] _ in self?.choose(credential) { self?.openCaregiverMode() } }, for: .touchUpInside)
                block.addArrangedSubview(review)
            }
            // Left by the bedside when its call to this phone wasn't answered.
            let bedside = state.people.first { $0.role == .bedside }
            let from = bedside?.name ?? state.householdName
            // Both ways in one thread, like a text conversation. It sits with the bedside's other actions, under
            // Send a message, and stays even while sending is off so earlier messages can still be played.
            let thread = PorchStyle.button("Messages with \(from)", symbol: "bubble.left.and.bubble.right", filled: false)
            thread.accessibilityIdentifier = "family.messages"
            thread.addAction(UIAction { [weak self] _ in self?.choose(credential) { self?.openMessages() } }, for: .touchUpInside)
            if family.unheard > 0 {
                let play = PorchStyle.button(family.unheard == 1 ? "New message from \(from)" : "\(family.unheard) new messages from \(from)", symbol: "envelope.badge.fill")
                play.accessibilityIdentifier = "family.newMessages"
                play.addAction(UIAction { [weak self] _ in self?.choose(credential) { self?.openMessages() } }, for: .touchUpInside)
                block.addArrangedSubview(play)
            }
            for person in state.people {
                let availability = PorchStyle.label(person.online ? (state.busy ? "On a call" : "Porch is open") : "Porch isn't ready", size: 17)
                availability.textAlignment = .center
                var views: [UIView] = [availability] + (person.role == .bedside ? [attendanceLabel(for: credential)] : [])
                // Drop-in buttons this phone can't use, while drop-ins are paused or not approved for it, aren't shown.
                let dropIns: [(NativeCall.Mode, Bool)] = [(.voice, state.me.permissions.audio), (.video, state.me.permissions.video)]
                let calls: [(String, String, NativeCall.Mode, Bool)] = [("Audio call", "phone.fill", .voice, false), ("Video call", "video.fill", .video, false)]
                    + dropIns.filter { state.dropInEnabled && $0.1 }.map { mode, _ -> (String, String, NativeCall.Mode, Bool) in
                        mode == .voice ? ("Drop in with audio", "waveform", .voice, true) : ("Drop in with video", "video.badge.waveform", .video, true)
                    }
                for (title, symbol, mode, drop) in calls {
                    let button = PorchStyle.button(title, symbol: symbol, filled: !drop)
                    // While another family's call rings or is on, CallKit has it: a call from here would be cut off.
                    button.isEnabled = family.error == nil && person.online && !state.busy && !starting && !SystemIncomingCalls.shared.hasCall
                    button.addAction(UIAction { [weak self] _ in self?.call(person, mode: mode, dropIn: drop, in: credential) }, for: .touchUpInside)
                    views.append(button)
                }
                // Messages wait on the bedside device, so they don't need it to be open right now.
                if family.messages {
                    let message = PorchStyle.button("Send a message", symbol: "envelope.fill", filled: false)
                    message.addAction(UIAction { [weak self] _ in
                        self?.choose(credential) { self?.navigationController?.pushViewController(MessageComposerViewController(recipient: person.name), animated: true) }
                    }, for: .touchUpInside)
                    views.append(message)
                }
                if person.id == bedside?.id { views.append(thread) }
                block.addArrangedSubview(section(person.name, views: views))
            }
            // Without a bedside to show, the thread still has to be reachable.
            if bedside == nil { block.addArrangedSubview(thread) }
            // Anyone can call the bedside on its own number, from any phone.
            if let number = family.number {
                let shown = PorchStyle.label(PorchNumber.display(number), size: 28, color: PorchStyle.ink, weight: .bold)
                shown.textAlignment = .center; shown.accessibilityIdentifier = "family.porchNumber"
                let add = PorchStyle.button("Add to Contacts", symbol: "person.crop.circle.badge.plus", filled: false)
                add.accessibilityIdentifier = "family.addPorchNumber"
                add.addAction(UIAction { [weak self] _ in self?.addToContacts(number, name: from) }, for: .touchUpInside)
                let send = PorchStyle.button("Send by text", symbol: "message", filled: false)
                send.accessibilityIdentifier = "family.textPorchNumber"
                send.addAction(UIAction { [weak self, weak send] _ in self?.sendByText(number, name: from, from: send) }, for: .touchUpInside)
                block.addArrangedSubview(section("\(from)'s Porch number", detail: "Be sure to add this to your Contacts and share it with friends & loved ones.", views: [shown, add, send]))
            }
        }
    }
    /// A text with the bedside's Porch number, to whoever they choose. A device that can't text, such as an iPad
    /// without Messages, gets the share sheet instead.
    private func sendByText(_ number: String, name: String, from source: UIView?) {
        let note = "Here's \(name)'s Porch number: \(PorchNumber.display(number)). Call it from any phone to talk with \(name)."
        guard MFMessageComposeViewController.canSendText() else {
            let share = UIActivityViewController(activityItems: [note], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = source
            share.popoverPresentationController?.sourceRect = source?.bounds ?? .zero
            present(share, animated: true); return
        }
        let compose = MFMessageComposeViewController()
        compose.body = note
        compose.messageComposeDelegate = self
        present(compose, animated: true)
    }
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
    /// A new contact for the bedside's Porch number, which they can change before saving. Porch never reads Contacts.
    private func addToContacts(_ number: String, name: String) {
        let contact = CNMutableContact()
        contact.givenName = "\(name)'s Porch"
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: number))]
        let editor = CNContactViewController(forNewContact: contact)
        editor.delegate = self
        present(UINavigationController(rootViewController: editor), animated: true)
    }
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        viewController.dismiss(animated: true)
    }
    private func confirmRemoval(of family: FamilyCredential, named name: String?) {
        let alert = UIAlertController(title: "Remove \(name ?? "this family") from this phone?", message: "They've already removed this phone. To join again, you'll need a new invitation.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            do { try FamilyCoordinator.shared.forget(family) } catch { if let self { showPorchError(error, on: self) } }
        })
        present(alert, animated: true)
    }
    private func offerVoicemail(to name: String, title: String, in family: FamilyCredential) {
        guard view.window != nil, presentedViewController == nil, FamilyCoordinator.shared.state(for: family)?.messagesEnabled != false else {
            showPorchError(FamilyServiceError(message: title, status: 409), on: self); return
        }
        let alert = UIAlertController(title: title, message: "Leave a message? It waits on their Porch until they play it.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Leave a message", style: .default) { [weak self] _ in
            self?.choose(family) { self?.navigationController?.pushViewController(MessageComposerViewController(recipient: name, kind: "voicemail", startAudioImmediately: true), animated: true) }
        })
        present(alert, animated: true)
    }
    private func call(_ person: FamilyPerson, mode: NativeCall.Mode, dropIn: Bool, in family: FamilyCredential) {
        guard !starting, !SystemIncomingCalls.shared.hasCall else { return }; starting = true
        FamilyCoordinator.shared.select(family); refresh()
        Task { [weak self] in
            guard let self else { return }
            defer { self.starting = false; self.refresh() }
            do {
                let microphone = await AVCaptureDevice.requestAccess(for: .audio)
                let camera = mode == .video ? await AVCaptureDevice.requestAccess(for: .video) : true
                guard microphone && camera else { throw FamilyServiceError(message: "Allow Porch to use the microphone and camera in Settings before calling.", status: 403) }
                // Another family can start ringing during the permission prompt or this request. Placing the call anyway
                // runs both, and answering the incoming one closes this screen while its call stays connected.
                guard !SystemIncomingCalls.shared.hasCall else { return }
                let session = try await FamilyCoordinator.shared.startCall(to: person, mode: mode, dropIn: dropIn, in: family)
                guard self.view.window != nil, UIApplication.shared.applicationState == .active, !SystemIncomingCalls.shared.hasCall else { await session.end(); return }
                let screen = try NativeCallViewController.paired(session)
                screen.onUnanswered = { [weak self] in self?.offerVoicemail(to: person.name, title: "\(person.name) didn't answer", in: family) }
                self.present(screen, animated: true)
            } catch {
                if (error as? FamilyServiceError)?.code == "offline" { self.offerVoicemail(to: person.name, title: "\(person.name)'s Porch isn't available", in: family) }
                else { showPorchError(error, on: self) }
            }
        }
    }
}

final class FamilyPairingViewController: CaregiverFormViewController {
    var invitation: URL?
    private let link = UITextField()
    private let nickname = UITextField()
    private let join = PorchStyle.button("Join family", symbol: "person.badge.plus")
    private var task: Task<Void, Never>?
    /// Joining another family adds it: this phone stays in the ones it's already in, such as the other set of parents.
    private var adding: Bool { !PorchDevice.families.isEmpty }
    override func viewDidLoad() {
        let adding = self.adding
        super.viewDidLoad(); title = adding ? "Join another family" : "Join your family"
        link.text = invitation?.absoluteString; link.keyboardType = .URL
        var views: [UIView] = [field(link, title: "Porch invitation", placeholder: "Paste the complete invitation link")]
        if adding { views.append(field(nickname, title: "What do you call this family?", placeholder: "For example, Sarah's parents", helper: "Only on this phone, to tell your families apart.")) }
        views.append(join)
        form.addArrangedSubview(section("Your Porch invite", detail: "Paste the link the caregiver sent you. It works once, for 24 hours.", views: views))
        // `field` resets capitalization; a family's name is capitalized word by word.
        nickname.autocapitalizationType = .words
        // A family that removed this phone doesn't call it any more.
        let calling = PorchDevice.families.filter { FamilyCoordinator.shared.link(for: $0)?.accessRemoved != true }
        if adding, !calling.isEmpty { form.addArrangedSubview(PorchStyle.label("This phone will still get calls from \(Self.names(calling)).", size: 17, color: PorchStyle.ink)) }
        join.addTarget(self, action: #selector(pair), for: .touchUpInside)
    }
    /// "Lee family", "Lee family and Mom", "Lee family, Mom and Dad".
    private static func names(_ families: [FamilyCredential]) -> String {
        let names = families.map { PorchDevice.familyName($0) ?? "your family" }
        guard let last = names.last, names.count > 1 else { return names.first ?? "your family" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if isMovingFromParent { task?.cancel() } }
    private func askForName(of family: FamilyCredential, sharing name: String, numbered: String) {
        let alert = UIAlertController(title: "Another family here is called \(name)", message: "What do you call the one you just joined? Until you name it, it's \(numbered). Only on this phone.", preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "For example, Sarah's parents"; field.autocapitalizationType = .words }
        let done: () -> Void = { [weak self] in self?.navigationController?.popToRootViewController(animated: true) }
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel) { _ in done() })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            PorchDevice.setNickname(alert?.textFields?.first?.text, for: family)
            // The home screen and incoming calls use it too.
            NotificationCenter.default.post(name: .porchFamilyChanged, object: nil)
            done()
        })
        present(alert, animated: true)
    }
    @objc private func pair() {
        guard task == nil else { return }
        do {
            guard let url = URL(string: link.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else { throw FamilyInvitation.InvitationError.invalid }
            let invite = try FamilyInvitation(url: url, defaultOrigin: PorchDevice.defaultOrigin)
            let familyNickname = adding ? nickname.text : nil
            join.isEnabled = false; view.endEditing(true)
            task = Task { [weak self] in
                guard let self else { return }; defer { self.task = nil; self.join.isEnabled = true }
                do {
                    let pending = try PorchDevice.pending(role: .family, origin: invite.origin, invitation: invite.code)
                    // Reopening an invitation this phone already used returns the same identity, which doesn't add one.
                    // Which family an invitation is from is known only once it's claimed, and claiming one for a fifth
                    // family would use it up, so a new invitation from one of the four is turned away too.
                    let families = PorchDevice.families
                    guard families.count < FamilyNames.limit || families.contains(where: { $0.deviceID == pending.deviceID }) else {
                        throw FamilyServiceError(message: "This phone is in \(FamilyNames.limit) families, the most Porch allows. To join another, or to join one of these again with a new invitation, leave one in Settings first.", status: 409)
                    }
                    var registration = PorchDevice.registration(pending); registration["code"] = invite.code
                    let response = try await FamilyService(origin: invite.origin).send("claimInvite", registration)
                    guard let token = response.credential else { throw FamilyInvitation.InvitationError.invalid }
                    let joined = FamilyCredential(origin: invite.origin, credential: token, role: .family)
                    // A pairing that hasn't checked in since this phone began remembering households doesn't say which
                    // one it's in yet. Ask it once, so a new invitation from that family still replaces it.
                    for family in families where family.deviceID != joined.deviceID && family.origin == joined.origin
                        && FamilyCoordinator.shared.state(for: family) == nil && PorchDevice.householdID(family) == nil {
                        let values = PollOrder.next(["available": FamilyCoordinator.shared.canReceive()])
                        if let state = try? await FamilyService(family).send("poll", values).state { PorchDevice.noteHousehold(state, for: family) }
                    }
                    // A new invitation from a family this phone is already in replaces its old pairing there, as it
                    // always has. It leaves only once the family has accepted this phone again.
                    let replaced = families.filter { $0.deviceID != joined.deviceID && $0.origin == joined.origin && response.state?.householdID != nil
                        && (FamilyCoordinator.shared.state(for: $0)?.householdID ?? PorchDevice.householdID($0)) == response.state?.householdID }
                    for previous in replaced {
                        do { _ = try await FamilyService(previous).send("leaveHousehold") }
                        // Already removed, or its household is gone: nothing is left to leave.
                        catch let failure as FamilyServiceError where [401, 404].contains(failure.status) {}
                        // Keep the old pairing so Join can retry; reclaiming this invitation returns the same identity.
                        catch { throw FamilyServiceError(message: "Couldn't switch families. Check your internet and tap Join family again.", status: 503) }
                    }
                    try PorchDevice.save(joined)
                    if let state = response.state { PorchDevice.noteHousehold(state, for: joined) }
                    let kept = replaced.compactMap { PorchDevice.nickname($0) }.first
                    for previous in replaced { try PorchDevice.removeFamily(previous) }
                    if let name = familyNickname?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { PorchDevice.setNickname(name, for: joined) }
                    else if let kept { PorchDevice.setNickname(kept, for: joined) }
                    PorchDevice.select(joined)
                    FamilyCoordinator.shared.start()
                    // Two sets of parents are often both "Mom". Left unnamed, the new one is numbered, so ask now, while
                    // it's clear which one it is.
                    if let name = PorchDevice.unnumberedName(joined), let numbered = PorchDevice.familyName(joined), numbered != name {
                        self.askForName(of: joined, sharing: name, numbered: numbered)
                    } else { self.navigationController?.popToRootViewController(animated: true) }
                } catch { if !Task.isCancelled { showPorchError(error, on: self) } }
            }
        } catch { showPorchError(error, on: self) }
    }
}

/// The numbers turned away while unknown callers are blocked, and the ones a caregiver allowed, opened from Calls.
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
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: .porchCaregiverChanged, object: admin)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    /// Redrawn after every change, including calls blocked meanwhile and changes another caregiver made.
    @objc func render() {
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
                let alert = UIAlertController(title: "Clear blocked numbers?", message: "This only clears the list. The numbers stay blocked.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in Task { await admin?.perform("clearBlockedCallers") } })
                self?.present(alert, animated: true)
            }, for: .touchUpInside)
            blocked.append(clear)
        }
        content.addArrangedSubview(group("Blocked", rows: blocked))
        var allowed: [UIView] = screening.allowed.map { caller in
            let number = PhoneNumberNormalization.display(caller.number)
            let remove = PorchStyle.button("Remove", symbol: "minus.circle", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 4)
            remove.accessibilityLabel = "Remove \(number) from allowed numbers"
            remove.addAction(UIAction { [weak admin] _ in Task { await admin?.perform("setCallerAllowed", ["number": caller.number, "allowed": false]) } }, for: .touchUpInside)
            return listRow(Self.text(number, "Allowed \(when(caller.allowedAt))"), trailing: FamilyAdminViewController.singleLine(remove))
        }
        if allowed.isEmpty { allowed.append(listRow([PorchStyle.label("None yet.", size: 16)])) }
        content.addArrangedSubview(group("Allowed", rows: allowed))
    }
    private static func text(_ title: String, _ detail: String) -> UIView {
        let text = UIStackView(arrangedSubviews: [PorchStyle.label(title, size: 18, color: PorchStyle.ink), PorchStyle.label(detail, size: 15)])
        text.axis = .vertical; text.spacing = 2
        return text
    }
}

/// Calls to and from the bedside for the last 90 days, newest first and grouped by day. Opened from caregiver mode on
/// the bedside iPad, or from Caregiver mode on an approved family phone.
final class CallHistoryViewController: CaregiverFormViewController {
    /// Set when caregiver mode was opened from a family phone; nil on the bedside iPad.
    private let remote: FamilyCredential?
    private let content = UIStackView()
    private var task: Task<Void, Never>?
    private var credential: FamilyCredential? { remote ?? PorchDevice.credential(for: .bedside) }
    init(remote: FamilyCredential? = nil) { self.remote = remote; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(remote:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Call history"
        hideKeyboardControl()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reload))
        content.axis = .vertical; content.spacing = 28
        form.addArrangedSubview(content)
        reload()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { task?.cancel(); task = nil }
    }
    @objc private func reload() {
        guard task == nil else { return }
        guard let credential else { showMessage("Go back to the clock and open caregiver mode to finish setup."); return }
        // A phone's caregiver session ends after ten idle minutes; the bedside keeps its own PIN.
        let pin: String
        if remote != nil {
            guard let active = RemoteCaregiverSession.shared.activePIN else { navigationController?.popToRootViewController(animated: true); return }
            pin = active
        } else { pin = NativeCallSettings.caregiverCode }
        if content.arrangedSubviews.isEmpty { showMessage("Loading calls…") }
        task = Task { [weak self] in
            do {
                let response = try await FamilyService(credential).send("callHistory", [:], pin: pin)
                guard let self, !Task.isCancelled else { return }
                self.task = nil; self.render(response.calls ?? [])
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.task = nil
                // A changed PIN, withdrawn approval or lockout ends a phone's caregiver session.
                if self.remote != nil, let failure = error as? FamilyServiceError, [401, 403, 429].contains(failure.status),
                   let navigation = self.navigationController, let home = navigation.viewControllers.first {
                    RemoteCaregiverSession.shared.end()
                    CATransaction.begin()
                    CATransaction.setCompletionBlock { showPorchError(error, on: home) }
                    navigation.popToRootViewController(animated: true)
                    CATransaction.commit()
                    return
                }
                self.showMessage("Couldn't load call history. \(error.localizedDescription)", retry: true)
            }
        }
    }
    private func clear() { content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() } }
    private func showMessage(_ message: String, retry: Bool = false) {
        clear()
        content.addArrangedSubview(PorchStyle.label(message))
        guard retry else { return }
        let again = PorchStyle.button("Try again", symbol: "arrow.clockwise")
        again.addAction(UIAction { [weak self] _ in self?.reload() }, for: .touchUpInside)
        content.addArrangedSubview(again)
    }
    private func render(_ calls: [CallHistoryEntry]) {
        guard !calls.isEmpty else { showMessage("No calls yet."); return }
        clear()
        content.addArrangedSubview(PorchStyle.label("Last 90 days", size: 15))
        // The bedside names phone numbers saved on its keypad, as it does elsewhere.
        let slots = remote == nil ? (try? CallSlots.load()) : nil
        let calendar = Calendar.current
        let days = Dictionary(grouping: calls) { calendar.startOfDay(for: Date(timeIntervalSince1970: $0.startedAt)) }
        let day = DateFormatter(); day.dateStyle = .full; day.timeStyle = .none; day.doesRelativeDateFormatting = true
        let time = DateFormatter(); time.dateStyle = .none; time.timeStyle = .short
        for start in days.keys.sorted(by: >) {
            let rows = (days[start] ?? []).sorted { $0.startedAt > $1.startedAt }.map { row($0, slots: slots, time: time) }
            content.addArrangedSubview(group(day.string(from: start), rows: rows))
        }
    }
    private func row(_ call: CallHistoryEntry, slots: CallSlots?, time: DateFormatter) -> UIView {
        let number = call.number.map { PhoneNumberNormalization.display($0) }
        let keypadName = call.via == "phone" ? slots?.contact(forPhoneNumber: call.number)?.name : nil
        let saved = keypadName?.isEmpty == false ? keypadName : nil
        // A caller known only by their number shows it once, formatted.
        let name = saved ?? (call.name == call.number ? number ?? call.name : call.name)
        let details = [call.kindText, call.outcomeText, name == number ? nil : number].compactMap { $0 }.joined(separator: " · ")
        let video = call.via == "porch" && call.mode == .video
        let symbol = call.isIncoming ? (video ? "arrow.down.left.video" : "phone.arrow.down.left") : (video ? "arrow.up.right.video" : "phone.arrow.up.right")
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = call.isMissed ? .systemRed : PorchStyle.accent
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let text = UIStackView(arrangedSubviews: [PorchStyle.label(name, size: 18, color: call.isMissed ? .systemRed : PorchStyle.ink, weight: .medium), PorchStyle.label(details, size: 15)])
        text.axis = .vertical; text.spacing = 2
        let leading = UIStackView(arrangedSubviews: [icon, text]); leading.alignment = .center; leading.spacing = 12
        let when = FamilyAdminViewController.singleLine(PorchStyle.label(time.string(from: Date(timeIntervalSince1970: call.startedAt)), size: 15))
        let row = listRow(leading, trailing: when)
        row.isAccessibilityElement = true
        row.accessibilityLabel = [name, details, when.text ?? ""].joined(separator: ", ")
        return row
    }
}

/// Approves one telephone number for audio drop-in when it calls the household's Porch number.
final class PhoneDropInViewController: CaregiverFormViewController, CNContactPickerDelegate {
    /// Set when approving from caregiver mode on a family phone.
    var remote: FamilyCredential?
    var onSaved: ((FamilyAdminState?) -> Void)?
    private let personName = UITextField(), phone = UITextField()
    private let save = PorchStyle.button("Approve audio drop-in", symbol: "phone.badge.plus")
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Add a phone number"
        phone.keyboardType = .phonePad; phone.textContentType = .telephoneNumber
        let contacts = PorchStyle.button("Choose from Contacts", symbol: "person.crop.circle", filled: false)
        contacts.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        form.addArrangedSubview(section("Who can drop in by phone?", views: [
            field(personName, title: "Their name", placeholder: "For example, David"),
            field(phone, title: "Their phone number", placeholder: "+14158676937", helper: "Start international numbers with +."),
            contacts, save,
        ]))
        // `field` resets capitalization; a person's name is capitalized word by word.
        personName.autocapitalizationType = .words
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
        form.addArrangedSubview(section("Caregiver PIN", detail: "The PIN set on the bedside iPad.", views: [field(pin, title: "Six-digit PIN", placeholder: "Enter six digits"), submit]))
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
    /// What sharing an invitation sends: a note, then the link.
    static func shareItems(_ link: URL) -> [Any] {
        // A web link opens Porch, or shows how to get it first.
        let note = link.scheme == "https" ? "Join our Porch! Open this link on your phone. If you don't have Porch yet, it shows you how to get it. It works once, for 24 hours."
            : "Join our Porch! This link works once, for 24 hours."
        return [note, link]
    }
    private func shareInvite(_ link: URL) {
        let share = UIActivityViewController(activityItems: Self.shareItems(link), applicationActivities: nil)
        share.popoverPresentationController?.sourceView = create
        share.popoverPresentationController?.sourceRect = create.bounds
        present(share, animated: true)
    }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Invite someone"
        personName.text = prefilledName
        // Family can drop in unless the caregiver turns it off for them.
        audio.isOn = true; video.isOn = true
        func row(_ title: String, _ toggle: UISwitch) -> UIView {
            toggle.onTintColor = PorchStyle.accent
            let row = UIStackView(arrangedSubviews: [PorchStyle.label(title, size: 18, color: PorchStyle.ink), toggle]); row.alignment = .center; row.spacing = 16; return row
        }
        form.addArrangedSubview(section("Who is this invitation for?", views: [field(personName, title: "Their name", placeholder: "For example, Ethan")]))
        form.addArrangedSubview(section("Approve drop-in", detail: "Lets them connect without anyone answering.", views: [row("Audio drop-in", audio), row("Video drop-in", video)]))
        form.addArrangedSubview(section("Caregiver mode", detail: "Can change settings from their phone with the PIN.", views: [row("Caregiver mode", caregiver)]))
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
                let link = FamilyInvitation.url(origin: credential.origin, code: code, defaultOrigin: PorchDevice.defaultOrigin)
                self.invitationLink = link; self.invitationExpiry = response.expiresAt ?? 0
                self.personName.isEnabled = false; self.audio.isEnabled = false; self.video.isEnabled = false; self.caregiver.isEnabled = false
                self.create.configuration?.title = "Share invitation again"
                self.inviteHint.text = !self.returnsToPerson ? "Invitation ready. Share it, then tap Done." : "Invitation ready. Share it, tap Done, then tap Save."
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
