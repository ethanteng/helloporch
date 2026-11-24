import UIKit
import AVFoundation
import CoreText
import LiveKit
import PorchCore

/// Caregivers' own voices (lib/family/voices.ts). In caregiver mode on their phone, a caregiver reads a short script
/// aloud for about a minute; ElevenLabs makes a voice from it, and the bedside can speak announcements in it. Only the
/// person whose voice it is records it, live, after agreeing to its use. The server deletes the recording once the
/// voice is made, and this phone deletes its copy when these pages close.
enum CaregiverVoice {
    static let minimumSeconds: TimeInterval = 20
    static let targetSeconds: TimeInterval = 60
    static let maximumSeconds: TimeInterval = 180
    /// The script moves on a paragraph at a time, so a minute's reading reaches the end.
    static let paragraphSeconds: TimeInterval = 12
    static let script = [
        "Good morning! It's a lovely day. I hope you slept well and had some breakfast.",
        "The kids are calling this afternoon, and I'll come by on Sunday. We'll bring lunch.",
        "The garden looks wonderful this year, and the tomatoes are almost ready. Your neighbor waved hello this morning.",
        "We found the old photo album, and the kids loved the pictures from the lake. I'll bring it on Sunday so we can look at it together.",
        "If you need anything, just tap the screen, and one of us will call you right back.",
        "Remember to drink some water and take a little walk. I love you, and I'll talk to you soon.",
    ]
    /// The script's paragraphs not being read yet, and finished ones.
    static let muted = PorchStyle.rgb(0x7A6455)
    /// The waveform's part that hasn't played yet, and the level meter at rest.
    static let quiet = PorchStyle.rgb(0xC9B8A6)
    /// 0:38, 1:02.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    /// The sentence the bedside's own preview speaks: a drop-in's announcement.
    @MainActor static func previewSentence(_ language: BedsideLanguage) -> String {
        PorchIncomingAudio.message(name: language.text("A family member"), video: true, language: language)
    }
    /// Who a family voice is, by their photo or initials.
    @MainActor static func avatar(for voice: NaturalVoices.Voice, admin: FamilyAdminViewController, state: FamilyAdminState) -> UIView {
        let person = state.people.first { $0.id == voice.memberID }
        let photo = FamilyPhotos.shared.data(for: person?.photoID)
        if photo == nil, let person { admin.loadPhoto(of: person) }
        return FamilyAdminViewController.avatar(voice.name, photo: photo, size: 38)
    }
    /// A short line saying what went wrong, beside what it was about.
    static func problem(_ text: String) -> UILabel {
        let label = PorchStyle.label(text, size: 15, color: PorchStyle.danger)
        label.accessibilityIdentifier = "voice.problem"
        return label
    }
}

// MARK: - Voice

/// Caregiver mode on a phone: the voice the bedside speaks announcements in. Your own voice comes first, to record or
/// choose, then other caregivers', the listed voices and the bedside's built-in one. A tap saves the choice at once.
final class VoiceSettingsViewController: CaregiverPageViewController {
    /// A choice on its way to the server, shown as chosen meanwhile. `.some(nil)` is the built-in voice.
    private var saving: String??
    private var removing = false
    private var failure: String?
    private enum Preview { case idle, loading, playing }
    private var preview = Preview.idle
    private var previewAttempt: UUID?
    private let player = VoiceClipPlayer()

