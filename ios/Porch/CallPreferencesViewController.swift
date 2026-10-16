import UIKit
import AVFoundation
import PorchCore

final class CallPreferencesViewController: CaregiverFormViewController {
    private let secondsLabel = PorchStyle.label("", size: 28, color: PorchStyle.ink, weight: .semibold)
    private let stepper = UIStepper()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Call preferences"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        stepper.minimumValue = Double(CallPreferences.fallbackRange.lowerBound)
        stepper.maximumValue = Double(CallPreferences.fallbackRange.upperBound)
        stepper.stepValue = 5
        stepper.value = Double(CallPreferences.fallbackSeconds())
        stepper.accessibilityLabel = "Wait before phone fallback"
        stepper.addTarget(self, action: #selector(updateValue), for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [secondsLabel, UIView(), stepper])
        row.alignment = .center
        row.spacing = 20
        form.addArrangedSubview(section("Wait before phone fallback", detail: "How long to try Porch before calling their regular phone. Applies to all people with phone fallback enabled on this iPad.", views: [row, PorchStyle.label("Choose 5 seconds to 2 minutes. The default is 20 seconds. Phone fallback is always voice only.", size: 16)]))
        form.addArrangedSubview(section("While dialing", detail: "You'll hear a familiar ringing tone while waiting for an answer. It stops when the call connects or ends. Adjust the sound with the iPad's volume buttons.", views: []))
        hideKeyboardControl()
        updateValue()
    }

    @objc private func updateValue() {
        let seconds = Int(stepper.value)
        secondsLabel.text = "\(seconds) seconds"
        stepper.accessibilityValue = secondsLabel.text
    }

    @objc private func save() {
        CallPreferences.saveFallbackSeconds(Int(stepper.value))
        navigationController?.popViewController(animated: true)
    }
}

/// Local ringback for both the Porch wait and the SIP dialing stage.
/// Playback shares LiveKit's audio session; it never publishes an audio track.
final class PorchRingback {
    private var player: AVAudioPlayer?

    func start() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--family-silent") { return }
        #endif
        guard player == nil else { return }
        guard let audio = try? AVAudioPlayer(data: Self.wave()) else { return }
        audio.numberOfLoops = -1
        audio.volume = 0.25
        audio.prepareToPlay()
        if audio.play() { player = audio }
    }

    func stop() { player?.stop(); player = nil }

    private static func wave() -> Data {
        let rate = 16_000
        let samples = rate * 6 // Two seconds ringing, four seconds silent.
        var data = Data()
        func ascii(_ text: String) { data.append(contentsOf: text.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        ascii("RIFF"); integer(UInt32(36 + samples * 2)); ascii("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1))
        integer(UInt32(rate)); integer(UInt32(rate * 2)); integer(UInt16(2)); integer(UInt16(16))
        ascii("data"); integer(UInt32(samples * 2))
        for index in 0..<samples {
            let t = Double(index) / Double(rate)
            let fade = max(0, min(1, t / 0.01, (2 - t) / 0.01))
            let tone = (sin(2 * .pi * 440 * t) + sin(2 * .pi * 480 * t)) * 0.35 * fade
            integer(Int16(t < 2 ? tone * Double(Int16.max) : 0))
        }
        return data
    }
}
