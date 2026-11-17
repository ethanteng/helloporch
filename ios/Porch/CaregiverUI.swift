import UIKit
import CoreText
import GameController
import PorchCore
import ImageIO

/// Porch's look, from the website's design system (app/(site)/globals.css): a cream page, paper cards, ink text and
/// buttons, and deep tomato for the small things. Android's PorchTheme.kt has the same colors.
enum PorchStyle {
    /// The site's page, --bg.
    static let page = rgb(0xF9EFDA)
    /// Cards and grouped rows: the site's --paper.
    static let surface = rgb(0xFEFBF6)
    /// Text: the site's --ink.
    static let ink = rgb(0x2E1D15)
    /// Secondary text: the site's --muted, 8:1 on cards.
    static let secondary = rgb(0x5B493F)
    /// Links, the chosen tab, switches, icons and badges: the site's --tomato-deep. The logo's own tomato is too light
    /// for text; this one is 5:1 on cards and 4.6:1 on the page.
    static let accent = rgb(0xC0401F)
    /// Filled buttons: ink, as the site's own buttons are, so red stays for ending and declining calls.
    static let action = ink
    static let border = rgb(0xDCCDB9)
    /// Highlights, such as a photo's placeholder: the site's --honey.
    static let honey = rgb(0xF2D39F)
    /// Green only where it means go: someone is at the bedside, a keypad is connected.
    static let go = rgb(0x2F7A55)
    /// "Played" on its faint green tag. `go` itself is 3.9:1 over the cream page there, short of 4.5:1 for that
    /// 15-point label, so the words are this darker shade of the same green. Android's PorchBrand.played matches.
    static let played = rgb(0x255F42)
    /// End call and Decline: the site's --help.
    static let danger = rgb(0xC13D34)
    /// The bedside at night and the call screens: warm darks, each as bright as the green-tinted one it replaced, so the
    /// bedside lights the room no more than it did.
    static let night = rgb(0x100C09)
    static let nightSurface = rgb(0x221B16)
    static let nightText = rgb(0xD9CEC1)
    static let nightSecondary = rgb(0xAB9A8A)
    /// The wordmark's brown, --brown-ink, and the logo's tomato.
    static let wordmark = rgb(0x64281A)
    static let tomato = rgb(0xE05D3D)

