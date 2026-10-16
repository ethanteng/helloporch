import UIKit
import AVFoundation
import PorchCore

final class CallPreferencesViewController: CaregiverFormViewController {
    private let secondsLabel = PorchStyle.label("", size: 28, color: PorchStyle.ink, weight: .semibold)
    private let stepper = UIStepper()
    private let testTone = PorchTonePlayer()
    private let testAnnouncement = PorchIncomingAudio()
    private let soundStatus = PorchStyle.label("", size: 16)
    private var soundTimer: Timer?

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
        let ring = PorchStyle.button("Test ringing", symbol: "speaker.wave.2")
        let announcement = PorchStyle.button("Test video announcement", symbol: "person.wave.2", filled: false)
        ring.accessibilityIdentifier = "calls.testRinging"; announcement.accessibilityIdentifier = "calls.testAnnouncement"
        ring.addTarget(self, action: #selector(testRing), for: .touchUpInside)
        announcement.addTarget(self, action: #selector(testVoice), for: .touchUpInside)
        form.addArrangedSubview(section("Incoming calls & drop-ins", detail: "Incoming calls ring until answered or declined. Approved drop-ins play a chime and announce the caller and call type before the five-second countdown. A short chime confirms connection and turning video on. Announcements use the bedside language. Use these tests without placing a call; adjust media volume with the iPad's volume buttons.", views: [ring, announcement, soundStatus]))
        hideKeyboardControl()
        updateValue()
    }

    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stopSoundTests() }
    private func stopSoundTests() { soundTimer?.invalidate(); soundTimer = nil; testTone.stop(); testAnnouncement.stop() }
    private func outputDescription() -> String {
        let session = AVAudioSession.sharedInstance()
        let output = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
        return "Output: \(output.isEmpty ? "system default" : output) · Media volume: \(Int(session.outputVolume * 100))%"
    }
    @objc private func testRing() {
        stopSoundTests()
        let started = testTone.play(.incoming)
        soundStatus.text = started ? "Playing a three-second ringing test.\n\(outputDescription())" : "Couldn't play the sound. Check the iPad's audio output and try again."
        soundTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.testTone.stop() } }
    }
    @objc private func testVoice() {
        stopSoundTests()
        let language = BedsidePreferences.load().language
        soundStatus.text = "Playing the video announcement in the bedside language."
        testAnnouncement.announce(name: language == .traditionalChinese ? "家人" : "A family member", video: true, language: language) { [weak self] success in
            self?.soundStatus.text = success ? "Video announcement completed. No call was placed." : "Couldn't play the announcement. Check the iPad's audio output and installed voices."
        }
        if soundStatus.text == "Playing the video announcement in the bedside language." { soundStatus.text?.append("\n\(outputDescription())") }
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
@MainActor final class PorchRingback {
    private let player = PorchTonePlayer()
    func start() { player.play(.ringback) }
    func stop() { player.stop() }
}
