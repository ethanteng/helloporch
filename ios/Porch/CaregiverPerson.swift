import UIKit
import AVFoundation
import PorchCore

/// One person, laid out like Add someone's last step: their button as the bedside shows it, then a row for each thing about
/// them that opens a screen of its own. A Porch family member has one name and photo, kept with their Porch profile, which
/// their key, calls and messages all show. Someone who's on the keypad only by phone keeps the name and photo saved with
/// their key. On a family phone, only the Porch parts show.
final class PersonViewController: CaregiverFormViewController {
    private weak var admin: FamilyAdminViewController?
    private var memberID: String?
    private var slot: Int?
    private let content = UIStackView()
    private lazy var chooser = PhotoChooser(presenter: self) { [weak self] data in self?.photoChosen(data) }
    private var inviteTask: Task<Void, Never>?

    init(admin: FamilyAdminViewController, memberID: String? = nil, slot: Int? = nil) {
        self.admin = admin; self.memberID = memberID; self.slot = slot
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:memberID:slot:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        hideKeyboardControl()
        content.axis = .vertical; content.spacing = 24
        form.addArrangedSubview(content)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .porchCaregiverChanged, object: admin)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func changed() { render() }

    /// The family member and their key, found again on every redraw: a key can move, and a key's person can join Porch.
    private struct Subject {
        let member: FamilyPerson?
        let slot: Int?
        let contact: CallContact?
        var exists: Bool { member != nil || contact != nil }
        var name: String { member?.name ?? contact?.name ?? "" }
        var firstName: String { member?.firstName ?? name.split(separator: " ").first.map(String.init) ?? name }
    }
    private func resolve(_ admin: FamilyAdminViewController) -> Subject {
        let people = admin.current?.people ?? []
        var member = memberID.flatMap { id in people.first { $0.id == id } }
        var key = slot.flatMap { admin.slots?.contact(for: $0) == nil ? nil : $0 }
        if let found = member, key.flatMap({ admin.slots?.contact(for: $0) }).map({ FamilyAdminViewController.contact($0, isFor: found) }) != true {
            key = admin.key(for: found)
        }
        let contact = key.flatMap { admin.slots?.contact(for: $0) }
        if member == nil, let contact { member = people.first { FamilyAdminViewController.contact(contact, isFor: $0) } }
        return Subject(member: member, slot: key, contact: contact)
    }
    /// The invitation their key waits on, while it can still be used.
    private func pendingInvitation(_ subject: Subject, _ admin: FamilyAdminViewController) -> PendingFamilyInvitation? {
        guard subject.member == nil, let id = subject.contact?.invitationID else { return nil }
        return admin.current?.invitations?.first { $0.id == id }
    }

    /// Redrawn after every change, including one another caregiver made.
    func render() {
        guard isViewLoaded else { return }
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let admin else { return }
        let subject = resolve(admin)
        memberID = subject.member?.id; slot = subject.slot
        guard subject.exists else {
            // Removed here or by another caregiver.
            if navigationController?.topViewController === self { navigationController?.popViewController(animated: true) }
            return
        }
        title = subject.name
        let photo = subject.contact?.customPhotoData ?? FamilyPhotos.shared.data(for: subject.member?.photoID) ?? subject.contact?.photoData
        if photo == nil, let member = subject.member { admin.loadPhoto(of: member) }
        if let key = subject.slot, let contact = subject.contact {
            content.addArrangedSubview(keyTop(subject, key: key, contact: contact, photo: photo, admin))
        } else {
            content.addArrangedSubview(header(subject, photo: photo, admin))
        }
        content.addArrangedSubview(group(rows: rows(subject, admin)))
        if let member = subject.member { content.addArrangedSubview(caregiverGroup(member, admin)) }
        if let remove = removeLink(subject, admin) { content.addArrangedSubview(remove) }
    }
    /// They're still in the family, or still on a key.
    var showsSomeone: Bool { admin.map { resolve($0).exists } ?? false }
    /// Back to this page from one of its screens, or past it once they're gone.
    func returnHere() {
        guard let navigation = navigationController, let index = navigation.viewControllers.firstIndex(of: self) else { return }
        if showsSomeone { navigation.popToViewController(self, animated: true) }
        else if index > 0 { navigation.popToViewController(navigation.viewControllers[index - 1], animated: true) }
    }
    private func push(_ controller: UIViewController) {
        view.endEditing(true)
        navigationController?.pushViewController(controller, animated: true)
    }
    private func open(_ title: String, keyboard: Bool = false, _ build: @escaping (PersonDetailViewController) -> [UIView]?) {
        guard let admin else { return }
        push(PersonDetailViewController(admin: admin, page: self, title: title, keyboard: keyboard, build: build))
    }