    override func viewDidLoad() { super.viewDidLoad(); title = "Voice" }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPreview()
    }

    override func build(_ admin: FamilyAdminViewController, _ state: FamilyAdminState?) {
        guard let state, let choices = state.announcementVoices else {
            content.addArrangedSubview(introduction("Voices aren't available right now."))
            return
        }
        let selected: String? = saving ?? choices.selected
        let mine = choices.familyVoice(of: admin.myID)
        var rows: [UIView] = []
        if let mine {
            rows.append(choiceRow(mine.name, detail: "Your voice", badge: CaregiverVoice.avatar(for: mine, admin: admin, state: state),
                                  chosen: selected == mine.id, identifier: "voice.mine") { [weak self] in self?.choose(mine.id) })
        } else {
            rows.append(recordRow())
        }
        for voice in choices.familyVoices where voice.memberID != admin.myID {
            rows.append(choiceRow(voice.name, detail: voice.detail, badge: CaregiverVoice.avatar(for: voice, admin: admin, state: state),
                                  chosen: selected == voice.id, identifier: "voice.family.\(voice.id)") { [weak self] in self?.choose(voice.id) })
        }
        for voice in choices.listedVoices {
            rows.append(choiceRow(voice.name, detail: voice.detail, chosen: selected == voice.id, identifier: "voice.listed.\(voice.id)") { [weak self] in self?.choose(voice.id) })
        }
        rows.append(choiceRow("Built-in voice", detail: "On \(admin.lovedOne)’s \(admin.bedsideDevice)", chosen: selected == nil, identifier: "voice.builtIn") { [weak self] in
            self?.choose(nil)
        })
        let voices = group("\(state.language.displayName) announcements", rows: rows)
        voices.accessibilityIdentifier = "voice.choices"
        var top: [UIView] = [voices]
        if let failure { top.append(CaregiverVoice.problem(failure)) }
        // The iPad's own voice is only on the iPad.
        top.append(previewButton(enabled: selected != nil))
        let stack = UIStackView(arrangedSubviews: top)
        stack.axis = .vertical; stack.spacing = 12
        content.addArrangedSubview(stack)
        guard mine != nil else { return }
        let again = actionRow("Record again", symbol: "mic") { [weak self] in self?.record() }
        again.accessibilityIdentifier = "voice.recordAgain"
        let remove = actionRow("Remove my voice", symbol: "trash", destructive: true) { [weak self] in self?.confirmRemove() }
        remove.accessibilityIdentifier = "voice.remove"
        remove.configuration?.showsActivityIndicator = removing
        remove.isEnabled = !removing
        content.addArrangedSubview(group(rows: [again, remove]))
    }

    /// A voice to choose: its name, how it sounds or whose it is, and a checkmark on the one in use.
    private func choiceRow(_ title: String, detail: String, badge: UIView? = nil, chosen: Bool, identifier: String, action: @escaping () -> Void) -> PorchListRow {
        let check = UIImageView(image: chosen ? UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)) : nil)
        check.tintColor = PorchStyle.accent
        check.contentMode = .center
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let views = (badge.map { [$0] } ?? []) + [FamilyAdminViewController.text(title, [detail]), check]
        let row = PorchListRow(views, label: "\(title), \(detail)", chevron: false, action: action)
        row.accessibilityIdentifier = identifier
        if chosen { row.accessibilityTraits.insert(.selected) }
        return row
    }
    /// Your voice before you've recorded it.
    private func recordRow() -> PorchListRow {
        let record = FamilyAdminViewController.singleLine(PorchStyle.label("Record", size: 17, color: PorchStyle.accent, weight: .semibold))
        let row = PorchListRow([FamilyAdminViewController.symbolBadge("mic.fill", size: 38), FamilyAdminViewController.text("Your voice", ["Not recorded"]), record],
                               label: "Your voice, not recorded. Record", chevron: false) { [weak self] in self?.record() }
        row.accessibilityIdentifier = "voice.record"
        return row
    }
    /// Outlined, as on the bedside's own settings: it plays here, on this phone.
    private func previewButton(enabled: Bool) -> UIButton {
        let playing = preview == .playing
        let button = PorchStyle.button(playing ? "Stop" : "Preview", symbol: playing ? "stop.fill" : "speaker.wave.2", filled: false)
        button.contentHorizontalAlignment = .leading
        button.configuration?.baseForegroundColor = PorchStyle.ink
        button.configuration?.imageColorTransformer = UIConfigurationColorTransformer { _ in PorchStyle.accent }
        button.configuration?.background.backgroundColor = PorchStyle.surface
        button.configuration?.background.strokeColor = PorchStyle.ink
        button.configuration?.background.strokeWidth = 1.5
        button.configuration?.showsActivityIndicator = preview == .loading
        button.isEnabled = enabled && preview != .loading
        button.accessibilityIdentifier = "voice.preview"
        button.accessibilityLabel = playing ? "Stop preview" : "Preview"
        button.addAction(UIAction { [weak self] _ in self?.togglePreview() }, for: .touchUpInside)
        return button
    }

    private func choose(_ voiceID: String?) {
        guard let admin, saving == nil, !removing, let state = admin.current, let choices = state.announcementVoices, voiceID != choices.selected else { return }
        stopPreview()
        saving = .some(voiceID); failure = nil; render()
        Task { [weak self] in
            var message: String?
            do { _ = try await admin.request("setSpeechVoice", ["language": state.language.rawValue, "voiceID": voiceID.map { $0 as Any } ?? NSNull()]) }
            catch { message = error.localizedDescription }
            guard let self else { return }
            self.saving = nil; self.failure = message; self.render()
        }
    }
    private func record() {
        guard let admin, saving == nil, !removing else { return }
        stopPreview(); failure = nil
        push(VoiceRecordingViewController(admin: admin))
    }
    private func confirmRemove() {
        let alert = UIAlertController(title: "Remove your voice?", message: "Porch stops using it and deletes it.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in self?.remove() })
        present(alert, animated: true)
    }
    private func remove() {
        guard let admin, saving == nil, !removing else { return }
        stopPreview()
        removing = true; failure = nil; render()
        Task { [weak self] in
            var message: String?
            do { _ = try await admin.request("removeVoice") } catch { message = error.localizedDescription }
            guard let self else { return }
            self.removing = false; self.failure = message; self.render()
        }
    }

    /// Plays the announcement a drop-in starts with, in the chosen voice and the bedside's language, as the bedside's
    /// own preview does. A second tap stops it.
    private func togglePreview() {
        guard preview == .idle else { stopPreview(); return }
        guard let admin, let state = admin.current, let voiceID = saving ?? state.announcementVoices?.selected else { return }
        let language = state.language
        let attempt = UUID(); previewAttempt = attempt
        preview = .loading; failure = nil; render()
        Task { [weak self] in
            do {
                let values: [String: Any] = ["language": language.rawValue, "voiceID": voiceID, "text": CaregiverVoice.previewSentence(language)]
                // The server waits up to 15 seconds for a new clip.
                guard let response = try await admin.request("previewSpeech", values, timeout: 30) else { self?.finishPreview(attempt, nil); return }
                guard let clip = response.clip, let url = URL(string: clip.url), url.scheme == "https" else { throw VoiceClipPlayer.unavailable }
                let audio = try await VoiceClipPlayer.download(url)
                guard let self, self.previewAttempt == attempt else { return }
                self.player.onFinish = { [weak self] in self?.finishPreview(attempt, nil) }
                guard self.player.start(try? AVAudioPlayer(data: audio)) else { throw VoiceClipPlayer.unavailable }
                self.preview = .playing; self.render()
            } catch { self?.finishPreview(attempt, error.localizedDescription) }
        }
    }
    private func finishPreview(_ attempt: UUID, _ message: String?) {
        guard previewAttempt == attempt else { return }
        previewAttempt = nil; player.stop()
        preview = .idle; failure = message; render()
    }
    private func stopPreview() {
        previewAttempt = nil; player.stop()
        guard preview != .idle else { return }
        preview = .idle; render()
    }
}

