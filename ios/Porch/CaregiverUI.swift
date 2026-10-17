import UIKit
import GameController
import PorchCore
import ImageIO

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

    static func centeredTextAttributes(_ attributes: AttributeContainer) -> AttributeContainer {
        var attributes = attributes
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributes.paragraphStyle = paragraph
        return attributes
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
        config.titleAlignment = .center
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { centeredTextAttributes($0) }
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { centeredTextAttributes($0) }
        if let symbol { config.image = UIImage(systemName: symbol); config.imagePadding = 10 }
        config.baseForegroundColor = filled ? .white : accent
        config.baseBackgroundColor = accent
        config.cornerStyle = .large
        config.contentInsets = .init(top: 15, leading: 20, bottom: 15, trailing: 20)
        button.configuration = config
        button.titleLabel?.font = font(18, weight: .semibold)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
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
    var hardwareKeyboardConnected = false
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
        system.setTitle(hardwareKeyboardConnected ? "Keyboard help" : (UIDevice.current.userInterfaceIdiom == .phone ? "Use iPhone keyboard" : "Use iPad keyboard"), for: .normal)
        system.accessibilityIdentifier = "caregiver.touchKeyboard.useNative"
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
    private let keyboardButton = PorchStyle.button("Porch keyboard", symbol: "square.grid.3x3", filled: false)
    private let nativeKeyboardButton = PorchStyle.button(UIDevice.current.userInterfaceIdiom == .phone ? "iPhone keyboard" : "iPad keyboard", symbol: "keyboard", filled: false)
    private let keyboardFooter = UIStackView()
    private let hardwareHint = PorchStyle.label("Your keypad can hide the iPad keyboard. Disconnect it during setup to use the iPad keyboard, or choose Porch keyboard to keep the keypad connected.", size: 15)
    private var keyboardControlsEnabled = true
    private var hardwareKeyboardConnected = GCKeyboard.coalesced != nil
    private var fields: [UITextField] = []
    private weak var activeField: UITextField?
    // Native input is always the default, even with a USB/Bluetooth keypad.
    // An empty input view is allowed only after choosing Porch keyboard.
    private var useTouchKeyboard = false
    private let emptyInput = UIView(frame: .zero)

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = PorchStyle.page
        view.tintColor = PorchStyle.accent
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-touch-keyboard") { useTouchKeyboard = true }
        if ProcessInfo.processInfo.arguments.contains("--preview-hardware-keyboard") { hardwareKeyboardConnected = true }
        #endif
        form.axis = .vertical
        form.spacing = 24
        scroll.keyboardDismissMode = .interactive
        keyboard.isHidden = true
        keyboard.onDone = { [weak self] in self?.view.endEditing(true) }
        keyboard.onNext = { [weak self] in self?.nextField() }
        keyboard.onSystemKeyboard = { [weak self] in self?.requestSystemKeyboard() }
        keyboardButton.addTarget(self, action: #selector(showTouchKeyboard), for: .touchUpInside)
        nativeKeyboardButton.addTarget(self, action: #selector(requestSystemKeyboard), for: .touchUpInside)
        keyboardButton.accessibilityIdentifier = "caregiver.porchKeyboard"
        nativeKeyboardButton.accessibilityIdentifier = "caregiver.nativeKeyboard"
        for button in [nativeKeyboardButton, keyboardButton] {
            button.configuration?.contentInsets = .init(top: 12, leading: 10, bottom: 12, trailing: 10)
            button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16)
            button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(15, weight: .medium); return attributes
            }
        }
        let options = UIStackView(arrangedSubviews: [nativeKeyboardButton, keyboardButton])
        options.distribution = .fillEqually
        keyboardFooter.axis = .vertical; keyboardFooter.spacing = 4
        keyboardFooter.isLayoutMarginsRelativeArrangement = true
        keyboardFooter.directionalLayoutMargins = .init(top: 0, leading: 16, bottom: 8, trailing: 16)
        keyboardFooter.accessibilityIdentifier = "caregiver.keyboardOptions"
        hardwareHint.textAlignment = .center; hardwareHint.isHidden = true
        keyboardFooter.addArrangedSubview(options); keyboardFooter.addArrangedSubview(hardwareHint)
        let body = UIStackView(arrangedSubviews: [scroll, keyboardFooter, keyboard])
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
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDisconnected), name: .GCKeyboardDidDisconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollToField), name: UIResponder.keyboardDidShowNotification, object: nil)
        updateKeyboardUI()
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    #if DEBUG
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if ProcessInfo.processInfo.arguments.contains("--preview-keyboard-help") {
            DispatchQueue.main.async { [weak self] in self?.requestSystemKeyboard() }
        }
    }
    #endif

    func hideKeyboardControl() { setKeyboardControlVisible(false) }
    func setKeyboardControlVisible(_ visible: Bool) { keyboardControlsEnabled = visible; updateKeyboardUI() }

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
        // Preserve the native assistant bar rather than stripping its controls.
        field.inputAssistantItem.allowsHidingShortcuts = false
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
        heading.textAlignment = .center
        let detailLabel = detail.map { PorchStyle.label($0) }
        detailLabel?.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [heading] + (detailLabel.map { [$0] } ?? []) + views)
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
        updateKeyboardUI()
        view.layoutIfNeeded()
        scrollToField()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.layer.borderColor = PorchStyle.border.cgColor
        textField.layer.borderWidth = 1
        if activeField === textField {
            activeField = nil
            updateKeyboardUI()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { nextField(); return false }

    private func updateKeyboardUI() {
        let customVisible = keyboardControlsEnabled && useTouchKeyboard && activeField != nil
        keyboard.isHidden = !customVisible
        keyboard.hardwareKeyboardConnected = hardwareKeyboardConnected
        keyboard.field = customVisible ? activeField : nil
        nativeKeyboardButton.configuration?.title = hardwareKeyboardConnected ? "Keyboard help" : (UIDevice.current.userInterfaceIdiom == .phone ? "iPhone keyboard" : "iPad keyboard")
        keyboardFooter.isHidden = !keyboardControlsEnabled || customVisible
        hardwareHint.isHidden = !hardwareKeyboardConnected || useTouchKeyboard || activeField == nil || UIDevice.current.userInterfaceIdiom != .pad
    }

    @objc private func showTouchKeyboard() {
        guard keyboardControlsEnabled, let target = activeField ?? fields.first(where: isVisible) else { return }
        useTouchKeyboard = true
        fields.forEach { $0.inputView = emptyInput }
        if target.isFirstResponder { target.reloadInputViews(); updateKeyboardUI() }
        else { target.becomeFirstResponder() }
        view.layoutIfNeeded(); scrollToField()
    }

    @objc private func keyboardConnected() {
        // A keypad must never change the caregiver's chosen input method.
        hardwareKeyboardConnected = true; updateKeyboardUI()
    }
    @objc private func keyboardDisconnected() { hardwareKeyboardConnected = false; updateKeyboardUI() }

    @objc private func requestSystemKeyboard() {
        guard keyboardControlsEnabled else { return }
        guard hardwareKeyboardConnected else { showSystemKeyboard(); return }
        guard presentedViewController == nil else { return }
        let target = activeField ?? fields.first(where: isVisible)
        let device = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        let operatingSystem = UIDevice.current.userInterfaceIdiom == .phone ? "iOS" : "iPadOS"
        let help = UIAlertController(title: "\(device) keyboard with a keypad", message: "\(operatingSystem) can hide the native keyboard while a physical keypad is connected. If there is no system keyboard control, disconnect the keypad during setup. Porch cannot force the native keyboard open.\n\nTo type while keeping the keypad connected, use Porch keyboard.\n\nIf Guided Access is on, pause it and enable Software Keyboards in Session Settings (or Options).", preferredStyle: .alert)
        help.view.accessibilityIdentifier = "caregiver.keyboardHelp"
        for (title, mode) in [("Use Porch keyboard", true), ("Try \(device) keyboard", false)] {
            help.addAction(UIAlertAction(title: title, style: .default) { [weak self, weak target, weak help] _ in
                let restore = { [weak self, weak target] in
                    guard let self else { return }
                    self.activeField = target
                    if mode { self.showTouchKeyboard() } else { self.showSystemKeyboard() }
                }
                if let help { help.dismiss(animated: false, completion: restore) }
                else { restore() }
            })
        }
        help.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak target, weak help] _ in
            let restore = { [weak target] in _ = target?.becomeFirstResponder() }
            if let help { help.dismiss(animated: false, completion: restore) }
            else { restore() }
        })
        present(help, animated: true)
    }

    @objc private func showSystemKeyboard() {
        guard keyboardControlsEnabled else { return }
        useTouchKeyboard = false
        fields.forEach { $0.inputView = nil }
        updateKeyboardUI()
        if let target = activeField ?? fields.first(where: isVisible) {
            if target.isFirstResponder { target.reloadInputViews() }
            else { target.becomeFirstResponder() }
        }
        view.layoutIfNeeded(); scrollToField()
    }

    private func isVisible(_ field: UITextField) -> Bool {
        guard field.isEnabled, field.isUserInteractionEnabled else { return false }
        var candidate: UIView? = field
        while let current = candidate {
            if current.isHidden || current.alpha == 0 { return false }
            if current === view { return true }
            candidate = current.superview
        }
        return false
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

/// Shared identity rendering for contact cards, incoming calls and active calls.
enum RecipientAppearance {
    static func color(hex: String?) -> UIColor {
        guard let hex, let value = UInt32(hex, radix: 16), hex.count == 6 else { return PorchStyle.nightSurface }
        return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    static func hex(color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", channel(r), channel(g), channel(b))
    }

    static func foreground(on color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? .black : .white
    }

    static func photo(_ data: Data?) -> UIImage? { data.flatMap { UIImage(data: $0) } }

    static func cardPhoto(_ data: Data?, width: CGFloat) -> UIImage? {
        guard let photo = photo(data) else { return nil }
        let size = CGSize(width: max(1, width), height: max(1, width))
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16).addClip()
            let scale = max(size.width / photo.size.width, size.height / photo.size.height)
            let scaled = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            photo.draw(in: CGRect(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2, width: scaled.width, height: scaled.height))
        }.withRenderingMode(.alwaysOriginal)
    }

    static func photoView(_ data: Data?) -> UIImageView {
        let view = UIImageView(image: photo(data))
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 20
        view.isAccessibilityElement = false // The adjacent name supplies the accessible identity.
        view.accessibilityIdentifier = "recipient.photo"
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    /// Decode a bounded, upright thumbnail instead of loading a full-resolution library image.
    static func preparedPhoto(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768
              ] as CFDictionary),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.82), data.count <= 1_000_000 else { return nil }
        return data
    }
}
