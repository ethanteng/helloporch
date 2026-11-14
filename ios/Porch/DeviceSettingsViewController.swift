import UIKit
import PorchCore

/// Settings for the bedside device itself: the desk phone as its keypad, and what the device is used as.
final class DeviceSettingsViewController: CaregiverFormViewController {
    private let receiverSwitch = UISwitch()
    private let phoneKeypad: Cell2JackKeypad
    /// A Cell2Jack plugged straight in can work: a build with the driver, on an iPad that may have an M chip.
    private let driver: Bool
    /// The iPad is known to have an M chip, so Connect the phone says it doesn't need the adapter.
    private let mChip: Bool

    init(phoneKeypad: Cell2JackKeypad = .shared, driver: Bool = Cell2JackKeypad.supportsDriverPlatform,
         mChip: Bool = IPadChip.hasMChip(model: PorchDevice.model)) {
        self.phoneKeypad = phoneKeypad; self.driver = driver; self.mChip = mChip
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(phoneKeypad:driver:mChip:)") }

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
        // The same steps as setup, with a test of a key and hanging up. With the driver it listens for the adapter and
        // the driver both, connects to the driver right away, and turns the phone keypad on once a Cell2Jack there
        // answers. That's the only way it turns on, so there's no switch for it here. Checking the phone through the
        // adapter there, with nothing on the driver, turns it back off. Opening it is also how to retry the connection.
        let phone = actionRow("Connect the phone", symbol: "phone.connection") { [weak self] in self?.connectPhone() }
        phone.accessibilityIdentifier = "device.connectPhone"
        var rows = [phone, toggleRow("Hang up when the receiver is put back", receiverSwitch)]
        if driver {
            // The USB driver's own switch is in Settings → Porch.
            rows.append(actionRow("Open app settings", symbol: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            })
        }
        form.addArrangedSubview(group("Connect the physical phone", detail: SetupPhoneViewController.parts, rows: rows))
        let device = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        form.addArrangedSubview(group(rows: [actionRow("Use this \(device) as a family device", symbol: "iphone") { [weak self] in self?.confirmFamilyDevice(device) }]))
        form.addArrangedSubview(textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } })
    }
    private func connectPhone() {
        let screen = SetupPhoneViewController(BedsideSetup(), keypad: phoneKeypad, tryDriver: driver, mChip: mChip)
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
