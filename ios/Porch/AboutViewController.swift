import UIKit
import MessageUI
import PorchCore

/// Porch's version, who made it and how to reach him, and the open-source licenses one tap away. The last page of
/// caregiver mode, and About Porch on a family phone. Android's About (About.kt) has the same screens and words.
final class AboutViewController: CaregiverFormViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CaregiverPage.about.title(onBedside: true)
        hideKeyboardControl()
        let icon = UIImageView(image: UIImage(named: "AboutIcon"))
        icon.layer.cornerRadius = 20; icon.layer.cornerCurve = .continuous; icon.clipsToBounds = true
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 88), icon.heightAnchor.constraint(equalToConstant: 88)])
        let name = PorchStyle.label("Porch", size: 26, color: PorchStyle.ink, weight: .bold)
        name.accessibilityTraits = .header
        let version = PorchStyle.label("Version \(PorchVersion.text)", size: 18, color: PorchStyle.ink, weight: .medium)
        version.accessibilityIdentifier = "about.version"
        let made = PorchStyle.label("Built with ❤️ in Oakland, CA", size: 16)
        for label in [name, version, made] { label.textAlignment = .center }
        let hero = UIStackView(arrangedSubviews: [icon, name, version, made, contactLink()])
        hero.axis = .vertical; hero.alignment = .center; hero.spacing = 4
        hero.setCustomSpacing(14, after: icon); hero.setCustomSpacing(18, after: version); hero.setCustomSpacing(2, after: made)
        hero.isLayoutMarginsRelativeArrangement = true
        hero.directionalLayoutMargins = .init(top: 28, leading: 0, bottom: 0, trailing: 0)
        form.addArrangedSubview(hero)
        let licenses = linkRow("Licenses") { [weak self] in self?.navigationController?.pushViewController(LicensesViewController(), animated: true) }
        licenses.accessibilityIdentifier = "about.licenses"
        form.addArrangedSubview(group(rows: [licenses]))
    }
    /// "Questions or feedback? Contact me.", with the last two words as the link. The whole line opens Contact.
    private func contactLink() -> UIButton {
        var question = AttributedString("Questions or feedback? ")
        question.font = PorchStyle.font(16); question.foregroundColor = PorchStyle.secondary
        var link = AttributedString("Contact me.")
        link.font = PorchStyle.font(16, weight: .semibold); link.foregroundColor = PorchStyle.accent
        var config = UIButton.Configuration.plain()
        config.attributedTitle = question + link
        config.titleAlignment = .center
        config.contentInsets = .init(top: 8, leading: 4, bottom: 8, trailing: 4)
        let button = UIButton(configuration: config)
        button.accessibilityLabel = "Questions or feedback? Contact me."
        button.accessibilityIdentifier = "about.contact"
        button.addAction(UIAction { [weak self] _ in self?.navigationController?.pushViewController(ContactViewController(), animated: true) }, for: .touchUpInside)
        return button
    }
}

extension CaregiverFormViewController {
    /// Privacy policy and About Porch, left-aligned at the bottom of a family device's screens, for anyone, not only a
    /// family's caregivers. Android's PorchLinks (About.kt) matches.
    func porchLinks() -> UIView {
        let privacy = textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } }
        privacy.accessibilityIdentifier = "family.privacy"
        let about = textLink("About Porch", size: 15) { [weak self] in
            self?.navigationController?.pushViewController(AboutViewController(), animated: true)
        }
        about.accessibilityIdentifier = "family.about"
        let links = UIStackView(arrangedSubviews: [privacy, about])
        links.axis = .vertical; links.alignment = .leading
        return links
    }
}