    // MARK: Top of the page

    /// Their button on the bedside, with its photo and color under it.
    private func keyTop(_ subject: Subject, key: Int, contact: CallContact, photo: Data?, _ admin: FamilyAdminViewController) -> UIView {
        let caption = PorchStyle.label("On \(admin.lovedOne)’s screen", size: 15, weight: .semibold)
        caption.textAlignment = .center
        let preview = AddCheckViewController.preview(name: subject.name, photo: photo, colorHex: contact.buttonColorHex,
                                                     key: CallSlots.symbol(for: key), identifier: "person.preview")
        let swatches = AddSwatch.row(selected: contact.buttonColorHex) { [weak self] hex in self?.saveColor(hex) }
        let look = UIStackView(arrangedSubviews: [photoButton(subject, photo: photo, admin), UIView(), swatches])
        look.alignment = .center
        let stack = UIStackView(arrangedSubviews: [caption, preview, look])
        stack.axis = .vertical; stack.spacing = 14
        stack.setCustomSpacing(8, after: caption)
        return stack
    }
    /// Their photo and how their device is doing, for someone without a key.
    private func header(_ subject: Subject, photo: Data?, _ admin: FamilyAdminViewController) -> UIView {
        let status: String
        if let member = subject.member { status = member.id == admin.myID ? "\(member.shortStatus) · This phone" : member.shortStatus }
        else { status = pendingInvitation(subject, admin) != nil ? "Invite sent" : "Not on Porch" }
        let statusLabel = PorchStyle.label(status, size: 16)
        statusLabel.textAlignment = .center
        let avatar = FamilyAdminViewController.avatar(subject.name, photo: photo, size: 96)
        let header = UIStackView(arrangedSubviews: [avatar, photoButton(subject, photo: photo, admin), statusLabel])
        header.axis = .vertical; header.alignment = .center; header.spacing = 8
        header.setCustomSpacing(12, after: avatar)
        return header
    }
    /// Takes or chooses a photo, and goes back to their own photo or none.
    private func photoButton(_ subject: Subject, photo: Data?, _ admin: FamilyAdminViewController) -> UIView {
        let button = PorchStyle.button(photo == nil ? "Photo" : "Change photo", symbol: "photo", filled: false)
        button.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
        button.accessibilityIdentifier = "person.choosePhoto"
        var choices: [UIMenuElement] = chooser.menu.children
        if let restore = restorePhoto(subject, admin) { choices.append(UIMenu(options: .displayInline, children: [restore])) }
        button.menu = UIMenu(children: choices)
        button.showsMenuAsPrimaryAction = true
        return FamilyAdminViewController.singleLine(button)
    }
    /// Back to their own photo, or no photo: a caregiver's choice for a family member, or a key's own photo.
    private func restorePhoto(_ subject: Subject, _ admin: FamilyAdminViewController) -> UIAction? {
        guard subject.member != nil || subject.contact?.customPhotoData != nil else { return nil }
        if let member = subject.member, member.override?.photoID == nil, subject.contact?.customPhotoData == nil { return nil }
        let own = subject.member?.profile?.photoID != nil
        return UIAction(title: own ? "Use their own photo" : "Remove photo", image: UIImage(systemName: own ? "arrow.uturn.backward" : "trash"),
                        attributes: own ? [] : .destructive) { [weak self] _ in self?.removePhoto() }
    }
    /// Undoes the photo a caregiver chose for them.
    func removePhoto() {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let member = subject.member, member.override?.photoID != nil else { clearKeyPhoto(); return }
        Task {
            guard await admin.perform("setMemberOverride", ["memberID": member.id, "photo": NSNull()]) else { return }
            self.clearKeyPhoto()
        }
    }
    private func photoChosen(_ data: Data?) {
        guard let admin else { return }
        guard let data else { admin.showError(FamilyServiceError(message: "That photo couldn't be opened. Please choose another photo.", status: 400)); return }
        let subject = resolve(admin)
        if let member = subject.member {
            Task {
                guard await admin.chooseOverridePhoto(data, for: member.id) else { return }
                // One photo per person: the key shows the one saved with their Porch profile.
                self.clearKeyPhoto()
            }
        } else if let key = subject.slot, let contact = subject.contact {
            save { try $0.setContact(contact.updating(photoData: .some(data)), for: key) }
        }
    }
    private func clearKeyPhoto() {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot, let contact = subject.contact, contact.customPhotoData != nil else { return }
        save { try $0.setContact(contact.updating(photoData: .some(nil)), for: key) }
    }
    func saveColor(_ hex: String?) {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot, let contact = subject.contact, contact.buttonColorHex?.uppercased() != hex?.uppercased() else { return }
        save { try $0.setContact(contact.updating(buttonColorHex: .some(hex)), for: key) }
    }

