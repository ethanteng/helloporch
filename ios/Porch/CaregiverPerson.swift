import UIKit
import AVFoundation
import PorchCore

/// One person: their name and photo, how the bedside reaches them, and what they can do. A Porch family member has one
/// name and photo, kept with their Porch profile, which their key, calls and messages all show. Someone who's on the
/// keypad only by phone keeps the name and photo saved with their key. On a family phone, only the Porch parts show.
final class PersonViewController: CaregiverFormViewController, UIColorPickerViewControllerDelegate {
    private weak var admin: FamilyAdminViewController?
    private var memberID: String?
    private var slot: Int?
    private let content = UIStackView()
    /// Kept across redraws, which happen whenever anything in the family changes.
    private let nameField = UITextField()
    private var editedName: String?
    private var renderAfterEditing = false
    private var pickedColor: UIColor?
    private lazy var chooser = PhotoChooser(presenter: self) { [weak self] data in self?.photoChosen(data) }

    init(admin: FamilyAdminViewController, memberID: String? = nil, slot: Int? = nil) {
        self.admin = admin; self.memberID = memberID; self.slot = slot
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:memberID:slot:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        content.axis = .vertical; content.spacing = 28
        form.addArrangedSubview(content)
        nameField.accessibilityIdentifier = "person.name"
        nameField.addAction(UIAction { [weak self] _ in self?.editedName = self?.nameField.text }, for: .editingChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .porchCaregiverChanged, object: admin)
        render()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func changed() { render() }
    override func textFieldDidEndEditing(_ textField: UITextField) {
        super.textFieldDidEndEditing(textField)
        if renderAfterEditing { renderAfterEditing = false; render() }
    }

    /// The family member and their key, found again on every redraw: a key can move, and a key's person can join Porch.
    private struct Subject {
        let member: FamilyPerson?
        let slot: Int?
        let contact: CallContact?
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
    private func invitePending(_ subject: Subject, _ admin: FamilyAdminViewController) -> Bool {
        subject.member == nil && subject.contact?.invitationID.map { id in admin.current?.invitations?.contains { $0.id == id } == true } == true
    }

    /// Redrawn after every change, including one another caregiver made.
    func render() {
        guard isViewLoaded else { return }
        // Waits while the caregiver types a name, so the keyboard doesn't close.
        guard !nameField.isFirstResponder else { renderAfterEditing = true; return }
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let admin else { return }
        let subject = resolve(admin)
        memberID = subject.member?.id; slot = subject.slot
        guard subject.member != nil || subject.contact != nil else {
            // Removed here or by another caregiver.
            if navigationController?.topViewController === self { navigationController?.popViewController(animated: true) }
            return
        }
        title = subject.name
        content.addArrangedSubview(header(subject, admin))
        content.addArrangedSubview(nameGroup(subject))
        if admin.slots != nil { content.addArrangedSubview(keypadGroup(subject, admin)) }
        if let reach = reachGroup(subject, admin) { content.addArrangedSubview(reach) }
        if let dropIn = dropInGroup(subject, admin) { content.addArrangedSubview(dropIn) }
        if let member = subject.member { content.addArrangedSubview(caregiverGroup(member, admin)) }
        if let remove = removeButton(subject, admin) { content.addArrangedSubview(remove) }
    }

    // MARK: Name and photo

    private func header(_ subject: Subject, _ admin: FamilyAdminViewController) -> UIView {
        let photo = subject.contact?.customPhotoData ?? FamilyPhotos.shared.data(for: subject.member?.photoID) ?? subject.contact?.photoData
        if photo == nil, let member = subject.member { admin.loadPhoto(of: member) }
        let change = PorchStyle.button(photo == nil ? "Add photo" : "Change photo", filled: false)
        change.accessibilityIdentifier = "person.choosePhoto"
        chooser.attach(to: change)
        var views: [UIView] = [FamilyAdminViewController.avatar(subject.name, photo: photo, size: 96), change]
        if let restore = restorePhoto(subject, admin) { views.append(restore) }
        let status: String
        if let member = subject.member { status = member.id == admin.myID ? "\(member.shortStatus) · This phone" : member.shortStatus }
        else { status = invitePending(subject, admin) ? "Invite sent" : "Not on Porch" }
        let statusLabel = PorchStyle.label(status, size: 16)
        statusLabel.textAlignment = .center
        views.append(statusLabel)
        let header = UIStackView(arrangedSubviews: views)
        header.axis = .vertical; header.alignment = .center; header.spacing = 4
        header.setCustomSpacing(10, after: views[0])
        return header
    }
    /// Back to their own photo, or no photo: a caregiver's choice for a family member, or a key's own photo.
    private func restorePhoto(_ subject: Subject, _ admin: FamilyAdminViewController) -> UIButton? {
        let keyPhoto = subject.contact?.customPhotoData != nil
        if let member = subject.member {
            let chosen = member.override?.photoID != nil
            guard chosen || keyPhoto else { return nil }
            let button = PorchStyle.button(member.profile?.photoID != nil ? "Use their own photo" : "Remove photo", filled: false)
            button.accessibilityIdentifier = "person.removePhoto"
            button.addAction(UIAction { [weak self, weak admin] _ in
                guard let self, let admin else { return }
                Task {
                    if chosen { guard await admin.perform("setMemberOverride", ["memberID": member.id, "photo": NSNull()]) else { return } }
                    self.clearKeyPhoto()
                }
            }, for: .touchUpInside)
            return button
        }
        guard keyPhoto else { return nil }
        let button = PorchStyle.button("Remove photo", filled: false)
        button.accessibilityIdentifier = "person.removePhoto"
        button.addAction(UIAction { [weak self] _ in self?.clearKeyPhoto() }, for: .touchUpInside)
        return button
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
    private func nameGroup(_ subject: Subject) -> UIView {
        let saved: String?
        let placeholder: String
        if let member = subject.member {
            // A name saved on their key before names moved to Porch profiles shows until it's saved here.
            saved = member.override?.name ?? subject.contact.flatMap { $0.customName.isEmpty ? nil : $0.customName }
            placeholder = member.profile?.name ?? member.invitedName ?? member.name
        } else { saved = subject.contact?.customName; placeholder = "Their name" }
        nameField.text = editedName ?? saved
        let save = PorchStyle.button("Save", symbol: "checkmark")
        save.accessibilityLabel = "Save name"
        save.addAction(UIAction { [weak self] _ in self?.saveName() }, for: .touchUpInside)
        let name = field(nameField, title: "Name", placeholder: placeholder)
        // `field` resets capitalization, including on every redraw of this page.
        nameField.autocapitalizationType = .words
        return group(rows: [listRow(name, trailing: FamilyAdminViewController.singleLine(save), alignedToBottom: true)])
    }
    private func saveName() {
        view.endEditing(true)
        guard let admin else { return }
        let subject = resolve(admin)
        let typed = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let member = subject.member {
            Task {
                guard await admin.perform("setMemberOverride", ["memberID": member.id, "name": typed]) else { return }
                self.editedName = nil
                // One name per person: the key goes by the one saved with their Porch profile.
                let current = self.resolve(admin)
                if let key = current.slot, let contact = current.contact, !contact.customName.isEmpty { self.save { try $0.setContact(contact.updating(name: ""), for: key) } }
                self.render()
            }
        } else if let key = subject.slot, let contact = subject.contact {
            if save({ try $0.setContact(contact.updating(name: typed), for: key) }) { editedName = nil; render() }
        }
    }

    // MARK: Keypad

    private func keypadGroup(_ subject: Subject, _ admin: FamilyAdminViewController) -> UIView {
        let slots = admin.slots ?? CallSlots()
        let keyButton = PorchStyle.button(subject.slot.map { "Key \(CallSlots.symbol(for: $0))" } ?? "Add to keypad", filled: false)
        keyButton.accessibilityIdentifier = "person.key"
        var choices: [UIMenuElement] = CallSlots.digits.filter { $0 == subject.slot || slots.action(for: $0) == .unassigned }.map { digit in
            UIAction(title: "Key \(CallSlots.symbol(for: digit))", state: digit == subject.slot ? .on : .off) { [weak self] _ in self?.move(to: digit) }
        }
        if subject.slot != nil {
            choices.append(UIAction(title: "Take off the keypad", image: UIImage(systemName: "minus.circle"), attributes: .destructive) { [weak self] _ in self?.confirmRemoveFromKeypad() })
        }
        if choices.isEmpty { keyButton.configuration?.title = "Keypad is full"; keyButton.isEnabled = false }
        keyButton.menu = UIMenu(children: choices)
        keyButton.showsMenuAsPrimaryAction = true
        var rows = [listRow(PorchStyle.label("Keypad key", size: 18, color: PorchStyle.ink), trailing: FamilyAdminViewController.singleLine(keyButton))]
        if let contact = subject.contact {
            let color = RecipientAppearance.color(hex: contact.buttonColorHex)
            let swatch = UIButton(type: .system)
            swatch.backgroundColor = color
            swatch.layer.cornerRadius = 18
            swatch.layer.borderWidth = 1; swatch.layer.borderColor = PorchStyle.border.cgColor
            NSLayoutConstraint.activate([swatch.widthAnchor.constraint(equalToConstant: 36), swatch.heightAnchor.constraint(equalToConstant: 36)])
            swatch.accessibilityLabel = "Button color"
            swatch.accessibilityValue = contact.buttonColorHex.map { "Color #\($0)" } ?? "Default color"
            swatch.accessibilityIdentifier = "person.color"
            if contact.buttonColorHex != nil {
                swatch.menu = UIMenu(children: [
                    UIAction(title: "Choose a color", image: UIImage(systemName: "paintpalette")) { [weak self] _ in self?.pickColor() },
                    UIAction(title: "Use the default color", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in self?.saveColor(nil) },
                ])
                swatch.showsMenuAsPrimaryAction = true
            } else {
                swatch.addAction(UIAction { [weak self] _ in self?.pickColor() }, for: .touchUpInside)
            }
            rows.append(listRow(PorchStyle.label("Button color", size: 18, color: PorchStyle.ink), trailing: swatch))
        }
        return group(rows: rows)
    }
    /// Puts them on a free key: moves their key, or gives a family member who isn't on the keypad one.
    private func move(to digit: Int) {
        guard let admin else { return }
        let subject = resolve(admin)
        if let key = subject.slot, let contact = subject.contact {
            guard key != digit else { return }
            if save({ try $0.setContact(nil, for: key); try $0.setContact(contact, for: digit) }) { slot = digit; render() }
        } else if let member = subject.member {
            if save({ slots in
                let contact = try CallContact(name: "", nativeCall: NativeCall(room: "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: .voice),
                                              familyMemberID: member.id, invitationID: member.invitationID, memberName: member.name)
                try slots.setContact(contact, for: digit)
            }) { slot = digit; render() }
        }
    }
    private func pickColor() {
        view.endEditing(true)
        guard let admin, let contact = resolve(admin).contact else { return }
        let picker = UIColorPickerViewController()
        picker.selectedColor = RecipientAppearance.color(hex: contact.buttonColorHex)
        picker.supportsAlpha = false
        picker.delegate = self
        pickedColor = nil
        present(picker, animated: true)
    }
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) { pickedColor = viewController.selectedColor }
    /// Saved once the picker closes, rather than for every color passed on the way.
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        guard let pickedColor else { return }
        self.pickedColor = nil
        saveColor(RecipientAppearance.hex(color: pickedColor))
    }
    private func saveColor(_ hex: String?) {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot, let contact = subject.contact else { return }
        save { try $0.setContact(contact.updating(buttonColorHex: .some(hex)), for: key) }
    }

    // MARK: How the bedside reaches them

    private func reachGroup(_ subject: Subject, _ admin: FamilyAdminViewController) -> UIView? {
        guard admin.onBedside, let key = subject.slot, let contact = subject.contact else { return nil }
        let porch = subject.member != nil ? "Connected" : invitePending(subject, admin) ? "Invite sent" : contact.invitationID != nil ? "Invite expired" : "Not on Porch"
        let porchRow = listRow(PorchStyle.label("Porch app", size: 18, color: PorchStyle.ink), trailing: FamilyAdminViewController.singleLine(PorchStyle.label(porch, size: 17)))
        porchRow.isAccessibilityElement = true; porchRow.accessibilityLabel = "Porch app, \(porch)"
        var rows: [UIView] = [porchRow]
        let linked = subject.member != nil || contact.invitationID != nil
        if subject.member == nil, !invitePending(subject, admin) {
            rows.append(actionRow("Invite \(subject.firstName)", symbol: "person.badge.plus") { [weak self] in self?.invite() })
        }
        if linked, let call = contact.nativeCall {
            let mode = PorchStyle.segmented(["Voice", "Video"])
            mode.selectedSegmentIndex = call.mode == .video ? 1 : 0
            mode.accessibilityLabel = "Calls start as"
            mode.addAction(UIAction { [weak self, weak mode] _ in
                guard let self, let mode, let admin = self.admin else { return }
                let current = self.resolve(admin)
                guard let key = current.slot, let contact = current.contact else { return }
                self.save { try $0.setContact(contact.updating(mode: mode.selectedSegmentIndex == 1 ? .video : .voice), for: key) }
            }, for: .valueChanged)
            rows.append(listRow(PorchStyle.label("Calls start as", size: 18, color: PorchStyle.ink), trailing: mode))
        }
        let others = contact.otherPhoneNumbers.count
        let number = contact.phoneNumber.map { PhoneNumberNormalization.display($0) + (others > 0 ? " +\(others)" : "") }
        let phone = linkRow("Phone", value: number ?? "Add") { [weak self, weak admin] in
            guard let self, let admin else { return }
            let editor = SetupViewController(slot: key, contact: contact)
            editor.onSaveSlot = { [weak admin] action, contact in try admin?.saveSlots { try $0.setContact(contact, for: key); try $0.setAction(action, for: key) } }
            self.navigationController?.pushViewController(editor, animated: true)
        }
        phone.accessibilityIdentifier = "person.phone"
        rows.append(phone)
        let fallback = linked && contact.phoneNumber != nil ? "If Porch isn't answered in \(CallPreferences.fallbackSeconds()) seconds, Porch calls their phone. Voice only." : nil
        return group("Reach \(subject.firstName)", detail: fallback, rows: rows)
    }
    /// Invites someone who's on the keypad by phone, and links their key to the invitation.
    private func invite() {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot, let contact = subject.contact else { return }
        let invite = admin.inviteScreen()
        invite.prefilledName = contact.name
        invite.onCreated = { [weak self] id, invitedName in
            // The name moves to the invitation, and the key follows the name they choose once they join.
            self?.save { slots in
                let linked = try CallContact(name: "", nativeCall: contact.nativeCall ?? NativeCall(room: "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: .voice),
                    phoneNumber: contact.phoneNumber, otherPhoneNumbers: contact.otherPhoneNumbers, invitationID: id,
                    memberName: invitedName.isEmpty ? contact.name : invitedName, buttonColorHex: contact.buttonColorHex, photoData: contact.customPhotoData)
                try slots.setContact(linked, for: key)
            }
        }
        navigationController?.pushViewController(invite, animated: true)
    }

    // MARK: Drop-in

    private func dropInGroup(_ subject: Subject, _ admin: FamilyAdminViewController) -> UIView? {
        let state = admin.current
        var rows: [UIView] = []
        if let person = subject.member {
            let audio = UISwitch(); audio.isOn = person.permissions.audio
            let video = UISwitch(); video.isOn = person.permissions.video
            audio.accessibilityIdentifier = "person.audioDropIn"; video.accessibilityIdentifier = "person.videoDropIn"
            for toggle in [audio, video] {
                toggle.addAction(UIAction { [weak self, weak admin, weak audio, weak video] _ in
                    guard let self, let admin, let audio, let video else { return }
                    Task {
                        if admin.onBedside, audio.isOn || video.isOn { guard await admin.requestMedia(video: video.isOn) else { self.render(); return } }
                        await admin.perform("setPermissions", ["memberID": person.id, "permissions": ["audio": audio.isOn, "video": video.isOn]])
                    }
                }, for: .valueChanged)
            }
            // Their Audio call and Video call drop in too, but only as the drop-ins approved above.
            // The switch stays usable when that approval is later removed, so a saved choice can be turned off.
            let approved = person.permissions.audio || person.permissions.video
            let calls = UISwitch(); calls.isOn = person.autoDropIn == true
            calls.isEnabled = approved || person.autoDropIn == true
            calls.accessibilityIdentifier = "person.autoDropIn"
            calls.addAction(UIAction { [weak self, weak admin, weak calls] _ in
                guard let self, let admin, let calls else { return }
                Task {
                    if admin.onBedside, calls.isOn { guard await admin.requestMedia(video: person.permissions.video) else { self.render(); return } }
                    await admin.perform("setAutoDropIn", ["memberID": person.id, "enabled": calls.isOn])
                }
            }, for: .valueChanged)
            rows += [toggleRow("Audio drop-in", audio), toggleRow("Video drop-in", video),
                     toggleRow("\(person.firstName)'s calls drop in too", detail: approved ? nil : "Turn on audio or video drop-in first.", calls)]
        }
        // Approvals live on the server, so a bedside that isn't paired yet can't offer them.
        if admin.onBedside, PorchDevice.credential(for: .bedside) != nil, let contact = subject.contact, let number = contact.phoneNumber {
            let phone = UISwitch(); phone.isOn = state?.phoneDropIns?.contains { $0.number == number } == true
            phone.accessibilityIdentifier = "person.phoneDropIn"
            phone.addAction(UIAction { [weak self, weak admin, weak phone] _ in
                guard let self, let admin, let phone else { return }
                Task {
                    // A drop-in answers on this iPad, so only it can grant its own microphone.
                    if phone.isOn, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                        admin.showError(FamilyServiceError(message: "Allow microphone access in iPad Settings before approving drop-in.", status: 403))
                        self.render(); return
                    }
                    await admin.perform("setPhoneDropIn", phone.isOn ? ["number": number, "name": contact.name, "enabled": true] : ["number": number, "enabled": false])
                }
            }, for: .valueChanged)
            rows.append(toggleRow("Calls from \(PhoneNumberNormalization.display(number)) drop in", detail: "Works with most US mobile phones.", phone))
        }
        guard !rows.isEmpty else { return nil }
        let detail = state?.dropInEnabled == false ? "Drop-ins are paused for everyone." : "Drop-ins connect without anyone answering."
        return group("Drop-in", detail: detail, rows: rows)
    }

    private func caregiverGroup(_ person: FamilyPerson, _ admin: FamilyAdminViewController) -> UIView {
        let isMe = person.id == admin.myID
        let caregiver = UISwitch(); caregiver.isOn = person.caregiver == true
        caregiver.isEnabled = !isMe
        caregiver.accessibilityIdentifier = "person.caregiver"
        caregiver.addAction(UIAction { [weak admin, weak caregiver] _ in
            guard let admin, let caregiver else { return }
            Task { await admin.perform("setCaregiver", ["memberID": person.id, "enabled": caregiver.isOn]) }
        }, for: .valueChanged)
        return group(rows: [toggleRow("Caregiver mode", detail: isMe ? "Another caregiver can change this." : "Can change settings from their phone with the PIN.", caregiver)])
    }

    // MARK: Removing

    private func removeButton(_ subject: Subject, _ admin: FamilyAdminViewController) -> UIView? {
        if let member = subject.member, member.id == admin.myID { return nil }
        guard subject.member != nil || subject.contact != nil else { return nil }
        let remove = PorchStyle.button("Remove \(subject.firstName)", symbol: "person.crop.circle.badge.minus", filled: false)
        remove.configuration?.baseForegroundColor = .systemRed
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
        let sheet = UIAlertController(title: "Remove \(member.name)?", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Take off the keypad", style: .default) { [weak self] _ in self?.removeFromKeypad() })
        sheet.addAction(UIAlertAction(title: "Remove from Porch", style: .destructive) { [weak self] _ in self?.removeFromPorch(member) })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = source ?? view
        sheet.popoverPresentationController?.sourceRect = source?.bounds ?? view.bounds
        present(sheet, animated: true)
    }
    private func confirmRemoveFromKeypad() {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot else { return }
        let alert = UIAlertController(title: "Take \(subject.name) off the keypad?", message: "Key \(CallSlots.symbol(for: key)) will be empty.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in self?.removeFromKeypad() })
        present(alert, animated: true)
    }
    /// Empties their key. Their phone drop-in goes with it.
    private func removeFromKeypad() {
        guard let admin else { return }
        let subject = resolve(admin)
        guard let key = subject.slot, let contact = subject.contact else { return }
        Task {
            if let number = contact.phoneNumber, admin.current?.phoneDropIns?.contains(where: { $0.number == number }) == true {
                guard await admin.perform("setPhoneDropIn", ["number": number, "enabled": false]) else { return }
            }
            self.save { try $0.setContact(nil, for: key) }
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