// MARK: - Recording

/// Reading the script aloud. Stop opens Listen back; it waits for the first 20 seconds, and recording stops by itself at
/// three minutes.
final class VoiceRecordingViewController: CaregiverFormViewController, AVAudioRecorderDelegate {
    private weak var admin: FamilyAdminViewController?
    private var recorder: AVAudioRecorder?
    private var starting = false
    private var discarding = false
    private var ticker: Timer?
    /// Seconds recorded, as the recorder last said.
    private var recorded: TimeInterval = 0
    /// The microphone's level ten times a second, for Listen back's waveform.
    private var levels: [Float] = []
    private var paragraph: Int?
    private let paragraphs = CaregiverVoice.script.map { text -> UILabel in
        let label = UILabel()
        label.text = text; label.numberOfLines = 0
        label.font = PorchStyle.titleFont(21); label.adjustsFontForContentSizeCategory = true
        label.textColor = PorchStyle.ink
        return label
    }
    private let script = UIScrollView()
    private let meter = VoiceLevelMeter()
    private let timer = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let button = VoiceRecordButton()
    private let buttonLabel = PorchStyle.label("Start", size: 15, color: PorchStyle.ink, weight: .semibold)
    private let notice = CaregiverVoice.problem("")

    init(admin: FamilyAdminViewController) { self.admin = admin; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(admin:)") }

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Your voice"
        hideKeyboardControl()
        let intro = PorchStyle.label("Read this aloud, somewhere quiet.", size: 16)
        // The script scrolls inside its card, so Stop stays on screen while it's read.
        let text = UIStackView(arrangedSubviews: paragraphs)
        text.axis = .vertical; text.spacing = 12
        text.translatesAutoresizingMaskIntoConstraints = false
        script.addSubview(text)
        script.alwaysBounceVertical = false
        script.accessibilityIdentifier = "voice.script"
        let card = UIView()
        card.backgroundColor = PorchStyle.surface
        card.layer.cornerRadius = 20; card.clipsToBounds = true
        script.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(script)
        NSLayoutConstraint.activate([
            script.leadingAnchor.constraint(equalTo: card.leadingAnchor), script.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            script.topAnchor.constraint(equalTo: card.topAnchor), script.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        let fits = script.heightAnchor.constraint(lessThanOrEqualTo: text.heightAnchor, constant: 36)
        let readable = script.heightAnchor.constraint(greaterThanOrEqualToConstant: 160); readable.priority = .required - 1
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: script.contentLayoutGuide.topAnchor, constant: 18),
            text.bottomAnchor.constraint(equalTo: script.contentLayoutGuide.bottomAnchor, constant: -18),
            text.leadingAnchor.constraint(equalTo: script.contentLayoutGuide.leadingAnchor, constant: 20),
            text.trailingAnchor.constraint(equalTo: script.contentLayoutGuide.trailingAnchor, constant: -20),
            text.widthAnchor.constraint(equalTo: script.frameLayoutGuide.widthAnchor, constant: -40),
            fits, readable,
        ])
        timer.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: Self.tabular(PorchFonts.sans(34, weight: .semibold)))
        timer.adjustsFontForContentSizeCategory = true
        timer.textColor = PorchStyle.ink; timer.text = CaregiverVoice.clock(0)
        timer.accessibilityIdentifier = "voice.timer"
        progress.progressTintColor = PorchStyle.accent
        progress.trackTintColor = PorchStyle.rgb(0xE6D9C6)
        progress.layer.cornerRadius = 3; progress.clipsToBounds = true
        progress.subviews.forEach { $0.layer.cornerRadius = 3; $0.clipsToBounds = true }
        progress.heightAnchor.constraint(equalToConstant: 6).isActive = true
        progress.isAccessibilityElement = false
        let hint = PorchStyle.label("About a minute", size: 14)
        button.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        buttonLabel.isAccessibilityElement = false
        let controls = UIStackView(arrangedSubviews: [meter, timer, progress, hint, button, buttonLabel])
        controls.axis = .vertical; controls.alignment = .center; controls.spacing = 8
        controls.setCustomSpacing(14, after: hint)
        progress.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        notice.isHidden = true; notice.textAlignment = .center
        let page = UIStackView(arrangedSubviews: [intro, card, controls, notice])
        page.axis = .vertical; page.spacing = 12
        page.setCustomSpacing(16, after: card)
        form.addArrangedSubview(page)
        // The script takes the room the controls leave, down to a few lines; below that the page scrolls instead.
        let fill = form.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -56)
        fill.priority = UILayoutPriority(200); fill.isActive = true
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied { show(Self.microphoneOff) }
        update()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Leaving throws away a recording that's still going.
        if isMovingFromParent || navigationController == nil { cancel() }
    }
    deinit { ticker?.invalidate() }

    static let microphoneOff = "Allow the microphone in Settings → Porch."
    /// Digits that don't shift the timer as they change.
    static func tabular(_ font: UIFont) -> UIFont {
        let settings: [[UIFontDescriptor.FeatureKey: Int]] = [[.type: kNumberSpacingType, .selector: kMonospacedNumbersSelector]]
        return UIFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: settings]), size: 0)
    }

    #if DEBUG
    private var pretending = false
    /// Tests and screenshots: the page `seconds` into a reading, without the microphone.
    func showReading(at seconds: TimeInterval, levels: [CGFloat]) {
        pretending = true; recorded = seconds
        levels.forEach(meter.push)
        update()
    }
    #else
    private let pretending = false
    #endif
    private var isRecording: Bool { recorder != nil || pretending }
    private func toggle() { isRecording ? stop() : start() }
    private func start() {
        guard !isRecording, !starting else { return }
        starting = true; show(nil)
        Task { [weak self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard let self else { return }
            self.starting = false
            guard allowed else { self.show(Self.microphoneOff); return }
            guard !self.discarding else { return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                // AAC in an MPEG-4 container, mono, as voice messages are.
                let recorder = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
                recorder.delegate = self; recorder.isMeteringEnabled = true
                guard recorder.record(forDuration: CaregiverVoice.maximumSeconds) else {
                    recorder.deleteRecording()
                    throw FamilyServiceError(message: "Couldn't start recording. Try again.", status: 0)
                }
                self.recorder = recorder; self.recorded = 0; self.levels = []
                self.ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.tick() } }
                self.update()
            } catch {
                try? FileManager.default.removeItem(at: file)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                self.show(error.localizedDescription)
            }
        }
    }
    private func stop() {
        guard let recorder, recorded >= CaregiverVoice.minimumSeconds else { return }
        recorder.stop()
    }
    private func cancel() {
        discarding = true
        guard let recorder else { return }
        self.recorder = nil; ticker?.invalidate(); ticker = nil
        recorder.stop(); _ = recorder.deleteRecording()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorded = recorder.currentTime
        recorder.updateMeters()
        // About -50 dB is a quiet room; 0 dB is as loud as it gets.
        let level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
        levels.append(level); meter.push(CGFloat(level))
        update()
    }
    private func update() {
        let recording = isRecording
        timer.text = CaregiverVoice.clock(recorded)
        timer.accessibilityLabel = recording ? "Recorded \(CaregiverVoice.clock(recorded))" : nil
        progress.progress = Float(min(1, recorded / CaregiverVoice.targetSeconds))
        button.isRecording = recording
        button.isEnabled = !recording || recorded >= CaregiverVoice.minimumSeconds
        buttonLabel.text = recording ? "Stop" : "Start"
        buttonLabel.alpha = button.isEnabled ? 1 : 0.4
        if !recording { meter.reset() }
        // While recording, the paragraph to read now is dark and the rest are muted.
        let now = recording ? min(paragraphs.count - 1, Int(recorded / CaregiverVoice.paragraphSeconds)) : nil
        guard now != paragraph else { return }
        paragraph = now
        for (index, label) in paragraphs.enumerated() { label.textColor = now == nil || now == index ? PorchStyle.ink : CaregiverVoice.muted }
        if let now { follow(paragraphs[now]) } else { script.setContentOffset(.zero, animated: false) }
    }
    /// Keeps the paragraph being read in view.
    private func follow(_ label: UILabel) {
        script.layoutIfNeeded()
        // In the script's own coordinates, which are its content's.
        let top = label.convert(label.bounds, to: script).minY - 18
        let limit = max(0, script.contentSize.height - script.bounds.height)
        script.setContentOffset(CGPoint(x: 0, y: min(max(0, top), limit)), animated: !pretending)
    }
    private func show(_ text: String?) {
        notice.text = text; notice.isHidden = text == nil
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.finished(recorder, successfully: flag) }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in self?.finished(recorder, successfully: false) }
    }
    private func finished(_ finished: AVAudioRecorder, successfully: Bool) {
        guard finished === recorder else { return }
        ticker?.invalidate(); ticker = nil; recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let file = finished.url
        // The file's own length, which can trail the recorder's count by the encoder's start-up.
        let length = min(CaregiverVoice.maximumSeconds, max(recorded, (try? AVAudioPlayer(contentsOf: file).duration) ?? 0))
        let levels = self.levels
        recorded = 0; self.levels = []; update()
        guard successfully, !discarding, let admin else { try? FileManager.default.removeItem(at: file); return }
        guard length >= CaregiverVoice.minimumSeconds else {
            try? FileManager.default.removeItem(at: file)
            show("Read for at least 20 seconds.")
            return
        }
        navigationController?.pushViewController(VoiceCheckViewController(admin: admin, recording: VoiceRecording(file: file, duration: length, levels: levels)), animated: true)
    }
}