    static func rgb(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// Text on the family's and caregivers' screens: DM Sans, the website's text font, following the reader's text size.
    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: PorchFonts.sans(size, weight: weight))
    }

    /// Names on the Call tab: Newsreader, the website's headings, following the reader's text size.
    static func titleFont(_ size: CGFloat) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: PorchFonts.serif(size))
    }

    /// Text on Mom's own screens (the bedside clock and its people, its messages, the call screens): the system font
    /// they were sized and tested with.
    static func systemFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
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
        styledLabel(text, font: font(size, weight: weight), color: color)
    }

    /// A label on Mom's own screens, in the system font (systemFont).
    static func systemLabel(_ text: String, size: CGFloat = 17, color: UIColor = secondary, weight: UIFont.Weight = .regular) -> UILabel {
        styledLabel(text, font: systemFont(size, weight: weight), color: color)
    }

    private static func styledLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    /// A button on the family's and caregivers' screens, its title in DM Sans Medium, the website's button weight. A
    /// configured button ignores its title label's font and draws the configuration's, 17-point text, so the
    /// configuration sets this one at that size.
    static func button(_ title: String, symbol: String? = nil, filled: Bool = true) -> UIButton {
        let button = styledButton(title, symbol: symbol, filled: filled, font: font(17, weight: .medium))
        button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = centeredTextAttributes($0)
            attributes.font = font(17, weight: .medium)
            return attributes
        }
        return button
    }

    /// A button on Mom's own screens, as they were sized and tested: the system font.
    static func systemButton(_ title: String, symbol: String? = nil, filled: Bool = true) -> UIButton {
        styledButton(title, symbol: symbol, filled: filled, font: systemFont(18, weight: .semibold))
    }

    private static func styledButton(_ title: String, symbol: String?, filled: Bool, font: UIFont) -> UIButton {
        let button = UIButton(type: .system)
        var config = filled ? UIButton.Configuration.filled() : .plain()
        config.title = title
        config.titleAlignment = .center
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { centeredTextAttributes($0) }
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { centeredTextAttributes($0) }
        if let symbol { config.image = UIImage(systemName: symbol); config.imagePadding = 10 }
        config.baseForegroundColor = filled ? .white : accent
        config.baseBackgroundColor = action
        config.cornerStyle = .large
        config.contentInsets = .init(top: 15, leading: 20, bottom: 15, trailing: 20)
        button.configuration = config
        button.titleLabel?.font = font
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return button
    }

    /// Change photo and Remove photo side by side under a photo, closer than full-size buttons stack.
    static func photoActions(_ buttons: [UIButton]) -> UIStackView {
        for button in buttons { button.configuration?.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12) }
        let row = UIStackView(arrangedSubviews: buttons)
        row.spacing = 8; row.alignment = .center
        return row
    }

    static func segmented(_ items: [String]) -> UISegmentedControl {
        let control = UISegmentedControl(items: items)
        control.selectedSegmentTintColor = accent
        control.backgroundColor = page
        control.setTitleTextAttributes([.foregroundColor: ink, .font: PorchFonts.sans(16, weight: .medium)], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: PorchFonts.sans(16, weight: .semibold)], for: .selected)
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return control
    }

    /// Screen titles in Newsreader, as the website's headings, and the bar's buttons in DM Sans.
    static func navigation(_ root: UIViewController) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        nav.overrideUserInterfaceStyle = .light
        nav.modalPresentationStyle = .fullScreen
        nav.view.tintColor = accent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = page
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: ink, .font: PorchFonts.serif(21)]
        appearance.largeTitleTextAttributes = [.foregroundColor: ink, .font: PorchFonts.serif(34)]
        let buttons = UIBarButtonItemAppearance()
        buttons.normal.titleTextAttributes = [.font: PorchFonts.sans(17, weight: .regular)]
        let done = UIBarButtonItemAppearance()
        done.normal.titleTextAttributes = [.font: PorchFonts.sans(17, weight: .semibold)]
        appearance.buttonAppearance = buttons
        appearance.backButtonAppearance = buttons
        appearance.doneButtonAppearance = done
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
        return nav
    }
}

