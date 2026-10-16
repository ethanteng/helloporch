import UIKit
import PorchCore

final class AdvancedSettingsViewController: CaregiverFormViewController {
    private let defaults: UserDefaults
    private let silenceSwitch = UISwitch()
    private let secondsField = UITextField()
    private let validation = PorchStyle.label("Enter a whole number from 15 to 1800 seconds.", size: 16, color: .systemRed)
    private var timeoutGroup = UIView()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
