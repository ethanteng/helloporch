import UIKit
import AVFoundation
import PorchCore

final class CallPreferencesViewController: CaregiverFormViewController {
    private let secondsLabel = PorchStyle.label("", size: 28, color: PorchStyle.ink, weight: .semibold)
    private let stepper = UIStepper()
    private let voicemailLabel = PorchStyle.label("", size: 28, color: PorchStyle.ink, weight: .semibold)
    private let voicemailStepper = UIStepper()
    private lazy var voicemailRow = UIStackView(arrangedSubviews: [voicemailLabel, UIView(), voicemailStepper])
    private let voicemailStatus = PorchStyle.label("", size: 16)
    /// The household's saved wait, once the server has sent it; the stepper follows it until changed here.
    private var savedVoicemailSeconds: Int?
    private var voicemailEdited = false
    private let leaveMessage = UISwitch()
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
        leaveMessage.isOn = CallPreferences.leaveMessageWhenUnanswered()
        leaveMessage.accessibilityIdentifier = "calls.leaveMessage"
        form.addArrangedSubview(group("When no one answers", footer: "If a Porch call isn't answered, is declined, or their Porch app isn't available, Porch says so, beeps and records a message for that person, like voicemail: audio for a voice call, video for a video call, up to two minutes. Pressing the hang-up key or Send message sends it; if nothing is said, nothing is sent. They get a notification and can play it in their Porch app. Calls that ring through to a regular phone use that phone's own voicemail instead.", rows: [toggleRow("Leave a message", leaveMessage)]))
        voicemailStepper.minimumValue = Double(CallPreferences.voicemailRange.lowerBound)
        voicemailStepper.maximumValue = Double(CallPreferences.voicemailRange.upperBound)
        voicemailStepper.stepValue = 5
        voicemailStepper.value = Double(CallPreferences.defaultVoicemailSeconds)
        voicemailStepper.accessibilityLabel = "Ring before voicemail"
        voicemailStepper.accessibilityIdentifier = "calls.voicemailWait"
        voicemailStepper.addTarget(self, action: #selector(voicemailStepped), for: .valueChanged)
        voicemailRow.alignment = .center
        voicemailRow.spacing = 20
        form.addArrangedSubview(section("Ring before voicemail", detail: "How long calls to Porch ring, from the family app or a regular phone, before the caller can leave a message. If family messages are off, the call ends instead. Approved drop-ins always get 45 seconds for their announcement and countdown.", views: [voicemailRow, voicemailStatus]))
        let ring = PorchStyle.button("Test ringing", symbol: "speaker.wave.2")
        let announcement = PorchStyle.button("Test video announcement", symbol: "person.wave.2", filled: false)
        ring.accessibilityIdentifier = "calls.testRinging"; announcement.accessibilityIdentifier = "calls.testAnnouncement"
        ring.addTarget(self, action: #selector(testRing), for: .touchUpInside)
        announcement.addTarget(self, action: #selector(testVoice), for: .touchUpInside)
        form.addArrangedSubview(section("Incoming calls & drop-ins", detail: "Incoming calls ring until answered, declined, or sent to voicemail. Approved drop-ins play a chime and announce the caller and call type before the five-second countdown. A short chime confirms connection and turning video on. Announcements use the bedside language. Use these tests without placing a call; adjust media volume with the iPad's volume buttons.", views: [ring, announcement, soundStatus]))
        hideKeyboardControl()
        updateValue()
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        familyChanged()
    }
    deinit { NotificationCenter.default.removeObserver(self) }

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
        testAnnouncement.announce(name: language.text("A family member"), video: true, language: language) { [weak self] success in
            self?.soundStatus.text = success ? "Video announcement completed. No call was placed." : "Couldn't play the announcement. Check the iPad's audio output and installed voices."
        }
        if soundStatus.text == "Playing the video announcement in the bedside language." { soundStatus.text?.append("\n\(outputDescription())") }
    }

    @objc private func updateValue() {
        let seconds = Int(stepper.value)
        secondsLabel.text = "\(seconds) seconds"
        stepper.accessibilityValue = secondsLabel.text
    }

    /// The voicemail wait lives with the household, so it needs the pairing and a connection to load.
    @objc private func familyChanged() {
        let paired = PorchDevice.credential(for: .bedside) != nil
        savedVoicemailSeconds = FamilyCoordinator.shared.state.map { $0.ringSeconds ?? CallPreferences.defaultVoicemailSeconds }
        if let saved = savedVoicemailSeconds, !voicemailEdited { voicemailStepper.value = Double(saved) }
        voicemailStepper.isEnabled = savedVoicemailSeconds != nil
        voicemailRow.isHidden = !paired
        voicemailStatus.text = !paired ? "Set up Family & drop-in on this iPad first."
            : savedVoicemailSeconds == nil ? "Connecting to Porch… Check the internet connection if this doesn't load."
            : "Choose 15 seconds to 2 minutes. The default is 45 seconds."
        showVoicemailValue()
    }

    @objc private func voicemailStepped() { voicemailEdited = true; showVoicemailValue() }

    private func showVoicemailValue() {
        voicemailLabel.text = "\(Int(voicemailStepper.value)) seconds"
        voicemailStepper.accessibilityValue = voicemailLabel.text
    }

    @objc private func save() {
        CallPreferences.saveFallbackSeconds(Int(stepper.value))
        CallPreferences.saveLeaveMessageWhenUnanswered(leaveMessage.isOn)
        let seconds = Int(voicemailStepper.value)
        guard let saved = savedVoicemailSeconds, seconds != saved, let credential = PorchDevice.credential(for: .bedside) else {
            navigationController?.popViewController(animated: true); return
        }
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { [weak self] in
            do {
                let response = try await FamilyService(credential).send("setRingSeconds", ["seconds": seconds], pin: NativeCallSettings.caregiverCode)
                FamilyCoordinator.shared.update(response)
                self?.navigationController?.popViewController(animated: true)
            } catch {
                guard let self else { return }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                showPorchError(error, on: self)
            }
        }
    }
}

/// Local ringback for both the Porch wait and the SIP dialing stage.
/// Playback shares LiveKit's audio session; it never publishes an audio track.
@MainActor final class PorchRingback {
    private let player = PorchTonePlayer()
    private var ringing = false, held = false, joining = false
    func start() { ringing = true; playIfReady() }
    func stop() { ringing = false; joining = false; player.stop() }
    /// Rings once the bedside has said who it's calling, rather than over it.
    func hold(until announcement: OutgoingCallAnnouncement) {
        held = true
        announcement.then { [weak self] in
            guard let self else { return }
            self.held = false
            self.playIfReady()
        }
    }
    /// Keep the tone off while joining replaces the playback session. A tone started beforehand
    /// is silenced by that switch and then looks like it is still playing, so it would not restart.
    func suspendForCallJoin() { joining = true; player.stop() }
    func resumeAfterCallJoin() { joining = false; playIfReady() }
    private func playIfReady() { if ringing, !held, !joining { player.play(.ringback) } }
}
