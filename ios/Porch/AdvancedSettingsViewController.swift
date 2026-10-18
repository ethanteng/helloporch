import UIKit
import PorchCore

final class AdvancedSettingsViewController: CaregiverFormViewController {
    #if PORCH_CELL2JACK_CALLS
    private let phoneSwitch = UISwitch()
    private let phoneStatus = PorchStyle.label("", size: 16)
    #endif
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
        #if PORCH_CELL2JACK_CALLS
        phoneSwitch.isOn = Cell2JackKeypad.shared.enabled
        phoneSwitch.onTintColor = PorchStyle.accent
        phoneSwitch.accessibilityIdentifier = "advanced.cell2jack"
        phoneSwitch.accessibilityLabel = "Use Cell2Jack phone keypad"
        phoneSwitch.addTarget(self, action: #selector(changePhoneKeypad), for: .valueChanged)
        let phoneRow = UIStackView(arrangedSubviews: [PorchStyle.label("Use Cell2Jack phone keypad", size: 20), phoneSwitch])
        phoneRow.spacing = 20; phoneRow.alignment = .center
        let retry = PorchStyle.button("Retry phone connection", symbol: "arrow.clockwise", filled: false)
        retry.addAction(UIAction { _ in Cell2JackKeypad.shared.refresh() }, for: .touchUpInside)
        let driver = PorchStyle.button("Open app settings", symbol: "gearshape", filled: false)
        driver.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
        form.addArrangedSubview(section("Cell2Jack phone keypad · experimental", detail: "This switch takes effect immediately. Phone keys can place real calls using your saved assignments. Keep Porch open on the clock. Press 0 (or your assigned call-control key) to hang up; hanging up the handset alone does not end a Porch call. Enable the USB driver in this app’s settings. USB provides keypad input; call audio follows the iPad’s selected audio output.", views: [phoneRow, phoneStatus, retry, driver]))
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPhoneStatus), name: .cell2JackKeypadChanged, object: nil)
        refreshPhoneStatus()
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

#if PORCH_CELL2JACK_CALLS
extension AdvancedSettingsViewController {
    @objc private func changePhoneKeypad() { Cell2JackKeypad.shared.setEnabled(phoneSwitch.isOn) }
    @objc private func refreshPhoneStatus() { phoneStatus.text = Cell2JackKeypad.shared.status }
}
#endif
