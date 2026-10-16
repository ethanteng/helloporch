import UIKit
import ContactsUI
import PorchCore

final class SlotsViewController: UITableViewController {
    var onSave: ((CallSlots) throws -> Void)?
    private var slots: CallSlots
    init(slots: CallSlots) { self.slots = slots; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init(slots:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        title = "Caregiver mode"
        tableView.backgroundColor = PorchStyle.page
        tableView.tintColor = PorchStyle.accent
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 94
        tableView.cellLayoutMarginsFollowReadableWidth = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Back to clock", style: .done, target: self, action: #selector(done))
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let state = FamilyCoordinator.shared.state { try? slots.reconcile(with: state) }
        tableView.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? CallSlots.count : section == 1 ? 3 : 1 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = PorchStyle.surface
        cell.accessoryType = .disclosureIndicator
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = PorchStyle.ink
        content.textProperties.font = PorchStyle.font(21, weight: .semibold)
        content.secondaryTextProperties.color = PorchStyle.secondary
        content.secondaryTextProperties.font = PorchStyle.font(16)
        content.secondaryTextProperties.numberOfLines = 0
        content.directionalLayoutMargins = .init(top: 18, leading: 18, bottom: 18, trailing: 18)
        content.imageProperties.tintColor = PorchStyle.accent
        content.imageToTextPadding = 18
        if indexPath.section == 0 {
            let number = CallSlots.digits[indexPath.row]
            let person = slots.contact(for: number)
            let action = slots.action(for: number) ?? .person
            content.text = action == .person ? (person?.name ?? "Add a person") : action.title
            content.image = UIImage(systemName: "\(number).circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32))
            content.secondaryText = person.map { contact in
                if let call = contact.nativeCall {
                    return "Porch \(call.mode == .video ? "video" : "voice")" + (contact.phoneNumber == nil ? "" : " · Phone fallback on")
                }
                return "Finish Porch setup"
            } ?? "Assign keypad number \(number)"
            if action != .person { content.secondaryText = action == .callControl ? "Tap to answer or hang up. Hold to decline a ringing call." : "Toggle your camera during a video call." }
            cell.accessibilityLabel = "Key \(number), \(content.text ?? "")"
        } else if indexPath.section == 1, indexPath.row == 0 {
            content.text = "Family & drop-in"
            content.secondaryText = "Pair devices, invite people, and approve access"
            content.image = UIImage(systemName: "person.2.fill")
        } else if indexPath.section == 1, indexPath.row == 1 {
            content.text = "Call preferences"
            content.secondaryText = "Phone fallback after \(CallPreferences.fallbackSeconds()) seconds · Dialing sound"
            content.image = UIImage(systemName: "phone.badge.waveform")
        } else if indexPath.section == 1 {
            content.text = "Bedside display"
            content.secondaryText = BedsidePreferences.load().appearance == .dynamic ? "Dynamic · Day, night & seasons" : "Default · Dark date & time"
            content.image = UIImage(systemName: "sun.and.horizon")
        } else {
            content.text = "Bedside mode"
            content.secondaryText = "Change this device to family mode"
            content.image = UIImage(systemName: "ipad.and.iphone")
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Keypad · people & controls", "Settings", "Device mode"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Ten digits, each with its own action. By default 1–8 call people, 9 toggles video, and 0 answers or hangs up. Any digit can be reassigned. Saving never places a call." : nil
    }
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = PorchStyle.secondary
    }
    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor = PorchStyle.secondary
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            let controller: UIViewController = indexPath.row == 0 ? FamilyAdminViewController() : indexPath.row == 1 ? CallPreferencesViewController() : BedsideDisplaySettingsViewController()
            navigationController?.pushViewController(controller, animated: true); return
        }
        if indexPath.section == 2 { offerExperienceChange(on: self); return }
        let number = CallSlots.digits[indexPath.row]
        let editor = SetupViewController(slot: number, contact: slots.contact(for: number), action: slots.action(for: number) ?? .person)
        editor.onSaveSlot = { [weak self] action, contact in
            guard let self else { return }
            var updated = self.slots
            try updated.setContact(contact, for: number)
            try updated.setAction(action, for: number)
            try self.onSave?(updated)
            self.slots = updated
            self.tableView.reloadData()
        }
        navigationController?.pushViewController(editor, animated: true)
    }
    @objc private func done() { view.endEditing(true); dismiss(animated: true) }
}

