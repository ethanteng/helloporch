import UIKit
import ContactsUI
import MessageUI
import UniformTypeIdentifiers
import PorchCore

/// Family mode: Call, Messages and You. Each tab keeps its own screens and the tab bar stays under them, so calling,
/// a family's messages and this phone's families and settings are always one tap apart.
final class FamilyTabBarController: UITabBarController {
    let home = FamilyHomeViewController()
    let inbox = FamilyInboxViewController()
    let you = FamilyYouViewController()
    static let callTab = 0, messagesTab = 1, youTab = 2

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.tintColor = PorchStyle.accent
        let tabs: [(UIViewController, String, String, String)] = [
            (home, "Call", "phone", "family.tab.call"),
            (inbox, "Messages", "bubble.left.and.bubble.right", "family.tab.messages"),
            (you, "You", "person.crop.circle", "family.tab.you"),
        ]
        viewControllers = tabs.map { root, title, symbol, identifier in
            let navigation = PorchStyle.navigation(root)
            navigation.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: UIImage(systemName: "\(symbol).fill"))
            navigation.tabBarItem.accessibilityIdentifier = identifier
            return navigation
        }
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = PorchStyle.page
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = PorchStyle.secondary
            item.normal.titleTextAttributes = [.foregroundColor: PorchStyle.secondary]
            item.selected.iconColor = PorchStyle.accent
            item.selected.titleTextAttributes = [.foregroundColor: PorchStyle.accent]
        }
        tabBar.unselectedItemTintColor = PorchStyle.secondary
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) { tabBar.scrollEdgeAppearance = appearance }
        chosen = PorchDevice.currentFamily?.deviceID
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openReceivedMessages(_:)), name: .porchOpenReceivedMessages, object: nil)
        updateBadge()
    }
    /// The family chosen last, which a family's thread, caregiver mode and name and photo are for.
    private var chosen: String?
    /// Each tab keeps its screens, so one family's thread or recording could still be open on another tab when the
    /// next family is chosen, and would then act for that one. Those tabs go back to their first screen instead.
    @objc private func familyChanged() {
        updateBadge()
        let current = PorchDevice.currentFamily?.deviceID
        defer { chosen = current }
        guard let previous = chosen, current != previous else { return }
        for case let navigation as UINavigationController in viewControllers ?? [] where navigation !== selectedViewController && navigation.viewControllers.count > 1 {
            navigation.popToRootViewController(animated: false)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    #if DEBUG
    private var previewShown = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !previewShown else { return }
        previewShown = true
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-messages") { openMessages(for: nil) }
        if arguments.contains("--preview-messages-tab") { selectedIndex = Self.messagesTab }
        if arguments.contains("--preview-profile") || arguments.contains("--preview-you"), let family = PorchDevice.currentFamily {
            selectedIndex = Self.youTab
            if arguments.contains("--preview-profile") { you.navigationController?.pushViewController(FamilyPageViewController(credential: family), animated: false) }
        } else if arguments.contains("--preview-you") { selectedIndex = Self.youTab }
    }
    #endif

    /// Its first screen with nothing open over it, which is where a call can ring.
    var isShowingTabRoot: Bool {
        presentedViewController == nil && (selectedViewController as? UINavigationController)?.viewControllers.count == 1
    }
    /// Joining a family. It belongs with the list of families on You; before there are any, the Call tab says how.
    /// An invitation is an interruption, so a caregiver session left open on another tab ends and each tab returns to its first screen.
    func showPairing(invitation: URL? = nil) {
        RemoteCaregiverSession.shared.end()
        selectedIndex = PorchDevice.families.isEmpty ? Self.callTab : Self.youTab
        for case let navigation as UINavigationController in viewControllers ?? [] {
            navigation.popToRootViewController(animated: false)
        }
        guard let navigation = selectedViewController as? UINavigationController else { return }
        let pairing = FamilyPairingViewController(); pairing.invitation = invitation
        navigation.pushViewController(pairing, animated: true)
    }
    /// A family's messages with its bedside, on the Messages tab. Nil keeps the family chosen last.
    func openMessages(for family: FamilyCredential?) {
        let chosen = family ?? PorchDevice.credential(for: .family)
        guard chosen != nil else { return }
        if presentedViewController != nil { dismiss(animated: false) }
        // Messages first, so choosing the family closes what's open for another one on the other tabs.
        selectedIndex = Self.messagesTab
        if let family { FamilyCoordinator.shared.select(family) }
        guard let navigation = selectedViewController as? UINavigationController else { return }
        if navigation.presentedViewController != nil { navigation.dismiss(animated: false) }
        navigation.popToRootViewController(animated: false)
        navigation.pushViewController(MessageThreadViewController(family: chosen), animated: true)
    }
    /// A message notification says which family it's from: each family knows this phone by its own ID.
    @objc private func openReceivedMessages(_ notification: Notification) {
        openMessages(for: PorchDevice.family(memberID: notification.userInfo?["recipientID"] as? String))
    }
    /// New messages from every family's bedside, and for caregivers what's waiting for their OK.
    static var waiting: Int {
        let coordinator = FamilyCoordinator.shared
        return PorchDevice.families.reduce(0) { total, credential in
            guard let link = coordinator.link(for: credential), !link.accessRemoved, let state = link.state else { return total }
            let review = state.me.caregiver == true ? (state.heldMessages ?? 0) + (state.heldTexts ?? 0) : 0
            return total + (state.newMessages ?? 0) + review
        }
    }
    @objc private func updateBadge() {
        let count = Self.waiting
        inbox.navigationController?.tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
    }
}

