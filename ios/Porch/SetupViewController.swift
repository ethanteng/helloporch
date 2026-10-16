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
                return contact.shortcutName == nil ? "FaceTime" : "Shortcut"
            } ?? "Assign keypad number \(number)"
            cell.accessibilityLabel = "Key \(number), \(person?.name ?? "add a person")"
        } else if indexPath.section == 1, indexPath.row == 0 {
            content.text = "Calling connection"
            content.secondaryText = NativeCallSettings.savedURL.isEmpty ? "Connect this iPad to Porch" : "Server and caregiver access codes"
            content.image = UIImage(systemName: "network")
        } else if indexPath.section == 1 {
            content.text = "Call preferences"
            content.secondaryText = "Phone fallback after \(CallPreferences.fallbackSeconds()) seconds · Dialing sound"
            content.image = UIImage(systemName: "phone.badge.waveform")
        } else {
            content.text = "Keep Porch ready"
            content.secondaryText = "Keypad, Guided Access, and daily use"
            content.image = UIImage(systemName: "moon.stars")
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Your people", "Connection", "Using this iPad"][section]
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
            let controller: UIViewController = indexPath.row == 0 ? NativeCallSettingsViewController() : CallPreferencesViewController()
            navigationController?.pushViewController(controller, animated: true); return
        }
        if indexPath.section == 2 { navigationController?.pushViewController(PorchDailyUseViewController(), animated: true); return }
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

final class PorchDailyUseViewController: CaregiverFormViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keep Porch ready"
        form.addArrangedSubview(section("A quiet bedside clock", detail: "Return to the clock when you're finished. Porch keeps the display awake while it is open. Use the iPad's brightness control to make the screen comfortable for the room.", views: []))
        form.addArrangedSubview(section("Keep the app open", detail: "For a dedicated calling iPad, enable Guided Access in iPad Settings → Accessibility. Open Porch, start a Guided Access session, and choose a suitable Display Auto-Lock setting. Leave Touch and Software Keyboards enabled for caregiver setup.", views: []))
        form.addArrangedSubview(section("Using the keypad", detail: "Press 1–6 to call the person assigned to that number. Porch needs to be the active app and the iPad must be unlocked. A normal keypad cannot wake Porch from the background or lock screen. Native Porch calls and phone fallback stay inside Porch.", views: []))
        form.addArrangedSubview(section("Joining a Porch call", detail: "The other person still joins the same room in the same mode. Incoming Porch notifications aren't available in this beta. If enabled, phone fallback rings their regular phone after the wait set in Call preferences.", views: []))
        hideKeyboardControl()
    }
}