/// A finished reading, waiting on this phone to be listened to and used.
struct VoiceRecording {
    let file: URL
    let duration: TimeInterval
    /// Microphone levels from 0 to 1, ten a second.
    let levels: [Float]
}

// MARK: - Listen back

/// Listening to the reading, agreeing that it's your voice, and making the voice from it.
final class VoiceCheckViewController: CaregiverFormViewController {
    private weak var admin: FamilyAdminViewController?
    private let recording: VoiceRecording
    private let player = VoiceClipPlayer()
    private var ticker: Timer?
    private var consented = false
    private var working = false
    private let play = UIButton(type: .system)
    private let wave: VoiceWaveformView
    private let check = UIImageView()
    private var consentRow: PorchListRow?
    private let use = PorchStyle.button("Use my voice")
    private let again = PorchStyle.button("Record again", filled: false)
    private let notice = CaregiverVoice.problem("")

    init(admin: FamilyAdminViewController, recording: VoiceRecording) {
        self.admin = admin; self.recording = recording
        wave = VoiceWaveformView(levels: recording.levels)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(admin:recording:)") }

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Your voice"
        hideKeyboardControl()
        let heading = UILabel()
        heading.text = "Listen back"; heading.font = PorchStyle.titleFont(27); heading.adjustsFontForContentSizeCategory = true
        heading.textColor = PorchStyle.ink; heading.accessibilityTraits = .header
        var circle = UIButton.Configuration.filled()
        circle.baseBackgroundColor = PorchStyle.ink; circle.baseForegroundColor = .white
        circle.cornerStyle = .capsule
        circle.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        circle.contentInsets = .zero
        play.configuration = circle
        play.accessibilityIdentifier = "voice.play"
        play.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)
        NSLayoutConstraint.activate([play.widthAnchor.constraint(equalToConstant: 44), play.heightAnchor.constraint(equalToConstant: 44)])
        play.setContentHuggingPriority(.required, for: .horizontal)
        let length = FamilyAdminViewController.singleLine(PorchStyle.label(CaregiverVoice.clock(recording.duration.rounded()), size: 16))
        length.accessibilityLabel = "\(CaregiverVoice.clock(recording.duration.rounded())) long"
        let listen = group(rows: [listRow([play, wave, length])])
        check.contentMode = .center
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let agreement = PorchStyle.label("This is my voice. Porch may use it to speak to \(admin?.lovedOne ?? "your loved one").", size: 16, color: PorchStyle.ink)
        let consent = PorchListRow([check, agreement], label: agreement.text ?? "", chevron: false) { [weak self] in self?.toggleConsent() }
        consent.accessibilityIdentifier = "voice.consent"
        consentRow = consent
        use.accessibilityIdentifier = "voice.use"
        use.addAction(UIAction { [weak self] _ in self?.makeVoice() }, for: .touchUpInside)
        again.accessibilityIdentifier = "voice.again"
        again.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        again.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        notice.isHidden = true
        let note = PorchStyle.label("ElevenLabs makes the voice. The recording isn't kept.", size: 14)
        let page = UIStackView(arrangedSubviews: [heading, listen, group(rows: [consent]), notice, use, again, note])
        page.axis = .vertical; page.spacing = 12
        page.setCustomSpacing(4, after: use); page.setCustomSpacing(4, after: again)
        form.addArrangedSubview(page)
        update()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ticker?.invalidate(); ticker = nil
        player.stop(); wave.progress = 0
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        // Record again, Back, or the voice is made: this phone doesn't keep the reading.
        if isMovingFromParent || navigationController == nil { try? FileManager.default.removeItem(at: recording.file) }
    }
    deinit { ticker?.invalidate() }

    private func update() {
        let playing = player.isPlaying
        play.configuration?.image = UIImage(systemName: playing ? "pause.fill" : "play.fill")
        play.accessibilityLabel = playing ? "Pause your recording" : "Play your recording"
        play.isEnabled = !working
        check.image = UIImage(systemName: consented ? "checkmark.square.fill" : "square", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular))
        check.tintColor = consented ? PorchStyle.accent : PorchStyle.secondary
        consentRow?.accessibilityValue = consented ? "Checked" : "Not checked"
        consentRow?.isEnabled = !working
        use.configuration?.title = working ? "Making your voice…" : "Use my voice"
        use.configuration?.showsActivityIndicator = working
        use.isEnabled = consented && !working
        again.isEnabled = !working
        // Leaving now would delete the reading while it uploads.
        navigationItem.hidesBackButton = working
        navigationController?.interactivePopGestureRecognizer?.isEnabled = !working
    }
    private func toggleConsent() {
        guard !working else { return }
        consented.toggle(); update()
    }

    private func togglePlayback() {
        if player.isPlaying { player.pause() }
        else if !player.resume() {
            player.onFinish = { [weak self] in self?.stopPlayback() }
            guard player.start(try? AVAudioPlayer(contentsOf: recording.file)) else { return }
            ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.showProgress() } }
        }
        update()
    }
    private func showProgress() {
        guard player.duration > 0 else { return }
        wave.progress = CGFloat(player.currentTime / player.duration)
    }
    private func stopPlayback() {
        ticker?.invalidate(); ticker = nil
        player.stop(); wave.progress = 0
        if isViewLoaded { update() }
    }

    /// Uploads the reading straight to storage, then asks the server to make the voice, which takes up to half a minute.
    private func makeVoice() {
        guard consented, !working, let admin else { return }
        stopPlayback()
        working = true; notice.isHidden = true; update()
        let recording = recording
        Task { [weak self] in
            do {
                let size = try recording.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let seconds = (recording.duration * 10).rounded() / 10
                guard let created = try await admin.request("voiceUpload", ["contentType": "audio/mp4", "sizeBytes": size, "durationSeconds": seconds]) else { self?.stopWorking(nil); return }
                guard let target = created.upload, let pathname = created.pathname, let url = URL(string: target.url) else {
                    throw FamilyServiceError(message: "Recording a voice isn't available right now.", status: 503)
                }
                var upload = URLRequest(url: url)
                upload.httpMethod = target.method; upload.timeoutInterval = 120
                for (field, value) in target.headers { upload.setValue(value, forHTTPHeaderField: field) }
                let (_, response) = try await URLSession.shared.upload(for: upload, fromFile: recording.file)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else { throw FamilyServiceError(message: "The recording didn't upload. Try again.", status: status, code: "upload") }
                // The server fetches the reading (up to 15 seconds) and ElevenLabs makes the voice (up to 45), within its
                // 60-second limit. Giving up sooner would leave a retry with "Record your voice again."
                guard try await admin.request("createVoice", ["pathname": pathname, "consent": true], timeout: 60) != nil else { self?.stopWorking(nil); return }
                self?.finish()
            } catch { self?.stopWorking(error.localizedDescription) }
        }
    }
    private func stopWorking(_ message: String?) {
        working = false
        notice.text = message; notice.isHidden = message == nil
        update()
    }
    /// The voice is made and chosen: back to the Voice page, which shows it.
    private func finish() {
        working = false; update()
        try? FileManager.default.removeItem(at: recording.file)
        guard let navigation = navigationController else { return }
        if let voice = navigation.viewControllers.last(where: { $0 is VoiceSettingsViewController }) { navigation.popToViewController(voice, animated: true) }
        else { navigation.popViewController(animated: true) }
    }
}

