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
        timeoutGroup = field(secondsField, title: "Seconds without talking", placeholder: "120", helper: "From 15 to 1800 seconds. Usually 120.")
        form.addArrangedSubview(section("Automatic hang-up", detail: "Turn this on to end calls when no one has talked for a while. Useful if your loved one forgets to hang up.", views: [row, timeoutGroup, validation]))
        form.addArrangedSubview(section("USB keypad & touch controls", detail: "A regular USB keypad and the touchscreen always work, even without Cell2Jack.", views: []))
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
        form.addArrangedSubview(section("Cell2Jack phone keypad", detail: "Lets your loved one use a desk phone as the keypad. Needs an iPad with an M chip, and the USB driver turned on in Settings → Porch.", views: [phoneRow, receiverRow, retry, driver]))
        } else {
            form.addArrangedSubview(section("Cell2Jack phone keypad", detail: "Cell2Jack needs an iPad with an M chip. A regular USB keypad and the touchscreen still work.", views: []))
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
