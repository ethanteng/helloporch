import UIKit
import Contacts
import ContactsUI
import LiveKit
import PorchCore

/// Lets a family member on a call with the bedside add someone: another family member on Porch, who rings like an
/// ordinary call and joins with video, or (for caregivers) a regular phone, such as a bank that needs Mom on the
/// line, with a keypad for its menus and its own hang-up. The server rings or dials them into the call's room. A
/// phone stays on only while this phone does, and only this phone sees its number.
@MainActor final class CallGuestControls {
    struct Snapshot { var call: FamilyCallRecord?; var canAddPhone: Bool; var family: [FamilyRelative] }
    let addButton = UIButton(type: .system)
    /// Who is being added and what the added phone is doing, with its keypad and hang-up; hidden until needed.
    let bar = UIStackView()
    private let porchStatus = PorchStyle.label("", size: 17, color: .white, weight: .semibold)
    private let status = PorchStyle.label("", size: 17, color: .white, weight: .semibold)
    private let phoneRow = UIStackView()
    private let keypadButton = UIButton(type: .system)
    private let hangUpButton = UIButton(type: .system)
    private weak var host: UIViewController?
    private let credential: FamilyCredential
    private let callID: String
    private let room: () -> Room?
    private let snapshot: () -> Snapshot
    private var guest: FamilyPhoneGuest?
    /// Guests this phone already saw end, so a snapshot from before the hang-up can't bring one back.
    private var finished: Set<String> = []
    private var legSeen = false, answered = false, dialing = false, ringing = false
    private var notice: String?, porchNotice: String?
    private var noticeTask: Task<Void, Never>?, porchNoticeTask: Task<Void, Never>?
    /// The family member just rung in, until the household's call shows them; and how each invitation last looked.
    private var invited: FamilyPorchGuest?
    private var porchStates: [String: String] = [:]
    private var since = Date.distantPast
    private var watchTask: Task<Void, Never>?
    /// A phone that hasn't joined the room by the end of its ring time, say after a dial request timed out, is
    /// hung up here. The server keeps tracking it until then, so this also removes a leg that arrives late.
    private static let joinSeconds: TimeInterval = 75
    private var myID: String { credential.credential.split(separator: ".").first.map(String.init) ?? "" }

    init(host: UIViewController, credential: FamilyCredential, callID: String, room: @escaping () -> Room?,
         snapshot: @escaping () -> Snapshot) {
        self.host = host; self.credential = credential; self.callID = callID; self.room = room; self.snapshot = snapshot
        CallScreenLayout.configure(addButton, title: "Add someone", symbol: "person.badge.plus")
        CallScreenLayout.configure(keypadButton, title: "Keypad", symbol: "circle.grid.3x3.fill")
        CallScreenLayout.configure(hangUpButton, title: "Hang up", symbol: "phone.down", isEnd: true)
        addButton.accessibilityIdentifier = "call.addSomeone"
        addButton.addAction(UIAction { [weak self] _ in self?.add() }, for: .touchUpInside)
        keypadButton.addAction(UIAction { [weak self] _ in self?.showKeypad() }, for: .touchUpInside)
        hangUpButton.addAction(UIAction { [weak self] _ in self?.hangUp() }, for: .touchUpInside)
        for label in [porchStatus, status] { label.textAlignment = .center; label.accessibilityTraits.insert(.updatesFrequently) }
        phoneRow.addArrangedSubview(keypadButton); phoneRow.addArrangedSubview(hangUpButton)
        phoneRow.distribution = .fillEqually; phoneRow.spacing = 8
        bar.addArrangedSubview(porchStatus); bar.addArrangedSubview(status); bar.addArrangedSubview(phoneRow)
        bar.axis = .vertical; bar.spacing = 8
        bar.accessibilityIdentifier = "call.guests"
        refresh()
    }