    // MARK: Rows

    private func rows(_ subject: Subject, _ admin: FamilyAdminViewController) -> [UIView] {
        let name = linkRow("Name", value: subject.name, symbol: "person") { [weak self] in self?.openName() }
        name.accessibilityIdentifier = "person.row.name"
        var rows: [UIView] = [name]
        if admin.onBedside, subject.slot != nil, let contact = subject.contact {
            let app = porchApp(subject, contact, admin)
            let porch = linkRow("Porch app", value: app.value, symbol: "video", valueIsAction: app.isAction) { [weak self] in self?.openPorchApp() }
            porch.accessibilityIdentifier = "person.row.app"
            rows.append(porch)
            let others = contact.otherPhoneNumbers.count
            let number = contact.phoneNumber.map { PhoneNumberNormalization.display($0) + (others > 0 ? " +\(others)" : "") }
            let phone = linkRow("Phone", value: number ?? "Add", symbol: "phone", valueIsAction: number == nil) { [weak self] in self?.openPhone() }
            phone.accessibilityIdentifier = "person.phone"
            rows.append(phone)
        }
        if admin.slots != nil {
            let key = linkRow("Key", value: subject.slot.map { CallSlots.symbol(for: $0) } ?? "None", symbol: "circle.grid.3x3") { [weak self] in self?.openKey() }
            key.accessibilityIdentifier = "person.key"
            rows.append(key)
        }
        if let value = dropInValue(subject, admin) {
            let dropIn = linkRow("Drop-in", value: value, symbol: "waveform") { [weak self] in self?.openDropIn() }
            dropIn.accessibilityIdentifier = "person.row.dropIn"
            rows.append(dropIn)
        }
        return rows
    }
    private func porchApp(_ subject: Subject, _ contact: CallContact, _ admin: FamilyAdminViewController) -> (value: String, isAction: Bool) {
        if subject.member != nil { return ("Connected", false) }
        if pendingInvitation(subject, admin) != nil { return ("Invite sent", false) }
        return contact.invitationID != nil ? ("Invite expired", false) : ("Invite", true)
    }
    /// The number whose calls can drop in: the one Porch calls. Approvals live on the server, so a bedside that isn't
    /// paired yet can't offer them.
    private func dropInNumber(_ subject: Subject, _ admin: FamilyAdminViewController) -> String? {
        guard admin.onBedside, PorchDevice.credential(for: .bedside) != nil else { return nil }
        return subject.contact?.phoneNumber
    }
    /// What the Drop-in row says, or nil when there's nothing to set.
    private func dropInValue(_ subject: Subject, _ admin: FamilyAdminViewController) -> String? {
        let number = dropInNumber(subject, admin)
        guard subject.member != nil || number != nil else { return nil }
        if admin.current?.dropInEnabled == false { return "Paused" }
        let phone = number.flatMap { number in admin.current?.phoneDropIns?.contains { $0.number == number } == true ? "Phone" : nil }
        let parts = [subject.member?.dropInModes, phone].compactMap { $0 }
        return parts.isEmpty ? "Off" : parts.joined(separator: " · ")
    }

    // MARK: Name

