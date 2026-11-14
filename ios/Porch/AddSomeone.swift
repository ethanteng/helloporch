import UIKit
import AVFoundation
import ContactsUI
import PorchCore

/// Someone being added, as the steps of Add someone fill them in. Every screen of one flow shares it.
final class AddSomeoneDraft {
    /// The key they go on; nil puts them on Porch without a key.
    var key: Int?
    /// Opened from a key, rather than from People's Add someone.
    let fromKeyTile: Bool
    /// The key the flow was opened from. It can be chosen again even if it holds a control, which they replace.
    let startKey: Int?
    /// An invitation already made, kept if a later part of adding them fails and Add is tapped again.
    var invitation: (id: String, link: URL)?
    /// Someone already on Porch, chosen in the first step.
    var member: FamilyPerson?
    var name = ""
    /// E.164 numbers. Porch calls the first; all of them can call in.
    var numbers: [String] = []
    var viaApp = false
    var video = true
    // Family can drop in unless the caregiver turns it off for them, as an invitation from People does.
    var dropInAudio = true
    var dropInVideo = true
    var photo: Data?
    var colorHex: String?

    init(key: Int?, fromKeyTile: Bool) {
        self.key = key; self.fromKeyTile = fromKeyTile
        startKey = fromKeyTile ? key : nil
    }
    /// The flow's title: the key, when it was opened from one, or Add someone.
    var title: String { fromKeyTile ? keySymbol.map { "Key \($0)" } ?? "Add someone" : "Add someone" }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    /// Asks Porch to make an invitation when they're added.
    var inviting: Bool { viaApp && member == nil }
    var keySymbol: String? { key.map { CallSlots.symbol(for: $0) } }

    /// The first key with nothing on it, in the order the keypad reads.
    static func firstFreeKey(_ slots: CallSlots) -> Int? {
        [1, 2, 3, 4, 5, 6, 7, 8, 9, CallSlots.star, 0, CallSlots.pound].first { slots.action(for: $0) == .unassigned }
    }
    /// What the Porch app row says about drop-in for an invitation.
    static func dropInSummary(audio: Bool, video: Bool) -> String {
        audio && video ? "Drop-in on" : audio ? "Audio drop-in" : video ? "Video drop-in" : "Drop-in off"
    }
    /// The colors offered for a key's button, with nil for the bedside's own.
    static let colors: [(name: String, hex: String?)] = [("Default color", nil), ("Blue", "1565C0"), ("Teal", "00838F"), ("Orange", "EF6C00"), ("Red", "C62828"), ("Purple", "6A1B9A")]
    static let badNumber = "Check this number. For other countries, start with +."
}

/// One screen of Add someone, with the pieces its screens share.
class AddSomeoneScreen: CaregiverFormViewController {
    private(set) weak var admin: FamilyAdminViewController?
    let draft: AddSomeoneDraft
    init(admin: FamilyAdminViewController, draft: AddSomeoneDraft) {
        self.admin = admin; self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:draft:)") }
    override func viewDidLoad() { super.viewDidLoad(); if showsFlowTitle { title = draft.title } }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); if showsFlowTitle { title = draft.title } }
    /// The Phone, Porch app and Key screens have titles of their own.
    var showsFlowTitle: Bool { true }
    var lovedOne: String { admin?.current?.householdName ?? "your loved one" }

    /// Back to the People page the flow was opened from.
    func finish() {
        view.endEditing(true)
        guard let navigation = navigationController else { return }
        if let people = navigation.viewControllers.last(where: { $0 is PeopleSettingsViewController }) { navigation.popToViewController(people, animated: true) }
        else { navigation.popToRootViewController(animated: true) }
    }
    func push(_ controller: UIViewController) { view.endEditing(true); navigationController?.pushViewController(controller, animated: true) }

    /// Three bars, the steps done so far filled in.
    func progress(_ step: Int) -> UIView {
        let bars = UIStackView(arrangedSubviews: (1...3).map { index in
            let bar = UIView()
            bar.backgroundColor = index <= step ? PorchStyle.accent : PorchStyle.border
            bar.layer.cornerRadius = 2
            bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
            return bar
        })
        bars.spacing = 6; bars.distribution = .fillEqually
        bars.isAccessibilityElement = true
        bars.accessibilityLabel = "Step \(step) of 3"
        bars.accessibilityIdentifier = "add.progress"
        return bars
    }
    func headline(_ text: String) -> UILabel {
        let label = PorchStyle.label(text, size: 28, color: PorchStyle.ink, weight: .bold)
        label.accessibilityTraits = .header
        label.accessibilityIdentifier = "add.headline"
        return label
    }
    /// Rows or views on a white card, with padding for views that aren't rows.
    func padded(_ views: [UIView], spacing: CGFloat = 14) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical; stack.spacing = spacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        return stack
    }
    func centeredLink(_ title: String, action: @escaping () -> Void) -> UIButton {
        let link = textLink(title, size: 17, action: action)
        link.contentHorizontalAlignment = .center
        return link
    }
    /// A row with an icon, its title, what it's set to, and a chevron.
    func detailRow(_ title: String, value: String, symbol: String, valueIsAction: Bool = false, action: @escaping () -> Void) -> PorchListRow {
        let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = PorchStyle.accent
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        let label = PorchStyle.label(title, size: 18, color: PorchStyle.ink)
        let detail = PorchStyle.label(value, size: 17, color: valueIsAction ? PorchStyle.accent : PorchStyle.secondary, weight: valueIsAction ? .semibold : .regular)
        detail.numberOfLines = 1
        detail.setContentHuggingPriority(.required, for: .horizontal)
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        return PorchListRow([icon, label, detail], label: "\(title), \(value)", action: action)
    }
    func errorLabel() -> UILabel {
        let label = PorchStyle.label("", size: 16, color: .systemRed)
        label.isHidden = true
        label.accessibilityIdentifier = "add.error"
        return label
    }
    func showError(_ message: String) { showPorchError(FamilyServiceError(message: message, status: 400), on: self) }
}

// MARK: Step 1: who

