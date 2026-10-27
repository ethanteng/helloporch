import UIKit
import AVFoundation
import ContactsUI
import PhotosUI
import UniformTypeIdentifiers
import PorchCore

/// A keypad key's editor. For an empty key or a control, it chooses what the key does and can put a person on it.
/// For a key that already has someone on it, it edits their phone numbers; the rest is on their page.
final class SetupViewController: CaregiverFormViewController, CNContactPickerDelegate, PHPickerViewControllerDelegate, UIColorPickerViewControllerDelegate {
    var onSaveSlot: ((KeypadAction, CallContact?) throws -> Void)?
    private let actionControl = UISegmentedControl(items: ["No action", "Person", "Call control", "Video toggle", "Messages"])
    private let actionDetail = PorchStyle.label("", size: 16)
    private var actionGroup = UIView()
    private var personGroup = UIView()
    private var fallbackGroup = UIView()
    /// The saved number the server approves for drop-in, if any. It follows a changed primary number.
    private var approvedNumber: String?
    private let initialAction: KeypadAction
    private let nameField = UITextField()
    private var nameGroup = UIView()
    private let modeLabel = PorchStyle.label("Calls start as", size: 18, color: PorchStyle.ink, weight: .semibold)
    private let modeControl = PorchStyle.segmented(["Voice", "Video"])
    private let phoneFallbackSwitch = UISwitch()
    private let fallbackDetail = PorchStyle.label("", size: 16)
    private let phoneField = UITextField()
    /// Their numbers besides the primary one. They can call in, but Porch never dials them.
    private var otherNumbers: [String] = []
    private let otherField = UITextField()
    private let otherNumbersList = UIStackView()
    private var otherGroup = UIView()
    private var selectedFamilyID: String?
    private var invitationID: String?
    /// The paired (or invited) family member's own name, which this key uses.
    private var memberName: String?
    private let photoSource = PorchStyle.label("Their photo from Porch", size: 15)
    private let invitationStatus = PorchStyle.label("", size: 17, color: PorchStyle.ink, weight: .medium)
    private let familyLink = PorchStyle.button("Invite them", symbol: "person.badge.plus", filled: false)
    private let existingPerson = PorchStyle.button("Choose from Family on Porch", symbol: "person.2", filled: false)
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
    /// Someone is already on this key, so only their numbers are edited here.
    private var editingNumbers: Bool { initialContact != nil }
    private var linked: Bool { selectedFamilyID != nil || invitationID != nil }
    private var saveTask: Task<Void, Never>?
    init(slot: Int, contact: CallContact?, action: KeypadAction = .person) {
        self.slot = slot; initialContact = contact; initialAction = action
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(slot:contact:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = editingNumbers ? "Phone" : "Key \(key)"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        actionControl.selectedSegmentIndex = KeypadAction.allCases.firstIndex(of: initialAction) ?? 0
        actionControl.accessibilityLabel = "Keypad action"
        actionControl.addTarget(self, action: #selector(updateAction), for: .valueChanged)
        actionControl.selectedSegmentTintColor = PorchStyle.accent
        actionControl.backgroundColor = PorchStyle.page
        actionControl.setTitleTextAttributes([.foregroundColor: PorchStyle.ink, .font: UIFont.systemFont(ofSize: 16, weight: .medium)], for: .normal)
        actionControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 16, weight: .semibold)], for: .selected)
        actionControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        actionGroup = section("What key \(key) does", views: [actionControl, actionDetail])
        form.addArrangedSubview(actionGroup)
        nameField.text = initialContact?.customName
        selectedFamilyID = initialContact?.familyMemberID
        invitationID = initialContact?.invitationID
        memberName = initialContact?.memberName
        phoneField.text = initialContact?.phoneNumber ?? (initialContact?.nativeCall == nil ? initialContact.flatMap { try? PhoneNumberNormalization.e164($0.address) } : nil)
        phoneField.keyboardType = .phonePad
        phoneField.textContentType = .telephoneNumber
        modeControl.selectedSegmentIndex = initialContact?.nativeCall?.mode == .video ? 1 : 0
        modeControl.accessibilityLabel = "Calls start as"
        nameGroup = field(nameField, title: "Name", placeholder: "For example, David")
        // `field` resets capitalization; a person's name is capitalized word by word.
        nameField.autocapitalizationType = .words
        chooseContactButton.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        configureFamilyLinks()
        familyLink.addTarget(self, action: #selector(invitePerson), for: .touchUpInside)
        invitationStatus.textAlignment = .center
        // Editing someone's numbers, Choose from Contacts goes under them instead.
        personGroup = section("Their details", views: [existingPerson, familyLink, invitationStatus, nameGroup] + (editingNumbers ? [] : [chooseContactButton]) + [modeLabel, modeControl])
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
        appearanceGroup = section("Photo & button color", views: [photoPreview, photoSource, photoButton, removePhotoButton, colorButton, resetColorButton])
        form.addArrangedSubview(appearanceGroup)
        updateAppearance()
        phoneFallbackSwitch.isOn = !(phoneField.text ?? "").isEmpty
        phoneFallbackSwitch.onTintColor = PorchStyle.accent
        phoneFallbackSwitch.accessibilityLabel = "Call their phone"
        phoneFallbackSwitch.addTarget(self, action: #selector(updateMethod), for: .valueChanged)
        let phoneToggle = UIStackView(arrangedSubviews: [PorchStyle.label("Call their phone", size: 18, color: PorchStyle.ink, weight: .medium), phoneFallbackSwitch])
        phoneToggle.alignment = .center; phoneToggle.spacing = 16
        phoneGroup = field(phoneField, title: "Primary number", placeholder: "+14158676937", helper: "Start international numbers with +.")
        otherNumbers = initialContact?.otherPhoneNumbers ?? []
        otherField.keyboardType = .phonePad
        otherField.textContentType = .telephoneNumber
        otherField.accessibilityIdentifier = "contact.otherNumber"
        otherNumbersList.axis = .vertical; otherNumbersList.spacing = 8
        let addOther = PorchStyle.button("Add number", symbol: "plus", filled: false)
        addOther.addAction(UIAction { [weak self] _ in self?.addOtherNumber() }, for: .touchUpInside)
        let otherHeading = PorchStyle.label("Other numbers", size: 16, color: PorchStyle.ink, weight: .semibold)
        let otherStack = UIStackView(arrangedSubviews: [otherHeading, otherNumbersList,
            field(otherField, title: "Add another number", placeholder: "+14155550123", helper: "These can call in. Porch only calls the primary number."), addOther])
        otherStack.axis = .vertical; otherStack.spacing = 8
        otherGroup = otherStack
        renderOtherNumbers()
        fallbackDetail.textAlignment = .center
        fallbackGroup = section("Phone", views: [fallbackDetail, phoneToggle, phoneGroup, otherGroup])
        form.addArrangedSubview(fallbackGroup)
        // A person already on the key is edited on their page; here, only their numbers.
        if editingNumbers {
            actionGroup.isHidden = true; personGroup.isHidden = true; appearanceGroup.isHidden = true
            form.addArrangedSubview(chooseContactButton)
        }
        refreshPhoneDropIn()
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
        // Someone already on the key has only their numbers here.
        if ProcessInfo.processInfo.arguments.contains("--preview-touch-keyboard") || ProcessInfo.processInfo.arguments.contains("--preview-system-keyboard") { (editingNumbers ? phoneField : nameField).becomeFirstResponder() }
        #endif
    }
    @objc private func updateMethod() {
        view.endEditing(true)
        phoneGroup.isHidden = !phoneFallbackSwitch.isOn
        otherGroup.isHidden = !phoneFallbackSwitch.isOn
        updateFallbackDetail()
    }
    private func updateFallbackDetail() {
        fallbackDetail.text = linked && phoneFallbackSwitch.isOn ? "If Porch isn't answered in \(CallPreferences.fallbackSeconds()) seconds, Porch calls this phone. Voice only." : nil
        fallbackDetail.isHidden = fallbackDetail.text == nil
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
    /// Follows the server's approvals, which may load or change while editing.
    @objc private func refreshPhoneDropIn() {
        guard saveTask == nil, let approvals = FamilyCoordinator.shared.state?.phoneDropIns else { return }
        approvedNumber = initialContact?.phoneNumber.flatMap { number in approvals.contains { $0.number == number } ? number : nil }
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
        // A family member on Porch goes by their Porch name, so only someone being added by phone takes the contact's.
        if !linked && !editingNumbers { nameField.text = CNContactFormatter.string(from: property.contact, style: .fullName) }
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
    /// The photo the linked family member has on Porch, which a family member's key shows.
    private var memberPhotoID: String? {
        if let person = linkedPerson { return person.photoID }
        return selectedFamilyID == nil ? nil : initialContact?.memberPhotoID
    }
    private var memberPhoto: Data? { FamilyPhotos.shared.data(for: memberPhotoID) }
    /// The member photo on screen, so polling redraws only once a new one has downloaded.
    private var shownMemberPhoto: String?
    private func updateAppearance() {
        shownMemberPhoto = memberPhotoID.flatMap { FamilyPhotos.shared.store.contains($0) ? $0 : nil }
        // One photo per family member, kept with their Porch profile, so only someone added by phone gets a photo here.
        let fallback = photoData == nil || linked ? memberPhoto : nil
        photoPreview.image = RecipientAppearance.photo(linked ? fallback : photoData ?? fallback)
        photoPreview.isHidden = photoPreview.image == nil
        photoSource.isHidden = !linked || fallback == nil
        photoButton.isHidden = linked
        removePhotoButton.isHidden = linked || photoData == nil
        photoButton.configuration?.title = photoData != nil ? "Change photo" : "Add photo"
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
        if !editingNumbers { personGroup.isHidden = !person; appearanceGroup.isHidden = !person }
        fallbackGroup.isHidden = !person
        setKeyboardControlVisible(person)
        actionDetail.text = chosenAction == .callControl ? "Hold to decline a call." : nil
        actionDetail.isHidden = actionDetail.text == nil
    }
    /// A family member on Porch goes by their Porch name and photo, so the name is only for someone added by phone.
    @objc private func configureFamilyLinks() {
        defer {
            // Someone invited without a name needs one here until they join and choose their own.
            nameGroup.isHidden = linked && (linkedPerson?.name ?? memberName)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            modeLabel.isHidden = !linked; modeControl.isHidden = !linked
            updateFallbackDetail()
            if memberPhotoID.flatMap({ FamilyPhotos.shared.store.contains($0) ? $0 : nil }) != shownMemberPhoto { updateAppearance() }
        }
        let state = FamilyCoordinator.shared.state
        let people = state?.people.filter { $0.role == .family } ?? []
        if let invitationID, let accepted = people.first(where: { $0.invitationID == invitationID }) { selectedFamilyID = accepted.id }
        if let selectedFamilyID, state != nil, !people.contains(where: { $0.id == selectedFamilyID }) { self.selectedFamilyID = nil }
        let pending = invitationID.map { id in state?.invitations?.contains { $0.id == id } == true } ?? false
        let name = linkedPerson?.name ?? memberName
        invitationStatus.text = selectedFamilyID != nil ? "\(name ?? "They")'s Porch app is connected" : pending ? "Waiting for \(name ?? "them") to accept the invite" : invitationID != nil ? "Invite expired or cancelled. Send a new invite." : nil
        invitationStatus.isHidden = invitationStatus.text == nil
        familyLink.isHidden = selectedFamilyID != nil || pending
        familyLink.configuration?.title = invitationID == nil ? "Invite them" : "Invite again"
        existingPerson.isHidden = selectedFamilyID != nil || pending || people.isEmpty
        existingPerson.menu = UIMenu(children: people.map { person in
            UIAction(title: person.name) { [weak self] _ in
                self?.selectedFamilyID = person.id; self?.invitationID = person.invitationID
                self?.memberName = person.name; self?.configureFamilyLinks(); self?.updateAppearance()
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
            self?.configureFamilyLinks(); self?.updateAppearance()
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
            guard linked || phoneFallbackSwitch.isOn else {
                throw FamilyServiceError(message: "Invite them to Porch or add a phone number so Porch can reach this person.", status: 400)
            }
            // A family member added here goes by their Porch name and photo. A key that had its own keeps them until
            // the caregiver changes them on the person's page.
            let ownDetails = editingNumbers || !linked
            let call = try NativeCall(room: initialContact?.nativeCall?.room ?? "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: modeControl.selectedSegmentIndex == 0 ? .voice : .video)
            let contact = try CallContact(name: ownDetails || !nameGroup.isHidden ? nameField.text ?? "" : "", nativeCall: call,
                phoneNumber: phoneFallbackSwitch.isOn ? PhoneNumberNormalization.e164(phoneField.text ?? "") : nil,
                otherPhoneNumbers: phoneFallbackSwitch.isOn ? otherNumbers : [], familyMemberID: selectedFamilyID, invitationID: invitationID,
                memberName: linkedPerson?.name ?? memberName, buttonColorHex: buttonColorHex, photoData: ownDetails ? photoData : nil)
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

    /// An approved number follows this person's saved primary number: a changed number moves the approval, and a
    /// removed one loses it. New approvals are made on the person's page.
    private func syncPhoneDropIn(number: String?, name: String) async throws {
        guard let previous = approvedNumber, previous != number else { return }
        guard let credential = PorchDevice.credential(for: .bedside) else { throw FamilyServiceError(message: "Finish bedside setup before changing phone drop-in.", status: 409) }
        var values: [String: Any]
        if let number {
            // A drop-in answers on this iPad, so only it can grant its own microphone.
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            guard microphone else { throw FamilyServiceError(message: "Allow microphone access in iPad Settings before approving drop-in.", status: 403) }
            // One request swaps a changed number, so a failure never leaves both approved.
            values = ["number": number, "name": name, "enabled": true, "replacing": previous]
        } else { values = ["number": previous, "enabled": false] }
        let response = try await FamilyService(credential).send("setPhoneDropIn", values, pin: NativeCallSettings.caregiverCode)
        FamilyCoordinator.shared.update(response)
        approvedNumber = number
    }

    private func showContactError(_ error: Error) {
        let alert = UIAlertController(title: "Couldn't save", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true { saveTask?.cancel() }
    }

    @objc private func cancel() {
        saveTask?.cancel()
        navigationController?.popViewController(animated: true)
    }
}