final class SetupViewController: CaregiverFormViewController, CNContactPickerDelegate {
    var onSave: ((CallContact?) throws -> Void)?
    private let nameField = UITextField()
    private let addressField = UITextField()
    private let shortcutField = UITextField()
    private let methodControl = UISegmentedControl(items: ["Porch", "FaceTime", "Shortcut"])
    private let roomField = UITextField()
    private let modeControl = UISegmentedControl(items: ["Voice", "Video"])
    private let phoneFallbackSwitch = UISwitch()
    private let phoneField = UITextField()
    private var nativeGroup = UIView()
    private var fallbackGroup = UIView()
    private var phoneGroup = UIView()
    private var faceTimeGroup = UIView()
    private var shortcutGroup = UIView()
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
        nameField.autocapitalizationType = .words
        roomField.text = initialContact?.nativeCall?.room ?? "porch-\(UUID().uuidString.prefix(8).lowercased())"
        shortcutField.text = initialContact?.shortcutName
        addressField.text = initialContact?.address
        phoneField.text = initialContact?.phoneNumber
        phoneField.keyboardType = .phonePad
        phoneField.textContentType = .telephoneNumber
        addressField.keyboardType = .emailAddress
        methodControl.selectedSegmentIndex = initialContact?.nativeCall != nil || initialContact == nil ? 0 : initialContact?.shortcutName == nil ? 1 : 2
        modeControl.selectedSegmentIndex = initialContact?.nativeCall?.mode == .video ? 1 : 0
        for control in [methodControl, modeControl] {
            control.selectedSegmentTintColor = PorchStyle.accent
            control.backgroundColor = PorchStyle.page
            control.setTitleTextAttributes([.foregroundColor: PorchStyle.ink, .font: UIFont.systemFont(ofSize: 16, weight: .medium)], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 16, weight: .semibold)], for: .selected)
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        methodControl.accessibilityLabel = "Calling method"
        modeControl.accessibilityLabel = "Porch call mode"
        methodControl.addTarget(self, action: #selector(updateMethod), for: .valueChanged)
        let personName = field(nameField, title: "Name", placeholder: "For example, David")
        nameField.autocapitalizationType = .words
        let method = UIStackView(arrangedSubviews: [PorchStyle.label("Call using", size: 16, color: PorchStyle.ink, weight: .semibold), methodControl])
        method.axis = .vertical; method.spacing = 8
        let choose = PorchStyle.button("Choose from Contacts", symbol: "person.crop.circle", filled: false)
        choose.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        form.addArrangedSubview(section("Their details", views: [personName, choose, method]))
        let room = field(roomField, title: "Porch room", placeholder: "A shared room name", helper: "Already filled in. Use this same room on the other device to join a Porch call.")
        roomField.keyboardType = .asciiCapable
        nativeGroup = section("Porch call", detail: "Choose how the call starts. The other person joins manually in this beta.", views: [modeControl, room])
        form.addArrangedSubview(nativeGroup)
        phoneFallbackSwitch.isOn = initialContact?.phoneNumber != nil
        phoneFallbackSwitch.onTintColor = PorchStyle.accent
        phoneFallbackSwitch.accessibilityLabel = "Call their phone if Porch isn't answered"
        phoneFallbackSwitch.addTarget(self, action: #selector(updateMethod), for: .valueChanged)
        let phoneToggle = UIStackView(arrangedSubviews: [PorchStyle.label("Call their phone", size: 18, color: PorchStyle.ink, weight: .medium), phoneFallbackSwitch])
        phoneToggle.alignment = .center; phoneToggle.spacing = 16
        phoneGroup = field(phoneField, title: "Phone number", placeholder: "+1 415 555 0123", helper: "Include + and the country code. Saving approves this number automatically.")
        fallbackGroup = section("If Porch isn't answered", detail: "Try Porch for \(CallPreferences.fallbackSeconds()) seconds, then ring their regular phone. Change this in Call preferences. Phone calls are voice only and carrier charges apply.", views: [phoneToggle, phoneGroup])
        form.addArrangedSubview(fallbackGroup)
        faceTimeGroup = section("FaceTime", views: [field(addressField, title: "FaceTime address", placeholder: "Email address or phone number", helper: "Use the address this person uses for FaceTime. This opens Apple's FaceTime app.")])
        shortcutGroup = section("Shortcut", views: [field(shortcutField, title: "Shortcut name", placeholder: "For example, Call David", helper: "Create and test a shortcut in Apple's Shortcuts app first. Enter its exact name here.")])
        form.addArrangedSubview(faceTimeGroup); form.addArrangedSubview(shortcutGroup)
        if initialContact != nil {
            let remove = PorchStyle.button("Remove person", symbol: "person.crop.circle.badge.minus", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addTarget(self, action: #selector(removePerson), for: .touchUpInside)
            form.addArrangedSubview(remove)
        }
        updateMethod()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-touch-keyboard") { nameField.becomeFirstResponder() }
        #endif
    }
    @objc private func updateMethod() {
        view.endEditing(true)
        nativeGroup.isHidden = methodControl.selectedSegmentIndex != 0
        fallbackGroup.isHidden = nativeGroup.isHidden
        phoneGroup.isHidden = !phoneFallbackSwitch.isOn
        faceTimeGroup.isHidden = methodControl.selectedSegmentIndex != 1
        shortcutGroup.isHidden = methodControl.selectedSegmentIndex != 2
    }
    @objc private func pickContact() {
        view.endEditing(true)
        let picker = CNContactPickerViewController()
        picker.overrideUserInterfaceStyle = .light
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers' OR key == 'emailAddresses'")
        present(picker, animated: true)
    }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
        nameField.text = CNContactFormatter.string(from: property.contact, style: .fullName)
        if property.key == CNContactPhoneNumbersKey, let phone = property.value as? CNPhoneNumber {
            if methodControl.selectedSegmentIndex == 0 {
                phoneField.text = phone.stringValue; phoneFallbackSwitch.isOn = true; updateMethod()
            } else { addressField.text = phone.stringValue }
        } else if property.key == CNContactEmailAddressesKey, let email = property.value as? String { addressField.text = email }
    }

    @objc private func save() {
        guard saveTask == nil else { return }
        do {
            let contact: CallContact
            if methodControl.selectedSegmentIndex == 0 {
                let call = try NativeCall(room: roomField.text ?? "", mode: modeControl.selectedSegmentIndex == 0 ? .voice : .video)
                contact = try CallContact(name: nameField.text ?? "", nativeCall: call,
                    phoneNumber: phoneFallbackSwitch.isOn ? (phoneField.text ?? "") : nil)
            } else {
                contact = try CallContact(name: nameField.text ?? "", address: addressField.text ?? "",
                    shortcutName: methodControl.selectedSegmentIndex == 2 ? (shortcutField.text ?? "") : nil)
            }
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
                        let server = try NativeCallSettings.load()
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