final class AddWhoViewController: AddSomeoneScreen, CNContactPickerDelegate {
    private let nameField = UITextField()
    private let nextButton = PorchStyle.button("Next")
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        form.addArrangedSubview(progress(1))
        form.addArrangedSubview(headline(draft.fromKeyTile ? draft.keySymbol.map { "Who goes on key \($0)?" } ?? "Who are you adding?" : "Who are you adding?"))
        // Family who joined Porch without a key, such as from an invitation sent from a phone.
        if let admin, draft.key != nil {
            let waiting = (admin.current?.people ?? []).filter { admin.key(for: $0) == nil }
            let rows = waiting.map { person -> UIView in
                let photo = FamilyPhotos.shared.data(for: person.photoID)
                let name = PorchStyle.label(person.name, size: 18, color: PorchStyle.ink, weight: .medium)
                let row = PorchListRow([FamilyAdminViewController.avatar(person.name, photo: photo), name], label: person.name) { [weak self] in self?.choose(person) }
                row.accessibilityIdentifier = "add.member.\(person.id)"
                return row
            }
            if !rows.isEmpty { form.addArrangedSubview(group("On Porch", rows: rows)) }
        }
        let contacts = PorchStyle.button("Choose from Contacts", symbol: "person.crop.circle", filled: false)
        contacts.accessibilityIdentifier = "add.contacts"
        contacts.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        nameField.accessibilityIdentifier = "add.name"
        let name = field(nameField, title: "Name", placeholder: "For example, David")
        // `field` resets capitalization; a person's name is capitalized word by word.
        nameField.autocapitalizationType = .words
        nameField.text = draft.member == nil ? draft.name : nil
        nameField.addAction(UIAction { [weak self] _ in self?.nameChanged() }, for: .editingChanged)
        form.addArrangedSubview(group("Someone new", rows: [padded([contacts, name])]))
        nextButton.accessibilityIdentifier = "add.next"
        nextButton.addTarget(self, action: #selector(goNext), for: .touchUpInside)
        form.addArrangedSubview(nextButton)
        if draft.fromKeyTile, let key = draft.key {
            let other = centeredLink("Use key \(CallSlots.symbol(for: key)) for something else") { [weak self] in
                guard let self, let admin = self.admin else { return }
                self.push(KeyActionViewController(admin: admin, key: key, offersSomeone: false))
            }
            other.accessibilityIdentifier = "add.somethingElse"
            form.addArrangedSubview(other)
        }
        nameChanged()
    }
    private var typedName: String { (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private func nameChanged() {
        nextButton.isEnabled = !typedName.isEmpty
        if draft.member == nil || !typedName.isEmpty { draft.name = typedName }
    }
    @objc private func cancel() { finish() }
    private func choose(_ person: FamilyPerson) {
        guard let admin else { return }
        draft.member = person; draft.name = person.name
        draft.viaApp = true; draft.numbers = []; draft.photo = nil
        push(AddCheckViewController(admin: admin, draft: draft))
    }
    @objc private func goNext() {
        guard let admin, !typedName.isEmpty else { return }
        guard typedName.count <= 80 else { showError(CallContact.ValidationError.nameTooLong.localizedDescription); return }
        draft.member = nil; draft.name = typedName
        push(AddReachViewController(admin: admin, draft: draft))
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
        guard let phone = property.value as? CNPhoneNumber else { return }
        do {
            let primary = try PhoneNumberNormalization.e164(phone.stringValue)
            // Their other numbers from Contacts, such as home and mobile, can call in too.
            var numbers = [primary]
            if property.contact.isKeyAvailable(CNContactPhoneNumbersKey) {
                for value in property.contact.phoneNumbers {
                    if let number = try? PhoneNumberNormalization.e164(value.value.stringValue), !numbers.contains(number), numbers.count < CallContact.maximumPhoneNumbers { numbers.append(number) }
                }
            }
            draft.numbers = numbers
            if let name = CNContactFormatter.string(from: property.contact, style: .fullName), !name.isEmpty { nameField.text = name }
            nameChanged()
        } catch { picker.dismiss(animated: true) { [weak self] in self?.showError(AddSomeoneDraft.badNumber) } }
    }
}

// MARK: Step 2: how to reach them

/// A choice that can be ticked on its own: a checkbox, an icon, its name, and what shows under it once ticked.
final class AddOptionCard: UIView {
    let header: PorchListRow
    private let box = UIImageView()
    private let body: UIView?
    private(set) var isOn = false
    var onChange: ((Bool) -> Void)?
    init(title: String, subtitle: String?, symbol: String, body: UIView?) {
        self.body = body
        let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = PorchStyle.accent
        icon.contentMode = .scaleAspectFit
        let iconBox = UIView(); iconBox.backgroundColor = PorchStyle.accent.withAlphaComponent(0.12); iconBox.layer.cornerRadius = 12
        icon.translatesAutoresizingMaskIntoConstraints = false; iconBox.addSubview(icon)
        NSLayoutConstraint.activate([iconBox.widthAnchor.constraint(equalToConstant: 44), iconBox.heightAnchor.constraint(equalToConstant: 44),
                                     icon.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor), icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
                                     icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24)])
        box.contentMode = .scaleAspectFit
        box.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        box.setContentHuggingPriority(.required, for: .horizontal)
        let text = FamilyAdminViewController.text(title, [subtitle])
        header = PorchListRow([box, iconBox, text], label: title, chevron: false) {}
        super.init(frame: .zero)
        backgroundColor = PorchStyle.surface
        layer.cornerRadius = 20
        layer.borderWidth = 2
        let stack = UIStackView(arrangedSubviews: [header] + (body.map { [padded($0)] } ?? []))
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: topAnchor, constant: 4), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)])
        header.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        set(false)
    }
    required init?(coder: NSCoder) { fatalError("Use init(title:subtitle:symbol:body:)") }
    private func padded(_ body: UIView) -> UIView {
        let wrap = UIStackView(arrangedSubviews: [body])
        wrap.isLayoutMarginsRelativeArrangement = true
        // Lines up with the title, past the checkbox.
        wrap.directionalLayoutMargins = .init(top: 0, leading: 16, bottom: 12, trailing: 16)
        return wrap
    }
    func set(_ on: Bool) {
        isOn = on
        box.image = UIImage(systemName: on ? "checkmark.square.fill" : "square")
        box.tintColor = on ? PorchStyle.accent : PorchStyle.secondary
        layer.borderColor = (on ? PorchStyle.accent : PorchStyle.surface).cgColor
        body?.superview?.isHidden = !on
        header.accessibilityTraits = on ? [.button, .selected] : .button
        header.accessibilityValue = on ? "Chosen" : "Not chosen"
    }
    private func toggle() { set(!isOn); onChange?(isOn) }
}