    /// Call whenever the room's participants or the household's call change.
    func refresh() {
        let current = snapshot(), call = current.call
        if guest == nil, let phone = call?.phoneGuest, phone.addedBy == myID, !finished.contains(phone.id) { track(phone) }
        let peers = room()?.remoteParticipants.values.map { $0 } ?? []
        if let guest {
            let leg = peers.first { $0.identity?.stringValue == guest.identity }
            let callStatus = leg?.attributes["sip.callStatus"]
            if leg != nil { legSeen = true }
            if callStatus == "active" { answered = true }
            let neverJoined = !legSeen && Date().timeIntervalSince(since) >= Self.joinSeconds
            if (legSeen && leg == nil) || callStatus == "hangup" || neverJoined { legEnded(guest) }
        }
        let porch = updatePorch(call?.porchGuest)
        // Mom is the other end of this call, and her LiveKit identity is that member id. The household
        // snapshot isn't loaded on the CallKit screen, so it can't be what decides she's still here.
        let bedsideID: String? = call?.guest == true ? nil : (call?.from == myID ? call?.to : (call?.to == myID ? call?.from : nil))
        let bedsideHere = bedsideID.map { id in peers.contains { $0.kind != .sip && $0.identity?.stringValue == id } } ?? false
        let canRing = porch?.isActive != true && current.family.contains { $0.canReceiveCalls }
        let canDial = current.canAddPhone && guest == nil
        addButton.isHidden = !(call?.state == "accepted" && call?.bedsideLeft != true && call?.guest != true && bedsideHere && (canRing || canDial))
        addButton.isEnabled = !dialing && !ringing
        addButton.configuration?.title = canRing ? "Add someone" : "Add a phone"
        porchStatus.text = porch?.state == "ringing" ? "Ringing \(porch!.name)…" : porchNotice
        porchStatus.isHidden = porchStatus.text == nil
        status.text = guest.map { answered ? "\($0.label) is on the call" : "Calling \($0.label)…" } ?? notice
        status.isHidden = status.text == nil
        phoneRow.isHidden = guest == nil
        keypadButton.isEnabled = answered
        if let guest { hangUpButton.configuration?.title = "Hang up \(guest.label)" }
        bar.isHidden = porchStatus.isHidden && status.isHidden
    }

    /// The latest family invitation, from the server once it has caught up with this phone. A change this phone
    /// sees happen is announced for a few seconds; one that was already over when the screen opened isn't.
    private func updatePorch(_ server: FamilyPorchGuest?) -> FamilyPorchGuest? {
        if let local = invited, server?.id == local.id { invited = nil }
        guard let porch = invited ?? server else { return nil }
        let previous = porchStates.updateValue(porch.state, forKey: porch.id)
        if let previous, previous != porch.state {
            switch porch.state {
            case "joined": showPorch("\(porch.name) joined the call.")
            case "declined": showPorch("\(porch.name) declined.")
            case "missed": showPorch("\(porch.name) didn't answer.")
            case "left": showPorch("\(porch.name) left the call.")
            case "cancelled": showPorch("Stopped ringing \(porch.name).")
            default: break
            }
        }
        return porch
    }