    private func openName() {
        guard let admin else { return }
        let field = UITextField()
        field.accessibilityIdentifier = "person.name"
        field.text = savedName(resolve(admin))
        open("Name", keyboard: true) { [weak self] detail in
            guard let self, let admin = self.admin else { return nil }
            let subject = self.resolve(admin)
            guard subject.exists else { return nil }
            let entry = detail.field(field, title: "Name", placeholder: self.namePlaceholder(subject))
            // The screen's title says what the field is for.
            (entry as? UIStackView)?.arrangedSubviews.first?.isHidden = true
            // `field` resets capitalization, including on every redraw.
            field.autocapitalizationType = .words
            let save = PorchStyle.button("Save")
            save.accessibilityIdentifier = "person.saveName"
            save.addAction(UIAction { [weak self, weak detail, weak field] _ in
                detail?.view.endEditing(true)
                self?.saveName(field?.text) { detail?.navigationController?.popViewController(animated: true) }
            }, for: .touchUpInside)
            return [entry, save]
        }
    }
    /// The name a caregiver saved for them, which the field starts with.
    private func savedName(_ subject: Subject) -> String? {
        // A name saved on their key before names moved to Porch profiles shows until it's saved here.
        if let member = subject.member { return member.override?.name ?? subject.contact.flatMap { $0.customName.isEmpty ? nil : $0.customName } }
        return subject.contact?.customName
    }
    /// A family member's own name, which an empty field goes back to.
    private func namePlaceholder(_ subject: Subject) -> String {
        subject.member.map { $0.profile?.name ?? $0.invitedName ?? $0.name } ?? "Their name"
    }
    func saveName(_ text: String?, then done: @escaping () -> Void = {}) {
        guard let admin else { return }
        let subject = resolve(admin)
        let typed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let member = subject.member {
            Task {
                guard await admin.perform("setMemberOverride", ["memberID": member.id, "name": typed]) else { return }
                // One name per person: the key goes by the one saved with their Porch profile.
                let current = self.resolve(admin)
                if let key = current.slot, let contact = current.contact, !contact.customName.isEmpty { self.save { try $0.setContact(contact.updating(name: ""), for: key) } }
                done()
            }
        } else if let key = subject.slot, let contact = subject.contact {
            if save({ try $0.setContact(contact.updating(name: typed), for: key) }) { done() }
        }
    }

    // MARK: Porch app