// MARK: - Pieces

/// Plays a short clip on this phone: a voice's preview, or a reading to listen back to. It shares the audio session
/// with calls, as the bedside's announcements do.
@MainActor final class VoiceClipPlayer: NSObject, AVAudioPlayerDelegate {
    static let unavailable = FamilyServiceError(message: "Couldn't play the preview. Try again.", status: 502)
    private var player: AVAudioPlayer?
    private var session: SessionRequirementHandle?
    /// Called once a clip plays to its end.
    var onFinish: (() -> Void)?
    var isPlaying: Bool { player?.isPlaying == true }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    /// Starts a clip from the beginning; false when it can't play.
    func start(_ audio: AVAudioPlayer?) -> Bool {
        stop()
        guard let audio else { return false }
        do { session = try AudioManager.shared.audioSession.acquire(requirement: .playbackOnly) } catch { return false }
        audio.delegate = self; audio.prepareToPlay()
        guard audio.play() else { stop(); return false }
        player = audio
        return true
    }
    func pause() { player?.pause() }
    /// Carries on from a pause; false when there's nothing to carry on with.
    func resume() -> Bool { player.map { $0.play() } ?? false }
    func stop() {
        player?.stop(); player = nil
        try? session?.release(); session = nil
    }
    /// A clip from its short-lived link. Announcements are a sentence or two.
    static func download(_ url: URL) async throws -> Data {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty, data.count <= 2_000_000 else { throw unavailable }
        return data
    }
    private func finished(_ audio: AVAudioPlayer) {
        guard player === audio else { return }
        stop(); onFinish?()
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.finished(player) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.finished(player) }
    }
}