final class AddReachViewController: AddSomeoneScreen {
    private let numberField = UITextField()
    private lazy var error = errorLabel()
    private var phone: AddOptionCard!
    private var app: AddOptionCard!
    override func viewDidLoad() {
        super.viewDidLoad()
        form.addArrangedSubview(progress(2))
        form.addArrangedSubview(headline("How should \(lovedOne) reach \(draft.firstName)?"))
        numberField.keyboardType = .phonePad
        numberField.textContentType = .telephoneNumber
        numberField.accessibilityIdentifier = "add.phoneNumber"
        let number = field(numberField, title: "\(draft.firstName)’s phone number", placeholder: "Phone number")
        // The option's own title says Phone, so the field needs no visible label.
        (number as? UIStackView)?.arrangedSubviews.first?.isHidden = true
        numberField.addAction(UIAction { [weak self] _ in self?.clearError() }, for: .editingChanged)
        let numberStack = UIStackView(arrangedSubviews: [number, error]); numberStack.axis = .vertical; numberStack.spacing = 8
        phone = AddOptionCard(title: "Phone", subtitle: nil, symbol: "phone", body: numberStack)
        phone.header.accessibilityIdentifier = "add.viaPhone"
        app = AddOptionCard(title: "Porch app", subtitle: "Video calls, photos and messages", symbol: "video", body: nil)
        app.header.accessibilityIdentifier = "add.viaApp"
        phone.onChange = { [weak self] on in
            guard let self else { return }
            self.clearError()
            if on { self.numberField.becomeFirstResponder() } else { self.view.endEditing(true) }
        }
        form.addArrangedSubview(phone)
        form.addArrangedSubview(app)
        let next = PorchStyle.button("Next")
        next.accessibilityIdentifier = "add.next"
        next.addTarget(self, action: #selector(goNext), for: .touchUpInside)
        form.addArrangedSubview(next)
    }
    // Back from Check, the Phone and Key screens there may have changed their numbers or key.
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); showDraft() }
    /// The numbers, choices and key the draft holds now, so Next never saves a number this screen showed earlier.
    private func showDraft() {
        numberField.text = draft.numbers.first.map { PhoneNumberNormalization.display($0) }
        clearError()
        // A phone number lives on a key, so someone without one can only be on Porch.
        phone.set(draft.key != nil && !draft.numbers.isEmpty)
        phone.header.isEnabled = draft.key != nil
        app.set(draft.viaApp)
    }
    private func clearError() {
        error.isHidden = true
        if !numberField.isFirstResponder { numberField.layer.borderColor = PorchStyle.border.cgColor; numberField.layer.borderWidth = 1 }
    }
    override func textFieldDidEndEditing(_ textField: UITextField) {
        super.textFieldDidEndEditing(textField)
        if textField === numberField, !error.isHidden { textField.layer.borderColor = UIColor.systemRed.cgColor; textField.layer.borderWidth = 2 }
    }
    @objc private func goNext() {
        guard let admin else { return }
        view.endEditing(true)
        guard phone.isOn || app.isOn else { showError("Choose Phone or Porch app."); return }
        if phone.isOn {
            guard let number = try? PhoneNumberNormalization.e164(numberField.text ?? "") else {
                error.text = AddSomeoneDraft.badNumber; error.isHidden = false
                numberField.layer.borderColor = UIColor.systemRed.cgColor; numberField.layer.borderWidth = 2
                UIAccessibility.post(notification: .announcement, argument: AddSomeoneDraft.badNumber)
                return
            }
            // The number typed here is the one Porch calls; any others from Contacts stay.
            var numbers = draft.numbers
            if numbers.first != number { numbers.removeAll { $0 == number }; numbers = [number] + numbers.dropFirst() }
            draft.numbers = Array(numbers.prefix(CallContact.maximumPhoneNumbers))
        } else { draft.numbers = [] }
        draft.viaApp = app.isOn
        push(AddCheckViewController(admin: admin, draft: draft))
    }
}

// MARK: Step 3: check

