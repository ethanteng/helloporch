import UIKit
import GameController

enum PorchStyle {
    static let page = UIColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1)
    static let surface = UIColor.white
    static let ink = UIColor(red: 0.12, green: 0.19, blue: 0.17, alpha: 1)
    static let secondary = UIColor(red: 0.35, green: 0.41, blue: 0.38, alpha: 1)
    static let accent = UIColor(red: 0.16, green: 0.36, blue: 0.29, alpha: 1)
    static let border = UIColor(red: 0.77, green: 0.81, blue: 0.78, alpha: 1)
    static let night = UIColor(red: 0.035, green: 0.055, blue: 0.05, alpha: 1)
    static let nightSurface = UIColor(red: 0.085, green: 0.12, blue: 0.105, alpha: 1)
    static let nightText = UIColor(red: 0.78, green: 0.83, blue: 0.79, alpha: 1)
    static let nightSecondary = UIColor(red: 0.56, green: 0.64, blue: 0.59, alpha: 1)

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }

    static func label(_ text: String, size: CGFloat = 17, color: UIColor = secondary, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font(size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func button(_ title: String, symbol: String? = nil, filled: Bool = true) -> UIButton {
        let button = UIButton(type: .system)
        var config = filled ? UIButton.Configuration.filled() : .plain()
        config.title = title
        if let symbol { config.image = UIImage(systemName: symbol); config.imagePadding = 10 }
        config.baseForegroundColor = filled ? .white : accent
        config.baseBackgroundColor = accent
        config.cornerStyle = .large
        config.contentInsets = .init(top: 15, leading: 20, bottom: 15, trailing: 20)
        button.configuration = config
        button.titleLabel?.font = font(18, weight: .semibold)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return button
    }

    static func navigation(_ root: UIViewController) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        nav.overrideUserInterfaceStyle = .light
        nav.modalPresentationStyle = .fullScreen
        nav.view.tintColor = accent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = page
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: ink, .font: UIFont.systemFont(ofSize: 19, weight: .semibold)]
        appearance.largeTitleTextAttributes = [.foregroundColor: ink]
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
        return nav
    }
}

/// A keyboard that belongs to the form, so a connected USB number pad cannot hide it.
/// Input stays local and uses UITextField's selection, insertion and deletion behavior.
final class CaregiverTouchKeyboard: UIView {
    weak var field: UITextField? { didSet { rebuild() } }
    var onDone: (() -> Void)?
    var onNext: (() -> Void)?
    var onSystemKeyboard: (() -> Void)?
    private let rows = UIStackView()
    private var uppercase = false
    private var symbols = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = PorchStyle.page
        accessibilityIdentifier = "caregiver.touchKeyboard"
        rows.axis = .vertical
        rows.spacing = 7
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    private func rebuild() {
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let field else { return }
        let heading = UIStackView(arrangedSubviews: [PorchStyle.label(field.accessibilityLabel ?? "Touch keyboard", size: 15), UIView()])
        heading.alignment = .center
        let system = UIButton(type: .system)
        system.setTitle("Use iPad keyboard", for: .normal)
        system.tintColor = PorchStyle.accent
        system.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        system.addAction(UIAction { [weak self] _ in self?.onSystemKeyboard?() }, for: .touchUpInside)
        heading.addArrangedSubview(system)
        rows.addArrangedSubview(heading)
        let phone = field.keyboardType == .phonePad || field.keyboardType == .numberPad
        let layouts: [[String]]
        if phone {
            layouts = field.keyboardType == .numberPad ? [["1", "2", "3", "4", "5"], ["6", "7", "8", "9", "0", "⌫"]] : [["1", "2", "3", "4", "5", "6"], ["7", "8", "9", "0", "+", "⌫"]]
        } else if symbols {
            layouts = [Array("@#$%&*()-_+").map(String.init), Array("[]{}<>^~|\\").map(String.init), Array("/:;!?.,='\"`").map(String.init)]
        } else {
            layouts = [Array("1234567890").map(String.init), Array("qwertyuiop").map(String.init), Array("asdfghjkl").map(String.init), Array("zxcvbnm").map(String.init)]
        }
        for values in layouts { addRow(values) }
        addRow(phone ? ["Paste", "Next", "Done"] : [uppercase ? "abc" : "ABC", symbols ? "Letters" : "Symbols", "Space", "⌫", "Paste", "Next", "Done"])
    }

    private func addRow(_ values: [String]) {
        let row = UIStackView()
        row.spacing = 6
        row.distribution = .fillEqually
        for value in values {
            let button = UIButton(type: .system)
            let title = value.count == 1 && uppercase ? value.uppercased() : value
            button.setTitle(title, for: .normal)
            button.setTitleColor(PorchStyle.ink, for: .normal)
            button.backgroundColor = PorchStyle.surface
            button.layer.cornerRadius = 9
            button.titleLabel?.font = .systemFont(ofSize: value.count > 1 ? 15 : 22, weight: .medium)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.75
            button.accessibilityLabel = value == "⌫" ? "Delete character" : title
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.press(value) }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        rows.addArrangedSubview(row)
    }

    private func press(_ key: String) {
        guard let field else { return }
        switch key {
        case "⌫": field.deleteBackward()
        case "Space": field.insertText(" ")
        case "Paste": field.paste(nil)
        case "ABC", "abc": uppercase.toggle(); rebuild()
        case "Symbols", "Letters": symbols.toggle(); rebuild()
        case "Next": onNext?()
        case "Done": onDone?()
        default: field.insertText(uppercase ? key.uppercased() : key)
        }
    }
}

