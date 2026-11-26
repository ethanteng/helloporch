import UIKit
import PorchCore

/// The honey of something waiting on a caregiver, which isn't an alarm: the bedside's phone isn't connected.
enum PhoneOutStyle {
    static let tint = PorchStyle.rgb(0xFAEBC9)
    static let icon = PorchStyle.rgb(0x8A5300)
    static let title = PorchStyle.rgb(0x6B4200)
    static let meta = PorchStyle.rgb(0x6B4F2A)
    static let dot = PorchStyle.rgb(0xC98A1B)
    static let goTint = PorchStyle.rgb(0xDCEFE3)
    static let goText = PorchStyle.rgb(0x1E5A3C)

    /// The banner on the bedside's card, which dims while it's pressed.
    final class Banner: UIControl {
        override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.7 : 1 } }
    }

    /// A phone with a line through it. SF Symbols has none before iOS 17, so it's drawn from phone.fill.
    static func phoneOff(pointSize: CGFloat = 17) -> UIImage? {
        guard let phone = UIImage(systemName: "phone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) else { return nil }
        let inset: CGFloat = 2, size = CGSize(width: phone.size.width + inset * 2, height: phone.size.height + inset * 2)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            phone.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: inset, y: inset))
            let line = context.cgContext
            line.setLineCap(.round)
            // Across the handset, with a gap either side so it reads over the phone.
            let from = CGPoint(x: size.width - 1.5, y: 1.5), to = CGPoint(x: 1.5, y: size.height - 1.5)
            line.move(to: from); line.addLine(to: to)
            line.setBlendMode(.clear); line.setLineWidth(5.5); line.strokePath()
            line.move(to: from); line.addLine(to: to)
            line.setBlendMode(.normal); line.setStrokeColor(UIColor.black.cgColor); line.setLineWidth(2); line.strokePath()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

/// What to check, from the banner on the bedside's card: whether the phone is connected now, which turns green once it
/// is, the plugs for how it's plugged in, the setup guide, and the steps to send whoever is there.
final class PhoneCheckViewController: CaregiverFormViewController {
    private let credential: FamilyCredential
    private let name: String
    private let device: String
    private let kind: BedsidePhoneKind?
    private let since: TimeInterval
    private let status = UIStackView()
    private let statusDot = UIView()
    private let statusText = PorchStyle.label("", size: 16, weight: .bold)
    private var guide: URL { device == "iPad" ? iPadGuideURL : URL(string: "https://helloporch.store/pilot/android#phone")! }

    init(credential: FamilyCredential, name: String, device: String, phone: BedsidePhone) {
        self.credential = credential; self.name = name; self.device = device
        self.kind = phone.phoneKind; self.since = phone.since
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(credential:name:device:phone:)") }

    /// As a sheet over the Call tab, with Done.
    static func sheet(credential: FamilyCredential, name: String, device: String, phone: BedsidePhone) -> UIViewController {
        let navigation = PorchStyle.navigation(PhoneCheckViewController(credential: credential, name: name, device: device, phone: phone))
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.prefersGrabberVisible = true
            sheet.detents = [.large()]
        }
        return navigation
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        hideKeyboardControl()
        let title = PorchStyle.label("Reconnect \(name)’s phone", size: 27, color: PorchStyle.ink)
        title.font = PorchStyle.titleFont(27)
        title.accessibilityTraits = .header

        statusDot.layer.cornerRadius = 5
        NSLayoutConstraint.activate([statusDot.widthAnchor.constraint(equalToConstant: 10), statusDot.heightAnchor.constraint(equalToConstant: 10)])
        status.addArrangedSubview(statusDot); status.addArrangedSubview(statusText)
        status.spacing = 10; status.alignment = .center
        status.isLayoutMarginsRelativeArrangement = true
        status.directionalLayoutMargins = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
        status.layer.cornerRadius = 12
        status.isAccessibilityElement = true
        status.accessibilityIdentifier = "phoneCheck.status"

        let lead = PorchStyle.label(PhoneChecks.lead(name: name, device: device), size: 17)
        let steps = UIStackView(arrangedSubviews: PhoneChecks.steps(kind: kind, device: device).enumerated().map { step($0.offset + 1, $0.element) })
        steps.axis = .vertical; steps.spacing = 0

        let guideLink = textLink("Step-by-step instructions") { [weak self] in
            if let url = self?.guide { UIApplication.shared.open(url) }
        }
        guideLink.configuration?.image = UIImage(systemName: "arrow.up.right.square")
        guideLink.configuration?.imagePlacement = .trailing; guideLink.configuration?.imagePadding = 6
        guideLink.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)

        let share = PorchStyle.button("Share these steps", symbol: "square.and.arrow.up")
        share.accessibilityIdentifier = "phoneCheck.share"
        share.addAction(UIAction { [weak self, weak share] _ in self?.share(from: share) }, for: .touchUpInside)

        for view in [title, status, lead, steps, guideLink, share] as [UIView] { form.addArrangedSubview(view) }
        form.setCustomSpacing(18, after: status)
        form.setCustomSpacing(4, after: lead)
        form.setCustomSpacing(4, after: steps)
        NotificationCenter.default.addObserver(self, selector: #selector(showStatus), name: .porchFamilyChanged, object: nil)
        showStatus()
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func step(_ number: Int, _ text: String) -> UIView {
        let badge = PorchStyle.label("\(number)", size: 15, color: PorchStyle.wordmark, weight: .bold)
        badge.textAlignment = .center
        badge.backgroundColor = PorchStyle.honey
        badge.layer.cornerRadius = 15; badge.clipsToBounds = true
        NSLayoutConstraint.activate([badge.widthAnchor.constraint(equalToConstant: 30), badge.heightAnchor.constraint(equalToConstant: 30)])
        badge.isAccessibilityElement = false
        let label = PorchStyle.label(text, size: 17, color: PorchStyle.ink)
        let row = UIStackView(arrangedSubviews: [badge, label])
        row.spacing = 14; row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 10, leading: 0, bottom: 10, trailing: 0)
        row.isAccessibilityElement = true; row.accessibilityLabel = "\(number). \(text)"
        return row
    }

    /// Live: once the bedside reports the phone back, it says Connected.
    @objc private func showStatus() {
        let out = FamilyCoordinator.shared.state(for: credential)?.bedsidePhone != nil
        let text = out ? "Not connected · since \(DropInSettingsViewController.time(since))" : "Connected"
        statusText.text = text
        statusText.textColor = out ? PhoneOutStyle.title : PhoneOutStyle.goText
        statusDot.backgroundColor = out ? PhoneOutStyle.dot : PorchStyle.go
        status.backgroundColor = out ? PhoneOutStyle.tint : PhoneOutStyle.goTint
        status.accessibilityLabel = text
    }

    private func share(from button: UIButton?) {
        let text = PhoneChecks.shareText(name: name, device: device, kind: kind, guide: guide)
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = button ?? view
        present(activity, animated: true)
    }
}
