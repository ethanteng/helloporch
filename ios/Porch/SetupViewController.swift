import UIKit
import ContactsUI
import PorchCore

final class SlotsViewController: UITableViewController {
    var onSave: ((CallSlots) throws -> Void)?
    private var slots: CallSlots

    init(slots: CallSlots) {
        self.slots = slots
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("Use init(slots:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your people"
        tableView.backgroundColor = PorchStyle.cream
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        CallSlots.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let number = indexPath.row + 1
        let contact = slots.contact(for: number)
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = "\(number)   \(contact?.name ?? "Add a person")"
        content.secondaryText = contact.map { person in
            person.shortcutName.map { "Shortcut: \($0)" } ?? "FaceTime: \(person.address)"
        } ?? "Not set up"
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityLabel = "Key \(number), \(contact?.name ?? "not set up")"
        cell.accessibilityHint = "Edit this person's calling settings."
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Choose a keypad number to set up or change."
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Each number can use FaceTime or its own shortcut. Unassigned numbers do not call anyone. Removing a person leaves their number empty; other people keep their numbers."
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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

    @objc private func done() { dismiss(animated: true) }
}

final class SetupViewController: UIViewController, CNContactPickerDelegate {
    var onSave: ((CallContact?) throws -> Void)?
    private let nameField = UITextField()
    private let addressField = UITextField()
    private let shortcutField = UITextField()
    private let methodControl = UISegmentedControl(items: ["Shortcut", "FaceTime"])
    private let choose = UIButton(type: .system)
    private let explanation = UILabel()
    private let initialContact: CallContact?
    private let slot: Int

    init(slot: Int, contact: CallContact?) {
        self.slot = slot
        initialContact = contact
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(slot:contact:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Person for key \(slot)"
        view.backgroundColor = PorchStyle.cream
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))

        methodControl.selectedSegmentIndex = initialContact == nil || initialContact?.shortcutName != nil ? 0 : 1
        methodControl.accessibilityLabel = "Calling method"
        methodControl.addTarget(self, action: #selector(updateMethod), for: .valueChanged)

        nameField.placeholder = "Name, such as David"
        nameField.text = initialContact?.name
        nameField.accessibilityLabel = "Contact name"
        addressField.placeholder = "FaceTime email or phone number"
        addressField.text = initialContact?.address
        addressField.accessibilityLabel = "FaceTime email or phone number"
        addressField.keyboardType = .asciiCapable
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.spellCheckingType = .no

        shortcutField.placeholder = "Exact shortcut name, such as Call David"
        shortcutField.text = initialContact?.shortcutName
        shortcutField.accessibilityLabel = "Shortcut name"
        shortcutField.autocapitalizationType = .none
        shortcutField.autocorrectionType = .no
        shortcutField.spellCheckingType = .no

        for field in [nameField, addressField, shortcutField] {
            field.borderStyle = .roundedRect
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            let height = field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
            height.priority = .defaultHigh
            height.isActive = true
        }

        choose.setTitle("Choose from Contacts", for: .normal)
        choose.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        choose.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        let chooseHeight = choose.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        chooseHeight.priority = .defaultHigh
        chooseHeight.isActive = true

        explanation.numberOfLines = 0
        explanation.font = .preferredFont(forTextStyle: .body)
        explanation.adjustsFontForContentSizeCategory = true
        explanation.textColor = PorchStyle.ink

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .onDrag
        let remove = UIButton(type: .system)
        remove.setTitle("Remove person from key \(slot)", for: .normal)
        remove.setTitleColor(.systemRed, for: .normal)
        remove.titleLabel?.font = .preferredFont(forTextStyle: .body)
        remove.titleLabel?.adjustsFontForContentSizeCategory = true
        remove.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        remove.addTarget(self, action: #selector(removePerson), for: .touchUpInside)
        let fields: [UIView] = [methodControl, nameField, shortcutField, choose, addressField, explanation]
        let stack = UIStackView(arrangedSubviews: fields + (initialContact == nil ? [] : [remove]))
        stack.axis = .vertical
        stack.spacing = 20
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        updateMethod()
    }

    @objc private func updateMethod() {
        let useShortcut = methodControl.selectedSegmentIndex == 0
        shortcutField.isHidden = !useShortcut
        addressField.isHidden = useShortcut
        choose.isHidden = useShortcut
        let instructions = useShortcut
            ? "In Apple's Shortcuts app, create a shortcut with a FaceTime action and select the person to call. Use a fixed recipient, without Ask Each Time. Run it once there and allow any requested permissions.\n\nEnter that shortcut's exact name above. The person's name is the label shown in Porch; the shortcut controls whom you call. If you rename or delete it, update Porch too."
            : "Choose the email or phone number this person uses for FaceTime. iPadOS may ask you to confirm the call."
        explanation.text = instructions + "\n\nAfter saving, tap Done to return to Porch and press \(slot) to test. Porch opens another app to call; you may need to reopen Porch afterward.\n\nHolding the setup button prevents accidental edits; it isn't a password lock."
    }

    @objc private func pickContact() {
        view.endEditing(true)
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers' OR key == 'emailAddresses'")
        present(picker, animated: true)
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
        let contact = property.contact
        nameField.text = CNContactFormatter.string(from: contact, style: .fullName)
        if property.key == CNContactPhoneNumbersKey, let phone = property.value as? CNPhoneNumber {
            addressField.text = phone.stringValue
        } else if property.key == CNContactEmailAddressesKey, let email = property.value as? String {
            addressField.text = email
        }
        // Selection only fills the form; it never places a call.
    }

    @objc private func save() {
        do {
            let contact = try CallContact(
                name: nameField.text ?? "",
                address: addressField.text ?? "",
                shortcutName: methodControl.selectedSegmentIndex == 0 ? (shortcutField.text ?? "") : nil
            )
            try onSave?(contact)
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Check the contact", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
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

    @objc private func cancel() { navigationController?.popViewController(animated: true) }
}