    private func openPorchApp() { open("Porch app") { [weak self] detail in self?.porchAppViews(detail) } }
    private func porchAppViews(_ detail: PersonDetailViewController) -> [UIView]? {
        guard let admin else { return nil }
        let subject = resolve(admin)
        guard subject.slot != nil, let contact = subject.contact else { return nil }
        var views: [UIView] = []
        if let member = subject.member {
            views.append(detail.group(rows: [detail.padded([Self.status("Connected", detail: member.shortStatus, symbol: "checkmark.circle.fill")])]))
        } else if let invitation = pendingInvitation(subject, admin) {
            let resend = PorchStyle.button("Send a new invite", filled: false)
            resend.accessibilityIdentifier = "person.resendInvite"
            resend.isEnabled = inviteTask == nil
            resend.addAction(UIAction { [weak self, weak detail] _ in self?.sendInvite(replacing: invitation.id, from: detail) }, for: .touchUpInside)
            let cancel = detail.centeredLink("Cancel invite", destructive: true) { [weak self, weak detail] in self?.confirmCancelInvite(invitation, on: detail) }
            cancel.accessibilityIdentifier = "person.cancelInvite"
            let status = Self.status("Invite sent", detail: "Expires \(Self.expiry(invitation.expiresAt))", symbol: "clock")
            views.append(detail.group(rows: [detail.padded([status, resend, cancel])]))
        } else {
            let expired = contact.invitationID != nil
            let invite = PorchStyle.button(expired ? "Send a new invite" : "Invite \(subject.firstName)", symbol: expired ? nil : "person.badge.plus")
            invite.accessibilityIdentifier = "person.invite"
            invite.isEnabled = inviteTask == nil
            invite.addAction(UIAction { [weak self, weak detail] _ in self?.sendInvite(replacing: nil, from: detail) }, for: .touchUpInside)
            views.append(expired ? detail.group(rows: [detail.padded([Self.status("Invite expired", detail: nil, symbol: "clock"), invite])]) : invite)
            // Or they joined Porch some other way, such as an invitation from People.
            let unlinked = (admin.current?.people ?? []).filter { admin.key(for: $0) == nil }
            if !unlinked.isEmpty {
                let choose = detail.actionRow("Choose from Family on Porch", symbol: "person.2")
                choose.accessibilityIdentifier = "person.linkFamily"
                choose.menu = UIMenu(children: unlinked.map { person in UIAction(title: person.name) { [weak self] _ in self?.link(to: person) } })
                choose.showsMenuAsPrimaryAction = true
                views.append(detail.group(rows: [choose]))
            }
        }
        if subject.member != nil || contact.invitationID != nil, let call = contact.nativeCall {
            let mode = PorchStyle.segmented(["Voice", "Video"])
            mode.selectedSegmentIndex = call.mode == .video ? 1 : 0
            mode.accessibilityLabel = "Calls start with"
            mode.accessibilityIdentifier = "person.callMode"
            mode.addAction(UIAction { [weak self, weak mode] _ in
                guard let self, let mode, let admin = self.admin else { return }
                let current = self.resolve(admin)
                guard let key = current.slot, let contact = current.contact else { return }
                self.save { try $0.setContact(contact.updating(mode: mode.selectedSegmentIndex == 1 ? .video : .voice), for: key) }
            }, for: .valueChanged)
            views.append(detail.group("Calls start with", rows: [detail.padded([mode])]))
        }
        return views
    }
    /// An icon beside a line or two about where things stand.
    private static func status(_ title: String, detail: String?, symbol: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)))
        icon.tintColor = PorchStyle.accent
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, FamilyAdminViewController.text(title, [detail])])
        row.spacing = 12; row.alignment = .center
        row.isAccessibilityElement = true
        row.accessibilityLabel = [title, detail].compactMap { $0 }.joined(separator: ". ")
        return row
    }
    /// Invitations last a day, so the expiry needs its day: "tomorrow, 3:14 PM", which follows "Expires".
    static func expiry(_ time: TimeInterval) -> String {
        let format = DateFormatter(); format.dateStyle = .short; format.timeStyle = .short; format.doesRelativeDateFormatting = true
        let text = format.string(from: Date(timeIntervalSince1970: time))
        for word in ["Today", "Tomorrow"] where text.hasPrefix(word) { return word.lowercased() + text.dropFirst(word.count) }
        return text
    }
    /// Invites them, or invites them again, as Add someone does, and shows the invitation to send.
    private func sendInvite(replacing old: String?, from detail: PersonDetailViewController?) {
        guard inviteTask == nil, let admin, let contact = resolve(admin).contact else { return }
        let name = contact.name
        inviteTask = Task { [weak self, weak detail] in
            defer { self?.inviteTask = nil; detail?.render() }
            do {
                // Asked first, so refusing the microphone or camera leaves the old invitation as it was.
                guard await admin.requestMedia(video: true) else { return }
                // The old invitation stops working next, so only the new one can join them to this key.
                if let old { guard await admin.perform("cancelInvite", ["inviteID": old]) else { return } }
                let invitation = try await AddCheckViewController.invite(name, audio: true, video: true, admin: admin)
                guard let self else { return }
                let current = self.resolve(admin)
                guard let key = current.slot, let contact = current.contact else { return }
                guard self.save({ try $0.setContact(Self.linked(contact, invitationID: invitation.id, name: name), for: key) }) else { return }
                let draft = AddSomeoneDraft(key: nil, fromKeyTile: false)
                draft.name = name
                let screen = AddInviteViewController(admin: admin, draft: draft, link: invitation.link)
                screen.returnsTo = self
                self.push(screen)
            } catch AddSomeoneCancelled.mediaRefused {
                // requestMedia has said why.
            } catch {
                admin.showError(error)
            }
        }
        detail?.render()
    }
    private func confirmCancelInvite(_ invitation: PendingFamilyInvitation, on presenter: UIViewController?) {
        guard let admin else { return }
        let alert = UIAlertController(title: "Cancel \(resolve(admin).firstName)’s invite?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep", style: .cancel))
        alert.addAction(UIAlertAction(title: "Cancel invite", style: .destructive) { [weak self] _ in self?.cancelInvite(invitation.id) })
        (presenter ?? self).present(alert, animated: true)
    }
    /// Cancels their invitation. Their key stays, reached by phone.
    func cancelInvite(_ id: String) {
        guard let admin else { return }
        Task {
            guard await admin.perform("cancelInvite", ["inviteID": id]) else { return }
            let current = self.resolve(admin)
            // A key with no number has no other way to reach them, so it keeps the invitation, which can be sent again.
            guard let key = current.slot, let contact = current.contact, contact.invitationID == id, contact.phoneNumber != nil else { return }
            self.save { try $0.setContact(Self.unlinked(contact), for: key) }
        }
    }
    /// Links the key of someone who's on the keypad by phone to them on Porch.
    func link(to person: FamilyPerson) {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot, let contact = subject.contact else { return }
        save { try $0.setContact(Self.linked(contact, memberID: person.id, invitationID: person.invitationID, name: person.name), for: key) }
    }
    /// A key for someone on Porch, or invited to it: it keeps the key's numbers, how calls start, color and photo, and goes
    /// by their Porch name.
    private static func linked(_ contact: CallContact, memberID: String? = nil, invitationID: String?, name: String) throws -> CallContact {
        try CallContact(name: "", nativeCall: contact.nativeCall ?? NativeCall(room: "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: .voice),
            phoneNumber: contact.phoneNumber, otherPhoneNumbers: contact.otherPhoneNumbers, familyMemberID: memberID, invitationID: invitationID,
            memberName: name, buttonColorHex: contact.buttonColorHex, photoData: contact.customPhotoData)
    }
    /// A key reached only by phone, under the name it had.
    private static func unlinked(_ contact: CallContact) throws -> CallContact {
        try CallContact(name: contact.name, nativeCall: contact.nativeCall ?? NativeCall(room: "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: .voice),
            phoneNumber: contact.phoneNumber, otherPhoneNumbers: contact.otherPhoneNumbers, buttonColorHex: contact.buttonColorHex, photoData: contact.customPhotoData)
    }

    // MARK: Phone and key

    private func openPhone() {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot, let contact = subject.contact else { return }
        push(AddPhoneNumbersViewController(admin: admin, key: key, contact: contact))
    }
    private func openKey() {
        guard let admin else { return }
        let subject = resolve(admin)
        let draft = AddSomeoneDraft(key: subject.slot, fromKeyTile: false, startKey: subject.slot)
        draft.name = subject.name
        let screen = AddKeyViewController(admin: admin, draft: draft)
        screen.onDone = { [weak self, weak screen] chosen in
            guard let self else { return }
            if let chosen, chosen != self.slot, !self.move(to: chosen) { return }
            screen?.navigationController?.popViewController(animated: true)
        }
        if subject.slot != nil { screen.takeOff = { [weak self, weak screen] in self?.confirmRemoveFromKeypad(on: screen) } }
        push(screen)
    }
    /// Puts them on a free key: moves their key, or gives a family member who isn't on the keypad one.
    @discardableResult func move(to digit: Int) -> Bool {
        guard let admin else { return false }
        let subject = resolve(admin)
        if let key = subject.slot, let contact = subject.contact {
            guard key != digit else { return true }
            // Saving notifies this page before it returns. A phone-only person is found by their key,
            // so the new key has to be tracked first or the redraw treats them as removed and closes.
            let previous = slot
            slot = digit
            guard save({ try $0.setContact(nil, for: key); try $0.setContact(contact, for: digit) }) else {
                slot = previous
                return false
            }
            render()
            return true
        } else if let member = subject.member {
            guard save({ slots in
                let contact = try CallContact(name: "", nativeCall: NativeCall(room: "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: .voice),
                                              familyMemberID: member.id, invitationID: member.invitationID, memberName: member.name)
                try slots.setContact(contact, for: digit)
            }) else { return false }
            slot = digit; render()
            return true
        }
        return false
    }

    // MARK: Drop-in

    private func openDropIn() { open("Drop-in") { [weak self] detail in self?.dropInViews(detail) } }
    /// Someone's drop-in on its own, under their name, for the Drop-in page's list.
    static func dropInScreen(admin: FamilyAdminViewController, memberID: String) -> UIViewController {
        let page = PersonViewController(admin: admin, memberID: memberID)
        let name = admin.current?.people.first { $0.id == memberID }?.name ?? "Drop-in"
        // The screen keeps the page, so the page can't keep the screen.
        return PersonDetailViewController(admin: admin, page: page, title: name, keyboard: false) { [unowned page] detail in page.dropInViews(detail) }
    }
    private func dropInViews(_ detail: PersonDetailViewController) -> [UIView]? {
        guard let admin else { return nil }
        let subject = resolve(admin)
        guard subject.exists else { return nil }
        let paused = admin.current?.dropInEnabled == false
        var views: [UIView] = [PorchStyle.label(paused ? "Drop-ins are paused for everyone." : "Connects without \(admin.lovedOne) answering.", size: 16)]
        // Porch app calls and phone calls are approved apart, so each gets its own card.
        if let person = subject.member {
            let audio = UISwitch(); audio.isOn = person.permissions.audio
            let video = UISwitch(); video.isOn = person.permissions.video
            audio.accessibilityIdentifier = "person.audioDropIn"; video.accessibilityIdentifier = "person.videoDropIn"
            for toggle in [audio, video] {
                toggle.addAction(UIAction { [weak admin, weak detail, weak audio, weak video] _ in
                    guard let admin, let audio, let video else { return }
                    Task {
                        if admin.onBedside, audio.isOn || video.isOn { guard await admin.requestMedia(video: video.isOn) else { detail?.render(); return } }
                        await admin.perform("setPermissions", ["memberID": person.id, "permissions": ["audio": audio.isOn, "video": video.isOn]])
                    }
                }, for: .valueChanged)
            }
            let rows = [detail.toggleRow("Audio", audio), detail.toggleRow("Video", video)]
            audio.accessibilityLabel = "Audio drop-in"; video.accessibilityLabel = "Video drop-in"
            views.append(detail.group("Porch app", rows: rows))
        }
        if let number = dropInNumber(subject, admin), let contact = subject.contact {
            let phone = UISwitch(); phone.isOn = admin.current?.phoneDropIns?.contains { $0.number == number } == true
            phone.accessibilityIdentifier = "person.phoneDropIn"
            phone.addAction(UIAction { [weak admin, weak detail, weak phone] _ in
                guard let admin, let phone else { return }
                Task {
                    // A drop-in answers on this iPad, so only it can grant its own microphone.
                    if phone.isOn, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                        admin.showError(FamilyServiceError(message: "Allow microphone access in iPad Settings before approving drop-in.", status: 403))
                        detail?.render(); return
                    }
                    await admin.perform("setPhoneDropIn", phone.isOn ? ["number": number, "name": contact.name, "enabled": true] : ["number": number, "enabled": false])
                }
            }, for: .valueChanged)
            let shown = PhoneNumberNormalization.display(number)
            let row = detail.toggleRow("Calls from \(shown)", detail: "Audio only.", phone)
            phone.accessibilityLabel = "Calls from \(shown) drop in"
            views.append(detail.group("Phone", rows: [row]))
        }
        return views
    }

    // MARK: Caregiver mode

    private func caregiverGroup(_ person: FamilyPerson, _ admin: FamilyAdminViewController) -> UIView {
        let isMe = person.id == admin.myID
        let caregiver = UISwitch(); caregiver.isOn = person.caregiver == true
        caregiver.isEnabled = !isMe
        caregiver.accessibilityIdentifier = "person.caregiver"
        caregiver.addAction(UIAction { [weak admin, weak caregiver] _ in
            guard let admin, let caregiver else { return }
            Task { await admin.perform("setCaregiver", ["memberID": person.id, "enabled": caregiver.isOn]) }
        }, for: .valueChanged)
        return group(rows: [toggleRow("Caregiver mode", detail: isMe ? "Another caregiver can change this." : "Can change settings from their phone.", caregiver)])
    }

    // MARK: Removing

    private func removeLink(_ subject: Subject, _ admin: FamilyAdminViewController) -> UIView? {
        if let member = subject.member, member.id == admin.myID { return nil }
        let remove = centeredLink("Remove \(subject.firstName)", destructive: true) {}
        remove.accessibilityIdentifier = "person.remove"
        remove.addAction(UIAction { [weak self, weak remove] _ in self?.confirmRemove(from: remove) }, for: .touchUpInside)
        return remove
    }
    private func confirmRemove(from source: UIView?) {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let member = subject.member else { confirmRemoveFromKeypad(); return }
        let leaving = "Their device will need a new invitation to call this Porch again."
        guard subject.slot != nil else {
            let alert = UIAlertController(title: "Remove \(member.name) from Porch?", message: leaving, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in self?.removeFromPorch(member) })
            present(alert, animated: true); return
        }
        let sheet = UIAlertController(title: "Remove \(member.name)?", message: "Remove from Porch also empties their key. \(leaving)", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Take off the keypad", style: .default) { [weak self] _ in self?.removeFromKeypad() })
        sheet.addAction(UIAlertAction(title: "Remove from Porch", style: .destructive) { [weak self] _ in self?.removeFromPorch(member) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = source ?? view
        sheet.popoverPresentationController?.sourceRect = source?.bounds ?? view.bounds
        present(sheet, animated: true)
    }
    /// Asks before emptying their key, on this page or the screen it was asked from.
    private func confirmRemoveFromKeypad(on presenter: UIViewController? = nil) {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot else { return }
        let alert = UIAlertController(title: "Take \(subject.name) off the keypad?", message: "Key \(CallSlots.symbol(for: key)) will be empty.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.removeFromKeypad { if presenter != nil { self?.returnHere() } }
        })
        (presenter ?? self).present(alert, animated: true)
    }
    /// Empties their key. Their phone drop-in goes with it.
    func removeFromKeypad(then done: @escaping () -> Void = {}) {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot, let contact = subject.contact else { return }
        Task {
            if let number = contact.phoneNumber, admin.current?.phoneDropIns?.contains(where: { $0.number == number }) == true {
                guard await admin.perform("setPhoneDropIn", ["number": number, "enabled": false]) else { return }
            }
            if self.save({ try $0.setContact(nil, for: key) }) { done() }
        }
    }
    /// Revokes their access, and on the bedside empties their key too.
    private func removeFromPorch(_ member: FamilyPerson) {
        guard let admin else { return }
        let onKeypad = resolve(admin).slot != nil
        Task {
            guard await admin.perform("revoke", ["memberID": member.id]) else { return }
            if onKeypad { self.removeFromKeypad() }
        }
    }

    /// Saves a keypad change, or shows why it couldn't be saved.
    @discardableResult private func save(_ change: (inout CallSlots) throws -> Void) -> Bool {
        do { try admin?.saveSlots(change); return true }
        catch { admin?.showError(error); return false }
    }
}

/// One part of someone's page on a screen of its own: their name, Porch app or drop-in. It redraws whenever the family
/// changes, as the page does, and goes back past the page once they're gone. It keeps the page that builds it, which
/// isn't always open: the Drop-in page's list opens someone's drop-in on its own.
final class PersonDetailViewController: CaregiverFormViewController {
    private weak var admin: FamilyAdminViewController?
    private let page: PersonViewController
    private let build: (PersonDetailViewController) -> [UIView]?
    private let keyboard: Bool
    private var typing = false
    private var redrawAfterEditing = false

    init(admin: FamilyAdminViewController, page: PersonViewController, title: String, keyboard: Bool, build: @escaping (PersonDetailViewController) -> [UIView]?) {
        self.admin = admin; self.page = page; self.build = build; self.keyboard = keyboard
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:page:title:keyboard:build:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        if !keyboard { hideKeyboardControl() }
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: .porchCaregiverChanged, object: admin)
        render()
    }
    @objc func render() {
        guard isViewLoaded else { return }
        // Waits while something is typed, so the keyboard doesn't close.
        guard !typing else { redrawAfterEditing = true; return }
        form.arrangedSubviews.forEach { form.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let views = build(self) else {
            guard let navigation = navigationController, navigation.topViewController === self else { return }
            if navigation.viewControllers.contains(page) { page.returnHere() } else { navigation.popViewController(animated: true) }
            return
        }
        views.forEach(form.addArrangedSubview)
    }
    override func textFieldDidBeginEditing(_ textField: UITextField) {
        super.textFieldDidBeginEditing(textField)
        typing = true
    }
    override func textFieldDidEndEditing(_ textField: UITextField) {
        super.textFieldDidEndEditing(textField)
        typing = false
        if redrawAfterEditing { redrawAfterEditing = false; render() }
    }
}