/// What a family is called on this phone's screens: what this phone calls it, or its household's name.
@MainActor func familyTitle(_ credential: FamilyCredential) -> String {
    PorchDevice.familyName(credential) ?? FamilyCoordinator.shared.state(for: credential)?.householdName ?? "Family"
}
/// The bedside's name in a family, once it has checked in.
@MainActor func bedsideName(_ credential: FamilyCredential) -> String? {
    let state = FamilyCoordinator.shared.state(for: credential)
    return state?.people.first { $0.role == .bedside }?.name ?? state?.householdName
}

/// The Messages tab: what's waiting for a caregiver's OK, then one thread for each family's bedside.
final class FamilyInboxViewController: CaregiverFormViewController {
    private let content = UIStackView()
    private struct Row: Equatable { let id: String; let name: String; let family: String?; let unheard: Int; let review: Int; let held: Int; let heldTexts: Int }
    /// The rows, or with none to show, what the page says instead.
    private struct Shown: Equatable { let rows: [Row]; let empty: String? }
    private var shown: Shown?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Messages"
        content.axis = .vertical; content.spacing = 16
        form.addArrangedSubview(content)
        hideKeyboardControl()
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: .porchFamilyChanged, object: nil)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func render() {
        guard isViewLoaded else { return }
        let coordinator = FamilyCoordinator.shared
        let families = PorchDevice.families.filter { coordinator.link(for: $0)?.accessRemoved != true }
        let several = PorchDevice.families.count > 1
        let rows = families.compactMap { credential -> Row? in
            guard let state = coordinator.state(for: credential) else { return nil }
            let name = bedsideName(credential) ?? familyTitle(credential)
            let held = state.me.caregiver == true ? state.heldMessages ?? 0 : 0, texts = state.me.caregiver == true ? state.heldTexts ?? 0 : 0
            let family = several ? familyTitle(credential) : nil
            return Row(id: credential.deviceID, name: name, family: family == name ? nil : family, unheard: state.newMessages ?? 0, review: held + texts, held: held, heldTexts: texts)
        }
        // Families that removed this phone aren't listed. When that's all of them, say so rather than Connecting.
        let all = PorchDevice.families
        let empty: String? = !rows.isEmpty ? nil : all.isEmpty ? "Join a family to send messages."
            : families.isEmpty ? (all.count == 1 ? "This phone was removed from this family." : "This phone was removed from these families.")
            : "Connecting to your family…"
        let next = Shown(rows: rows, empty: empty)
        guard next != shown else { return }
        shown = next
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        if let empty {
            let label = PorchStyle.label(empty)
            label.textAlignment = .center
            content.addArrangedSubview(label); return
        }
        // Phone voicemail and texts from numbers that aren't on the keypad wait for a caregiver.
        for row in rows where row.review > 0 {
            guard let credential = families.first(where: { $0.deviceID == row.id }) else { continue }
            let review = PorchStyle.button(FamilyHomeViewController.reviewTitle(voicemails: row.held, texts: row.heldTexts), symbol: "exclamationmark.bubble.fill")
            if several { review.configuration?.subtitle = row.family ?? row.name }
            review.accessibilityIdentifier = "family.heldVoicemail"
            review.addAction(UIAction { [weak self] _ in FamilyCoordinator.shared.select(credential); self?.openCaregiverMode(for: credential) }, for: .touchUpInside)
            content.addArrangedSubview(review)
        }
        content.addArrangedSubview(group(rows: rows.compactMap { row in
            guard let credential = families.first(where: { $0.deviceID == row.id }) else { return nil }
            let name = PorchStyle.label(row.name, size: 18, color: PorchStyle.ink, weight: .semibold)
            var lines: [UIView] = [name]
            let new = row.unheard == 1 ? "1 new message" : row.unheard > 1 ? "\(row.unheard) new messages" : nil
            if let detail = [row.family, new].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                lines.append(PorchStyle.label(detail, size: 15, color: new == nil ? PorchStyle.secondary : PorchStyle.accent, weight: new == nil ? .regular : .semibold))
            }
            let text = UIStackView(arrangedSubviews: lines); text.axis = .vertical; text.spacing = 2
            let label = [row.name, row.family, new].compactMap { $0 }.joined(separator: ", ")
            let thread = PorchListRow([FamilyAdminViewController.avatar(row.name, size: 44), text], label: "Messages with \(label)") { [weak self] in
                (self?.tabBarController as? FamilyTabBarController)?.openMessages(for: credential)
            }
            thread.accessibilityIdentifier = row.unheard > 0 ? "family.newMessages" : "family.messages"
            return thread
        }))
    }
    /// Caregiver mode for one family. Every visit starts with the PIN.
    private func openCaregiverMode(for credential: FamilyCredential) {
        guard FamilyCoordinator.shared.state(for: credential)?.me.caregiver == true else {
            let alert = UIAlertController(title: "Caregiver mode isn't on for you", message: "Ask the caregiver to turn it on for you.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true); return
        }
        navigationController?.pushViewController(RemoteCaregiverPINViewController(family: credential), animated: true)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// The You tab: this phone's families, each with its own page, joining another, and this phone's own settings.
final class FamilyYouViewController: CaregiverFormViewController {
    private let content = UIStackView()
    private struct Shown: Equatable { let families: [[String?]]; let canJoin: Bool }
    private var shown: Shown?
    private var device: String { UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad" }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "You"
        content.axis = .vertical; content.spacing = 24
        form.addArrangedSubview(content)
        hideKeyboardControl()
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: .porchFamilyChanged, object: nil)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func render() {
        guard isViewLoaded else { return }
        let families = PorchDevice.families
        let next = Shown(families: families.map { [$0.deviceID, familyTitle($0), bedsideName($0)] }, canJoin: families.count < FamilyNames.limit)
        guard next != shown else { return }
        shown = next
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        var rows: [UIView] = families.map { credential in
            let name = familyTitle(credential), person = bedsideName(credential)
            let row = linkRow(name, value: person == name ? nil : person) { [weak self] in
                self?.navigationController?.pushViewController(FamilyPageViewController(credential: credential), animated: true)
            }
            row.accessibilityIdentifier = "family.page"
            return row
        }
        if next.canJoin {
            let join = actionRow(families.isEmpty ? "Join a family" : "Join another family", symbol: "plus") { [weak self] in
                self?.navigationController?.pushViewController(FamilyPairingViewController(), animated: true)
            }
            join.accessibilityIdentifier = "family.join"
            rows.append(join)
        }
        content.addArrangedSubview(group("Your families", rows: rows))
        let camera = UISwitch(); camera.isOn = CallPreferences.startVideoWithCamera()
        camera.accessibilityIdentifier = "family.startVideoWithCamera"
        camera.addAction(UIAction { [weak camera] _ in if let camera { CallPreferences.saveStartVideoWithCamera(camera.isOn) } }, for: .valueChanged)
        var phone: [UIView] = [toggleRow("Start video calls with my camera on", camera)]
        if PorchDevice.canBeBedside {
            phone.append(linkRow("Use this \(device) as the bedside Porch", symbol: "ipad") { [weak self] in self?.confirmBedside() })
        }
        content.addArrangedSubview(group("On this \(device)", rows: phone))
        let privacy = textLink("Privacy policy", size: 16) { [weak self] in if let self { showPrivacyPolicy(on: self) } }
        privacy.accessibilityIdentifier = "family.privacy"
        content.addArrangedSubview(privacy)
    }
    private func confirmBedside() {
        let alert = UIAlertController(title: "Use this \(device) as the bedside Porch?", message: "Only do this on the device next to your loved one. You can switch back later.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Use as bedside", style: .default) { _ in PorchDevice.experience = .bedside })
        present(alert, animated: true)
    }
}

/// One family on this phone, opened from You: what the bedside shows for this phone, what this phone calls the family,
/// caregiver mode, the bedside's Porch number, and leaving. Opening it chooses the family, so the screens it opens, such
/// as caregiver mode, are for it.
final class FamilyPageViewController: CaregiverFormViewController {
    let credential: FamilyCredential
    private let content = UIStackView()
    private struct Shown: Equatable {
        let title: String, person: String?, me: String?, caregiver: Bool, number: String?, removed: Bool, connected: Bool
    }
    private var shown: Shown?
    init(credential: FamilyCredential) {
        self.credential = credential
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(credential:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        content.axis = .vertical; content.spacing = 24
        form.addArrangedSubview(content)
        hideKeyboardControl()
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: .porchFamilyChanged, object: nil)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A family already taken off this phone has nothing to show; selecting it would point the other tabs at whoever is left.
        guard isOnThisPhone else { return }
        FamilyCoordinator.shared.select(credential)
    }
    private var isOnThisPhone: Bool { PorchDevice.families.contains { $0.deviceID == credential.deviceID } }
    @objc private func render() {
        guard isViewLoaded else { return }
        // Left, or taken off this phone: back to the list, including a name or photo page still open over this one.
        // Once this page has left the stack, a later check-in must not pop whatever was opened next.
        guard isOnThisPhone else {
            if navigationController?.viewControllers.contains(where: { $0 === self }) == true {
                navigationController?.popToRootViewController(animated: true)
            }
            return
        }
        let link = FamilyCoordinator.shared.link(for: credential), state = link?.state
        let next = Shown(title: familyTitle(credential), person: bedsideName(credential), me: state?.me.name, caregiver: state?.me.caregiver == true,
                         number: state?.porchNumber, removed: link?.accessRemoved == true, connected: state != nil)
        guard next != shown else { return }
        shown = next
        title = next.title
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        if next.removed {
            content.addArrangedSubview(PorchStyle.label("This phone was removed from this family.", size: 17))
            content.addArrangedSubview(centeredLink("Remove \(next.title) from this phone", destructive: true) { [weak self] in self?.confirmRemoval() })
            return
        }
        guard next.connected else {
            content.addArrangedSubview(PorchStyle.label(link?.error ?? "Connecting to your family…"))
            content.addArrangedSubview(centeredLink("Leave \(next.title)", destructive: true) { [weak self] in self?.confirmLeave() })
            return
        }
        var rows: [UIView] = []
        let profile = linkRow("Your name and photo", value: next.me, symbol: "person.crop.circle") { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(FamilyProfileViewController(family: self.credential), animated: true)
        }
        profile.accessibilityIdentifier = "family.profile"
        rows.append(profile)
        let name = linkRow("Family name", value: next.title, symbol: "tag") { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(FamilyNameViewController(credential: self.credential), animated: true)
        }
        name.accessibilityIdentifier = "family.nickname"
        rows.append(name)
        if next.caregiver {
            let caregiver = linkRow("Caregiver mode", symbol: "lock.fill") { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(RemoteCaregiverPINViewController(family: self.credential), animated: true)
            }
            caregiver.accessibilityIdentifier = "family.caregiverMode"
            rows.append(caregiver)
        }
        content.addArrangedSubview(group(rows: rows))
        // Anyone can call the bedside on its own number, from any phone.
        if let number = next.number {
            let from = next.person ?? next.title
            let row = linkRow("Porch number", value: PorchNumber.display(number), symbol: "number") { [weak self] in
                self?.navigationController?.pushViewController(PorchNumberViewController(number: number, name: from), animated: true)
            }
            row.accessibilityIdentifier = "family.porchNumber"
            content.addArrangedSubview(group(rows: [row]))
        }
        let leave = centeredLink("Leave \(next.title)", destructive: true) { [weak self] in self?.confirmLeave() }
        leave.accessibilityIdentifier = "family.leave"
        content.addArrangedSubview(leave)
    }
    private var device: String { UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad" }
    private func confirmLeave() {
        let name = familyTitle(credential)
        let alert = UIAlertController(title: "Leave \(name)?", message: "This \(device) stops getting their calls and messages. To join again, you'll need a new invitation.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Leave", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do { try await FamilyCoordinator.shared.leave(self.credential); self.navigationController?.popToRootViewController(animated: true) }
                catch { showPorchError(error, on: self) }
            }
        })
        present(alert, animated: true)
    }
    private func confirmRemoval() {
        let name = familyTitle(credential)
        let alert = UIAlertController(title: "Remove \(name) from this phone?", message: "They've already removed this phone. To join again, you'll need a new invitation.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do { try FamilyCoordinator.shared.forget(self.credential) } catch { showPorchError(error, on: self) }
        })
        present(alert, animated: true)
    }
}