/// The website's fonts: DM Sans for text, Newsreader for titles, Bricolage Grotesque for the wordmark. They're data sets
/// in the asset catalog (Assets.xcassets/Fonts), which every app target already bundles, and each registers for this
/// process the first time a font is asked for. Their licenses (OFL, ios/FontLicenses) are in Acknowledgements.
enum PorchFonts {
    static let names = ["DMSans-Regular", "DMSans-Medium", "DMSans-SemiBold", "DMSans-Bold",
                        "Newsreader-Medium", "BricolageGrotesque-ExtraBold"]
    /// Whether every font registered. One that's missing falls back to the system font.
    static let registered: Bool = names.allSatisfy { name in
        guard let data = NSDataAsset(name: name)?.data, let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider) else { return false }
        // Registered already, by an earlier test host in this process say, is as good.
        return CTFontManagerRegisterGraphicsFont(font, nil) || UIFont(name: name, size: 12) != nil
    }

    static func named(_ name: String, size: CGFloat) -> UIFont? {
        _ = registered
        return UIFont(name: name, size: size)
    }

    static func sans(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let name = weight.rawValue >= UIFont.Weight.bold.rawValue ? "DMSans-Bold"
            : weight.rawValue >= UIFont.Weight.semibold.rawValue ? "DMSans-SemiBold"
            : weight.rawValue >= UIFont.Weight.medium.rawValue ? "DMSans-Medium" : "DMSans-Regular"
        return named(name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func serif(_ size: CGFloat) -> UIFont {
        named("Newsreader-Medium", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    static func wordmark(_ size: CGFloat) -> UIFont {
        named("BricolageGrotesque-ExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    }
}

/// The HelloPorch logo as the website draws it (components/PorchLogo.tsx): the smiling "p" in tomato beside "Porch" in
/// the wordmark's brown. The Call tab's title; VoiceOver reads it as the "Porch" heading it replaces.
final class PorchWordmark: UIView {
    private let mark = CAShapeLayer()
    private let text = UILabel()
    private let markSize: CGSize
    private let gap: CGFloat

    init(size: CGFloat = 24) {
        // The mark is 1.05em tall and its viewBox 82 by 88, with 0.2em between it and the word.
        markSize = CGSize(width: size * 1.05 * 82 / 88, height: size * 1.05)
        gap = size * 0.2
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = "Porch"
        accessibilityTraits = .header
        accessibilityIdentifier = "porch.wordmark"
        text.attributedText = NSAttributedString(string: "Porch", attributes: [
            .font: PorchFonts.wordmark(size), .foregroundColor: PorchStyle.wordmark, .kern: -0.045 * size])
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        let height = markSize.height, width = markSize.width, scale = height / 88
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 20, y: 44)); path.addLine(to: CGPoint(x: 20, y: 91))
        path.append(UIBezierPath(arcCenter: CGPoint(x: 52, y: 44), radius: 32, startAngle: 0, endAngle: 2 * .pi, clockwise: true))
        path.move(to: CGPoint(x: 36, y: 42)); path.addQuadCurve(to: CGPoint(x: 68, y: 42), controlPoint: CGPoint(x: 52, y: 60))
        path.apply(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -11, y: -7.5))
        mark.path = path.cgPath
        mark.fillColor = nil
        mark.strokeColor = PorchStyle.tomato.cgColor
        mark.lineWidth = 9 * scale
        mark.lineCap = .round
        let markView = UIView()
        markView.layer.addSublayer(mark)
        markView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(markView)
        NSLayoutConstraint.activate([
            markView.leadingAnchor.constraint(equalTo: leadingAnchor),
            markView.widthAnchor.constraint(equalToConstant: width),
            markView.heightAnchor.constraint(equalToConstant: height),
            markView.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: markView.trailingAnchor, constant: gap),
            text.trailingAnchor.constraint(equalTo: trailingAnchor),
            text.topAnchor.constraint(equalTo: topAnchor),
            text.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("Use init(size:)") }
    /// A navigation bar sizes its title view by this.
    override var intrinsicContentSize: CGSize {
        let word = text.intrinsicContentSize
        return CGSize(width: markSize.width + gap + word.width, height: max(markSize.height, word.height))
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
        case "Space": insert(" ", into: field)
        case "Paste": field.paste(nil)
        case "ABC", "abc": uppercase.toggle(); rebuild()
        case "Symbols", "Letters": symbols.toggle(); rebuild()
        case "Next": onNext?()
        case "Done": onDone?()
        default: insert(uppercase ? key.uppercased() : key, into: field)
        }
    }
    private func insert(_ text: String, into field: UITextField) {
        // Secure UITextField insertion can clear its contents after a help
        // alert restores focus. The touch keyboard should edit the caret or
        // selection the caregiver kept, rather than start a new PIN.
        if field.isSecureTextEntry, let range = field.selectedTextRange {
            field.replace(range, withText: text)
            field.sendActions(for: .editingChanged)
        } else { field.insertText(text) }
    }
}

/// A tappable row for a `group` card: highlights while pressed and reads as one button to VoiceOver.
final class PorchListRow: UIControl {
    init(_ views: [UIView], label: String, chevron: Bool = true, action: @escaping () -> Void) {
        super.init(frame: .zero)
        var arranged = views
        if chevron {
            let image = UIImageView(image: UIImage(systemName: "chevron.right"))
            image.tintColor = PorchStyle.secondary
            image.setContentHuggingPriority(.required, for: .horizontal)
            image.setContentCompressionResistancePriority(.required, for: .horizontal)
            arranged.append(image)
        }
        let stack = UIStackView(arrangedSubviews: arranged)
        stack.alignment = .center
        stack.spacing = 12
        stack.isUserInteractionEnabled = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityTraits = .button
        addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:label:chevron:action:)") }
    /// The page showing beside a list, such as the caregiver sidebar on an iPad.
    var isCurrent = false { didSet { update() } }
    override var isHighlighted: Bool { didSet { update() } }
    override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.5; update() } }
    private func update() {
        backgroundColor = isHighlighted ? PorchStyle.page : isCurrent ? PorchStyle.accent.withAlphaComponent(0.12) : nil
        var traits: UIAccessibilityTraits = .button
        if !isEnabled { traits.insert(.notEnabled) }
        if isCurrent { traits.insert(.selected) }
        accessibilityTraits = traits
    }
}