class CaregiverFormViewController: UIViewController, UITextFieldDelegate {
    let form = UIStackView()
    let scroll = UIScrollView()
    private let keyboard = CaregiverTouchKeyboard()
    private let keyboardButton = PorchStyle.button("On-screen keyboard", symbol: "keyboard", filled: false)
    private var fields: [UITextField] = []
    private weak var activeField: UITextField?
    private var useTouchKeyboard = GCKeyboard.coalesced != nil
    private let emptyInput = UIView(frame: .zero)

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = PorchStyle.page
        view.tintColor = PorchStyle.accent
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-touch-keyboard") { useTouchKeyboard = true }
        #endif
        form.axis = .vertical
        form.spacing = 24
        scroll.keyboardDismissMode = .interactive
        keyboard.isHidden = true
        keyboard.onDone = { [weak self] in self?.view.endEditing(true) }
        keyboard.onNext = { [weak self] in self?.nextField() }
        keyboard.onSystemKeyboard = { [weak self] in self?.showSystemKeyboard() }
        keyboardButton.addTarget(self, action: #selector(showTouchKeyboard), for: .touchUpInside)
        let body = UIStackView(arrangedSubviews: [scroll, keyboardButton, keyboard])
        body.axis = .vertical
        body.spacing = 0
        [body, form].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(body)
        scroll.addSubview(form)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            body.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            form.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            form.trailingAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            form.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            form.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            form.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            form.widthAnchor.constraint(lessThanOrEqualToConstant: 760)
        ])
        let width = form.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        width.priority = .defaultHigh; width.isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardConnected), name: .GCKeyboardDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollToField), name: UIResponder.keyboardDidShowNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    func hideKeyboardControl() { keyboardButton.isHidden = true }

    func field(_ field: UITextField, title: String, placeholder: String, helper: String? = nil) -> UIView {
        if !fields.contains(where: { $0 === field }) { fields.append(field) }
        field.delegate = self
        field.accessibilityLabel = title
        field.accessibilityIdentifier = field.accessibilityIdentifier ?? title
        field.textColor = PorchStyle.ink
        field.tintColor = PorchStyle.accent
        field.backgroundColor = PorchStyle.surface
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: PorchStyle.secondary])
        field.borderStyle = .none
        field.layer.cornerRadius = 12
        field.layer.borderWidth = 1
        field.layer.borderColor = PorchStyle.border.cgColor
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 48))
        field.leftView = padding
        field.leftViewMode = .always
        field.rightView = UIView(frame: padding.frame)
        field.rightViewMode = .always
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        field.returnKeyType = .next
        field.inputView = useTouchKeyboard ? emptyInput : nil
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        let stack = UIStackView(arrangedSubviews: [PorchStyle.label(title, size: 16, color: PorchStyle.ink, weight: .semibold), field])
        stack.axis = .vertical
        stack.spacing = 8
        if let helper { stack.addArrangedSubview(PorchStyle.label(helper, size: 15)) }
        return stack
    }

    func section(_ title: String, detail: String? = nil, views: [UIView]) -> UIView {
        let heading = PorchStyle.label(title, size: 22, color: PorchStyle.ink, weight: .semibold)
        let stack = UIStackView(arrangedSubviews: [heading] + (detail.map { [PorchStyle.label($0)] } ?? []) + views)
        stack.axis = .vertical
        stack.spacing = 18
        let card = UIView()
        card.backgroundColor = PorchStyle.surface
        card.layer.cornerRadius = 20
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])
        return card
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeField = textField
        textField.layer.borderColor = PorchStyle.accent.cgColor
        textField.layer.borderWidth = 2
        keyboard.field = textField
        keyboard.isHidden = !useTouchKeyboard
        keyboardButton.isHidden = useTouchKeyboard
        view.layoutIfNeeded()
        scrollToField()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.layer.borderColor = PorchStyle.border.cgColor
        textField.layer.borderWidth = 1
        if activeField === textField {
            activeField = nil
            keyboard.isHidden = true
            keyboardButton.isHidden = false
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { nextField(); return false }

    @objc private func showTouchKeyboard() {
        useTouchKeyboard = true
        fields.forEach { $0.inputView = emptyInput }
        if let activeField {
            activeField.reloadInputViews()
            textFieldDidBeginEditing(activeField)
        } else { fields.first(where: isVisible)?.becomeFirstResponder() }
    }

    @objc private func keyboardConnected() {
        if activeField != nil { showTouchKeyboard() }
        else { useTouchKeyboard = true; fields.forEach { $0.inputView = emptyInput } }
    }

    private func showSystemKeyboard() {
        useTouchKeyboard = false
        fields.forEach { $0.inputView = nil }
        keyboard.isHidden = true
        keyboardButton.isHidden = false
        activeField?.reloadInputViews()
        scrollToField()
    }

    private func isVisible(_ field: UITextField) -> Bool {
        var view: UIView? = field
        while let current = view {
            if current.isHidden { return false }
            view = current.superview
        }
        return true
    }

    private func nextField() {
        let visible = fields.filter(isVisible)
        guard let activeField, let index = visible.firstIndex(of: activeField), index + 1 < visible.count else {
            view.endEditing(true); return
        }
        visible[index + 1].becomeFirstResponder()
    }

    @objc private func scrollToField() {
        guard let activeField else { return }
        scroll.scrollRectToVisible(activeField.convert(activeField.bounds, to: scroll).insetBy(dx: 0, dy: -20), animated: true)
    }
}
