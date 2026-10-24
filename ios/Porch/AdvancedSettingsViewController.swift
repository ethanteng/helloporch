import UIKit
import PorchCore

final class AdvancedSettingsViewController: CaregiverFormViewController {
    private let phoneSwitch = UISwitch()
    private let receiverSwitch = UISwitch()
    private let defaults: UserDefaults
    private let phoneKeypad: Cell2JackKeypad
    private let silenceSwitch = UISwitch()
    private let secondsField = UITextField()
    private let validation = PorchStyle.label("Enter a whole number from 15 to 1800 seconds.", size: 16, color: .systemRed)
    private var timeoutGroup = UIView()

    init(defaults: UserDefaults = .standard, phoneKeypad: Cell2JackKeypad = .shared) {
        self.defaults = defaults
        self.phoneKeypad = phoneKeypad
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(defaults:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Advanced"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        silenceSwitch.isOn = CallPreferences.disconnectAfterSilence(in: defaults)
        silenceSwitch.onTintColor = PorchStyle.accent
        silenceSwitch.accessibilityLabel = "End calls after silence"
        silenceSwitch.accessibilityIdentifier = "advanced.silenceEnabled"
        silenceSwitch.addTarget(self, action: #selector(updateControls), for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [PorchStyle.label("End calls after silence", size: 20, color: PorchStyle.ink, weight: .medium), silenceSwitch])
        row.spacing = 20
        row.alignment = .center
        secondsField.text = String(CallPreferences.silenceSeconds(in: defaults))
        secondsField.keyboardType = .numberPad
        secondsField.accessibilityIdentifier = "advanced.silenceSeconds"
        secondsField.addTarget(self, action: #selector(updateControls), for: .editingChanged)
        timeoutGroup = field(secondsField, title: "Seconds without talking", placeholder: "120", helper: "Choose 15–1800 seconds (up to 30 minutes). The default is 120 seconds.")
        form.addArrangedSubview(section("Automatic hang-up", detail: "Optionally end a call when neither person has spoken for this long. Speech from either side restarts the timer, including a voicemail greeting or message. Applies to Porch calls and phone fallback on this device. The timer starts after connection and resets while reconnecting.", views: [row, timeoutGroup, validation]))
        form.addArrangedSubview(section("USB keypad & touch controls", detail: "Your standard USB keypad and the on-screen controls stay available at all times, including when Cell2Jack is off or disconnected. Connect a standard keypad to use it as a backup; no driver or mode switch is needed.", views: []))
        #if !PORCH_NO_CELL2JACK
        if Cell2JackKeypad.supportsDriverPlatform {
        phoneSwitch.isOn = phoneKeypad.enabled
        phoneSwitch.onTintColor = PorchStyle.accent
        phoneSwitch.accessibilityIdentifier = "advanced.cell2jack"
        phoneSwitch.accessibilityLabel = "Use Cell2Jack phone keypad"
        phoneSwitch.addTarget(self, action: #selector(changePhoneKeypad), for: .valueChanged)
        let phoneRow = UIStackView(arrangedSubviews: [PorchStyle.label("Use Cell2Jack phone keypad", size: 20), phoneSwitch])
        phoneRow.spacing = 20; phoneRow.alignment = .center
        receiverSwitch.isOn = phoneKeypad.receiverHangUp
        receiverSwitch.onTintColor = PorchStyle.accent
        receiverSwitch.accessibilityIdentifier = "advanced.cell2jackReceiverHangUp"
        receiverSwitch.accessibilityLabel = "Hang up when the receiver is put back"
        receiverSwitch.addTarget(self, action: #selector(changeReceiverHangUp), for: .valueChanged)
        let receiverRow = UIStackView(arrangedSubviews: [PorchStyle.label("Hang up when the receiver is put back", size: 20), receiverSwitch])
        receiverRow.spacing = 20; receiverRow.alignment = .center
        let retry = PorchStyle.button("Retry phone connection", symbol: "arrow.clockwise", filled: false)
        retry.addAction(UIAction { [weak self] _ in self?.phoneKeypad.refresh() }, for: .touchUpInside)
        let driver = PorchStyle.button("Open app settings", symbol: "gearshape", filled: false)
        driver.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
        form.addArrangedSubview(section("Cell2Jack phone keypad", detail: "Optional, off by default. Requires an M-series iPad with iPadOS 16 or later and the USB driver enabled in this app’s settings. These switches take effect immediately. Use your saved person keys to call and your call-control key (normally 0) to hang up. Putting the receiver back on the phone also hangs up; turn that off if they set the receiver down right after pressing a key, since the sound comes from the iPad. Picking it up does nothing by itself. Keep Porch open. USB provides keypad input; sound follows the iPad’s selected audio output.", views: [phoneRow, receiverRow, retry, driver]))
        } else {
            form.addArrangedSubview(section("Cell2Jack phone keypad", detail: "Cell2Jack requires an M-series iPad with iPadOS 16 or later. You can continue using a standard USB keypad and touch controls on this device.", views: []))
        }
        #endif
        updateControls()
    }

    private var seconds: Int? {
        guard let value = Int((secondsField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
              CallPreferences.silenceRange.contains(value) else { return nil }
        return value
    }
    @objc private func updateControls() {
        timeoutGroup.isHidden = !silenceSwitch.isOn
        validation.isHidden = !silenceSwitch.isOn || seconds != nil
        navigationItem.rightBarButtonItem?.isEnabled = !silenceSwitch.isOn || seconds != nil
        setKeyboardControlVisible(silenceSwitch.isOn)
        if !silenceSwitch.isOn { view.endEditing(true) }
    }
    @objc private func save() {
        guard !silenceSwitch.isOn || seconds != nil else { return }
        CallPreferences.saveSilence(enabled: silenceSwitch.isOn, seconds: seconds ?? CallPreferences.silenceSeconds(in: defaults), in: defaults)
        view.endEditing(true)
        navigationController?.popViewController(animated: true)
    }
}

extension AdvancedSettingsViewController {
    @objc private func changePhoneKeypad() { phoneKeypad.setEnabled(phoneSwitch.isOn) }
    @objc private func changeReceiverHangUp() { phoneKeypad.setReceiverHangUp(receiverSwitch.isOn) }
}