    private func track(_ added: FamilyPhoneGuest) {
        guest = added; legSeen = false; answered = false; notice = nil; since = Date()
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(Self.joinSeconds * 1_000_000_000)) } catch { return }
            self?.refresh()
        }
    }

    private func legEnded(_ ended: FamilyPhoneGuest) {
        finished.insert(ended.id); guest = nil
        show(answered ? "\(ended.label) hung up." : "\(ended.label) didn't answer.")
        legSeen = false; answered = false
        // Frees the call for another number. The server also checks the room, so a failure here is harmless.
        Task { [credential, callID] in _ = try? await FamilyService(credential).send("removePhoneGuest", ["callID": callID, "guestID": ended.id]) }
    }

    private func show(_ message: String) {
        notice = message; noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            self?.notice = nil; self?.refresh()
        }
    }

    private func showPorch(_ message: String) {
        porchNotice = message; porchNoticeTask?.cancel()
        porchNoticeTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            self?.porchNotice = nil; self?.refresh()
        }
    }

    /// Family on Porch first, since they join with video; then a phone number. With only one choice, it opens directly.
    private func add() {
        guard let host, host.presentedViewController == nil else { return }
        let current = snapshot()
        let people = (invited ?? current.call?.porchGuest)?.isActive == true ? [] : current.family.filter(\.canReceiveCalls)
        let canDial = current.canAddPhone && guest == nil
        if people.isEmpty { if canDial { addPhone() }; return }
        let menu = UIAlertController(title: "Add someone to this call", message: current.call?.mode == .video ? "Family join on Porch with video." : nil, preferredStyle: .actionSheet)
        for person in people {
            menu.addAction(UIAlertAction(title: person.name, style: .default) { [weak self] _ in self?.ring(person) })
        }
        if canDial { menu.addAction(UIAlertAction(title: "A phone number…", style: .default) { [weak self] _ in self?.addPhone() }) }
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        menu.popoverPresentationController?.sourceView = addButton
        menu.popoverPresentationController?.sourceRect = addButton.bounds
        host.present(menu, animated: true)
    }

    private func ring(_ person: FamilyRelative) {
        ringing = true; refresh()
        Task { [weak self] in
            guard let self else { return }
            defer { self.ringing = false; self.refresh() }
            do {
                let response = try await FamilyService(self.credential).send("addPorchGuest", ["callID": self.callID, "memberID": person.id])
                FamilyCoordinator.shared.update(response)
                if let added = response.porchGuest { self.invited = added; self.porchStates[added.id] = added.state }
            } catch { if let host = self.host { showPorchError(error, on: host) } }
        }
    }

    private func addPhone() {
        guard let host, host.presentedViewController == nil else { return }
        let form = AddPhoneGuestViewController { [weak self] label, number in try await self?.dial(label: label, number: number) }
        host.present(UINavigationController(rootViewController: form), animated: true)
    }

    private func dial(label: String, number: String) async throws {
        guard !dialing else { throw FamilyServiceError(message: "Porch is still checking the last number. Try again in a moment.", status: 409) }
        dialing = true; refresh()
        var settle: UInt64 = 0
        defer {
            // A failed dial may still be ringing, and the server keeps tracking it. Wait for the next check-in
            // to show it here before another number can be dialed.
            let delay = settle
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                self?.dialing = false; self?.refresh()
            }
        }
        let response: FamilyResponse
        do { response = try await FamilyService(credential).send("addPhoneGuest", ["callID": callID, "phoneNumber": number, "label": label], timeout: 25) }
        catch { if (error as? FamilyServiceError)?.status ?? 502 >= 500 { settle = 6_000_000_000 }; throw error }
        FamilyCoordinator.shared.update(response)
        guard let added = response.phoneGuest else { throw FamilyServiceError(message: "Couldn't add that phone number.", status: 502) }
        track(added)
    }

    private func hangUp() {
        guard let current = guest else { return }
        hangUpButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { self.hangUpButton.isEnabled = true; self.refresh() }
            do {
                let response = try await FamilyService(self.credential).send("removePhoneGuest", ["callID": self.callID, "guestID": current.id])
                FamilyCoordinator.shared.update(response)
                guard self.guest?.id == current.id else { return }
                self.finished.insert(current.id); self.guest = nil; self.legSeen = false; self.answered = false
                self.show("You hung up \(current.label).")
            } catch { if let host = self.host { showPorchError(error, on: host) } }
        }
    }

    private func showKeypad() {
        guard let host, host.presentedViewController == nil, let guest, let room = room() else { return }
        let keypad = PhoneKeypadViewController(name: guest.label) { [weak room] code, digit in
            try await room?.localParticipant.publishDtmf(code: code, digit: digit)
        }
        host.present(UINavigationController(rootViewController: keypad), animated: true)
    }
}

/// Who is on a call, as the call screens show them.
@MainActor enum CallPeople {
    /// Everyone on Porch, `first` (the person the screen is about) leading, with their camera and photo. An added
    /// phone has no video, so it gets no tile.
    static func tiles(_ peers: [RemoteParticipant], first: String?) -> [CallVideoStage.Tile] {
        peers.filter { $0.kind != .sip }
            .sorted { $0.identity?.stringValue == first && $1.identity?.stringValue != first }
            .map { peer in
                let track = peer.videoTracks.first { !$0.isMuted && $0.track is VideoTrack }?.track as? VideoTrack
                let photo = peer.identity.flatMap { FamilyPhotos.shared.photo(forMember: $0.stringValue) }.flatMap(UIImage.init(data:))
                return CallVideoStage.Tile(name: peer.name ?? "", track: track, photo: photo)
            }
    }
    /// What the bedside says about people added to its call, in its language: "Calling David…", "David joined the call".
    static func bedsideLines(_ peers: [RemoteParticipant], call: FamilyCallRecord?) -> [String] {
        var lines: [String] = []
        if let porch = call?.porchGuest {
            if porch.state == "ringing" { lines.append(BedsideText.string("Calling %@…", porch.name)) }
            else if porch.state == "joined", peers.contains(where: { $0.identity?.stringValue == porch.memberID }) {
                lines.append(BedsideText.string("%@ joined the call", porch.name))
            }
        }
        if let phone = peers.first(where: { $0.kind == .sip }) {
            let name = phone.name ?? ""
            lines.append(phone.attributes["sip.callStatus"] == "active" ? BedsideText.string("%@ joined the call", name) : BedsideText.string("Calling %@…", name))
        }
        return lines
    }
}