final class AddCheckViewController: AddSomeoneScreen {
    private lazy var chooser = PhotoChooser(presenter: self) { [weak self] data in self?.photoChosen(data) }
    private var saveTask: Task<Void, Never>?
    private let add = PorchStyle.button("Add")
    override func viewDidLoad() {
        super.viewDidLoad()
        hideKeyboardControl()
        add.accessibilityIdentifier = "add.save"
        add.addTarget(self, action: #selector(save), for: .touchUpInside)
    }
    // Comes back from the Phone, Porch app and Key screens with the draft changed.
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); render() }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { saveTask?.cancel() }
    }
    private func render() {
        form.arrangedSubviews.forEach { form.removeArrangedSubview($0); $0.removeFromSuperview() }
        form.addArrangedSubview(progress(3))
        form.addArrangedSubview(headline(draft.keySymbol.map { "Check key \($0)" } ?? "Check \(draft.firstName)"))
        if let key = draft.keySymbol {
            let caption = PorchStyle.label("On \(lovedOne)’s screen", size: 15, weight: .semibold)
            caption.textAlignment = .center
            form.addArrangedSubview(caption)
            form.setCustomSpacing(8, after: caption)
            form.addArrangedSubview(preview(key))
        }
        if draft.key != nil { form.addArrangedSubview(appearance()) }
        var rows: [UIView] = []
        if draft.member != nil || draft.viaApp {
            let value = draft.member != nil ? "Connected" : AddSomeoneDraft.dropInSummary(audio: draft.dropInAudio, video: draft.dropInVideo)
            let row = detailRow("Porch app", value: value, symbol: "video") { [weak self] in self?.openApp() }
            row.accessibilityIdentifier = "add.row.app"
            rows.append(row)
        }
        if draft.key != nil {
            let number = draft.numbers.first.map { PhoneNumberNormalization.display($0) + (draft.numbers.count > 1 ? " +\(draft.numbers.count - 1)" : "") }
            let row = detailRow("Phone", value: number ?? "Add", symbol: "phone", valueIsAction: number == nil) { [weak self] in self?.openPhone() }
            row.accessibilityIdentifier = "add.row.phone"
            rows.append(row)
        }
        let keyRow = detailRow("Key", value: draft.keySymbol ?? "None", symbol: "circle.grid.3x3") { [weak self] in self?.openKey() }
        keyRow.accessibilityIdentifier = "add.row.key"
        rows.append(keyRow)
        form.addArrangedSubview(group(rows: rows))
        add.configuration?.title = saveTask != nil ? "Adding…" : draft.keySymbol.map { "Add to key \($0)" } ?? "Invite \(draft.firstName)"
        form.addArrangedSubview(add)
    }
    /// Their button as the bedside shows it.
    private func preview(_ key: String) -> UIView {
        let color = RecipientAppearance.color(hex: draft.colorHex)
        let foreground = RecipientAppearance.foreground(on: color)
        let photo = draft.member.map { FamilyPhotos.shared.data(for: $0.photoID) } ?? draft.photo
        let picture: UIView
        if let image = RecipientAppearance.cardPhoto(photo, width: 96) {
            let view = UIImageView(image: image); view.contentMode = .scaleAspectFill
            NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: 96), view.heightAnchor.constraint(equalToConstant: 96)])
            picture = view
        } else {
            // Initials in the card's own lettering color, so they read on dark and light buttons alike.
            let circle = FamilyAdminViewController.circle(size: 64)
            circle.backgroundColor = foreground.withAlphaComponent(0.16)
            let initials = UILabel()
            initials.text = draft.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
            initials.font = .systemFont(ofSize: 23, weight: .semibold)
            initials.textColor = foreground
            FamilyAdminViewController.center(initials, in: circle)
            picture = circle
        }
        let name = PorchStyle.label(draft.name, size: 26, color: foreground, weight: .semibold)
        let press = PorchStyle.label("Press \(key)", size: 18, color: foreground.withAlphaComponent(0.8), weight: .medium)
        [name, press].forEach { $0.textAlignment = .center }
        let stack = UIStackView(arrangedSubviews: [picture, name, press])
        stack.axis = .vertical; stack.alignment = .center; stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 20, leading: 20, bottom: 20, trailing: 20)
        stack.backgroundColor = color
        stack.layer.cornerRadius = 24
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "\(draft.name), press \(key)"
        stack.accessibilityIdentifier = "add.preview"
        return stack
    }
    /// Photo, for someone not yet on Porch, and the button colors.
    private func appearance() -> UIView {
        var views: [UIView] = []
        if draft.member == nil {
            let photo = PorchStyle.button(draft.photo == nil ? "Photo" : "Change photo", symbol: "photo", filled: false)
            photo.configuration?.contentInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
            photo.accessibilityIdentifier = "add.photo"
            chooser.attach(to: photo)
            views.append(FamilyAdminViewController.singleLine(photo))
            views.append(UIView())
        }
        let swatches = UIStackView(arrangedSubviews: AddSomeoneDraft.colors.map { choice in
            AddSwatch(hex: choice.hex, name: choice.name, selected: choice.hex == draft.colorHex) { [weak self] in self?.draft.colorHex = choice.hex; self?.render() }
        })
        swatches.spacing = 2
        swatches.setContentHuggingPriority(.required, for: .horizontal)
        views.append(swatches)
        let row = UIStackView(arrangedSubviews: views)
        row.alignment = .center
        if draft.member != nil { row.addArrangedSubview(UIView()); row.insertArrangedSubview(UIView(), at: 0); row.distribution = .equalCentering }
        return row
    }
    private func photoChosen(_ data: Data?) {
        guard let data else { showError("That photo couldn't be opened. Please choose another photo."); return }
        draft.photo = data; render()
    }
    private func openApp() { guard let admin else { return }; push(AddPorchAppViewController(admin: admin, draft: draft)) }
    private func openPhone() { guard let admin else { return }; push(AddPhoneNumbersViewController(admin: admin, draft: draft)) }
    private func openKey() { guard let admin else { return }; push(AddKeyViewController(admin: admin, draft: draft)) }

    @objc private func save() {
        guard saveTask == nil, let admin else { return }
        guard draft.viaApp || draft.member != nil || !draft.numbers.isEmpty else { showError("Choose Phone or Porch app."); return }
        let draft = draft
        add.isEnabled = false; add.configuration?.title = "Adding…"
        view.isUserInteractionEnabled = false
        saveTask = Task { [weak self] in
            defer {
                self?.saveTask = nil
                self?.view.isUserInteractionEnabled = true
                self?.add.isEnabled = true
                if let self, self.isViewLoaded { self.render() }
            }
            do {
                let link = try await AddCheckViewController.add(draft, admin: admin)
                guard let self, !Task.isCancelled else { return }
                if let link { self.push(AddInviteViewController(admin: admin, draft: draft, link: link)) } else { self.finish() }
            } catch AddSomeoneCancelled.mediaRefused {
                // requestMedia has said why.
            } catch {
                if !Task.isCancelled { admin.showError(error) }
            }
        }
    }
    /// Approves their number, makes their invitation, and puts them on their key. Returns the invitation's link.
    @MainActor static func add(_ draft: AddSomeoneDraft, admin: FamilyAdminViewController) async throws -> URL? {
        if let number = draft.numbers.first {
            let server = try NativeCallSettings.loadForPhone()
            _ = try await NativeCallSettings.authorizePhone(number, server: server, refresh: true)
            try Task.checkCancellation()
        }
        var invitation = draft.invitation
        if draft.inviting, invitation == nil {
            guard let credential = PorchDevice.credential(for: .bedside), let pin = admin.caregiverPIN() else {
                throw FamilyServiceError(message: "Finish setting up this iPad before inviting someone.", status: 409)
            }
            // Drop-in answers on this iPad, so only it can grant its own microphone and camera.
            if draft.dropInAudio || draft.dropInVideo { guard await admin.requestMedia(video: draft.dropInVideo) else { throw AddSomeoneCancelled.mediaRefused } }
            let response = try await FamilyService(credential).send("createInvite", ["name": draft.name, "permissions": ["audio": draft.dropInAudio, "video": draft.dropInVideo], "caregiver": false], pin: pin)
            guard let code = response.code, let id = response.invitationID else { throw FamilyInvitation.InvitationError.invalid }
            FamilyCoordinator.shared.update(response)
            invitation = (id, FamilyInvitation.url(origin: credential.origin, code: code, defaultOrigin: PorchDevice.defaultOrigin))
            draft.invitation = invitation
            try Task.checkCancellation()
        }
        if let key = draft.key {
            let linked = draft.member != nil || invitation != nil
            let contact = try CallContact(name: linked ? "" : draft.name,
                nativeCall: NativeCall(room: "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: draft.video ? .video : .voice),
                phoneNumber: draft.numbers.first, otherPhoneNumbers: Array(draft.numbers.dropFirst()),
                familyMemberID: draft.member?.id, invitationID: draft.member?.invitationID ?? invitation?.id,
                memberName: draft.member?.name ?? (invitation != nil ? draft.name : nil),
                buttonColorHex: draft.colorHex, photoData: draft.member == nil ? draft.photo : nil)
            try admin.saveSlots { try $0.setContact(contact, for: key); try $0.setAction(.person, for: key) }
        }
        return invitation?.link
    }
}

