import UIKit
import AVFoundation
import PorchCore

/// Calls to and from the bedside. Ringing, screening and call history are kept with the household, so caregiver mode
/// on a family phone has them too. Phone fallback, leaving a message and hanging up after silence are the bedside's own.
/// Changes apply right away.
final class CallSettingsViewController: CaregiverPageViewController {
    private let defaults: UserDefaults
    private let testTone = PorchTonePlayer()
    private let testAnnouncement = PorchIncomingAudio()
    private let soundStatus = PorchStyle.label("", size: 15)
    private var soundTimer: Timer?

    init(admin: FamilyAdminViewController, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(admin: admin)
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:defaults:)") }
    override func viewDidLoad() { super.viewDidLoad(); title = "Calls" }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stopSoundTests() }

    override func build(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) {
        let name = admin.lovedOne
        let screening = state?.callScreening
        content.addArrangedSubview(group("Calls to \(name)", rows: (admin.onBedside ? [voicemailRow(admin)] : []) + [blockRow(admin, screening), blockedRow(screening)]))
        guard admin.onBedside else {
            content.addArrangedSubview(group(rows: [historyRow(admin)]))
            return
        }
        content.addArrangedSubview(group("Calls from \(name)", detail: "If Porch isn't answered, Porch calls the person's phone.", rows: [fallbackRow(), leaveMessageRow()]))
        var all = [silenceToggle()]
        if CallPreferences.disconnectAfterSilence(in: defaults) { all.append(silenceRow()) }
        content.addArrangedSubview(group("All calls", rows: all + [historyRow(admin), soundsRow()]))
    }

    static func duration(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) sec" : seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) sec"
    }

    /// The household's wait, which needs the pairing and a connection to load.
    private func voicemailRow(_ admin: FamilyAdminViewController) -> UIView {
        let saved = FamilyCoordinator.shared.state.map { $0.ringSeconds ?? CallPreferences.defaultVoicemailSeconds }
        let stepper = UIStepper()
        stepper.minimumValue = Double(CallPreferences.voicemailRange.lowerBound)
        stepper.maximumValue = Double(CallPreferences.voicemailRange.upperBound)
        stepper.stepValue = 5
        stepper.value = Double(saved ?? CallPreferences.defaultVoicemailSeconds)
        // One change once the caregiver lets go, rather than one per step.
        stepper.isContinuous = false
        stepper.isEnabled = saved != nil
        stepper.accessibilityIdentifier = "calls.voicemailWait"
        let value = PorchStyle.label(saved.map { Self.duration($0) } ?? "–")
        let row = stepperRow("Ring before voicemail", value: value, stepper)
        stepper.addAction(UIAction { [weak admin, weak stepper, weak value] _ in
            guard let admin, let stepper else { return }
            value?.text = Self.duration(Int(stepper.value)); stepper.accessibilityValue = value?.text
            Task { await admin.perform("setRingSeconds", ["seconds": Int(stepper.value)]) }
        }, for: .valueChanged)
        return row
    }
    private func blockRow(_ admin: FamilyAdminViewController, _ screening: CallScreening?) -> UIView {
        let block = UISwitch(); block.isOn = screening?.enabled == true
        block.isEnabled = screening != nil
        block.accessibilityIdentifier = "calls.blockUnknown"
        block.addAction(UIAction { [weak admin, weak block] _ in
            guard let admin, let block else { return }
            Task { await admin.perform("setBlockUnknownCallers", ["enabled": block.isOn]) }
        }, for: .valueChanged)
        let detail = screening == nil ? "Not available on this Porch's server yet."
            : screening?.enabled == true ? "Only keypad contacts and numbers you allow can ring." : nil
        return toggleRow("Block unknown callers", detail: detail, block)
    }
    private func blockedRow(_ screening: CallScreening?) -> UIView {
        let blocked = screening?.blocked ?? [], allowed = screening?.allowed ?? []
        let text = UIStackView(arrangedSubviews: [PorchStyle.label("Blocked numbers", size: 18, color: PorchStyle.ink)])
        text.axis = .vertical; text.spacing = 2
        if !allowed.isEmpty { text.addArrangedSubview(PorchStyle.label("\(allowed.count) allowed", size: 15)) }
        let count = FamilyAdminViewController.singleLine(PorchStyle.label(blocked.isEmpty ? "None" : "\(blocked.count)", size: 18))
        let list = PorchListRow([text, count], label: blocked.isEmpty ? "Blocked numbers, none" : "Blocked numbers, \(blocked.count)") { [weak self] in
            guard let self, let admin = self.admin else { return }
            self.push(BlockedCallersViewController(admin: admin))
        }
        list.accessibilityIdentifier = "calls.blockedNumbers"
        list.isEnabled = screening != nil
        return list
    }
    private func fallbackRow() -> UIView {
        let stepper = UIStepper()
        stepper.minimumValue = Double(CallPreferences.fallbackRange.lowerBound)
        stepper.maximumValue = Double(CallPreferences.fallbackRange.upperBound)
        stepper.stepValue = 5
        stepper.value = Double(CallPreferences.fallbackSeconds(in: defaults))
        stepper.accessibilityIdentifier = "calls.fallbackWait"
        let value = PorchStyle.label(Self.duration(Int(stepper.value)))
        let row = stepperRow("Try their phone after", value: value, stepper)
        stepper.addAction(UIAction { [weak self, weak stepper, weak value] _ in
            guard let self, let stepper else { return }
            CallPreferences.saveFallbackSeconds(Int(stepper.value), in: self.defaults)
            value?.text = Self.duration(Int(stepper.value)); stepper.accessibilityValue = value?.text
        }, for: .valueChanged)
        return row
    }
    private func leaveMessageRow() -> UIView {
        let leave = UISwitch(); leave.isOn = CallPreferences.leaveMessageWhenUnanswered(in: defaults)
        leave.accessibilityIdentifier = "calls.leaveMessage"
        leave.addAction(UIAction { [weak self, weak leave] _ in
            guard let self, let leave else { return }
            CallPreferences.saveLeaveMessageWhenUnanswered(leave.isOn, in: self.defaults)
        }, for: .valueChanged)
        return toggleRow("Leave a message if no one answers", leave)
    }
    private func silenceToggle() -> UIView {
        let silence = UISwitch(); silence.isOn = CallPreferences.disconnectAfterSilence(in: defaults)
        silence.accessibilityIdentifier = "calls.silence"
        silence.addAction(UIAction { [weak self, weak silence] _ in
            guard let self, let silence else { return }
            CallPreferences.saveSilence(enabled: silence.isOn, seconds: CallPreferences.silenceSeconds(in: self.defaults), in: self.defaults)
            self.render()
        }, for: .valueChanged)
        return toggleRow("End calls after silence", silence)
    }
    /// Whole minutes. A time saved in seconds by an older version shows as it is until it's changed.
    private func silenceRow() -> UIView {
        let seconds = CallPreferences.silenceSeconds(in: defaults)
        let stepper = UIStepper()
        stepper.minimumValue = 1
        stepper.maximumValue = Double(CallPreferences.silenceRange.upperBound / 60)
        stepper.value = Double(max(1, (seconds + 30) / 60))
        stepper.accessibilityIdentifier = "calls.silenceMinutes"
        let value = PorchStyle.label(Self.duration(seconds))
        let row = stepperRow("After no one talks for", value: value, stepper)
        stepper.addAction(UIAction { [weak self, weak stepper, weak value] _ in
            guard let self, let stepper else { return }
            let seconds = Int(stepper.value) * 60
            CallPreferences.saveSilence(enabled: true, seconds: seconds, in: self.defaults)
            value?.text = Self.duration(seconds); stepper.accessibilityValue = value?.text
        }, for: .valueChanged)
        return row
    }
    private func historyRow(_ admin: FamilyAdminViewController) -> UIView {
        let history = linkRow("Call history", symbol: "clock.arrow.circlepath") { [weak self, weak admin] in
            guard let self, let admin else { return }
            self.push(CallHistoryViewController(remote: admin.remote))
        }
        history.accessibilityIdentifier = "calls.history"
        return history
    }
    private func soundsRow() -> UIView {
        let ring = PorchStyle.button("Ringing", symbol: "speaker.wave.2", filled: false)
        let announcement = PorchStyle.button("Drop-in announcement", symbol: "person.wave.2", filled: false)
        ring.accessibilityIdentifier = "calls.testRinging"; announcement.accessibilityIdentifier = "calls.testAnnouncement"
        ring.accessibilityLabel = "Test ringing"; announcement.accessibilityLabel = "Test drop-in announcement"
        ring.addTarget(self, action: #selector(testRing), for: .touchUpInside)
        announcement.addTarget(self, action: #selector(testVoice), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [ring, announcement])
        buttons.spacing = 8; buttons.distribution = .fillEqually
        soundStatus.isHidden = soundStatus.text?.isEmpty != false
        let stack = UIStackView(arrangedSubviews: [PorchStyle.label("Test sounds", size: 18, color: PorchStyle.ink), buttons, soundStatus])
        stack.axis = .vertical; stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
        return stack
    }

    private func stopSoundTests() { soundTimer?.invalidate(); soundTimer = nil; testTone.stop(); testAnnouncement.stop() }
    private func outputDescription() -> String {
        let session = AVAudioSession.sharedInstance()
        let output = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
        return "Output: \(output.isEmpty ? "system default" : output) · Media volume: \(Int(session.outputVolume * 100))%"
    }
    private func showSound(_ text: String) { soundStatus.text = text; soundStatus.isHidden = false }
    @objc private func testRing() {
        stopSoundTests()
        let started = testTone.play(.incoming)
        showSound(started ? "Playing a three-second ringing test.\n\(outputDescription())" : "Couldn't play the sound. Check the iPad's volume and try again.")
        soundTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.testTone.stop() } }
    }
    @objc private func testVoice() {
        stopSoundTests()
        let language = BedsidePreferences.load().language
        showSound("Playing the drop-in announcement in the bedside language.\n\(outputDescription())")
        testAnnouncement.announce(name: language.text("A family member"), video: true, language: language) { [weak self] success in
            self?.showSound(success ? "Announcement finished. No call was placed." : "Couldn't play the announcement. Check the iPad's volume.")
        }
    }
}

/// Local ringback for both the Porch wait and the SIP dialing stage.
/// Playback shares LiveKit's audio session; it never publishes an audio track.
@MainActor final class PorchRingback {
    private let player = PorchTonePlayer()
    private var ringing = false, held = false
    func start() { ringing = true; if !held { player.play(.ringback) } }
    func stop() { ringing = false; player.stop() }
    /// Rings once the bedside has said who it's calling, rather than over it.
    func hold(until announcement: OutgoingCallAnnouncement) {
        held = true
        announcement.then { [weak self] in
            guard let self else { return }
            self.held = false
            if self.ringing { self.player.play(.ringback) }
        }
    }
}
