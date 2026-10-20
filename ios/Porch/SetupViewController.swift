import UIKit
import AVFoundation
import ContactsUI
import PhotosUI
import UniformTypeIdentifiers
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
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? CallSlots.count : section == 1 ? 4 : 1 }
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
            let key = CallSlots.symbol(for: number)
            let person = slots.contact(for: number)
            let action = slots.action(for: number) ?? .person
            content.text = action == .person ? (person?.name ?? "Add a person") : action.title
            let badge = number == CallSlots.star ? "asterisk" : number == CallSlots.pound ? "number" : key
            content.image = UIImage(systemName: "\(badge).circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32))
            if let photo = RecipientAppearance.photo(person?.photoData) {
                content.image = photo
                content.imageProperties.maximumSize = CGSize(width: 64, height: 64)
                content.imageProperties.cornerRadius = 12
                content.text = "\(key) · \(person?.name ?? "")"
            }
            content.secondaryText = person.map { contact in
                if let call = contact.nativeCall {
                    let dropIn = contact.phoneNumber.map { number in FamilyCoordinator.shared.state?.phoneDropIns?.contains { $0.number == number } == true } == true
                    return "Porch \(call.mode == .video ? "video" : "voice")" + (contact.phoneNumber == nil ? "" : " · Phone fallback on") + (contact.otherPhoneNumbers.isEmpty ? "" : " · \(contact.phoneNumbers.count) numbers") + (dropIn ? " · Phone drop-in on" : "")
                }
                return "Finish Porch setup"
            } ?? "Assign key \(key)"
            switch action {
            case .person: break
            case .callControl: content.secondaryText = "Tap to answer or hang up. Hold to decline a ringing call."
            case .toggleVideo: content.secondaryText = "Toggle your camera during a video call."
            case .messages: content.secondaryText = "Play or stop family messages."
            }
            cell.accessibilityLabel = "Key \(key), \(content.text ?? "")"
        } else if indexPath.section == 1, indexPath.row == 0 {
            content.text = "Family & drop-in"
            content.secondaryText = "Pair devices, invite people, and approve access"
            content.image = UIImage(systemName: "person.2.fill")
        } else if indexPath.section == 1, indexPath.row == 1 {
            content.text = "Call preferences"
            let voicemail = FamilyCoordinator.shared.state.map { "Voicemail after \($0.ringSeconds ?? CallPreferences.defaultVoicemailSeconds) seconds · " } ?? ""
            content.secondaryText = voicemail + "Phone fallback after \(CallPreferences.fallbackSeconds()) seconds · Dialing sound"
            content.image = UIImage(systemName: "phone.badge.waveform")
        } else if indexPath.section == 1, indexPath.row == 2 {
            content.text = "Bedside display"
            content.secondaryText = BedsidePreferences.load().appearance == .dynamic ? "Dynamic · Day, night & seasons" : "Default · Dark date & time"
            content.image = UIImage(systemName: "sun.and.horizon")
        } else if indexPath.section == 1 {
            content.text = "Advanced"
            content.secondaryText = CallPreferences.disconnectAfterSilence() ? "End calls after \(CallPreferences.silenceSeconds()) seconds of silence" : "Automatic hang-up is off"
            content.image = UIImage(systemName: "gearshape.2")
            cell.accessibilityIdentifier = "caregiver.advanced"
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
        section == 0 ? "Twelve keys, each with its own action. By default 1–8 call people, 9 toggles video, 0 answers or hangs up, and * and # are free. Any key can be reassigned. Saving never places a call." : nil
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
            let controller: UIViewController = indexPath.row == 0 ? FamilyAdminViewController() : indexPath.row == 1 ? CallPreferencesViewController() : indexPath.row == 2 ? BedsideDisplaySettingsViewController() : AdvancedSettingsViewController()
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
            // Invites may be accepted while the caregiver is editing another slot.
            if let state = FamilyCoordinator.shared.state { try updated.reconcile(with: state) }
            try self.onSave?(updated)
            self.slots = updated
            self.tableView.reloadData()
        }
        navigationController?.pushViewController(editor, animated: true)
    }
    @objc private func done() { view.endEditing(true); dismiss(animated: true) }
}