/// The big round button: a red dot to start, a red square to stop.
final class VoiceRecordButton: UIControl {
    private let mark = UIView()
    private var markSize: [NSLayoutConstraint] = []
    var isRecording = false { didSet { update() } }
    init() {
        super.init(frame: .zero)
        // An ink ring: a paper circle on an ink one.
        backgroundColor = PorchStyle.ink
        layer.cornerRadius = 38
        let face = UIView()
        face.backgroundColor = PorchStyle.surface
        face.layer.cornerRadius = 34
        mark.backgroundColor = PorchStyle.danger
        for view in [face, mark] { view.isUserInteractionEnabled = false; view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        markSize = [mark.widthAnchor.constraint(equalToConstant: 56), mark.heightAnchor.constraint(equalToConstant: 56)]
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 76), heightAnchor.constraint(equalToConstant: 76),
            face.widthAnchor.constraint(equalToConstant: 68), face.heightAnchor.constraint(equalToConstant: 68),
            face.centerXAnchor.constraint(equalTo: centerXAnchor), face.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.centerXAnchor.constraint(equalTo: centerXAnchor), mark.centerYAnchor.constraint(equalTo: centerYAnchor),
        ] + markSize)
        isAccessibilityElement = true
        accessibilityIdentifier = "voice.recordButton"
        update()
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    override var isEnabled: Bool { didSet { update() } }
    override var isHighlighted: Bool { didSet { update() } }
    private func update() {
        let side: CGFloat = isRecording ? 28 : 56
        markSize.forEach { $0.constant = side }
        mark.layer.cornerRadius = isRecording ? 7 : 28
        alpha = !isEnabled ? 0.4 : isHighlighted ? 0.7 : 1
        accessibilityLabel = isRecording ? "Stop recording" : "Start recording"
        accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
    }
}