enum AddSomeoneCancelled: Error { case mediaRefused }

/// One button color: a circle in a target big enough to tap, ringed when chosen.
final class AddSwatch: UIControl {
    init(hex: String?, name: String, selected: Bool, action: @escaping () -> Void) {
        super.init(frame: .zero)
        let circle = UIView()
        circle.backgroundColor = RecipientAppearance.color(hex: hex)
        circle.layer.cornerRadius = 15
        circle.isUserInteractionEnabled = false
        circle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circle)
        layer.cornerRadius = 22
        layer.borderWidth = selected ? 3 : 0
        layer.borderColor = PorchStyle.ink.cgColor
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 44), heightAnchor.constraint(equalToConstant: 44),
                                     circle.widthAnchor.constraint(equalToConstant: 30), circle.heightAnchor.constraint(equalToConstant: 30),
                                     circle.centerXAnchor.constraint(equalTo: centerXAnchor), circle.centerYAnchor.constraint(equalTo: centerYAnchor)])
        isAccessibilityElement = true
        accessibilityLabel = name
        accessibilityTraits = selected ? [.button, .selected] : .button
        accessibilityIdentifier = "add.color.\(hex ?? "default")"
        addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("Use init(hex:name:selected:action:)") }
}

// MARK: Step 4: the invitation

final class AddInviteViewController: AddSomeoneScreen {
    private let link: URL
    private let share = PorchStyle.button("Share invite link", symbol: "square.and.arrow.up")
    init(admin: FamilyAdminViewController, draft: AddSomeoneDraft, link: URL) {
        self.link = link
        super.init(admin: admin, draft: draft)
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:draft:link:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        hideKeyboardControl()
        navigationItem.hidesBackButton = true
        let badge = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)))
        badge.tintColor = PorchStyle.accent
        badge.contentMode = .center
        form.addArrangedSubview(badge)
        let heading = headline(draft.keySymbol.map { "\(draft.firstName) is on key \($0)" } ?? "Invite ready")
        heading.textAlignment = .center
        form.addArrangedSubview(heading)
        let title = PorchStyle.label("Send \(draft.firstName) the invite", size: 20, color: PorchStyle.ink, weight: .semibold)
        title.textAlignment = .center
        let code = UIImageView(image: SetupYourPhoneViewController.qrCode(link.absoluteString))
        code.contentMode = .scaleAspectFit
        code.layer.magnificationFilter = .nearest
        code.isAccessibilityElement = true
        code.accessibilityLabel = "QR code for \(draft.firstName)’s invitation"
        code.accessibilityIdentifier = "add.inviteCode"
        code.heightAnchor.constraint(equalToConstant: 220).isActive = true
        share.accessibilityIdentifier = "add.share"
        share.addTarget(self, action: #selector(shareLink), for: .touchUpInside)
        let expiry = PorchStyle.label("Works once, for 24 hours.", size: 15)
        expiry.textAlignment = .center
        form.addArrangedSubview(group(rows: [padded([title, code, share, expiry], spacing: 16)]))
        let done = PorchStyle.button("Done", filled: false)
        done.accessibilityIdentifier = "add.done"
        done.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        form.addArrangedSubview(done)
    }
    @objc private func shareLink() {
        let sheet = UIActivityViewController(activityItems: FamilyInviteViewController.shareItems(link), applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = share
        sheet.popoverPresentationController?.sourceRect = share.bounds
        present(sheet, animated: true)
    }
}

// MARK: Phone numbers

/// Someone's phone numbers: which one Porch calls, and the rest that can call in. In Add someone it changes the draft.
/// Opened from the Phone row on someone's page, it edits a copy of their key's numbers, and Done saves them there.
final class AddPhoneNumbersViewController: AddSomeoneScreen, CNContactPickerDelegate {
    override var showsFlowTitle: Bool { false }
    /// The key and person whose numbers Done saves, when this was opened from their page.
    private let saving: (key: Int, contact: CallContact)?
    /// Redrawn whenever a number is added, removed or made the one Porch calls.
    private let host = UIStackView()
    private let numberField = UITextField()
    private let addButton = PorchStyle.button("Add", filled: false)
    private let done = PorchStyle.button("Done")
    private lazy var error = errorLabel()
    private var saveTask: Task<Void, Never>?

