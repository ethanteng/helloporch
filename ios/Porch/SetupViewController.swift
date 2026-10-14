import UIKit
import ContactsUI
import PorchCore

final class SetupViewController: UIViewController, CNContactPickerDelegate {
    var onSave: ((CallContact) -> Void)?
    private let nameField = UITextField()
    private let addressField = UITextField()
    private let initialContact: CallContact?

    init(contact: CallContact?) {
        initialContact = contact
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(contact:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Contact for key 1"
        view.backgroundColor = PorchStyle.cream
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))

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

        for field in [nameField, addressField] {
            field.borderStyle = .roundedRect
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }

        let choose = UIButton(type: .system)
        choose.setTitle("Choose from Contacts", for: .normal)
        choose.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        choose.addTarget(self, action: #selector(pickContact), for: .touchUpInside)
        choose.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        let explanation = UILabel()
        explanation.text = "Choose the email or phone number this person uses for FaceTime. Their name and chosen address are saved on this iPad.\n\nAfter saving, return to Porch and press 1 to test.\n\nHolding the setup button prevents accidental edits; it isn't a password lock."
        explanation.numberOfLines = 0
        explanation.font = .preferredFont(forTextStyle: .body)
        explanation.adjustsFontForContentSizeCategory = true
        explanation.textColor = PorchStyle.ink

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .onDrag
        let stack = UIStackView(arrangedSubviews: [choose, nameField, addressField, explanation])
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
            let contact = try CallContact(name: nameField.text ?? "", address: addressField.text ?? "")
            onSave?(contact)
            dismiss(animated: true)
        } catch {
            let alert = UIAlertController(title: "Check the contact", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    @objc private func cancel() { dismiss(animated: true) }
}