final class SetupViewController: CaregiverFormViewController, CNContactPickerDelegate {
    var onSave: ((CallContact?) throws -> Void)?
    var onSaveSlot: ((KeypadAction, CallContact?) throws -> Void)?
    private let actionControl = UISegmentedControl(items: ["Person", "Call control", "Video toggle"])
    private let actionDetail = PorchStyle.label("", size: 16)
    private var personGroup = UIView()
    private var fallbackGroup = UIView()
    private var removeButton: UIButton?
    private let initialAction: KeypadAction
    private let nameField = UITextField()
    private let modeControl = UISegmentedControl(items: ["Voice-only", "Video"])
    private let phoneFallbackSwitch = UISwitch()
    private let phoneField = UITextField()
    private var selectedFamilyID: String?
    private var invitationID: String?
    private let invitationStatus = PorchStyle.label("", size: 17, color: PorchStyle.ink, weight: .medium)
    private let familyLink = PorchStyle.button("Invite them", symbol: "person.badge.plus", filled: false)
    private let existingPerson = PorchStyle.button("Choose from your Porch", symbol: "person.2", filled: false)
    private let chooseContactButton = PorchStyle.button("Choose from Contacts", symbol: "person.crop.circle", filled: false)
    private var phoneGroup = UIView()
    private let initialContact: CallContact?
    private let slot: Int
    private var saveTask: Task<Void, Never>?
    init(slot: Int, contact: CallContact?, action: KeypadAction = .person) {
        self.slot = slot; initialContact = contact; initialAction = action
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(slot:contact:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialAction != .person ? "Key \(slot)" : initialContact == nil ? "Add a person" : "Edit person"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        let badge = PorchStyle.label("KEYPAD NUMBER \(slot)", size: 14, color: PorchStyle.accent, weight: .semibold)
        form.addArrangedSubview(badge)
        actionControl.selectedSegmentIndex = KeypadAction.allCases.firstIndex(of: initialAction) ?? 0
        actionControl.accessibilityLabel = "Keypad action"
        actionControl.addTarget(self, action: #selector(updateAction), for: .valueChanged)
        form.addArrangedSubview(section("What this key does", views: [actionControl, actionDetail]))
        nameField.text = initialContact?.name
        selectedFamilyID = initialContact?.familyMemberID
        invitationID = initialContact?.invitationID
        nameField.autocapitalizationType = .words
        phoneField.text = initialContact?.phoneNumber ?? (initialContact?.nativeCall == nil ? initialContact.flatMap { try? PhoneNumberNormalization.e164($0.address) } : nil)
        phoneField.keyboardType = .phonePad
        phoneField.textContentType = .telephoneNumber
        modeControl.selectedSegmentIndex = initialContact?.nativeCall?.mode == .video ? 1 : 0
        for control in [modeControl, actionControl] {
            control.selectedSegmentTintColor = PorchStyle.accent
            control.backgroundColor = PorchStyle.page
            control.setTitleTextAttributes([.foregroundColor: PorchStyle.ink, .font: UIFont.systemFont(ofSize: 16, weight: .medium)], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 16, weight: .semibold)], for: .selected)
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        modeControl.accessibilityLabel = "Default calling mode"
        let personName = field(nameField, title: "Name", placeholder: "For example, David")
        chooseContactButton.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        configureFamilyLinks()
        familyLink.addTarget(self, action: #selector(invitePerson), for: .touchUpInside)
        personGroup = section("Their details", views: [personName, chooseContactButton, PorchStyle.label("Default calling mode", size: 18, color: PorchStyle.ink, weight: .semibold), modeControl, invitationStatus, familyLink, existingPerson])
        form.addArrangedSubview(personGroup)
        nameField.autocapitalizationType = .words
        phoneFallbackSwitch.isOn = !(phoneField.text ?? "").isEmpty
        phoneFallbackSwitch.onTintColor = PorchStyle.accent
        phoneFallbackSwitch.accessibilityLabel = "Call their phone if Porch isn't answered"
        phoneFallbackSwitch.addTarget(self, action: #selector(updateMethod), for: .valueChanged)
        let phoneToggle = UIStackView(arrangedSubviews: [PorchStyle.label("Call their phone", size: 18, color: PorchStyle.ink, weight: .medium), phoneFallbackSwitch])
        phoneToggle.alignment = .center; phoneToggle.spacing = 16
        phoneGroup = field(phoneField, title: "Phone number", placeholder: "+14158676937", helper: "Include + and the country code for international numbers. Other numbers use this device's region (\(PhoneNumberNormalization.deviceRegion)). Internet is needed to save a phone number.")
        fallbackGroup = section("If Porch isn't answered", detail: "Ring Porch for up to \(CallPreferences.fallbackSeconds()) seconds, then call their phone. If their app is unavailable, try their phone right away. Change the wait in Call preferences. Phone calls are voice only and carrier charges apply.", views: [phoneToggle, phoneGroup])
        form.addArrangedSubview(fallbackGroup)
        if initialContact != nil {
            let remove = PorchStyle.button("Remove person", symbol: "person.crop.circle.badge.minus", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addTarget(self, action: #selector(removePerson), for: .touchUpInside)
            form.addArrangedSubview(remove); removeButton = remove
        }
        updateMethod(); updateAction()
        NotificationCenter.default.addObserver(self, selector: #selector(configureFamilyLinks), name: .porchFamilyChanged, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-touch-keyboard") { nameField.becomeFirstResponder() }
        #endif
    }
    @objc private func updateMethod() {
        view.endEditing(true)
        phoneGroup.isHidden = !phoneFallbackSwitch.isOn
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
        nameField.text = CNContactFormatter.string(from: property.contact, style: .fullName)
        guard let phone = property.value as? CNPhoneNumber else { return }
        do {
            phoneField.text = try PhoneNumberNormalization.e164(phone.stringValue)
            phoneFallbackSwitch.isOn = true; updateMethod()
        } catch { picker.dismiss(animated: true) { [weak self] in self?.showContactError(error) } }
    }

    private var chosenAction: KeypadAction { KeypadAction.allCases[actionControl.selectedSegmentIndex] }
    @objc private func updateAction() {
        view.endEditing(true)
        let person = chosenAction == .person
        personGroup.isHidden = !person; fallbackGroup.isHidden = !person; removeButton?.isHidden = !person
        setKeyboardControlVisible(person)
        actionDetail.text = person ? "Call the person below using their default calling mode." : chosenAction == .callControl ? "Tap to answer an incoming call or hang up. Hold for one second to decline a ringing call. Tap during a drop-in countdown to stop it. This replaces any person assigned to this key." : "Turn your camera off or on during a video call. Voice-only and regular phone calls keep the camera off. This replaces any person assigned to this key."
    }
    @objc private func configureFamilyLinks() {
        let state = FamilyCoordinator.shared.state
        let people = state?.people ?? []
        if let invitationID, let accepted = people.first(where: { $0.invitationID == invitationID }) { selectedFamilyID = accepted.id }
        if let selectedFamilyID, state != nil, !people.contains(where: { $0.id == selectedFamilyID }) { self.selectedFamilyID = nil }
        let pending = invitationID.map { id in state?.invitations?.contains { $0.id == id } == true } ?? false
        invitationStatus.text = selectedFamilyID != nil ? "Porch app connected" : pending ? "Waiting to accept invite" : invitationID != nil ? "Invite expired or cancelled. Send a new invite." : "Invite them to receive calls in Porch."
        familyLink.isHidden = selectedFamilyID != nil || pending
        familyLink.configuration?.title = invitationID == nil ? "Invite them" : "Invite again"
        existingPerson.isHidden = selectedFamilyID != nil || pending || people.isEmpty
        existingPerson.menu = UIMenu(children: people.map { person in
            UIAction(title: person.name) { [weak self] _ in
                self?.selectedFamilyID = person.id; self?.invitationID = person.invitationID
                self?.nameField.text = person.name; self?.configureFamilyLinks()
            }
        })
        existingPerson.showsMenuAsPrimaryAction = true
    }
    @objc private func invitePerson() {
        let controller = FamilyInviteViewController(); controller.prefilledName = nameField.text; controller.returnsToPerson = true
        controller.onCreated = { [weak self] id, name in
            self?.invitationID = id; self?.nameField.text = name; self?.selectedFamilyID = nil
            self?.configureFamilyLinks()
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func save() {
        guard saveTask == nil else { return }
        do {
            if chosenAction != .person {
                try onSaveSlot?(chosenAction, nil)
                navigationController?.popViewController(animated: true); return
            }
            configureFamilyLinks()
            guard selectedFamilyID != nil || invitationID != nil || phoneFallbackSwitch.isOn else {
                throw FamilyServiceError(message: "Invite them to Porch or add a phone number so Porch can reach this person.", status: 400)
            }
            let call = try NativeCall(room: initialContact?.nativeCall?.room ?? "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: modeControl.selectedSegmentIndex == 0 ? .voice : .video)
            let contact = try CallContact(name: nameField.text ?? "", nativeCall: call,
                phoneNumber: phoneFallbackSwitch.isOn ? PhoneNumberNormalization.e164(phoneField.text ?? "") : nil, familyMemberID: selectedFamilyID, invitationID: invitationID)
            phoneField.text = contact.phoneNumber
            view.isUserInteractionEnabled = false
            navigationItem.rightBarButtonItem?.isEnabled = false
            navigationItem.rightBarButtonItem?.title = "Saving…"
            saveTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.saveTask = nil
                    self.view.isUserInteractionEnabled = true
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    self.navigationItem.rightBarButtonItem?.title = "Save"
                }
                do {
                    if let number = contact.phoneNumber {
                        let server = try NativeCallSettings.loadForPhone()
                        _ = try await NativeCallSettings.authorizePhone(number, server: server, refresh: true)
                    }
                    try Task.checkCancellation()
                    try self.onSave?(contact)
                    try self.onSaveSlot?(.person, contact)
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    if !Task.isCancelled { self.showContactError(error) }
                }
            }
        } catch {
            showContactError(error)
        }
    }

    private func showContactError(_ error: Error) {
        let alert = UIAlertController(title: "Couldn't save the contact", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true { saveTask?.cancel() }
    }

    @objc private func removePerson() {
        let alert = UIAlertController(title: "Remove \(initialContact?.name ?? "this person")?", message: "Key \(slot) will be unassigned. Your other people will keep their numbers.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try self.onSave?(nil)
                try self.onSaveSlot?(.person, nil)
                self.navigationController?.popViewController(animated: true)
            } catch {
                let errorAlert = UIAlertController(title: "Couldn't save", message: error.localizedDescription, preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
            }
        })
        present(alert, animated: true)
    }

    @objc private func cancel() {
        saveTask?.cancel()
        navigationController?.popViewController(animated: true)
    }
}