    init(admin: FamilyAdminViewController, draft: AddSomeoneDraft, saving: (key: Int, contact: CallContact)?) {
        self.saving = saving
        super.init(admin: admin, draft: draft)
    }
    override convenience init(admin: FamilyAdminViewController, draft: AddSomeoneDraft) { self.init(admin: admin, draft: draft, saving: nil) }
    /// The numbers of someone already on a key, from their page.
    convenience init(admin: FamilyAdminViewController, key: Int, contact: CallContact) {
        let draft = AddSomeoneDraft(key: key, fromKeyTile: false)
        draft.name = contact.name; draft.numbers = contact.phoneNumbers
        self.init(admin: admin, draft: draft, saving: (key, contact))
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:draft:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Phone"
        host.axis = .vertical
        numberField.keyboardType = .phonePad
        numberField.textContentType = .telephoneNumber
        numberField.accessibilityIdentifier = "add.newNumber"
        numberField.addAction(UIAction { [weak self] _ in self?.error.isHidden = true }, for: .editingChanged)
        addButton.accessibilityIdentifier = "add.addNumber"
        addButton.addAction(UIAction { [weak self] _ in _ = self?.takeTyped() }, for: .touchUpInside)
        form.addArrangedSubview(host)
        form.addArrangedSubview(error)
        form.addArrangedSubview(PorchStyle.label("All of these can call \(lovedOne).", size: 16))
        done.accessibilityIdentifier = "add.doneNumbers"
        done.addAction(UIAction { [weak self] _ in self?.finishNumbers() }, for: .touchUpInside)
        form.addArrangedSubview(done)
        renderList()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { saveTask?.cancel() }
    }
    private func renderList() {
        host.arrangedSubviews.forEach { host.removeArrangedSubview($0); $0.removeFromSuperview() }
        var rows: [UIView] = draft.numbers.enumerated().map { index, number in
            let shown = PhoneNumberNormalization.display(number)
            let radio = UIImageView(image: UIImage(systemName: index == 0 ? "largecircle.fill.circle" : "circle"))
            radio.tintColor = index == 0 ? PorchStyle.accent : PorchStyle.secondary
            radio.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22)
            radio.setContentHuggingPriority(.required, for: .horizontal)
            radio.setContentCompressionResistancePriority(.required, for: .horizontal)
            var views: [UIView] = [radio, PorchStyle.label(shown, size: 18, color: PorchStyle.ink)]
            if index == 0 { views.append(PaddedLabel("Porch calls")) }
            let choose = PorchListRow(views, label: shown, chevron: false) { [weak self] in self?.makeFirst(number) }
            choose.accessibilityValue = index == 0 ? "Porch calls this number" : nil
            choose.accessibilityTraits = index == 0 ? [.button, .selected] : .button
            choose.accessibilityIdentifier = "add.number.\(index)"
            let remove = UIButton(type: .system)
            remove.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
            remove.tintColor = PorchStyle.secondary
            remove.accessibilityLabel = "Remove \(shown)"
            remove.addAction(UIAction { [weak self] _ in self?.remove(number) }, for: .touchUpInside)
            NSLayoutConstraint.activate([remove.widthAnchor.constraint(equalToConstant: 48), remove.heightAnchor.constraint(equalToConstant: 48)])
            // The number row has its own padding, so this row adds only a little past the remove button.
            let row = listRow(choose, trailing: remove)
            row.directionalLayoutMargins = .init(top: 0, leading: 0, bottom: 0, trailing: 8)
            return row
        }
        let entry = field(numberField, title: "Add a number", placeholder: "Add a number")
        // The placeholder says what the field is for, so it needs no label above it.
        (entry as? UIStackView)?.arrangedSubviews.first?.isHidden = true
        rows.append(listRow(entry, trailing: FamilyAdminViewController.singleLine(addButton)))
        let contacts = actionRow("Choose from Contacts", symbol: "person.crop.circle") { [weak self] in self?.pickContact() }
        contacts.accessibilityIdentifier = "add.numberFromContacts"
        rows.append(contacts)
        host.addArrangedSubview(group(rows: rows))
    }
    private func makeFirst(_ number: String) {
        draft.numbers.removeAll { $0 == number }
        draft.numbers.insert(number, at: 0)
        renderList()
    }
    private func remove(_ number: String) { draft.numbers.removeAll { $0 == number }; renderList() }
    private func show(_ message: String?) {
        error.text = message; error.isHidden = message == nil
        if let message { UIAccessibility.post(notification: .announcement, argument: message) }
    }
    /// Adds what's typed, if anything. False, with the reason shown, when it can't be added.
    private func takeTyped() -> Bool {
        let typed = (numberField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return true }
        let message: String?
        if let number = try? PhoneNumberNormalization.e164(typed) {
            if draft.numbers.contains(number) { message = "That number is already saved for them." }
            else if draft.numbers.count >= CallContact.maximumPhoneNumbers { message = CallContact.ValidationError.tooManyPhoneNumbers.localizedDescription }
            else { message = nil; draft.numbers.append(number); numberField.text = nil; renderList() }
        } else { message = AddSomeoneDraft.badNumber }
        show(message)
        return message == nil
    }

    // MARK: Contacts

    private func pickContact() {
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
    /// The number tapped becomes the one Porch calls.
    func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
        guard let phone = property.value as? CNPhoneNumber else { return }
        guard let number = try? PhoneNumberNormalization.e164(phone.stringValue) else { show(AddSomeoneDraft.badNumber); return }
        if draft.numbers.contains(number) || draft.numbers.count < CallContact.maximumPhoneNumbers {
            makeFirst(number); show(nil)
        } else { show(CallContact.ValidationError.tooManyPhoneNumbers.localizedDescription) }
    }

    // MARK: Done

    private func finishNumbers() {
        guard saveTask == nil, takeTyped() else { return }
        view.endEditing(true)
        guard let saving, let admin else { navigationController?.popViewController(animated: true); return }
        let numbers = draft.numbers
        guard numbers != saving.contact.phoneNumbers else { navigationController?.popViewController(animated: true); return }
        // Someone who isn't on Porch is reached only by phone.
        guard !numbers.isEmpty || saving.contact.familyMemberID != nil || saving.contact.invitationID != nil else {
            show("Add a number so Porch can reach \(draft.firstName)."); return
        }
        done.isEnabled = false; done.configuration?.title = "Saving…"
        view.isUserInteractionEnabled = false
        saveTask = Task { [weak self] in
            defer {
                self?.saveTask = nil
                self?.view.isUserInteractionEnabled = true
                self?.done.isEnabled = true; self?.done.configuration?.title = "Done"
            }
            do {
                try await Self.save(numbers, to: saving.key, replacing: saving.contact, admin: admin)
                guard let self, !Task.isCancelled else { return }
                self.navigationController?.popViewController(animated: true)
            } catch {
                if !Task.isCancelled { admin.showError(error) }
            }
        }
    }
    /// Approves the number Porch calls, moves its phone drop-in with it, and saves the key with everything else kept.
    @MainActor static func save(_ numbers: [String], to key: Int, replacing original: CallContact, admin: FamilyAdminViewController) async throws {
        if let number = numbers.first {
            let server = try NativeCallSettings.loadForPhone()
            _ = try await NativeCallSettings.authorizePhone(number, server: server, refresh: true)
            try Task.checkCancellation()
        }
        try await movePhoneDropIn(from: original.phoneNumber, to: numbers.first, name: original.name)
        try Task.checkCancellation()
        let contact = try CallContact(name: original.customName,
            nativeCall: original.nativeCall ?? NativeCall(room: "contact-\(UUID().uuidString.prefix(8).lowercased())", mode: .video),
            phoneNumber: numbers.first, otherPhoneNumbers: Array(numbers.dropFirst()), familyMemberID: original.familyMemberID,
            invitationID: original.invitationID, memberName: original.memberName, buttonColorHex: original.buttonColorHex,
            photoData: original.customPhotoData)
        try admin.saveSlots { try $0.setContact(contact, for: key) }
    }
    /// A phone drop-in approval follows the number Porch calls: a new one moves it, and none withdraws it.
    @MainActor private static func movePhoneDropIn(from previous: String?, to number: String?, name: String) async throws {
        guard let previous, previous != number, FamilyCoordinator.shared.state?.phoneDropIns?.contains(where: { $0.number == previous }) == true else { return }
        guard let credential = PorchDevice.credential(for: .bedside) else { throw FamilyServiceError(message: "Finish bedside setup before changing phone drop-in.", status: 409) }
        let values: [String: Any]
        if let number {
            // A drop-in answers on this iPad, so only it can grant its own microphone.
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw FamilyServiceError(message: "Allow microphone access in iPad Settings before approving drop-in.", status: 403)
            }
            // One request swaps the number, so a failure never leaves both approved.
            values = ["number": number, "name": name, "enabled": true, "replacing": previous]
        } else { values = ["number": previous, "enabled": false] }
        let response = try await FamilyService(credential).send("setPhoneDropIn", values, pin: NativeCallSettings.caregiverCode)
        FamilyCoordinator.shared.update(response)
    }
}