/// What this phone calls a family, to tell it from the others: two sets of parents are often both "Mom".
final class FamilyNameViewController: CaregiverFormViewController {
    private let credential: FamilyCredential
    private let nameField = UITextField()
    init(credential: FamilyCredential) {
        self.credential = credential
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(credential:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Family name"
        let device = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        nameField.text = PorchDevice.nickname(credential)
        nameField.accessibilityIdentifier = "family.nicknameField"
        let household = FamilyCoordinator.shared.state(for: credential)?.householdName ?? familyTitle(credential)
        let entry = field(nameField, title: "Family name", placeholder: household, helper: "Only on this \(device).")
        // The screen's title says what the field is for.
        (entry as? UIStackView)?.arrangedSubviews.first?.isHidden = true
        nameField.autocapitalizationType = .words
        let save = PorchStyle.button("Save")
        save.accessibilityIdentifier = "family.saveNickname"
        save.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.view.endEditing(true)
            PorchDevice.setNickname(self.nameField.text, for: self.credential)
            // The tabs and incoming calls use it too.
            NotificationCenter.default.post(name: .porchFamilyChanged, object: nil)
            self.navigationController?.popViewController(animated: true)
        }, for: .touchUpInside)
        form.addArrangedSubview(entry)
        form.addArrangedSubview(save)
    }
}