class CaregiverFormViewController: UIViewController, UITextFieldDelegate {
    let form = UIStackView()
    let scroll = UIScrollView()
    private let keyboard = CaregiverTouchKeyboard()
    private let keyboardButton = PorchStyle.button("Porch keyboard", symbol: "square.grid.3x3", filled: false)
    private let nativeKeyboardButton = PorchStyle.button(UIDevice.current.userInterfaceIdiom == .phone ? "iPhone keyboard" : "iPad keyboard", symbol: "keyboard", filled: false)
    private let keyboardFooter = UIStackView()
    private let hardwareHint = PorchStyle.label("A connected keypad can hide the iPad keyboard. Unplug it while typing, or use Porch keyboard.", size: 15)
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
        let args = ProcessInfo.processInfo.arguments
        // A keyboard preview opens on the form's first field, such as the name on someone's page.
        if args.contains("--preview-touch-keyboard") || args.contains("--preview-system-keyboard"), activeField == nil, let field = fields.first(where: isVisible) {
            field.becomeFirstResponder()
        }
        if args.contains("--preview-keyboard-help") {
            DispatchQueue.main.async { [weak self] in self?.requestSystemKeyboard() }
        }
    }
    #endif

    func hideKeyboardControl() { setKeyboardControlVisible(false) }
    func setKeyboardControlVisible(_ visible: Bool) { keyboardControlsEnabled = visible; updateKeyboardUI() }

    func field(_ field: UITextField, title: String, placeholder: String, helper: String? = nil) -> UIView {
        // Pages that redraw pass the same field again, which keeps the one height constraint it got the first time.
        if !fields.contains(where: { $0 === field }) { fields.append(field); field.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true }
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
        field.font = PorchStyle.font(17)
        field.adjustsFontForContentSizeCategory = true
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

    /// A heading, and what it's about when that isn't plain, over the rows or views it introduces.
    func heading(_ title: String?, detail: String? = nil) -> [UIView] {
        var views: [UIView] = []
        if let title {
            let heading = PorchStyle.label(title, size: 20, color: PorchStyle.ink, weight: .semibold)
            heading.accessibilityTraits = .header
            views.append(heading)
        }
        if let detail { views.append(PorchStyle.label(detail, size: 15)) }
        return views
    }

    /// One card of compact rows, under an optional heading, for settings that belong together.
    func group(_ title: String? = nil, detail: String? = nil, rows: [UIView]) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.backgroundColor = PorchStyle.surface
        card.layer.cornerRadius = 20
        card.clipsToBounds = true
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = UIView(); line.backgroundColor = PorchStyle.border
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                card.addArrangedSubview(line)
            }
            card.addArrangedSubview(row)
        }
        let introduction = heading(title, detail: detail)
        let stack = UIStackView(arrangedSubviews: introduction + [card])
        stack.axis = .vertical
        stack.spacing = 10
        if title != nil, detail != nil, let first = introduction.first { stack.setCustomSpacing(4, after: first) }
        return stack
    }

    /// A row that opens more: its title, what it's set to now, and a chevron.
    /// `valueIsAction` shows the value as what tapping does, such as Add, in the accent color; `valueColor` colors a
    /// value that needs noticing, such as Every call in red.
    func linkRow(_ title: String, value: String? = nil, symbol: String? = nil, valueIsAction: Bool = false, valueColor: UIColor? = nil, action: @escaping () -> Void) -> PorchListRow {
        var views: [UIView] = []
        if let symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = PorchStyle.accent
            icon.contentMode = .scaleAspectFit
            icon.setContentHuggingPriority(.required, for: .horizontal)
            icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
            views.append(icon)
        }
        views.append(PorchStyle.label(title, size: 18, color: PorchStyle.ink))
        if let value {
            let label = PorchStyle.label(value, size: 17, color: valueColor ?? (valueIsAction ? PorchStyle.accent : PorchStyle.secondary), weight: valueIsAction || valueColor != nil ? .semibold : .regular)
            label.numberOfLines = 1
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            views.append(label)
        }
        return PorchListRow(views, label: value.map { "\(title), \($0)" } ?? title, action: action)
    }

    /// A number set with − and +, `value` showing it beside them.
    func stepperRow(_ title: String, value: UILabel, _ stepper: UIStepper) -> UIView {
        stepper.accessibilityLabel = title
        stepper.accessibilityValue = value.text
        stepper.setContentCompressionResistancePriority(.required, for: .horizontal)
        value.font = PorchStyle.font(18, weight: .medium)
        value.textColor = PorchStyle.ink
        value.numberOfLines = 1
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        return listRow([PorchStyle.label(title, size: 18, color: PorchStyle.ink), value, stepper])
    }

    /// A full-width button row in a `group` card, such as Invite someone.
    func actionRow(_ title: String, symbol: String? = nil, destructive: Bool = false, action: (() -> Void)? = nil) -> UIButton {
        let button = PorchStyle.button(title, symbol: symbol, filled: false)
        button.contentHorizontalAlignment = .leading
        button.configuration?.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        if destructive { button.configuration?.baseForegroundColor = .systemRed }
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        if let action { button.addAction(UIAction { _ in action() }, for: .touchUpInside) }
        return button
    }

    /// A plain text link, for things that matter less than the settings above them.
    /// A text link centered on its own line, red for one that removes something.
    func centeredLink(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> UIButton {
        let link = textLink(title, size: 17, action: action)
        link.contentHorizontalAlignment = .center
        if destructive { link.configuration?.baseForegroundColor = .systemRed }
        return link
    }
    /// Views that aren't rows, padded to sit on a white card.
    func padded(_ views: [UIView], spacing: CGFloat = 14) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical; stack.spacing = spacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        return stack
    }
    func textLink(_ title: String, size: CGFloat = 16, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = PorchStyle.accent
        config.contentInsets = .init(top: 10, leading: 4, bottom: 10, trailing: 4)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes; attributes.font = PorchStyle.font(size); return attributes
        }
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    /// After Save: back to where this was opened from or, where it's the first page beside the caregiver
    /// sidebar, a moment of "Saved".
    func finishSave() {
        if let navigation = navigationController, navigation.viewControllers.first !== self {
            navigation.popViewController(animated: true); return
        }
        guard let item = navigationItem.rightBarButtonItem else { return }
        item.title = "Saved"; item.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak item] in item?.title = "Save"; item?.isEnabled = true }
    }

    /// One padded row for a `group` card.
    func listRow(_ views: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        return row
    }

    /// A `group` row whose content takes all the width its trailing control leaves. Plain constraints rather
    /// than a stack, so the control always sits at its natural width against the trailing edge.
    func listRow(_ content: UIView, trailing: UIView, alignedToBottom: Bool = false) -> UIView {
        let row = UIView()
        row.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
        for view in [content, trailing] { view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view) }
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        let margins = row.layoutMarginsGuide
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -12),
            trailing.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            content.topAnchor.constraint(greaterThanOrEqualTo: margins.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor),
            trailing.topAnchor.constraint(greaterThanOrEqualTo: margins.topAnchor),
            trailing.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor),
            content.centerYAnchor.constraint(equalTo: margins.centerYAnchor),
            alignedToBottom ? trailing.bottomAnchor.constraint(equalTo: content.bottomAnchor) : trailing.centerYAnchor.constraint(equalTo: margins.centerYAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
        return row
    }

    func toggleRow(_ title: String, detail: String? = nil, _ toggle: UISwitch) -> UIView {
        toggle.onTintColor = PorchStyle.accent
        toggle.accessibilityLabel = title
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        let text = UIStackView(arrangedSubviews: [PorchStyle.label(title, size: 18, color: PorchStyle.ink)] + (detail.map { [PorchStyle.label($0, size: 15)] } ?? []))
        text.axis = .vertical; text.spacing = 2
        return listRow([text, toggle])
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
        let help = UIAlertController(title: "\(device) keyboard with a keypad", message: "A connected keypad can hide the \(operatingSystem) keyboard. Unplug it while you type, or use Porch keyboard.\n\nIf Guided Access is on, pause it and turn on Software Keyboards in its options.", preferredStyle: .alert)
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

    /// The same preparation for a photo just taken with the camera.
    static func preparedPhoto(_ image: UIImage) -> Data? {
        let scale = min(1, 768 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        // Drawing applies the camera's orientation, so the saved photo is upright.
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = upright.jpegData(compressionQuality: 0.82), data.count <= 1_000_000 else { return nil }
        return data
    }
}
