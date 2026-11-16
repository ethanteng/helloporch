import UIKit
import GameController
import PorchCore

/// Settings for the bedside device itself: the desk phone as its keypad, and what the device is used as.
final class DeviceSettingsViewController: CaregiverFormViewController {
    private let receiverSwitch = UISwitch()
    private let phoneKeypad: Cell2JackKeypad
    /// A Cell2Jack plugged straight in can work: a build with the driver, on an iPad that may have an M chip.
    private let driver: Bool
    /// The iPad is known to have an M chip, so Connect the phone says it doesn't need the adapter.
    private let mChip: Bool
    /// A keyboard is attached, which may be the phone adapter (`Cell2JackKeypad.deskPhone`).
    private let keyboardConnected: () -> Bool
    private var phoneGroup: UIView?
    /// What the phone group shows, so it's rebuilt only when that changes: the driver retries every few seconds while
    /// the Cell2Jack is unplugged.
    private var shownPhone: DeskPhone?

    init(phoneKeypad: Cell2JackKeypad = .shared, driver: Bool = Cell2JackKeypad.supportsDriverPlatform,
         mChip: Bool = IPadChip.hasMChip(model: PorchDevice.model),
         keyboardConnected: @escaping () -> Bool = { GCKeyboard.coalesced != nil }) {
        self.phoneKeypad = phoneKeypad; self.driver = driver; self.mChip = mChip; self.keyboardConnected = keyboardConnected
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(phoneKeypad:driver:mChip:keyboardConnected:)") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = CaregiverPage.device.title(onBedside: true)
        hideKeyboardControl()
        // Every family has the Porch phone adapter, which needs no driver: every build, any iPad. With the driver, an
        // iPad that may have an M chip also takes a Cell2Jack plugged straight in. Hanging up with the receiver applies
        // to both.
        receiverSwitch.isOn = phoneKeypad.receiverHangUp
        receiverSwitch.accessibilityIdentifier = "device.cell2jackReceiverHangUp"
        receiverSwitch.addTarget(self, action: #selector(changeReceiverHangUp), for: .valueChanged)
        showPhone()
        let device = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        form.addArrangedSubview(group(rows: [actionRow("Use this \(device) as a family device", symbol: "iphone") { [weak self] in self?.confirmFamilyDevice(device) }]))
        form.addArrangedSubview(textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } })
        for name in [Notification.Name.cell2JackKeypadChanged, .GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            NotificationCenter.default.addObserver(self, selector: #selector(phoneChanged), name: name, object: nil)
        }
    }
    @objc private func phoneChanged() { showPhone() }
    /// The phone group. Once the phone is set up here, a row at the top says whether it's connected now. Connected, the
    /// way in is Check the phone, which opens the check already done: it's still the one place to press a key without
    /// calling anyone. Otherwise it's Connect the phone, the same steps as setup, with a test of a key and hanging up.
    /// With the driver that connects to the driver right away, and turns the phone keypad on once a Cell2Jack there
    /// answers. That's the only way it turns on, so there's no switch for it here. Checking the phone through the
    /// adapter there, with nothing on the driver, turns it back off. Opening it is also how to retry the connection.
    private func showPhone() {
        let phone = phoneKeypad.deskPhone(driver: driver, keyboardConnected: keyboardConnected())
        guard phone != shownPhone else { return }
        shownPhone = phone
        let connected = phone == .connected
        let action = actionRow(connected ? "Check the phone" : "Connect the phone",
                               symbol: connected ? "circle.grid.3x3.fill" : "phone.connection") { [weak self] in
            self?.connectPhone(checking: connected)
        }
        action.accessibilityIdentifier = "device.connectPhone"
        var rows = [action, toggleRow("Hang up when the receiver is put back", receiverSwitch)]
        if phone != .notSetUp { rows.insert(statusRow(connected: connected), at: 0) }
        if driver {
            // The USB driver's own switch is in Settings → Porch.
            rows.append(actionRow("Open app settings", symbol: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            })
        }
        let group = group("Connect the physical phone", detail: SetupPhoneViewController.parts, rows: rows)
        if let old = phoneGroup, let index = form.arrangedSubviews.firstIndex(of: old) {
            old.removeFromSuperview(); form.insertArrangedSubview(group, at: index)
        } else {
            form.addArrangedSubview(group)
        }
        phoneGroup = group
    }
    /// Whether the phone is connected now: a filled check, or the amber of a message that's waiting with an exclamation mark.
    private func statusRow(connected: Bool) -> UIView {
        let badge = UIView()
        badge.backgroundColor = connected ? PorchStyle.go : UIColor(red: 0.98, green: 0.74, blue: 0.24, alpha: 0.26)
        badge.layer.cornerRadius = 14
        let icon = UIImageView(image: UIImage(systemName: connected ? "checkmark" : "exclamationmark",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))
        icon.tintColor = connected ? .white : UIColor(red: 0.52, green: 0.32, blue: 0, alpha: 1)
        for view in [badge, icon] { view.translatesAutoresizingMaskIntoConstraints = false }
        badge.addSubview(icon)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 28), badge.heightAnchor.constraint(equalToConstant: 28),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor), icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        let text = connected ? "The phone is connected" : "The phone isn't connected"
        let row = listRow([badge, PorchStyle.label(text, size: 18, color: PorchStyle.ink, weight: .semibold)])
        row.isAccessibilityElement = true; row.accessibilityLabel = text
        row.accessibilityIdentifier = "device.phoneStatus"
        return row
    }
    private func connectPhone(checking: Bool) {
        let screen = SetupPhoneViewController(BedsideSetup(), keypad: phoneKeypad, tryDriver: driver, mChip: mChip,
                                              keyboardConnected: keyboardConnected, checking: checking)
        let navigation = PorchStyle.navigation(screen)
        screen.onContinue = { [weak navigation] in navigation?.dismiss(animated: true) }
        present(navigation, animated: true)
    }
    private func confirmFamilyDevice(_ device: String) {
        // Family settings only offer bedside mode on an iPad, so an iPhone that leaves it cannot switch back.
        let message = PorchDevice.canBeBedside ? "You can switch back later." : nil
        let alert = UIAlertController(title: "Use this \(device) as a family device?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Use as family device", style: .default) { _ in PorchDevice.experience = .family })
        present(alert, animated: true)
    }
    @objc private func changeReceiverHangUp() { phoneKeypad.setReceiverHangUp(receiverSwitch.isOn) }
}