/// A bedside's own phone number, which anyone can call it on: in Contacts in one tap, or sent to someone.
final class PorchNumberViewController: CaregiverFormViewController, CNContactViewControllerDelegate, MFMessageComposeViewControllerDelegate {
    private let number: String
    private let name: String
    init(number: String, name: String) {
        self.number = number; self.name = name
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(number:name:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Porch number"
        hideKeyboardControl()
        let shown = PorchStyle.label(PorchNumber.display(number), size: 30, color: PorchStyle.ink, weight: .bold)
        shown.textAlignment = .center; shown.accessibilityIdentifier = "family.porchNumberShown"
        let add = PorchStyle.button("Add to Contacts", symbol: "person.crop.circle.badge.plus", filled: false)
        add.accessibilityIdentifier = "family.addPorchNumber"
        add.addAction(UIAction { [weak self] _ in self?.addToContacts() }, for: .touchUpInside)
        let share = PorchStyle.button("Share this number", symbol: "message", filled: false)
        share.accessibilityIdentifier = "family.sharePorchNumber"
        share.addAction(UIAction { [weak self, weak share] _ in self?.shareNumber(from: share) }, for: .touchUpInside)
        form.addArrangedSubview(section("\(name)'s Porch number", views: [shown, add, share]))
    }
    /// The bedside's Porch number as a contact, named so it's easy to find.
    private var contact: CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = "\(name)'s Porch"
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: number))]
        return contact
    }
    /// A new contact, which they can change before saving. Porch never reads Contacts.
    private func addToContacts() {
        let editor = CNContactViewController(forNewContact: contact)
        editor.delegate = self
        present(UINavigationController(rootViewController: editor), animated: true)
    }
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        viewController.dismiss(animated: true)
    }
    /// A text with the number, to whoever they choose, with a contact card so they can save it in one tap. A device
    /// that can't text, such as an iPad without Messages, gets the share sheet instead.
    private func shareNumber(from source: UIView?) {
        let note = "Here's \(name)'s Porch number: \(PorchNumber.display(number)). Call it from any phone to talk with \(name)."
        // Without the card the text still carries the number, so a card that can't be made is left out.
        let card = try? CNContactVCardSerialization.data(with: [contact])
        let filename = "\(name)'s Porch.vcf"
        guard MFMessageComposeViewController.canSendText() else {
            var items: [Any] = [note]
            if let card {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                if (try? card.write(to: file, options: .atomic)) != nil { items.append(file) }
            }
            let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
            share.popoverPresentationController?.sourceView = source
            share.popoverPresentationController?.sourceRect = source?.bounds ?? .zero
            present(share, animated: true); return
        }
        let compose = MFMessageComposeViewController()
        compose.body = note
        if let card, MFMessageComposeViewController.canSendAttachments(), MFMessageComposeViewController.isSupportedAttachmentUTI(UTType.vCard.identifier) {
            compose.addAttachmentData(card, typeIdentifier: UTType.vCard.identifier, filename: filename)
        }
        compose.messageComposeDelegate = self
        present(compose, animated: true)
    }
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}