/// A small rounded label, such as "Porch calls" beside a number.
final class PaddedLabel: UILabel {
    init(_ text: String) {
        super.init(frame: .zero)
        self.text = text
        font = PorchStyle.font(14, weight: .semibold)
        textColor = PorchStyle.accent
        backgroundColor = PorchStyle.accent.withAlphaComponent(0.12)
        layer.cornerRadius = 12; clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:)") }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 20, height: size.height + 8)
    }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 10, dy: 4)) }
}

// MARK: Porch app

final class AddPorchAppViewController: AddSomeoneScreen {
    override var showsFlowTitle: Bool { false }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Porch app"
        hideKeyboardControl()
        let mode = PorchStyle.segmented(["Voice", "Video"])
        mode.selectedSegmentIndex = draft.video ? 1 : 0
        mode.accessibilityLabel = "Calls start with"
        mode.accessibilityIdentifier = "add.callMode"
        mode.addAction(UIAction { [weak self, weak mode] _ in self?.draft.video = mode?.selectedSegmentIndex == 1 }, for: .valueChanged)
        form.addArrangedSubview(group("Calls start with", rows: [padded([mode])]))
        if draft.inviting {
            let audio = UISwitch(); audio.isOn = draft.dropInAudio; audio.accessibilityIdentifier = "add.audioDropIn"
            let video = UISwitch(); video.isOn = draft.dropInVideo; video.accessibilityIdentifier = "add.videoDropIn"
            audio.addAction(UIAction { [weak self, weak audio] _ in self?.draft.dropInAudio = audio?.isOn == true }, for: .valueChanged)
            video.addAction(UIAction { [weak self, weak video] _ in self?.draft.dropInVideo = video?.isOn == true }, for: .valueChanged)
            let audioRow = toggleRow("Audio", audio), videoRow = toggleRow("Video", video)
            audio.accessibilityLabel = "Audio drop-in"; video.accessibilityLabel = "Video drop-in"
            form.addArrangedSubview(group("Drop-in", detail: "Connects without \(lovedOne) answering.", rows: [audioRow, videoRow]))
        }
        let done = PorchStyle.button("Done")
        done.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        form.addArrangedSubview(done)
    }
}

// MARK: Key

/// Chooses a free key, or none for someone who's only on the Porch app.
final class AddKeyViewController: AddSomeoneScreen {
    override var showsFlowTitle: Bool { false }
    private let grid = UIStackView()
    private var chosen: Int?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Key"
        hideKeyboardControl()
        chosen = draft.key
        grid.axis = .vertical; grid.spacing = 10
        form.addArrangedSubview(grid)
        let done = PorchStyle.button("Done")
        done.accessibilityIdentifier = "add.doneKey"
        done.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.draft.key = self.chosen
            self.navigationController?.popViewController(animated: true)
        }, for: .touchUpInside)
        form.addArrangedSubview(done)
        // A phone number lives on a key, and someone already on Porch is added only to put them on one.
        if draft.numbers.isEmpty, draft.inviting {
            let none = centeredLink("Not on the keypad") { [weak self] in
                self?.draft.key = nil
                self?.navigationController?.popViewController(animated: true)
            }
            none.accessibilityIdentifier = "add.noKey"
            form.addArrangedSubview(none)
        }
        renderGrid()
    }
    private func renderGrid() {
        grid.arrangedSubviews.forEach { grid.removeArrangedSubview($0); $0.removeFromSuperview() }
        let slots = admin?.slots ?? CallSlots()
        let order = [1, 2, 3, 4, 5, 6, 7, 8, 9, CallSlots.star, 0, CallSlots.pound]
        for start in stride(from: 0, to: order.count, by: 3) {
            let row = UIStackView(arrangedSubviews: order[start..<start + 3].map { digit -> UIView in
                let action = slots.action(for: digit) ?? .unassigned
                let free = action == .unassigned || digit == draft.startKey
                let label: String
                switch action {
                case .person: label = slots.contact(for: digit)?.name ?? ""
                case .callControl: label = "Answer / hang up"
                case .toggleVideo: label = "Video on / off"
                case .messages: label = "Messages"
                case .unassigned: label = ""
                }
                return AddKeyTile(key: CallSlots.symbol(for: digit), title: digit == chosen ? draft.firstName : label, free: free, selected: digit == chosen) { [weak self] in
                    self?.chosen = digit; self?.renderGrid()
                }
            })
            row.spacing = 10; row.distribution = .fillEqually
            grid.addArrangedSubview(row)
        }
    }
}