/// How loud the microphone has been over the last couple of seconds, newest on the right.
final class VoiceLevelMeter: UIView {
    private static let bars = 17
    private var bars: [UIView] = []
    private var heights: [NSLayoutConstraint] = []
    private var levels = Array(repeating: CGFloat(0), count: VoiceLevelMeter.bars)
    private var active = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        let stack = UIStackView(); stack.spacing = 4; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<Self.bars {
            let bar = UIView(); bar.layer.cornerRadius = 2.5
            let height = bar.heightAnchor.constraint(equalToConstant: 6)
            NSLayoutConstraint.activate([bar.widthAnchor.constraint(equalToConstant: 5), height])
            bars.append(bar); heights.append(height); stack.addArrangedSubview(bar)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor), heightAnchor.constraint(equalToConstant: 40),
        ])
        apply()
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func push(_ level: CGFloat) { levels.removeFirst(); levels.append(level); active = true; apply() }
    func reset() { levels = Array(repeating: 0, count: Self.bars); active = false; apply() }
    private func apply() {
        for (index, bar) in bars.enumerated() {
            heights[index].constant = 6 + levels[index] * 34
            bar.backgroundColor = active ? PorchStyle.accent : CaregiverVoice.quiet
        }
    }
}

/// The reading's loudness as bars, the part played so far in ink.
final class VoiceWaveformView: UIView {
    private static let bars = 28
    private let shape: [CGFloat]
    var progress: CGFloat = 0 { didSet { setNeedsDisplay() } }
    init(levels: [Float]) {
        // How loud each slice of the reading was on average, against the loudest slice.
        if levels.count >= Self.bars {
            let slice = Double(levels.count) / Double(Self.bars)
            let averages = (0..<Self.bars).map { bar -> CGFloat in
                let start = Int(Double(bar) * slice), end = min(levels.count, max(start + 1, Int(Double(bar + 1) * slice)))
                return CGFloat(levels[start..<end].reduce(0, +)) / CGFloat(end - start)
            }
            let loudest = max(averages.max() ?? 0, 0.01)
            shape = averages.map { $0 / loudest }
        } else {
            shape = (0..<Self.bars).map { CGFloat(0.35 + 0.3 * sin(Double($0) * 1.7)) }
        }
        super.init(frame: .zero)
        isOpaque = false; contentMode = .redraw
        isAccessibilityElement = false
        heightAnchor.constraint(equalToConstant: 34).isActive = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("Use init(levels:)") }
    override func draw(_ rect: CGRect) {
        let gap: CGFloat = 2, count = CGFloat(Self.bars)
        let width = max(1, (bounds.width - gap * (count - 1)) / count)
        for (index, level) in shape.enumerated() {
            let height = max(4, bounds.height * min(1, max(0.15, level)))
            let x = CGFloat(index) * (width + gap)
            (CGFloat(index) / count < progress ? PorchStyle.ink : CaregiverVoice.quiet).setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: (bounds.height - height) / 2, width: width, height: height), cornerRadius: 1).fill()
        }
    }
}