/// Names and dials the phone to add. The caller's own form, so it uses the family phone's keyboard.
final class AddPhoneGuestViewController: CaregiverFormViewController, CNContactPickerDelegate {
    private let name = UITextField(), phone = UITextField()
    private let call = PorchStyle.button("Call and add to this call", symbol: "phone.badge.plus")
    private let onCall: (String, String) async throws -> Void
    init(onCall: @escaping (String, String) async throws -> Void) {
        self.onCall = onCall
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(onCall:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Add a phone"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        name.autocapitalizationType = .words
        phone.keyboardType = .phonePad; phone.textContentType = .telephoneNumber
        name.accessibilityIdentifier = "phoneGuest.name"; phone.accessibilityIdentifier = "phoneGuest.number"
        let contacts = PorchStyle.button("Choose from Contacts", symbol: "person.crop.circle", filled: false)
        contacts.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        call.addTarget(self, action: #selector(dial), for: .touchUpInside)
        form.addArrangedSubview(section("Who should join the call?", detail: "Porch calls this number and adds them to your call. If you hang up, their call ends too.", views: [
            field(name, title: "Who are you calling?", placeholder: "For example, Bank", helper: "The bedside shows this name."),
            field(phone, title: "Their phone number", placeholder: "(800) 555-0123", helper: "US and Canadian numbers, including toll-free numbers."),
            contacts, call,
        ]))
        hideKeyboardControl()
    }
    @objc private func pickContact() {
        view.endEditing(true)
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
        present(picker, animated: true)
    }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
        if let contactName = CNContactFormatter.string(from: property.contact, style: .fullName), !contactName.isEmpty { name.text = String(contactName.prefix(40)) }
        if let number = property.value as? CNPhoneNumber { phone.text = number.stringValue }
    }
    @objc private func dial() {
        view.endEditing(true)
        let label = (name.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { showPorchError(FamilyServiceError(message: "Enter who you're calling, such as Bank.", status: 400), on: self); return }
        call.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { self.call.isEnabled = true }
            do {
                // Numbers without a country code are North American, wherever this phone is set up.
                let number = try PhoneNumberNormalization.e164(self.phone.text ?? "", region: "US")
                try await self.onCall(String(label.prefix(40)), number)
                self.dismiss(animated: true)
            } catch { showPorchError(error, on: self) }
        }
    }
}

/// Sends key presses to the added phone, for menus such as "press 1 for your account balance".
final class PhoneKeypadViewController: UIViewController {
    private let name: String
    private let send: (UInt32, String) async throws -> Void
    private let pressed = PorchStyle.label(" ", size: 32, color: PorchStyle.ink, weight: .semibold)
    private var queue: Task<Void, Never>?
    init(name: String, send: @escaping (UInt32, String) async throws -> Void) {
        self.name = name; self.send = send
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(name:send:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Keypad for \(name)"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        pressed.textAlignment = .center; pressed.lineBreakMode = .byTruncatingHead; pressed.numberOfLines = 1
        pressed.accessibilityLabel = "Keys pressed"
        let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 12; grid.distribution = .fillEqually
        for keys in [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]] {
            let row = UIStackView(); row.spacing = 12; row.distribution = .fillEqually
            for key in keys {
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.gray()
                configuration.title = key; configuration.cornerStyle = .capsule
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = attributes; attributes.font = PorchStyle.font(30, weight: .semibold); return attributes
                }
                button.configuration = configuration
                button.accessibilityLabel = key == "*" ? "Star" : key == "#" ? "Pound" : key
                button.accessibilityIdentifier = "phoneGuest.key.\(key)"
                button.addAction(UIAction { [weak self] _ in self?.press(key) }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            grid.addArrangedSubview(row)
        }
        let stack = UIStackView(arrangedSubviews: [pressed, grid]); stack.axis = .vertical; stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let guide = view.safeAreaLayoutGuide
        // A phone-sized pad, which gets shorter keys when the screen is short.
        let width = stack.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -64)
        let shape = grid.heightAnchor.constraint(equalTo: grid.widthAnchor, multiplier: 1.1)
        width.priority = .defaultHigh; shape.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420), width,
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor, constant: -24), shape,
        ])
    }
    private func press(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pressed.text = String(((pressed.text ?? "").trimmingCharacters(in: .whitespaces) + key).suffix(24))
        // SIP keypad codes: digits are themselves, * is 10 and # is 11. Presses go out in order.
        let code: UInt32 = key == "*" ? 10 : key == "#" ? 11 : UInt32(key) ?? 0
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            do { try await self?.send(code, key) }
            catch { if let self { showPorchError(error, on: self) } }
        }
    }
}