/// One key to choose: free, chosen, or in use and greyed out with who or what is on it.
final class AddKeyTile: UIControl {
    init(key: String, title: String, free: Bool, selected: Bool, action: @escaping () -> Void) {
        super.init(frame: .zero)
        layer.cornerRadius = 16
        backgroundColor = selected ? PorchStyle.surface : free ? nil : PorchStyle.border.withAlphaComponent(0.35)
        layer.borderWidth = selected ? 3 : free ? 1.5 : 0
        layer.borderColor = (selected ? PorchStyle.accent : PorchStyle.border).cgColor
        let number = PorchStyle.label(key, size: 17, color: free ? PorchStyle.accent : PorchStyle.secondary, weight: .bold)
        let name = PorchStyle.label(title, size: 15, color: selected ? PorchStyle.ink : PorchStyle.secondary, weight: selected ? .semibold : .medium)
        name.textAlignment = .center; name.numberOfLines = 2
        for view in [number, name] { view.translatesAutoresizingMaskIntoConstraints = false; view.isUserInteractionEnabled = false; addSubview(view) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
            number.topAnchor.constraint(equalTo: topAnchor, constant: 8), number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            name.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 8),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            name.topAnchor.constraint(greaterThanOrEqualTo: number.bottomAnchor, constant: 2),
            name.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])
        isEnabled = free
        isAccessibilityElement = true
        accessibilityLabel = "Key \(key)"
        accessibilityValue = free ? (selected ? "Chosen" : "Free") : title
        accessibilityTraits = selected ? [.button, .selected] : free ? .button : [.button, .notEnabled]
        accessibilityIdentifier = "add.key.\(key)"
        addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("Use init(key:title:free:selected:action:)") }
}

// MARK: What a key does

/// What a key does when it isn't someone's: a call control, Messages, or nothing. Opened from a key holding a
/// control, it can also put someone on the key.
final class KeyActionViewController: CaregiverFormViewController {
    private weak var admin: FamilyAdminViewController?
    private let key: Int
    private let offersSomeone: Bool
    private var choice: KeypadAction
    private var choices: [(KeypadAction, UIImageView, PorchListRow)] = []
    static let options: [(KeypadAction, String)] = [(.callControl, "Answer / hang up"), (.toggleVideo, "Video on / off"), (.messages, "Play messages"), (.unassigned, "Nothing")]
    init(admin: FamilyAdminViewController, key: Int, offersSomeone: Bool) {
        self.admin = admin; self.key = key; self.offersSomeone = offersSomeone
        let current = admin.slots?.action(for: key) ?? .unassigned
        choice = current == .person ? .unassigned : current
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:key:offersSomeone:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        let symbol = CallSlots.symbol(for: key)
        title = "Key \(symbol)"
        hideKeyboardControl()
        let heading = PorchStyle.label("What should key \(symbol) do?", size: 28, color: PorchStyle.ink, weight: .bold)
        heading.accessibilityTraits = .header
        form.addArrangedSubview(heading)
        if offersSomeone {
            let someone = PorchListRow([PorchStyle.label("Someone", size: 18, color: PorchStyle.ink)], label: "Someone") { [weak self] in
                guard let self, let admin = self.admin else { return }
                self.navigationController?.pushViewController(AddWhoViewController(admin: admin, draft: AddSomeoneDraft(key: self.key, fromKeyTile: true)), animated: true)
            }
            someone.accessibilityIdentifier = "keypad.action.person"
            form.addArrangedSubview(group(rows: [someone]))
        }
        let rows = Self.options.map { action, title -> UIView in
            let radio = UIImageView()
            radio.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22)
            radio.setContentHuggingPriority(.required, for: .horizontal)
            let row = PorchListRow([radio, PorchStyle.label(title, size: 18, color: PorchStyle.ink)], label: title, chevron: false) { [weak self] in
                self?.choice = action; self?.update()
            }
            row.accessibilityIdentifier = "keypad.action.\(action.rawValue)"
            self.choices.append((action, radio, row))
            return row
        }
        form.addArrangedSubview(group(rows: rows))
        let save = PorchStyle.button("Save")
        save.accessibilityIdentifier = "keypad.action.save"
        save.addTarget(self, action: #selector(saveChoice), for: .touchUpInside)
        form.addArrangedSubview(save)
        update()
    }
    private func update() {
        for (action, radio, row) in choices {
            let on = action == choice
            radio.image = UIImage(systemName: on ? "largecircle.fill.circle" : "circle")
            radio.tintColor = on ? PorchStyle.accent : PorchStyle.secondary
            row.accessibilityTraits = on ? [.button, .selected] : .button
        }
    }
    @objc private func saveChoice() {
        guard let admin else { return }
        do {
            try admin.saveSlots { try $0.setContact(nil, for: key); try $0.setAction(choice, for: key) }
            guard let navigation = navigationController else { return }
            if let people = navigation.viewControllers.last(where: { $0 is PeopleSettingsViewController }) { navigation.popToViewController(people, animated: true) }
            else { navigation.popToRootViewController(animated: true) }
        } catch { admin.showError(error) }
    }
}
