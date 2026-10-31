import UIKit
import PorchCore

/// Settings for the bedside device itself: a desk phone as its keypad, and what the device is used as.
final class DeviceSettingsViewController: CaregiverFormViewController {
    private let phoneSwitch = UISwitch()
    private let receiverSwitch = UISwitch()
    private let phoneKeypad: Cell2JackKeypad

    init(phoneKeypad: Cell2JackKeypad = .shared) {
        self.phoneKeypad = phoneKeypad
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(phoneKeypad:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = CaregiverPage.device.title(onBedside: true)
        hideKeyboardControl()
        #if !PORCH_NO_CELL2JACK
        if Cell2JackKeypad.supportsDriverPlatform {
            phoneSwitch.isOn = phoneKeypad.enabled
            phoneSwitch.accessibilityIdentifier = "device.cell2jack"
            phoneSwitch.addTarget(self, action: #selector(changePhoneKeypad), for: .valueChanged)
            receiverSwitch.isOn = phoneKeypad.receiverHangUp
            receiverSwitch.accessibilityIdentifier = "device.cell2jackReceiverHangUp"
            receiverSwitch.addTarget(self, action: #selector(changeReceiverHangUp), for: .valueChanged)
            // The same steps as setup, with a test of the phone. It turns the phone keypad on once the Cell2Jack answers.
            let connect = actionRow("Connect the phone", symbol: "phone.connection") { [weak self] in self?.connectPhone() }
            connect.accessibilityIdentifier = "device.connectPhone"
            let retry = actionRow("Retry phone connection", symbol: "arrow.clockwise") { [weak self] in self?.phoneKeypad.refresh() }
            let settings = actionRow("Open app settings", symbol: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            form.addArrangedSubview(group("Cell2Jack phone keypad", detail: "Needs an iPad with an M chip and the USB driver on in Settings → Porch.",
                rows: [connect, toggleRow("Use Cell2Jack phone keypad", phoneSwitch), toggleRow("Hang up when the receiver is put back", receiverSwitch), retry, settings]))
        } else {
            let unsupported = UIStackView(arrangedSubviews: heading("Cell2Jack phone keypad", detail: "Needs an iPad with an M chip."))
            unsupported.axis = .vertical; unsupported.spacing = 4
            form.addArrangedSubview(unsupported)
        }
        #endif
        let device = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        form.addArrangedSubview(group(rows: [actionRow("Use this \(device) as a family device", symbol: "iphone") { [weak self] in self?.confirmFamilyDevice(device) }]))
        form.addArrangedSubview(textLink("Privacy policy", size: 15) { [weak self] in if let self { showPrivacyPolicy(on: self) } })
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Connect the phone may have turned it on.
        phoneSwitch.isOn = phoneKeypad.enabled
    }
    private func connectPhone() {
        let screen = SetupPhoneViewController(BedsideSetup(), keypad: phoneKeypad)
        let navigation = PorchStyle.navigation(screen)
        screen.onContinue = { [weak navigation] in navigation?.dismiss(animated: true) }
        present(navigation, animated: true)
    }
    private func confirmFamilyDevice(_ device: String) {
        let alert = UIAlertController(title: "Use this \(device) as a family device?", message: "For calling the bedside Porch from this \(device). You can switch back later.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Use as family device", style: .default) { _ in PorchDevice.experience = .family })
        present(alert, animated: true)
    }
    @objc private func changePhoneKeypad() { phoneKeypad.setEnabled(phoneSwitch.isOn) }
    @objc private func changeReceiverHangUp() { phoneKeypad.setReceiverHangUp(receiverSwitch.isOn) }
}
