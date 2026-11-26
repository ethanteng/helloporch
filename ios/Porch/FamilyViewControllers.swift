import UIKit
import AVFoundation
import ContactsUI
import MessageUI
import SafariServices
import UniformTypeIdentifiers
import PorchCore

/// On the website, so the policy can change without an app update.
let privacyPolicyURL = URL(string: "https://helloporch.store/privacy")!
func showPrivacyPolicy(on controller: UIViewController) {
    controller.present(SFSafariViewController(url: privacyPolicyURL), animated: true)
}
/// The iPad setup guide, at its part on the desk phone: the steps for plugging it in, the parts and the tips.
let iPadGuideURL = URL(string: "https://helloporch.store/pilot/ios#phone")!
func showIPadGuide(on controller: UIViewController) {
    controller.present(SFSafariViewController(url: iPadGuideURL), animated: true)
}
func showPorchError(_ error: Error, on controller: UIViewController) {
    let alert = UIAlertController(title: "Couldn't complete that", message: error.localizedDescription, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    controller.present(alert, animated: true)
}
/// Family mode's Call tab: a card for each family's bedside, with its calls. Messages and settings have tabs of their
/// own, so a phone in two families, such as both sets of parents, shows two short cards rather than every button and
/// setting of both.
final class FamilyHomeViewController: CaregiverFormViewController {
    private let status = PorchStyle.label("", size: 17)
    private let cards = UIStackView()
    /// Under each name: on a call, not ready, or whether someone is at the bedside. That changes by the minute, so it's
    /// updated in place rather than rebuilding the cards. One for each family, by this phone's ID there.
    private var statusLines: [String: UILabel] = [:]
    /// What each family's live call strip says under its caller, updated every second while a call is on.
    private var liveCallLines: [String: (label: UILabel, call: BedsideCall)] = [:]
    private var ticker: Timer?
    private var starting = false
    /// One family's card as it's drawn. Its status line is left out: that's updated in place.
    private struct Card: Equatable {
        let id: String
        let name: String
        /// The family's name, with more than one family, when it says something the bedside's name doesn't.
        let family: String?
        let removed: Bool
        /// It has checked in and has a bedside to call.
        let connected: Bool
        let callable: Bool
        /// Drop-ins this phone may start: drop-in is on, and approved for it or every call drops in.
        let dropIns: [NativeCall.Mode]
        /// For caregivers while every call drops in: who turned it on, and when, such as "Tom, 3:12 PM".
        let everyCall: String?
        /// For caregivers: a phone call that started while every call drops in, while it rings or is on. Its time is
        /// updated in place.
        let liveCall: BedsideCall?
    }
    private struct Presentation: Equatable {
        let cards: [Card]
        let starting: Bool
        let ringing: Bool
        let largeText: Bool
        /// The cards' width, which decides how their call buttons fit.
        let width: CGFloat
    }
    private var displayed: Presentation?
    override func viewDidLoad() {
        // Not `title`, which would rename the Call tab too.
        super.viewDidLoad(); navigationItem.title = "Porch"; navigationItem.titleView = PorchWordmark()
        cards.axis = .vertical; cards.spacing = 16
        status.textAlignment = .center
        form.spacing = 16
        form.addArrangedSubview(status); form.addArrangedSubview(cards)
        hideKeyboardControl()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPushStatus), name: .porchSystemCallChanged, object: nil)
        refresh()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory { refresh() }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The first cards are drawn before layout, for the screen's width; rotating or a split view changes it too.
        if let displayed, abs(form.bounds.width.rounded() - displayed.width) >= 1 { refresh() }
    }
    @objc private func refreshPushStatus() { displayed = nil; refresh() }
    /// Joining from the Call tab, before this phone is in any family.
    private func showPairing() {
        if let tabs = tabBarController as? FamilyTabBarController { tabs.showPairing() }
        else { navigationController?.pushViewController(FamilyPairingViewController(), animated: true) }
    }
    private func statusLine(for credential: FamilyCredential) -> UILabel {
        if let label = statusLines[credential.deviceID] { return label }
        let label = PorchStyle.label("", size: 16)
        label.accessibilityIdentifier = "family.status"
        statusLines[credential.deviceID] = label
        return label
    }
    /// What a card says under the name: why its bedside can't be reached, or how it is, and whether that's someone
    /// at the bedside right now.
    static func status(of link: FamilyCoordinator.Link?) -> (text: String, present: Bool) {
        if link?.accessRemoved == true { return ("This phone was removed from this family.", false) }
        if let error = link?.error { return (error, false) }
        guard let state = link?.state else { return ("Connecting…", false) }
        guard let bedside = state.people.first(where: { $0.role == .bedside }), bedside.online else { return ("Porch isn't ready", false) }
        if state.busy { return ("On a call", false) }
        // Without a fresh check-in the last one's time stands still, so an error above shows instead.
        if let attended = BedsideAttendance.text(attendedAt: state.bedsideAttendedAt, now: state.serverTime, device: BedsideAttendance.device(in: state)) {
            return (attended, BedsideAttendance.isPresent(attendedAt: state.bedsideAttendedAt, now: state.serverTime))
        }
        return ("Porch is open", false)
    }
    @objc private func refresh() {
        guard isViewLoaded else { return }
        let coordinator = FamilyCoordinator.shared
        let credentials = PorchDevice.families
        let several = credentials.count > 1
        let next = Presentation(cards: credentials.map { credential in
            let link = coordinator.link(for: credential), state = link?.state
            let bedside = state?.people.first { $0.role == .bedside }
            let name = bedside?.name ?? state?.householdName ?? PorchDevice.familyName(credential) ?? "Family"
            let family = several ? PorchDevice.familyName(credential).flatMap { $0 == name ? nil : $0 } : nil
            let dropIns = state.map { state in NativeCall.Mode.allCases.filter(state.canDropIn) } ?? []
            let everyCall = state.flatMap { state in
                state.me.caregiver == true ? state.everyCall.map { on in
                    "\(on.who(bedsideDevice: bedside?.platform == "android" ? "tablet" : "iPad")), \(DropInSettingsViewController.time(on.at))"
                } : nil
            }
            return Card(id: credential.deviceID, name: name, family: family, removed: link?.accessRemoved == true, connected: state != nil && bedside != nil,
                        callable: link?.error == nil && bedside?.online == true && state?.busy == false, dropIns: dropIns, everyCall: everyCall,
                        liveCall: state?.me.caregiver == true ? state?.bedsideCall : nil)
        }, starting: starting, ringing: SystemIncomingCalls.shared.hasCall, largeText: traitCollection.preferredContentSizeCategory.isAccessibilityCategory,
           width: (form.bounds.width > 0 ? form.bounds.width : min(view.bounds.width - 48, 760)).rounded())
        for credential in credentials {
            let (text, present) = Self.status(of: coordinator.link(for: credential)), label = statusLine(for: credential)
            label.text = text
            label.textColor = present ? PorchStyle.go : PorchStyle.secondary
            label.font = PorchStyle.font(16, weight: present ? .semibold : .regular)
        }
        // Ringing while locked is what's expected, so only its absence is mentioned.
        let push = SystemIncomingCalls.shared.pushReady ? nil : "Keep Porch open so you don't miss calls."
        let device = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .denied ? "Allow microphone access in \(device) Settings → Porch to answer calls." : nil
        // So nobody forgets that calls are being turned away. Polls refresh this, so scheduled hours show as they start.
        let quiet = DoNotDisturb.load().applies(at: Date()) ? "Do Not Disturb is on" : nil
        status.text = credentials.isEmpty ? "Ask the caregiver to invite you." : microphone ?? quiet ?? push
        status.isHidden = status.text == nil
        guard next != displayed else { updateCallTimes(); return }
        displayed = next
        cards.arrangedSubviews.forEach { cards.removeArrangedSubview($0); $0.removeFromSuperview() }
        statusLines = statusLines.filter { id, _ in credentials.contains { $0.deviceID == id } }
        liveCallLines = [:]
        defer { updateCallTimes(); syncTicker() }
        guard !credentials.isEmpty else {
            let join = PorchStyle.button("Join a family", symbol: "person.badge.plus")
            join.addAction(UIAction { [weak self] _ in self?.showPairing() }, for: .touchUpInside)
            cards.addArrangedSubview(join); return
        }
        for (credential, card) in zip(credentials, next.cards) { cards.addArrangedSubview(view(for: card, credential: credential, in: next)) }
    }
    private func view(for card: Card, credential: FamilyCredential, in presentation: Presentation) -> UIView {
        let name = PorchStyle.label(card.name, size: 21, color: PorchStyle.ink)
        name.font = PorchStyle.titleFont(24)
        name.accessibilityTraits = .header
        let text = UIStackView(arrangedSubviews: [name] + (card.family.map { [PorchStyle.label($0, size: 15)] } ?? []) + [statusLine(for: credential)])
        text.axis = .vertical; text.spacing = 2
        let header = UIStackView(arrangedSubviews: [FamilyAdminViewController.avatar(card.name, size: 56), text])
        header.spacing = 14; header.alignment = .center
        var views: [UIView] = [header]
        if !card.removed, let call = card.liveCall { views.insert(liveCallStrip(call, credential: credential), at: 0) }
        if let everyCall = card.everyCall, !card.removed { views.insert(everyCallBanner(everyCall, credential: credential), at: 0) }
        if card.removed {
            // A family that removed this phone can't reach it again. Taking it off leaves the others as they are.
            let remove = PorchStyle.button("Remove from this phone", symbol: "minus.circle", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addAction(UIAction { [weak self] _ in self?.confirmRemoval(of: credential, named: card.family ?? PorchDevice.familyName(credential)) }, for: .touchUpInside)
            views.append(remove)
        } else if card.connected, let bedside = FamilyCoordinator.shared.state(for: credential)?.people.first(where: { $0.role == .bedside }) {
            views.append(callButtons(card, bedside: bedside, credential: credential, in: presentation))
        }
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical; stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        stack.backgroundColor = PorchStyle.surface
        stack.layer.cornerRadius = 20
        stack.accessibilityIdentifier = "family.card"
        return stack
    }
    /// Call, Video and, when it's approved for this phone, Drop in. Approved for both, Drop in asks which.
    private func callButtons(_ card: Card, bedside: FamilyPerson, credential: FamilyCredential, in presentation: Presentation) -> UIView {
        // While another family's call rings or is on, CallKit has it: a call from here would be cut off.
        let enabled = card.callable && !presentation.starting && !presentation.ringing
        func button(_ title: String, symbol: String, filled: Bool, label: String, identifier: String) -> UIButton {
            let button = PorchStyle.button(title, symbol: symbol, filled: filled)
            button.configuration?.imagePadding = 6
            button.configuration?.contentInsets = .init(top: 12, leading: 8, bottom: 12, trailing: 8)
            button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(17, weight: .semibold); return attributes
            }
            if !filled { button.configuration?.background.strokeColor = PorchStyle.border; button.configuration?.background.strokeWidth = 1.5 }
            button.accessibilityLabel = label
            button.accessibilityIdentifier = identifier
            button.isEnabled = enabled
            return button
        }
        let call = button("Call", symbol: "phone.fill", filled: true, label: "Call \(card.name)", identifier: "family.call")
        call.addAction(UIAction { [weak self] _ in self?.call(bedside, mode: .voice, dropIn: false, in: credential) }, for: .touchUpInside)
        let video = button("Video", symbol: "video.fill", filled: true, label: "Video call \(card.name)", identifier: "family.videoCall")
        video.addAction(UIAction { [weak self] _ in self?.call(bedside, mode: .video, dropIn: false, in: credential) }, for: .touchUpInside)
        var buttons = [call, video]
        if let only = card.dropIns.first {
            let drop = button("Drop in", symbol: "waveform", filled: false, label: card.dropIns.count > 1 ? "Drop in on \(card.name)"
                : only == .video ? "Drop in on \(card.name) with video" : "Drop in on \(card.name) with audio", identifier: "family.dropIn")
            if card.dropIns.count > 1 {
                drop.menu = UIMenu(children: [
                    UIAction(title: "Drop in with audio", image: UIImage(systemName: "waveform")) { [weak self] _ in self?.call(bedside, mode: .voice, dropIn: true, in: credential) },
                    UIAction(title: "Drop in with video", image: UIImage(systemName: "video.badge.waveform")) { [weak self] _ in self?.call(bedside, mode: .video, dropIn: true, in: credential) },
                ])
                drop.showsMenuAsPrimaryAction = true
            } else {
                drop.addAction(UIAction { [weak self] _ in self?.call(bedside, mode: only, dropIn: true, in: credential) }, for: .touchUpInside)
            }
            buttons.append(drop)
        }
        let row = UIStackView(arrangedSubviews: buttons)
        row.spacing = 8; row.distribution = .fillEqually
        // Each button gets an equal share of the card. Where a title and its icon don't fit side by side, as on most
        // iPhones with three buttons, the icons go above the titles; where even that doesn't fit, and with very large text,
        // the buttons stack. Every card follows the one with the most buttons, so they look alike.
        let columns = CGFloat(presentation.cards.filter { $0.connected && !$0.removed }.map { $0.dropIns.isEmpty ? 2 : 3 }.max() ?? buttons.count)
        let share = (presentation.width - 32 - row.spacing * (columns - 1)) / columns
        let fits = { buttons.allSatisfy { $0.intrinsicContentSize.width <= share } }
        if !presentation.largeText, !fits() {
            for button in buttons { button.configuration?.imagePlacement = .top; button.configuration?.imagePadding = 4 }
            if !fits() { for button in buttons { button.configuration?.imagePlacement = .leading; button.configuration?.imagePadding = 6 } }
        }
        if presentation.largeText || !fits() { row.axis = .vertical }
        return row
    }
    /// For caregivers while every call drops in: who turned it on, and a Turn off that needs no PIN.
    private func everyCallBanner(_ who: String, credential: FamilyCredential) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        icon.tintColor = PorchStyle.danger
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let title = PorchStyle.label("Every call drops in", size: 16, color: DropInSettingsViewController.darkRed, weight: .bold)
        let detail = PorchStyle.label(who, size: 14, color: UIColor(red: 0x6B / 255, green: 0x3A / 255, blue: 0x2E / 255, alpha: 1))
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical; text.spacing = 1
        text.isAccessibilityElement = true; text.accessibilityLabel = "Every call drops in. \(who)"
        let off = PorchStyle.button("Turn off", filled: false)
        off.configuration?.baseForegroundColor = UIColor(red: 0xB0 / 255, green: 0x3A / 255, blue: 0x2E / 255, alpha: 1)
        off.configuration?.background.backgroundColor = PorchStyle.surface
        off.configuration?.background.strokeColor = PorchStyle.danger
        off.configuration?.background.strokeWidth = 1.5
        off.configuration?.cornerStyle = .fixed
        off.configuration?.background.cornerRadius = 10
        off.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
        off.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(15, weight: .bold); return attributes
        }
        off.setContentHuggingPriority(.required, for: .horizontal)
        off.setContentCompressionResistancePriority(.required, for: .horizontal)
        // One line: with two wrapping texts in the row, UIKit would cap the notice's text at half the row.
        off.configuration?.titleLineBreakMode = .byTruncatingTail
        off.accessibilityLabel = "Turn off every call"
        off.accessibilityIdentifier = "family.everyCall.turnOff"
        off.addAction(UIAction { [weak self, weak off] _ in
            off?.isEnabled = false
            Task { [weak self] in
                do {
                    FamilyCoordinator.shared.update(try await FamilyService(credential).send("turnOffEveryCall"))
                    self?.showToast("Every call is off")
                } catch {
                    off?.isEnabled = true
                    if let self { showPorchError(error, on: self) }
                }
            }
        }, for: .touchUpInside)
        let banner = UIStackView(arrangedSubviews: [icon, text, off])
        banner.spacing = 10; banner.alignment = .center
        banner.isLayoutMarginsRelativeArrangement = true
        banner.directionalLayoutMargins = .init(top: 8, leading: 12, bottom: 8, trailing: 8)
        banner.backgroundColor = DropInSettingsViewController.redTint
        banner.layer.cornerRadius = 14
        banner.accessibilityIdentifier = "family.everyCall"
        return banner
    }
    /// A phone call on the bedside that started while every call drops in: who, what it's doing, and End call, which
    /// needs no PIN.
    private func liveCallStrip(_ call: BedsideCall, credential: FamilyCredential) -> UIView {
        let dot = UIView()
        dot.backgroundColor = PorchStyle.go
        dot.layer.cornerRadius = 5
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 10), dot.heightAnchor.constraint(equalToConstant: 10)])
        let title = PorchStyle.label(call.title, size: 16, color: PorchStyle.ink, weight: .bold)
        title.numberOfLines = 1; title.lineBreakMode = .byTruncatingTail
        let meta = PorchStyle.label("", size: 14, color: PorchStyle.secondary)
        meta.numberOfLines = 1
        meta.accessibilityIdentifier = "family.liveCall.status"
        liveCallLines[credential.deviceID] = (meta, call)
        let text = UIStackView(arrangedSubviews: [title, meta])
        text.axis = .vertical; text.spacing = 1
        let end = PorchStyle.button("End call")
        end.configuration?.baseBackgroundColor = PorchStyle.danger
        end.configuration?.cornerStyle = .fixed
        end.configuration?.background.cornerRadius = 10
        end.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
        end.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(15, weight: .bold); return attributes
        }
        end.setContentHuggingPriority(.required, for: .horizontal)
        end.setContentCompressionResistancePriority(.required, for: .horizontal)
        end.accessibilityLabel = "End the call with \(call.title)"
        end.accessibilityIdentifier = "family.liveCall.end"
        end.addAction(UIAction { [weak self, weak end] _ in
            end?.isEnabled = false
            Task { [weak self] in
                do {
                    FamilyCoordinator.shared.update(try await FamilyService(credential).send("endBedsideCall", ["callID": call.id]))
                    self?.showToast("Call ended")
                } catch {
                    end?.isEnabled = true
                    if let self { showPorchError(error, on: self) }
                }
            }
        }, for: .touchUpInside)
        let strip = UIStackView(arrangedSubviews: [dot, text, end])
        strip.spacing = 10; strip.alignment = .center
        strip.isLayoutMarginsRelativeArrangement = true
        strip.directionalLayoutMargins = .init(top: 8, leading: 12, bottom: 8, trailing: 8)
        strip.backgroundColor = PorchStyle.surface
        strip.layer.cornerRadius = 14
        strip.layer.borderWidth = 1.5
        strip.layer.borderColor = PorchStyle.border.cgColor
        strip.accessibilityIdentifier = "family.liveCall"
        return strip
    }
    /// How long each connected call has been on, by the server's clock as of its family's last check-in.
    private func updateCallTimes() {
        for (id, line) in liveCallLines {
            let link = PorchDevice.families.first { $0.deviceID == id }.flatMap { FamilyCoordinator.shared.link(for: $0) }
            let text = line.call.status(serverNow: link?.serverNow() ?? Date().timeIntervalSince1970)
            if line.label.text != text { line.label.text = text }
        }
    }
    /// Ticks once a second while a connected call is shown, and only then.
    private func syncTicker() {
        let needed = view.window != nil && liveCallLines.values.contains { $0.call.isConnected }
        if !needed { ticker?.invalidate(); ticker = nil; return }
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.updateCallTimes() } }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); updateCallTimes(); syncTicker() }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); ticker?.invalidate(); ticker = nil }
    /// A short note at the bottom that fades on its own, such as after turning something off.
    private func showToast(_ text: String) {
        let label = PorchStyle.label(text, size: 15, color: .white, weight: .semibold)
        label.textAlignment = .center
        let toast = UIView()
        toast.backgroundColor = PorchStyle.ink
        toast.layer.cornerRadius = 22
        toast.isUserInteractionEnabled = false
        for item in [toast, label] { item.translatesAutoresizingMaskIntoConstraints = false }
        toast.addSubview(label)
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 20), label.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: toast.topAnchor, constant: 12), label.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -12),
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        UIAccessibility.post(notification: .announcement, argument: text)
        UIView.animate(withDuration: 0.3, delay: 2.2, options: []) { toast.alpha = 0 } completion: { _ in toast.removeFromSuperview() }
    }
    /// What's waiting for this caregiver's OK: phone voicemail, texts, or both.
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
        let alert = UIAlertController(title: title, message: "Leave a message?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Leave a message", style: .default) { [weak self] _ in
            FamilyCoordinator.shared.select(family)
            self?.navigationController?.pushViewController(MessageComposerViewController(recipient: name, kind: "voicemail", startAudioImmediately: true, family: family), animated: true)
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
        if adding { views.append(field(nickname, title: "What do you call this family?", placeholder: "For example, Sarah's parents", helper: "Only on this phone.")) }
        views.append(join)
        form.addArrangedSubview(section("Your Porch invite", detail: "Paste the link a caregiver sent you.", views: views))
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
        let alert = UIAlertController(title: "Name this family", message: "You're in more than one family called \(name). What do you call this one?", preferredStyle: .alert)
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
        icon.tintColor = call.isMissed ? .systemRed : PorchStyle.secondary
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

/// Opens caregiver mode on an approved family phone with the household's caregiver PIN, or straight to what needs
/// a caregiver's OK.
final class RemoteCaregiverPINViewController: CaregiverFormViewController {
    enum Opens { case caregiverMode, needsOK }
    /// The family whose PIN this screen checks. Opening another family's page while it sits on its tab must not switch that.
    private let family: FamilyCredential?
    private let opens: Opens
    private let pin = UITextField()
    private let submit: UIButton
    private var task: Task<Void, Never>?
    init(family: FamilyCredential? = nil, opens: Opens = .caregiverMode) {
        self.family = family ?? PorchDevice.credential(for: .family)
        self.opens = opens
        submit = PorchStyle.button(opens == .needsOK ? "Unlock" : "Open caregiver mode", symbol: "lock.fill")
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(family:opens:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = opens == .needsOK ? "Needs your OK" : "Caregiver mode"
        pin.isSecureTextEntry = true; pin.keyboardType = .numberPad
        pin.accessibilityIdentifier = "caregiver.pin"
        form.addArrangedSubview(section("Caregiver PIN", detail: "The PIN set on the bedside iPad.", views: [field(pin, title: "Six-digit PIN", placeholder: "Enter six digits"), submit]))
        submit.addTarget(self, action: #selector(unlock), for: .touchUpInside)
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if isMovingFromParent { task?.cancel() } }
    @objc private func unlock() {
        guard task == nil, let credential = family ?? PorchDevice.credential(for: .family) else { return }
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
                let next: UIViewController = self.opens == .needsOK
                    ? MessageQueueViewController(remote: credential, messages: response.admin?.messages ?? [], texts: response.admin?.texts ?? [], needsOK: true)
                    : FamilyAdminViewController(remote: credential, state: response.admin)
                guard let navigation = self.navigationController else { return }
                navigation.setViewControllers(Array(navigation.viewControllers.dropLast()) + [next], animated: true)
            } catch { if !Task.isCancelled { showPorchError(error, on: self) } }
        }
    }
}

final class FamilyInviteViewController: CaregiverFormViewController {
    var prefilledName: String?
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
    /// The bedside's name, such as Mom, for what drop-in means.
    private var lovedOne: String { (remote.map { FamilyCoordinator.shared.state(for: $0) } ?? FamilyCoordinator.shared.state)?.householdName ?? "your loved one" }
    @objc private func finishedInvite() { navigationController?.popViewController(animated: true) }
    /// How an invitation from People reaches someone's key: by its name (`CallSlots.followInvitations`).
    static let keypadHint = "If they're on the keypad, use the name on their key."
    /// What sharing an invitation sends: a note, then the link.
    static func shareItems(_ link: URL) -> [Any] {
        // A web link opens Porch, or shows how to get it first.
        let note = link.scheme == "https" ? "Join our Porch! Open this link on your phone. If you don't have Porch yet, it shows you how to get it. It expires after 24 hours."
            : "Join our Porch! This link expires after 24 hours."
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
        // An invitation from a key is already that key's. One from People finds its key by name once they join.
        let keypadHint = onCreated == nil ? Self.keypadHint : nil
        form.addArrangedSubview(section("Who is this invitation for?", detail: keypadHint, views: [field(personName, title: "Their name", placeholder: "For example, Ethan")]))
        form.addArrangedSubview(section("Approve drop-in", detail: "Connects without \(lovedOne) answering.", views: [row("Audio drop-in", audio), row("Video drop-in", video)]))
        form.addArrangedSubview(section("Caregiver mode", detail: "Can change settings from their phone.", views: [row("Caregiver mode", caregiver)]))
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
                self.inviteHint.text = "Invitation ready. Share it, then tap Done."
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
    private let answer = PorchStyle.systemButton("Answer", symbol: "phone.fill")
    private let keypadHint = PorchStyle.systemLabel("", size: 18, color: PorchStyle.nightSecondary)
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
        let name = PorchStyle.systemLabel(session.peerName, size: 48, color: PorchStyle.nightText, weight: .semibold)
        name.textAlignment = .center
        countdown.font = PorchStyle.systemFont(28); countdown.textColor = PorchStyle.nightText; countdown.numberOfLines = 0; countdown.textAlignment = .center
        answer.configuration?.title = BedsideText.string(call.mode == .video ? "Answer video call" : "Answer audio call")
        answer.configuration?.baseBackgroundColor = PorchStyle.go
        answer.addTarget(self, action: #selector(accept), for: .touchUpInside)
        let decline = PorchStyle.systemButton(BedsideText.string(call.kind == "dropIn" ? "Don't connect" : "Decline"), symbol: "phone.down.fill")
        decline.configuration?.baseBackgroundColor = PorchStyle.danger
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
