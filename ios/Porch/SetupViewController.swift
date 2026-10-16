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
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? CallSlots.count : section == 1 ? 2 : 1 }
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
            let number = indexPath.row + 1
            let person = slots.contact(for: number)
            content.text = person?.name ?? "Add a person"
            content.image = UIImage(systemName: "\(number).circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32))
            content.secondaryText = person.map { contact in
                if let call = contact.nativeCall {
                    return "Porch \(call.mode == .video ? "video" : "voice")" + (contact.phoneNumber == nil ? "" : " · Phone fallback on")
                }
                return "Finish Porch setup"
            } ?? "Assign keypad number \(number)"
            cell.accessibilityLabel = "Key \(number), \(person?.name ?? "add a person")"
        } else if indexPath.section == 1, indexPath.row == 0 {
            content.text = "Family & drop-in"
            content.secondaryText = "Pair devices, invite people, and approve access"
            content.image = UIImage(systemName: "person.2.fill")
        } else if indexPath.section == 1 {
            content.text = "Call preferences"
            content.secondaryText = "Phone fallback after \(CallPreferences.fallbackSeconds()) seconds · Dialing sound"
            content.image = UIImage(systemName: "phone.badge.waveform")
        } else {
            content.text = "Bedside mode"
            content.secondaryText = "Change this device to family mode"
            content.image = UIImage(systemName: "ipad.and.iphone")
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Your people", "Calling", "Device mode"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Each person keeps their keypad number. Saving a contact never places a call." : nil
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
            let controller: UIViewController = indexPath.row == 0 ? FamilyAdminViewController() : CallPreferencesViewController()
            navigationController?.pushViewController(controller, animated: true); return
        }
        if indexPath.section == 2 { offerExperienceChange(on: self); return }
        let number = indexPath.row + 1
        let editor = SetupViewController(slot: number, contact: slots.contact(for: number))
        editor.onSave = { [weak self] contact in
            guard let self else { return }
            var updated = self.slots
            try updated.setContact(contact, for: number)
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
    private let nameField = UITextField()
    private let modeControl = UISegmentedControl(items: ["Voice", "Video"])
    private let phoneFallbackSwitch = UISwitch()
    private let phoneField = UITextField()
    private var selectedFamilyID: String?
    private let familyLink = PorchStyle.button("Link a family member", symbol: "person.2", filled: false)
    private let chooseContactButton = PorchStyle.button("Choose from Contacts", symbol: "person.crop.circle", filled: false)
    private var phoneGroup = UIView()
    private let initialContact: CallContact?
    private let slot: Int
    private var saveTask: Task<Void, Never>?
    init(slot: Int, contact: CallContact?) {
        self.slot = slot; initialContact = contact
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(slot:contact:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialContact == nil ? "Add a person" : "Edit person"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        let badge = PorchStyle.label("KEYPAD NUMBER \(slot)", size: 14, color: PorchStyle.accent, weight: .semibold)
        form.addArrangedSubview(badge)
        nameField.text = initialContact?.name
        selectedFamilyID = initialContact?.familyMemberID
        nameField.autocapitalizationType = .words
        phoneField.text = initialContact?.phoneNumber ?? (initialContact?.nativeCall == nil ? initialContact.flatMap { try? PhoneNumberNormalization.e164($0.address) } : nil)
        phoneField.keyboardType = .phonePad
        phoneField.textContentType = .telephoneNumber
        modeControl.selectedSegmentIndex = initialContact?.nativeCall?.mode == .video ? 1 : 0
        for control in [modeControl] {
            control.selectedSegmentTintColor = PorchStyle.accent
            control.backgroundColor = PorchStyle.page
            control.setTitleTextAttributes([.foregroundColor: PorchStyle.ink, .font: UIFont.systemFont(ofSize: 16, weight: .medium)], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 16, weight: .semibold)], for: .selected)
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        modeControl.accessibilityLabel = "Porch call mode"
        let personName = field(nameField, title: "Name", placeholder: "For example, David")
        chooseContactButton.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        configureFamilyLinks()
        form.addArrangedSubview(section("Their details", views: [personName, chooseContactButton, modeControl, familyLink]))
        nameField.autocapitalizationType = .words
        phoneFallbackSwitch.isOn = !(phoneField.text ?? "").isEmpty
        phoneFallbackSwitch.onTintColor = PorchStyle.accent
        phoneFallbackSwitch.accessibilityLabel = "Call their phone if Porch isn't answered"
        phoneFallbackSwitch.addTarget(self, action: #selector(updateMethod), for: .valueChanged)
        let phoneToggle = UIStackView(arrangedSubviews: [PorchStyle.label("Call their phone", size: 18, color: PorchStyle.ink, weight: .medium), phoneFallbackSwitch])
        phoneToggle.alignment = .center; phoneToggle.spacing = 16
        phoneGroup = field(phoneField, title: "Phone number", placeholder: "+14158676937", helper: "Include + and the country code for international numbers. Other numbers use this device's region (\(PhoneNumberNormalization.deviceRegion)). Internet is needed to save a phone number.")
        let fallbackGroup = section("If Porch isn't answered", detail: "Ring Porch for up to \(CallPreferences.fallbackSeconds()) seconds, then call their phone. If their app is unavailable, try their phone right away. Change the wait in Call preferences. Phone calls are voice only and carrier charges apply.", views: [phoneToggle, phoneGroup])
        form.addArrangedSubview(fallbackGroup)
        if initialContact != nil {
            let remove = PorchStyle.button("Remove person", symbol: "person.crop.circle.badge.minus", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addTarget(self, action: #selector(removePerson), for: .touchUpInside)
            form.addArrangedSubview(remove)
        }
        updateMethod()
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

    @objc private func configureFamilyLinks() {
        let people = FamilyCoordinator.shared.state?.people ?? []
        familyLink.isHidden = false
        familyLink.configuration?.title = selectedFamilyID.flatMap { id in people.first(where: { $0.id == id })?.name }.map { "Linked to \($0)" } ?? (selectedFamilyID == nil ? "Link their Porch app" : "Linked Porch app")
        let actions = people.map { person in
            UIAction(title: person.name, state: selectedFamilyID == person.id ? .on : .off) { [weak self] _ in
                self?.selectedFamilyID = person.id
                if self?.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { self?.nameField.text = person.name }
                self?.configureFamilyLinks()
            }
        }
        let manual = UIAction(title: "No Porch app yet", state: selectedFamilyID == nil ? .on : .off) { [weak self] _ in
            self?.selectedFamilyID = nil; self?.configureFamilyLinks()
        }
        let invite = UIAction(title: "Invite their Porch app", image: UIImage(systemName: "person.badge.plus")) { [weak self] _ in
            let controller = FamilyInviteViewController(); controller.prefilledName = self?.nameField.text
            self?.navigationController?.pushViewController(controller, animated: true)
        }
        familyLink.menu = UIMenu(children: actions + [invite, manual]); familyLink.showsMenuAsPrimaryAction = true
    }

    @objc private func save() {
        guard saveTask == nil else { return }
        do {
            guard selectedFamilyID != nil || phoneFallbackSwitch.isOn else {
                throw FamilyServiceError(message: "Link their Porch app or add a phone number so Porch can reach this person.", status: 400)
            }
            let call = try NativeCall(room: initialContact?.nativeCall?.room ?? "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: modeControl.selectedSegmentIndex == 0 ? .voice : .video)
            let contact = try CallContact(name: nameField.text ?? "", nativeCall: call,
                phoneNumber: phoneFallbackSwitch.isOn ? PhoneNumberNormalization.e164(phoneField.text ?? "") : nil, familyMemberID: selectedFamilyID)
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