final class SetupViewController: CaregiverFormViewController, CNContactPickerDelegate, PHPickerViewControllerDelegate, UIColorPickerViewControllerDelegate {
    var onSave: ((CallContact?) throws -> Void)?
    var onSaveSlot: ((KeypadAction, CallContact?) throws -> Void)?
    private let actionControl = UISegmentedControl(items: ["Person", "Call control", "Video toggle", "Messages"])
    private let actionDetail = PorchStyle.label("", size: 16)
    private var personGroup = UIView()
    private var fallbackGroup = UIView()
    private var phoneDropInGroup = UIView()
    private let phoneDropInSwitch = UISwitch()
    /// The saved number the server currently approves for drop-in, if any.
    private var approvedNumber: String?
    private var phoneDropInTouched = false
    private var removeButton: UIButton?
    private let initialAction: KeypadAction
    private let nameField = UITextField()
    private let modeControl = UISegmentedControl(items: ["Voice-only", "Video"])
    private let phoneFallbackSwitch = UISwitch()
    private let phoneField = UITextField()
    /// Their numbers besides the primary one. They can call in, but Porch never dials them.
    private var otherNumbers: [String] = []
    private let otherField = UITextField()
    private let otherNumbersList = UIStackView()
    private var otherGroup = UIView()
    private var selectedFamilyID: String?
    private var invitationID: String?
    /// The paired (or invited) family member's own name, which this key uses when Name is left empty.
    private var memberName: String?
    private let nameHelp = PorchStyle.label("", size: 15)
    private let photoSource = PorchStyle.label("Their photo from Porch", size: 15)
    private let invitationStatus = PorchStyle.label("", size: 17, color: PorchStyle.ink, weight: .medium)
    private let familyLink = PorchStyle.button("Invite them", symbol: "person.badge.plus", filled: false)
    private let existingPerson = PorchStyle.button("Choose from your Porch", symbol: "person.2", filled: false)
    private let chooseContactButton = PorchStyle.button("Choose from Contacts", symbol: "person.crop.circle", filled: false)
    private var phoneGroup = UIView()
    private var appearanceGroup = UIView()
    private var buttonColorHex: String?
    private var photoData: Data?
    private let photoPreview = RecipientAppearance.photoView(nil)
    private let colorButton = PorchStyle.button("Choose button color", symbol: "paintpalette", filled: false)
    private let photoButton = PorchStyle.button("Add photo", symbol: "photo", filled: false)
    private let removePhotoButton = PorchStyle.button("Remove photo", filled: false)
    private let resetColorButton = PorchStyle.button("Use default color", filled: false)
    private let initialContact: CallContact?
    private let slot: Int
    /// The slot as the keypad labels it: a digit, * or #.
    private var key: String { CallSlots.symbol(for: slot) }
    private var saveTask: Task<Void, Never>?
    init(slot: Int, contact: CallContact?, action: KeypadAction = .person) {
        self.slot = slot; initialContact = contact; initialAction = action
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(slot:contact:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialAction != .person ? "Key \(key)" : initialContact == nil ? "Add a person" : "Edit person"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        let badge = PorchStyle.label("KEYPAD KEY \(key)", size: 14, color: PorchStyle.accent, weight: .semibold)
        form.addArrangedSubview(badge)
        actionControl.selectedSegmentIndex = KeypadAction.allCases.firstIndex(of: initialAction) ?? 0
        actionControl.accessibilityLabel = "Keypad action"
        actionControl.addTarget(self, action: #selector(updateAction), for: .valueChanged)
        form.addArrangedSubview(section("What this key does", views: [actionControl, actionDetail]))
        nameField.text = initialContact?.customName
        selectedFamilyID = initialContact?.familyMemberID
        invitationID = initialContact?.invitationID
        memberName = initialContact?.memberName
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
        personGroup = section("Their details", views: [personName, nameHelp, chooseContactButton, PorchStyle.label("Default calling mode", size: 18, color: PorchStyle.ink, weight: .semibold), modeControl, invitationStatus, familyLink, existingPerson])
        form.addArrangedSubview(personGroup)
        buttonColorHex = initialContact?.buttonColorHex
        photoData = initialContact?.customPhotoData
        photoPreview.contentMode = .scaleAspectFit
        photoSource.textAlignment = .center
        photoPreview.heightAnchor.constraint(equalToConstant: 240).isActive = true
        colorButton.accessibilityIdentifier = "recipient.chooseColor"
        photoButton.accessibilityIdentifier = "recipient.choosePhoto"
        removePhotoButton.accessibilityIdentifier = "recipient.removePhoto"
        colorButton.addTarget(self, action: #selector(pickColor), for: .touchUpInside)
        photoButton.addTarget(self, action: #selector(pickPhoto), for: .touchUpInside)
        removePhotoButton.addAction(UIAction { [weak self] _ in self?.photoData = nil; self?.updateAppearance() }, for: .touchUpInside)
        resetColorButton.addAction(UIAction { [weak self] _ in self?.buttonColorHex = nil; self?.updateAppearance() }, for: .touchUpInside)
        appearanceGroup = section("Photo & button color", detail: "Help them recognize this person. Their photo appears on the call button and call screens. Saved on this device only. For someone with the Porch app, Porch uses the photo they chose unless you add one here.", views: [photoPreview, photoSource, photoButton, removePhotoButton, colorButton, resetColorButton])
        form.addArrangedSubview(appearanceGroup)
        updateAppearance()
        nameField.autocapitalizationType = .words
        phoneFallbackSwitch.isOn = !(phoneField.text ?? "").isEmpty
        phoneFallbackSwitch.onTintColor = PorchStyle.accent
        phoneFallbackSwitch.accessibilityLabel = "Call their phone if Porch isn't answered"
        phoneFallbackSwitch.addTarget(self, action: #selector(updateMethod), for: .valueChanged)
        let phoneToggle = UIStackView(arrangedSubviews: [PorchStyle.label("Call their phone", size: 18, color: PorchStyle.ink, weight: .medium), phoneFallbackSwitch])
        phoneToggle.alignment = .center; phoneToggle.spacing = 16
        phoneGroup = field(phoneField, title: "Primary number", placeholder: "+14158676937", helper: "The number Porch calls. Include + and the country code for international numbers. Other numbers use this device's region (\(PhoneNumberNormalization.deviceRegion)). Internet is needed to save a phone number.")
        otherNumbers = initialContact?.otherPhoneNumbers ?? []
        otherField.keyboardType = .phonePad
        otherField.textContentType = .telephoneNumber
        otherField.accessibilityIdentifier = "contact.otherNumber"
        otherNumbersList.axis = .vertical; otherNumbersList.spacing = 8
        let addOther = PorchStyle.button("Add number", symbol: "plus", filled: false)
        addOther.addAction(UIAction { [weak self] _ in self?.addOtherNumber() }, for: .touchUpInside)
        let otherHeading = PorchStyle.label("Other numbers", size: 16, color: PorchStyle.ink, weight: .semibold)
        let otherStack = UIStackView(arrangedSubviews: [otherHeading, otherNumbersList,
            field(otherField, title: "Add another number", placeholder: "+14155550123", helper: "Such as their home or mobile. These can call this Porch too, but Porch only ever calls the primary number."), addOther])
        otherStack.axis = .vertical; otherStack.spacing = 8
        otherGroup = otherStack
        renderOtherNumbers()
        fallbackGroup = section("If Porch isn't answered", detail: "Ring Porch for up to \(CallPreferences.fallbackSeconds()) seconds, then call their primary number. If their app is unavailable, try it right away. Change the wait in Call preferences. Phone calls are voice only and carrier charges apply. All of their numbers can ring Porch while unknown callers are blocked.", views: [phoneToggle, phoneGroup, otherGroup])
        form.addArrangedSubview(fallbackGroup)
        refreshPhoneDropIn()
        phoneDropInSwitch.addAction(UIAction { [weak self] _ in self?.phoneDropInTouched = true }, for: .valueChanged)
        phoneDropInSwitch.onTintColor = PorchStyle.accent
        phoneDropInSwitch.accessibilityLabel = "Audio drop-in when they call this Porch"
        let dropInToggle = UIStackView(arrangedSubviews: [PorchStyle.label("Audio drop-in when they call", size: 18, color: PorchStyle.ink, weight: .medium), phoneDropInSwitch])
        dropInToggle.alignment = .center; dropInToggle.spacing = 16
        phoneDropInGroup = section("Drop-in by phone", detail: "Calls from their primary number to this Porch's phone number connect with audio after the announcement, once Allow approved drop-ins is on in Family & drop-in. Only calls their phone company verifies drop in; others ring for a normal answer.", views: [dropInToggle])
        form.addArrangedSubview(phoneDropInGroup)
        if initialContact != nil {
            let remove = PorchStyle.button("Remove person", symbol: "person.crop.circle.badge.minus", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addTarget(self, action: #selector(removePerson), for: .touchUpInside)
            form.addArrangedSubview(remove); removeButton = remove
        }
        updateMethod(); updateAction()
        NotificationCenter.default.addObserver(self, selector: #selector(configureFamilyLinks), name: .porchFamilyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPhoneDropIn), name: .porchFamilyChanged, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-recipient-appearance") {
            view.layoutIfNeeded()
            let section = appearanceGroup.convert(appearanceGroup.bounds, to: scroll)
            let offset = min(max(0, section.minY - 24), max(0, scroll.contentSize.height - scroll.bounds.height))
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-touch-keyboard") || ProcessInfo.processInfo.arguments.contains("--preview-system-keyboard") { nameField.becomeFirstResponder() }
        #endif
    }
    @objc private func updateMethod() {
        view.endEditing(true)
        phoneGroup.isHidden = !phoneFallbackSwitch.isOn
        otherGroup.isHidden = !phoneFallbackSwitch.isOn
        updatePhoneDropIn()
    }
    /// One row per other number: Make primary swaps it with the primary number, which is the one Porch calls.
    private func renderOtherNumbers() {
        otherNumbersList.arrangedSubviews.forEach { otherNumbersList.removeArrangedSubview($0); $0.removeFromSuperview() }
        if otherNumbers.isEmpty { otherNumbersList.addArrangedSubview(PorchStyle.label("None", size: 15)) }
        for number in otherNumbers {
            let shown = PhoneNumberNormalization.display(number)
            let label = PorchStyle.label(shown, size: 18, color: PorchStyle.ink)
            let primary = PorchStyle.button("Make primary", filled: false)
            primary.accessibilityLabel = "Make \(shown) the primary number"
            primary.addAction(UIAction { [weak self] _ in self?.makePrimary(number) }, for: .touchUpInside)
            let remove = PorchStyle.button("Remove", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.accessibilityLabel = "Remove \(shown)"
            remove.addAction(UIAction { [weak self] _ in self?.otherNumbers.removeAll { $0 == number }; self?.renderOtherNumbers() }, for: .touchUpInside)
            for button in [primary, remove] {
                button.setContentHuggingPriority(.required, for: .horizontal)
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
            let actions = UIStackView(arrangedSubviews: [primary, remove])
            actions.spacing = 8
            // Not one stack: it would cap the number and the buttons at an equal share of the row, and
            // keeping the buttons at their width would squeeze the whole form on iPad.
            let row = listRow(label, trailing: actions)
            row.directionalLayoutMargins = .zero
            otherNumbersList.addArrangedSubview(row)
        }
    }
    /// Adds what's typed in Add another number. Throws if it isn't a phone number, is already saved, or is one too many.
    private func takeOtherNumber() throws {
        let typed = otherField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !typed.isEmpty else { return }
        let number = try PhoneNumberNormalization.e164(typed)
        let primary = try? PhoneNumberNormalization.e164(phoneField.text ?? "")
        guard number != primary, !otherNumbers.contains(number) else { throw FamilyServiceError(message: "That number is already saved for them.", status: 400) }
        guard otherNumbers.count + 1 < CallContact.maximumPhoneNumbers else { throw CallContact.ValidationError.tooManyPhoneNumbers }
        otherNumbers.append(number); otherField.text = nil
        renderOtherNumbers()
    }
    private func addOtherNumber() {
        view.endEditing(true)
        do { try takeOtherNumber() } catch { showContactError(error) }
    }
    private func makePrimary(_ number: String) {
        view.endEditing(true)
        let previous = try? PhoneNumberNormalization.e164(phoneField.text ?? "")
        otherNumbers = otherNumbers.compactMap { $0 == number ? previous : $0 }
        phoneField.text = number
        renderOtherNumbers()
    }
    /// Follows the server's approvals (which may load or change while editing) until the caregiver flips the switch.
    @objc private func refreshPhoneDropIn() {
        guard !phoneDropInTouched, saveTask == nil, let approvals = FamilyCoordinator.shared.state?.phoneDropIns else { return }
        approvedNumber = initialContact?.phoneNumber.flatMap { number in approvals.contains { $0.number == number } ? number : nil }
        phoneDropInSwitch.isOn = approvedNumber != nil
    }
    private func updatePhoneDropIn() {
        // Approvals live on the server, so a bedside that isn't paired yet can't offer them.
        phoneDropInGroup.isHidden = chosenAction != .person || !phoneFallbackSwitch.isOn || PorchDevice.credential(for: .bedside) == nil
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
            let primary = try PhoneNumberNormalization.e164(phone.stringValue)
            phoneField.text = primary
            // Their other numbers from Contacts, such as home and mobile, can call in too.
            if property.contact.isKeyAvailable(CNContactPhoneNumbersKey) {
                let others = property.contact.phoneNumbers.compactMap { try? PhoneNumberNormalization.e164($0.value.stringValue) }
                otherNumbers = []
                for number in others where number != primary && !otherNumbers.contains(number) && otherNumbers.count + 1 < CallContact.maximumPhoneNumbers { otherNumbers.append(number) }
                renderOtherNumbers()
            }
            phoneFallbackSwitch.isOn = true; updateMethod()
        } catch { picker.dismiss(animated: true) { [weak self] in self?.showContactError(error) } }
    }

    private var linkedPerson: FamilyPerson? { selectedFamilyID.flatMap { id in FamilyCoordinator.shared.state?.people.first { $0.id == id } } }
    /// The photo the linked family member has on Porch, shown when this key has none of its own.
    private var memberPhotoID: String? {
        if let person = linkedPerson { return person.photoID }
        return selectedFamilyID == nil ? nil : initialContact?.memberPhotoID
    }
    private var memberPhoto: Data? { FamilyPhotos.shared.data(for: memberPhotoID) }
    /// The member photo on screen, so polling redraws only once a new one has downloaded.
    private var shownMemberPhoto: String?
    private func updateAppearance() {
        shownMemberPhoto = memberPhotoID.flatMap { FamilyPhotos.shared.store.contains($0) ? $0 : nil }
        let fallback = photoData == nil ? memberPhoto : nil
        photoPreview.image = RecipientAppearance.photo(photoData ?? fallback)
        photoPreview.isHidden = photoPreview.image == nil
        photoSource.isHidden = fallback == nil
        removePhotoButton.isHidden = photoData == nil
        removePhotoButton.configuration?.title = memberPhoto == nil ? "Remove photo" : "Use their photo from Porch"
        photoButton.configuration?.title = photoData != nil ? "Change photo" : fallback != nil ? "Use a different photo" : "Add photo"
        let color = RecipientAppearance.color(hex: buttonColorHex)
        colorButton.configuration?.baseBackgroundColor = color
        colorButton.configuration?.baseForegroundColor = RecipientAppearance.foreground(on: color)
        colorButton.configuration?.background.backgroundColor = color
        colorButton.accessibilityValue = buttonColorHex.map { "Color #\($0)" } ?? "Default color"
        resetColorButton.isHidden = buttonColorHex == nil
    }

    @objc private func pickColor() {
        view.endEditing(true)
        let picker = UIColorPickerViewController()
        picker.selectedColor = RecipientAppearance.color(hex: buttonColorHex)
        picker.supportsAlpha = false
        picker.delegate = self
        present(picker, animated: true)
    }
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        buttonColorHex = RecipientAppearance.hex(color: viewController.selectedColor)
        updateAppearance()
    }

    @objc private func pickPhoto() {
        view.endEditing(true)
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        photoButton.isEnabled = false
        navigationItem.rightBarButtonItem?.isEnabled = false
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
            let data = url.flatMap { RecipientAppearance.preparedPhoto(at: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.photoButton.isEnabled = true
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                if let data { self.photoData = data; self.updateAppearance() }
                else { self.showContactError(FamilyServiceError(message: "That photo couldn't be opened. Please choose another photo.", status: 400)) }
            }
        }
    }

    private var chosenAction: KeypadAction { KeypadAction.allCases[actionControl.selectedSegmentIndex] }
    @objc private func updateAction() {
        view.endEditing(true)
        let person = chosenAction == .person
        personGroup.isHidden = !person; fallbackGroup.isHidden = !person; appearanceGroup.isHidden = !person; removeButton?.isHidden = !person
        updatePhoneDropIn()
        setKeyboardControlVisible(person)
        switch chosenAction {
        case .person: actionDetail.text = "Call the person below using their default calling mode."
        case .callControl: actionDetail.text = "Tap to answer an incoming call or hang up. Hold for one second to decline a ringing call. Tap during a drop-in countdown to stop it. This replaces any person assigned to this key."
        case .toggleVideo: actionDetail.text = "Turn your camera off or on during a video call. Voice-only and regular phone calls keep the camera off. This replaces any person assigned to this key."
        case .messages: actionDetail.text = "Play waiting family messages, or stop them while they play. This replaces any person assigned to this key."
        }
    }
    /// A Porch family member can go by their own name, so Name is optional for them.
    private func updateNameHelp() {
        let porch = selectedFamilyID != nil || invitationID != nil
        let theirs = linkedPerson?.name ?? memberName
        nameField.attributedPlaceholder = NSAttributedString(string: porch ? theirs ?? "Their name" : "For example, David", attributes: [.foregroundColor: PorchStyle.secondary])
        nameHelp.text = "Leave blank to use their name from Porch\(theirs.map { " (now “\($0)”)" } ?? "")."
        nameHelp.isHidden = !porch
    }
    @objc private func configureFamilyLinks() {
        defer {
            updateNameHelp()
            if memberPhotoID.flatMap({ FamilyPhotos.shared.store.contains($0) ? $0 : nil }) != shownMemberPhoto { updateAppearance() }
        }
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
                // Name stays as typed; left empty, the key follows the name they choose in Porch.
                self?.selectedFamilyID = person.id; self?.invitationID = person.invitationID
                self?.memberName = person.name; self?.configureFamilyLinks()
            }
        })
        existingPerson.showsMenuAsPrimaryAction = true
    }
    @objc private func invitePerson() {
        let typed = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let controller = FamilyInviteViewController(); controller.prefilledName = typed.isEmpty ? memberName : typed; controller.returnsToPerson = true
        // The name moves to the invitation, and the key follows the name they choose once they join.
        controller.onCreated = { [weak self] id, name in
            self?.invitationID = id; self?.memberName = name; self?.nameField.text = nil; self?.selectedFamilyID = nil
            self?.configureFamilyLinks()
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func save() {
        guard saveTask == nil else { return }
        do {
            if chosenAction != .person {
                guard approvedNumber != nil else {
                    try onSaveSlot?(chosenAction, nil)
                    navigationController?.popViewController(animated: true); return
                }
                // A control replaces the person on this key, so their phone drop-in goes too.
                view.isUserInteractionEnabled = false
                saveTask = Task { [weak self] in
                    guard let self else { return }
                    defer { self.saveTask = nil; self.view.isUserInteractionEnabled = true }
                    do {
                        self.phoneDropInTouched = true; self.phoneDropInSwitch.isOn = false
                        try await self.syncPhoneDropIn(number: nil, name: "")
                        try Task.checkCancellation()
                        try self.onSaveSlot?(self.chosenAction, nil)
                        self.navigationController?.popViewController(animated: true)
                    } catch { if !Task.isCancelled { self.showContactError(error) } }
                }
                return
            }
            configureFamilyLinks()
            // A number typed in Add another number counts even if Add number wasn't tapped.
            if phoneFallbackSwitch.isOn { try takeOtherNumber() }
            guard selectedFamilyID != nil || invitationID != nil || phoneFallbackSwitch.isOn else {
                throw FamilyServiceError(message: "Invite them to Porch or add a phone number so Porch can reach this person.", status: 400)
            }
            let call = try NativeCall(room: initialContact?.nativeCall?.room ?? "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: modeControl.selectedSegmentIndex == 0 ? .voice : .video)
            let contact = try CallContact(name: nameField.text ?? "", nativeCall: call,
                phoneNumber: phoneFallbackSwitch.isOn ? PhoneNumberNormalization.e164(phoneField.text ?? "") : nil,
                otherPhoneNumbers: phoneFallbackSwitch.isOn ? otherNumbers : [], familyMemberID: selectedFamilyID, invitationID: invitationID,
                memberName: linkedPerson?.name ?? memberName, buttonColorHex: buttonColorHex, photoData: photoData)
            phoneField.text = contact.phoneNumber
            otherNumbers = contact.otherPhoneNumbers; renderOtherNumbers()
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
                    try await self.syncPhoneDropIn(number: contact.phoneNumber, name: contact.name)
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

    /// The server's approval follows this person's saved number: a changed or removed number loses drop-in.
    private func syncPhoneDropIn(number: String?, name: String) async throws {
        let wanted = phoneDropInSwitch.isOn && PorchDevice.credential(for: .bedside) != nil ? number : nil
        guard wanted != nil || approvedNumber != nil else { return }
        guard let credential = PorchDevice.credential(for: .bedside) else { throw FamilyServiceError(message: "Finish bedside setup before changing phone drop-in.", status: 409) }
        var values: [String: Any]
        if let wanted {
            // A drop-in answers on this iPad, so only it can grant its own microphone.
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            guard microphone else { throw FamilyServiceError(message: "Allow microphone access in iPad Settings before approving drop-in.", status: 403) }
            values = ["number": wanted, "name": name, "enabled": true]
            // One request swaps a changed number, so a failure never leaves both approved.
            if let previous = approvedNumber, previous != wanted { values["replacing"] = previous }
        } else if let previous = approvedNumber { values = ["number": previous, "enabled": false] }
        else { return }
        let response = try await FamilyService(credential).send("setPhoneDropIn", values, pin: NativeCallSettings.caregiverCode)
        FamilyCoordinator.shared.update(response)
        approvedNumber = wanted
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
        let alert = UIAlertController(title: "Remove \(initialContact?.name ?? "this person")?", message: "Key \(key) will be unassigned. Your other people will keep their numbers.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    // Removing a person also withdraws their phone drop-in.
                    self.phoneDropInTouched = true; self.phoneDropInSwitch.isOn = false
                    try await self.syncPhoneDropIn(number: nil, name: "")
                    try self.onSave?(nil)
                    try self.onSaveSlot?(.person, nil)
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    let errorAlert = UIAlertController(title: "Couldn't save", message: error.localizedDescription, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

    @objc private func cancel() {
        saveTask?.cancel()
        navigationController?.popViewController(animated: true)
    }
}