/// How to reach the person who makes Porch. On a family device, the email starts one, and on an iPhone the number calls
/// it. On the bedside they're only shown, since either would take the iPad away from Porch.
final class ContactViewController: CaregiverFormViewController, MFMailComposeViewControllerDelegate {
    static let email = "ethan@helloporch.store"
    static let phone = "+14158676937"
    private let canEmail: Bool
    private let canCall: Bool
    init(onBedside: Bool = PorchDevice.experience == .bedside, onPhone: Bool = UIDevice.current.userInterfaceIdiom == .phone) {
        canEmail = !onBedside; canCall = !onBedside && onPhone
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(onBedside:onPhone:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Contact"
        hideKeyboardControl()
        let email = row(Self.email, symbol: "envelope", label: "Email", action: canEmail ? { [weak self] in self?.writeEmail() } : nil)
        email.accessibilityIdentifier = "contact.email"
        let number = PorchNumber.display(Self.phone)
        let phone = row(number, symbol: "phone", label: "Phone", action: canCall ? { [weak self] in self?.call() } : nil)
        phone.accessibilityIdentifier = "contact.phone"
        form.addArrangedSubview(group(rows: [email, phone]))
    }
    /// A button when it does something, otherwise the same icon and words to read.
    private func row(_ text: String, symbol: String, label: String, action: (() -> Void)?) -> UIView {
        if let action {
            let button = actionRow(text, symbol: symbol, action: action)
            button.accessibilityLabel = "\(label), \(text)"
            return button
        }
        let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = PorchStyle.accent
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let row = listRow([icon, PorchStyle.label(text, size: 17, color: PorchStyle.ink)])
        row.isAccessibilityElement = true; row.accessibilityLabel = "\(label), \(text)"
        return row
    }
    private func writeEmail() {
        // A sheet over Porch, so caregiver mode on a phone stays open. Without Mail set up, the mail app the phone uses.
        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            mail.setToRecipients([Self.email])
            present(mail, animated: true)
        } else if let url = URL(string: "mailto:\(Self.email)") { UIApplication.shared.open(url) }
    }
    private func call() {
        if let url = URL(string: "tel:\(Self.phone)") { UIApplication.shared.open(url) }
    }
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

/// The open-source software in Porch, one row each. A tap shows its license here, never in a browser, which on a family
/// phone would end caregiver mode.
final class LicensesViewController: CaregiverFormViewController {
    private let licenses: [Acknowledgement]
    init(licenses: [Acknowledgement] = Acknowledgement.bundled) {
        self.licenses = licenses
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(licenses:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Licenses"
        hideKeyboardControl()
        let rows = licenses.map { license -> UIView in
            let row = linkRow(license.title) { [weak self] in
                self?.navigationController?.pushViewController(LicenseViewController(license), animated: true)
            }
            row.accessibilityIdentifier = "licenses.row"
            return row
        }
        form.addArrangedSubview(group(rows: rows))
    }
}

/// One license, titled with what it's for.
final class LicenseViewController: CaregiverFormViewController {
    let license: Acknowledgement
    init(_ license: Acknowledgement) {
        self.license = license
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = license.title
        hideKeyboardControl()
        let text = PorchStyle.label(license.reflowed, size: 14, color: PorchStyle.ink)
        text.accessibilityIdentifier = "license.text"
        form.addArrangedSubview(group(rows: [padded([text])]))
    }
}

/// One entry of Settings → Porch → Acknowledgements: what Porch includes, and its license.
struct Acknowledgement: Equatable {
    let title: String
    let text: String
    /// The text with its hard line breaks taken out, so it wraps to the screen. Most licenses are broken at about 80
    /// columns: those lines join up within a paragraph, while a short line, such as a title or a copyright, keeps its own.
    /// Android's About does the same (LicenseText.kt).
    var reflowed: String {
        var paragraphs: [String] = [], current = "", joinNext = false
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { paragraphs.append(current); current = "" }
                continue
            }
            current += current.isEmpty ? line : (joinNext ? " " : "\n") + line
            joinNext = line.count >= 55
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }
    /// The same file the Settings app shows (ios/scripts/generate-acknowledgements.py writes it), so there's one list to
    /// keep up to date. The family build has its own Settings.bundle, at the same place in the app.
    static let bundled = load(Bundle.main.url(forResource: "Acknowledgements", withExtension: "plist", subdirectory: "Settings.bundle"))
    /// Its titled entries, in order. The first, untitled one only introduces the list.
    static func load(_ url: URL?) -> [Acknowledgement] {
        guard let url, let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entries = plist["PreferenceSpecifiers"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let title = entry["Title"] as? String, let text = entry["FooterText"] as? String else { return nil }
            return Acknowledgement(title: title, text: text)
        }
    }
}

/// Porch's version, as App Store Connect and TestFlight show it: "0.1.0 (78)", the build in brackets.
enum PorchVersion {
    static var text: String { text(Bundle.main.infoDictionary) }
    static func text(_ info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}
