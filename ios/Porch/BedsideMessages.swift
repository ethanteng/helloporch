import UIKit
import AVFoundation
import LiveKit
import PorchCore
import Vision

extension Notification.Name {
    static let porchMessagesReady = Notification.Name("porch.messages.ready")
    static let porchMessageAutoplayChanged = Notification.Name("porch.messages.autoplay")
}

/// Keeps waiting family messages downloaded on the bedside iPad, so they play instantly and
/// without a connection, and reports delivery and playback to the sender.
@MainActor final class BedsideMessages: NSObject {
    static let shared = BedsideMessages()
    /// Downloaded messages that haven't been played, oldest first.
    private(set) var ready: [FamilyMessage] = []
    private var downloading = Set<String>()
    private var retryAfter: [String: Date] = [:]
    /// Played here; hidden at once even before the server confirms.
    private var played = Set<String>()
    private var unreported = Set<String>()
    private var releasing = Set<String>()
    private var started = false
    private let folder = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        .appendingPathComponent("PorchMessages", isDirectory: true)

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(self, selector: #selector(sync), name: .porchFamilyChanged, object: nil)
        sync()
    }
    func file(for message: FamilyMessage) -> URL { folder.appendingPathComponent("\(message.id).\(message.fileExtension)") }

    @objc func sync() {
        guard PorchDevice.experience == .bedside, let credential = PorchDevice.credential(for: .bedside),
              let state = FamilyCoordinator.shared.state, state.me.role == .bedside else { return }
        let all = state.messages ?? []
        played.formIntersection(Set(all.map(\.id))); unreported.formIntersection(Set(all.map(\.id))); releasing.formIntersection(Set(all.map(\.id)))
        // Phone voicemail plays only once it's released: by a caregiver, or here when the phone
        // company verified the caller and the number is saved on the keypad. Others wait for a caregiver.
        let slots: CallSlots? = all.contains(where: { $0.held == true }) ? (try? CallSlots.load()) : nil
        for message in all where message.held == true && message.callerVerified == true && !releasing.contains(message.id)
            && slots?.contact(forPhoneNumber: message.callerNumber) != nil {
            releaseKnownCaller(message, credential: credential)
        }
        let waiting = all.filter { $0.held != true }
        let queue = waiting.filter { !played.contains($0.id) }.sorted { $0.sentAt < $1.sentAt }
        // Removed, expired and played messages leave the iPad too.
        let keep = Set(queue.map { file(for: $0).lastPathComponent })
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        let nowReady = queue.filter { FileManager.default.fileExists(atPath: file(for: $0).path) }
        if nowReady != ready { ready = nowReady; NotificationCenter.default.post(name: .porchMessagesReady, object: self) }
        for id in unreported { report(id, credential: credential) }
        // Don't compete with a call for bandwidth.
        guard !state.busy else { return }
        for message in queue where !downloading.contains(message.id) && !FileManager.default.fileExists(atPath: file(for: message).path)
            && (retryAfter[message.id] ?? .distantPast) < Date() {
            download(message, credential: credential)
        }
    }

    private func download(_ message: FamilyMessage, credential: FamilyCredential) {
        downloading.insert(message.id)
        Task { [weak self] in
            do {
                guard let media = try await FamilyService(credential).send("messageMedia", ["messageID": message.id]).media,
                      let url = URL(string: media.url) else { throw FamilyServiceError(message: "Missing message link.", status: 0) }
                let (temporary, response) = try await URLSession.shared.download(from: url)
                guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                    throw FamilyServiceError(message: "Couldn't download the message.", status: (response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                guard let self else { return }
                try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
                let destination = self.file(for: message)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
                self.downloading.remove(message.id)
                _ = try? await FamilyService(credential).send("messageDelivered", ["messageID": message.id])
                self.sync()
            } catch {
                self?.downloading.remove(message.id)
                self?.retryAfter[message.id] = Date().addingTimeInterval(60)
            }
        }
    }

    private func releaseKnownCaller(_ message: FamilyMessage, credential: FamilyCredential) {
        releasing.insert(message.id)
        Task { [weak self] in
            // The next poll carries it as released; after a failure, a later sync tries again.
            do { _ = try await FamilyService(credential).send("releaseKnownCaller", ["messageID": message.id]) }
            catch { self?.releasing.remove(message.id) }
        }
    }

    /// Who a message is from, as the bedside shows and speaks it: the keypad contact's name
    /// first, then the family member's name, or the caller's number for phone voicemail. A phone
    /// caller borrows a contact's name and photo only when the caller ID was verified.
    static func sender(of message: FamilyMessage, slots: CallSlots) -> (name: String, contact: CallContact?) {
        let contact = message.fromPhone ? (message.callerVerified == true ? slots.contact(forPhoneNumber: message.callerNumber) : nil)
            : slots.contacts.compactMap { $0 }.first { $0.familyMemberID == message.from }
        if let contact { return (contact.name, contact) }
        guard message.fromPhone else { return (message.fromName, nil) }
        return (message.callerNumber.map { PhoneNumberNormalization.display($0) } ?? BedsideText.string("Unknown caller"), nil)
    }

    /// Played to the end: the message leaves the queue for good (the sender sees it was played).
    func markPlayed(_ message: FamilyMessage) {
        played.insert(message.id)
        guard let credential = PorchDevice.credential(for: .bedside) else { return }
        report(message.id, credential: credential)
        sync()
    }
    private func report(_ id: String, credential: FamilyCredential) {
        unreported.remove(id)
        Task { [weak self] in
            do { _ = try await FamilyService(credential).send("messagePlayed", ["messageID": id]) }
            catch { self?.unreported.insert(id) }
        }
    }
}

/// A chime, then who the message is from and when, in the bedside language and voice. A natural clip
/// gets a few seconds to arrive, since nothing is counting down; otherwise the built-in voice speaks.
@MainActor final class MessageAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    private let tone = PorchTonePlayer()
    private let clip = PorchClipPlayer()
    private let speech = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var announcement: UUID?
    private var completion: (() -> Void)?
    private var timers: [Timer] = []
    private var watchdog: Timer?

    override init() { super.init(); speech.delegate = self; speech.usesApplicationAudioSession = true }
    func announce(_ text: String, completion: @escaping () -> Void) {
        stop()
        self.completion = completion
        if PorchTonePlayer.isSilentPreview { finish(); return }
        tone.play(.announcement)
        let language = BedsideText.language
        let naturalVoice = PorchNaturalVoice.selected(for: language)
        let voice = PorchAnnouncementVoice.resolve(for: language, identifier: BedsidePreferences.load().announcementVoiceIdentifier(for: language))
        guard voice != nil || naturalVoice != nil else {
            // No voice for this language: the screen still shows who it's from.
            timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.finish() } })
            return
        }
        utterance = voice.map { voice in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            return utterance
        }
        let announcement = UUID(); self.announcement = announcement
        timers.append(Timer.scheduledTimer(withTimeInterval: CallTone.announcement.duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                var ready: URL?
                if let naturalVoice { ready = await PorchNaturalVoice.clip(text, language: language, voiceID: naturalVoice, within: 3) }
                guard let self, self.announcement == announcement else { return }
                if let ready, self.clip.play(ready, completion: { [weak self] success in
                    guard let self, self.announcement == announcement else { return }
                    if success { self.finish() } else { PorchNaturalVoice.discard(ready); self.speakBuiltIn() }
                }) { self.armWatchdog(); return }
                if let ready { PorchNaturalVoice.discard(ready) }
                self.speakBuiltIn()
            }
        })
        // Until speech starts. Fetching a clip must not shorten the sentence, and a stuck speech
        // service must not hold up the message.
        armWatchdog()
    }
    /// 15 seconds from when speech starts, or from the announcement if it never does.
    private func armWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.finish() } }
    }
    private func speakBuiltIn() {
        guard let utterance else { finish(); return }
        armWatchdog()
        speech.speak(utterance)
    }
    func stop() {
        completion = nil; utterance = nil; announcement = nil
        timers.forEach { $0.invalidate() }; timers = []
        watchdog?.invalidate(); watchdog = nil
        speech.stopSpeaking(at: .immediate); clip.stop(); tone.stop()
    }
    private func finish() { let callback = completion; stop(); callback?() }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in if self?.utterance === utterance { self?.finish() } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in if self?.utterance === utterance { self?.finish() } }
    }
}

/// Plays waiting messages one after another until none are left or someone stops it.
/// A message stopped partway stays in the queue; only one played to the end is removed.
final class MessagePlayerViewController: UIViewController {
    var onFinish: (() -> Void)?
    private var queue: [FamilyMessage]
    private let slots: CallSlots
    private var current: FamilyMessage?
    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private let videoView = UIView()
    private let identity = UIStackView()
    private var photo = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    /// Who and when, kept on screen over a playing video.
    private let banner = UILabel()
    private let bannerView = UIView()
    private let stopButton = PorchStyle.button("Stop", symbol: "stop.fill")
    private let announcer = MessageAnnouncer()
    private var session: SessionRequirementHandle?
    private var observers: [NSObjectProtocol] = []
    private var keypad = CallTrigger()
    private var ended = false
    /// An incoming call took over. That is not Stop, so whatever is still waiting can start on its own afterward.
    private(set) var interrupted = false

    override var canBecomeFirstResponder: Bool { true }
    override var prefersStatusBarHidden: Bool { true }

    init(messages: [FamilyMessage], slots: CallSlots) {
        queue = messages; self.slots = slots
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen; isModalInPresentation = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(messages:slots:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark; view.backgroundColor = PorchStyle.night
        videoView.translatesAutoresizingMaskIntoConstraints = false; videoView.isHidden = true
        playerLayer.videoGravity = .resizeAspect
        videoView.layer.addSublayer(playerLayer)
        view.addSubview(videoView)
        nameLabel.font = PorchStyle.font(48, weight: .semibold); nameLabel.textColor = PorchStyle.nightText
        detailLabel.font = PorchStyle.font(28); detailLabel.textColor = PorchStyle.nightSecondary
        for label in [nameLabel, detailLabel] { label.textAlignment = .center; label.numberOfLines = 0; label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.5 }
        identity.axis = .vertical; identity.spacing = 20; identity.alignment = .center
        identity.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(identity)
        bannerView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        bannerView.layer.cornerRadius = 24; bannerView.layer.cornerCurve = .continuous
        bannerView.isHidden = true; bannerView.translatesAutoresizingMaskIntoConstraints = false
        banner.font = PorchStyle.font(30, weight: .semibold); banner.textColor = .white
        banner.textAlignment = .center; banner.numberOfLines = 2; banner.adjustsFontSizeToFitWidth = true; banner.minimumScaleFactor = 0.6
        banner.accessibilityIdentifier = "messages.banner"
        banner.translatesAutoresizingMaskIntoConstraints = false
        bannerView.addSubview(banner)
        view.addSubview(bannerView)
        var config = stopButton.configuration!
        config.title = BedsideText.string("Stop")
        config.baseBackgroundColor = UIColor(red: 0.68, green: 0.19, blue: 0.19, alpha: 1)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(36, weight: .semibold); return attributes
        }
        config.contentInsets = .init(top: 24, leading: 48, bottom: 24, trailing: 48)
        stopButton.configuration = config
        stopButton.accessibilityIdentifier = "messages.stop"
        stopButton.addTarget(self, action: #selector(stop), for: .touchUpInside)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stopButton)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor), videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: view.topAnchor), videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            identity.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            identity.centerYAnchor.constraint(equalTo: guide.centerYAnchor, constant: -60),
            identity.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 32),
            identity.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -32),
            bannerView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 24),
            bannerView.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            bannerView.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 32),
            bannerView.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -32),
            banner.topAnchor.constraint(equalTo: bannerView.topAnchor, constant: 14),
            banner.bottomAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: -14),
            banner.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 28),
            banner.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -28),
            stopButton.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            stopButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -36),
            stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        })
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); playerLayer.frame = videoView.bounds }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keypad.resetKeys(); becomeFirstResponder()
        guard current == nil, !ended else { return }
        // Share the audio session with calls; releasing it never interrupts one.
        session = try? AudioManager.shared.audioSession.acquire(requirement: .playbackOnly)
        playNext()
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); tearDown(); resignFirstResponder() }

    private func playNext() {
        guard !ended else { return }
        guard !queue.isEmpty else { close(); return }
        let message = queue.removeFirst()
        let file = BedsideMessages.shared.file(for: message)
        guard FileManager.default.fileExists(atPath: file.path) else { playNext(); return }
        current = message
        let (name, contact) = BedsideMessages.sender(of: message, slots: slots)
        let sent = MessagePlayerViewController.sentText(message.sentAt)
        nameLabel.text = BedsideText.string(message.kind == "voicemail" ? "Voicemail from %@" : "Message from %@", name)
        detailLabel.text = BedsideText.string("Sent %@", sent)
        banner.text = "\(nameLabel.text ?? "") · \(detailLabel.text ?? "")"
        identity.arrangedSubviews.forEach { identity.removeArrangedSubview($0); $0.removeFromSuperview() }
        // Someone without a keypad number still shows the photo Porch has for them.
        let photoData = contact?.photoData ?? (message.fromPhone ? nil : FamilyPhotos.shared.photo(forMember: message.from))
        if RecipientAppearance.photo(photoData) != nil {
            photo = RecipientAppearance.photoView(photoData)
            photo.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([photo.widthAnchor.constraint(equalToConstant: 240), photo.heightAnchor.constraint(equalToConstant: 240)])
            identity.addArrangedSubview(photo)
        }
        identity.addArrangedSubview(nameLabel); identity.addArrangedSubview(detailLabel)
        identity.isHidden = false; videoView.isHidden = true; bannerView.isHidden = true
        BedsideText.applyAccessibilityLanguage(to: view)
        announcer.announce(Self.announcement(for: message, slots: slots)) { [weak self] in
            self?.play(message, file: file)
        }
    }
    private func play(_ message: FamilyMessage, file: URL) {
        guard !ended, current?.id == message.id else { return }
        let item = AVPlayerItem(url: file)
        let player = AVPlayer(playerItem: item)
        playerLayer.player = player
        if message.mode == "video" { identity.isHidden = true; videoView.isHidden = false; bannerView.isHidden = false }
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.completed(message) }
        })
        // A file that can't play is skipped and stays queued for the caregiver to review.
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self, self.current?.id == message.id else { return }; self.current = nil; self.playNext() }
        })
        self.player = player
        player.play()
    }
    private func completed(_ message: FamilyMessage) {
        guard !ended, current?.id == message.id else { return }
        current = nil
        BedsideMessages.shared.markPlayed(message)
        playNext()
    }
    /// What the bedside says before playing a message.
    static func announcement(for message: FamilyMessage, slots: CallSlots) -> String {
        BedsideText.string(message.kind == "voicemail" ? "Voicemail from %@. Sent %@." : "Message from %@. Sent %@.", BedsideMessages.sender(of: message, slots: slots).name, sentText(message.sentAt))
    }
    static func sentText(_ sentAt: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = BedsideText.language.locale
        formatter.doesRelativeDateFormatting = true; formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: sentAt))
    }

    private func tearDown() {
        announcer.stop()
        player?.pause(); player = nil; playerLayer.player = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        try? session?.release(); session = nil
    }
    /// Stopping early leaves the current message queued to play another time.
    @objc func stop() { close() }
    /// Closes at once for something more important, such as an incoming call.
    func interrupt(then next: @escaping () -> Void) {
        interrupted = true
        close(animated: false, then: next)
    }
    private func close(animated: Bool = true, then next: (() -> Void)? = nil) {
        guard !ended else { next?(); return }
        ended = true; tearDown()
        let finished = onFinish
        if presentingViewController != nil { dismiss(animated: animated) { finished?(); next?() } } else { finished?(); next?() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let digit = CallTrigger.slot(for: Int(key.keyCode.rawValue)),
                  key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty else { unhandled.insert(press); continue }
            // The messages key stops playback, and so does the hang-up key people already know.
            let action = (try? CallSlots.load())?.action(for: digit)
            if keypad.keyDown(Int(key.keyCode.rawValue)), action == .messages || action == .callControl { stop() }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { keypad.keyUp(Int(key.keyCode.rawValue)) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        keypad.resetKeys(); super.pressesCancelled(presses, with: event)
    }
}

extension MessagePlayerViewController: Cell2JackDigitReceiving {
    func receiveCell2JackDigit(_ digit: Int) -> String {
        let action = (try? CallSlots.load())?.action(for: digit)
        guard action == .messages || action == .callControl else { return "message key ignored" }
        stop(); return "message playback stopped"
    }
}

/// The microphone, or the front camera and microphone, for one message from the bedside.
/// Recording stops on its own at two minutes. A recording without any sound isn't kept.
@MainActor final class BedsideMessageRecorder: NSObject, AVAudioRecorderDelegate, AVCaptureFileOutputRecordingDelegate {
    private(set) var video: Bool
    let previewLayer = AVCaptureVideoPreviewLayer()
    /// The finished recording, or nil when nothing worth sending was recorded.
    var onFinish: ((MessageRecording?) -> Void)?
    private var audio: AVAudioRecorder?
    private let capture = AVCaptureSession()
    private let movie = AVCaptureMovieFileOutput()
    private let captureQueue = DispatchQueue(label: "porch.message.capture")
    private var rotation: NSObject?
    private var rotationObservation: NSKeyValueObservation?
    private var file: URL?
    private var startedAt: Date?
    private var heard = 0
    private var discarding = false
    var isRecording: Bool { startedAt != nil }
    var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }
    /// Something louder than a quiet room was picked up, such as someone speaking.
    var heardSound: Bool { heard >= 2 }

    init(video: Bool) { self.video = video; super.init() }

    struct RecorderError: LocalizedError { var errorDescription: String? { "Couldn't record a message." } }

    /// Asks for access and sets up the input. Video shows its preview from here on, and becomes
    /// audio when the camera isn't available.
    func prepare() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RecorderError() }
        if video, await AVCaptureDevice.requestAccess(for: .video),
           let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let microphone = AVCaptureDevice.default(for: .audio) {
            try configureVideo(camera: camera, microphone: microphone)
            let session = capture
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in captureQueue.async { session.startRunning(); done.resume() } }
        } else {
            video = false
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("bedside-message-\(UUID().uuidString).m4a")
            let recorder = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
            recorder.delegate = self; recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else { throw RecorderError() }
            audio = recorder; self.file = file
        }
    }

    private func configureVideo(camera: AVCaptureDevice, microphone: AVCaptureDevice) throws {
        capture.beginConfiguration()
        defer { capture.commitConfiguration() }
        // The audio session belongs to LiveKit's shared handle, so calls and cues stay consistent.
        capture.automaticallyConfiguresApplicationAudioSession = false
        // About the size of a family phone's video message, so two minutes stays well under the limit.
        capture.sessionPreset = capture.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
        for input in [try AVCaptureDeviceInput(device: camera), try AVCaptureDeviceInput(device: microphone)] {
            guard capture.canAddInput(input) else { throw RecorderError() }
            capture.addInput(input)
        }
        guard capture.canAddOutput(movie) else { throw RecorderError() }
        capture.addOutput(movie)
        movie.maxRecordedDuration = CMTime(seconds: CallPreferences.messageSeconds, preferredTimescale: 600)
        previewLayer.session = capture
        previewLayer.videoGravity = .resizeAspectFill
        if #available(iOS 17.0, *) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)
            rotation = coordinator
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                Task { @MainActor [weak self] in
                    guard let connection = self?.previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
                    connection.videoRotationAngle = angle
                }
            }
        }
    }

    /// Before iOS 17, the preview and recording follow the screen's orientation.
    func orient(_ orientation: UIInterfaceOrientation) {
        if #available(iOS 17.0, *) { return }
        let value: AVCaptureVideoOrientation
        switch orientation {
        case .landscapeLeft: value = .landscapeLeft
        case .landscapeRight: value = .landscapeRight
        case .portraitUpsideDown: value = .portraitUpsideDown
        default: value = .portrait
        }
        previewLayer.connection?.videoOrientation = value
        if !movie.isRecording { movie.connection(with: .video)?.videoOrientation = value }
    }

    func start(orientation: UIInterfaceOrientation) -> Bool {
        guard !isRecording, !discarding else { return false }
        if video {
            if #available(iOS 17.0, *), let coordinator = rotation as? AVCaptureDevice.RotationCoordinator, let connection = movie.connection(with: .video) {
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            } else { orient(orientation) }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("bedside-message-\(UUID().uuidString).mov")
            self.file = file
            movie.startRecording(to: file, recordingDelegate: self)
        } else {
            guard audio?.record(forDuration: CallPreferences.messageSeconds) == true else { return false }
        }
        startedAt = Date()
        return true
    }

    /// Called a few times a second while recording.
    func sample() {
        guard isRecording else { return }
        let level: Float
        if video { level = movie.connection(with: .audio)?.audioChannels.first?.averagePowerLevel ?? -160 }
        else { audio?.updateMeters(); level = audio?.averagePower(forChannel: 0) ?? -160 }
        if level > -40 { heard += 1 }
    }

    /// Finishes the recording; `onFinish` receives it.
    func stop() {
        guard isRecording else { return }
        if video { movie.stopRecording() } else { audio?.stop() }
    }
    /// Throws the recording away, whether or not it started.
    func cancel() {
        discarding = true; onFinish = nil
        if isRecording { stop() } else { finish(successfully: false) }
    }

    private func finish(successfully: Bool) {
        let duration = min(CallPreferences.messageSeconds, elapsed)
        startedAt = nil; audio = nil; rotationObservation = nil
        let session = capture
        captureQueue.async { if session.isRunning { session.stopRunning() } }
        let callback = onFinish; onFinish = nil
        guard successfully, !discarding, let file, duration >= 2, heardSound else {
            if let file { try? FileManager.default.removeItem(at: file) }
            callback?(nil); return
        }
        callback?(MessageRecording(file: file, mode: video ? "video" : "audio", contentType: video ? "video/quicktime" : "audio/mp4", duration: duration))
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.finish(successfully: flag) }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in self?.finish(successfully: false) }
    }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Reaching the two-minute limit, or an interruption, still leaves a complete file.
        let finished = error == nil || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        Task { @MainActor [weak self] in self?.finish(successfully: finished) }
    }
}

/// Messages the bedside left for family, kept on the iPad until they're sent. Mom goes back to the
/// clock right away, and uploads retry on their own, so a dropped connection doesn't lose a message.
@MainActor final class BedsideOutbox: NSObject {
    static let shared = BedsideOutbox()
    private struct Item: Codable {
        let id: String; let file: String; let to: String; let mode: String; let contentType: String
        let duration: TimeInterval; let createdAt: Date
        var attempts = 0; var retryAt = Date.distantPast
    }
    /// A message that still can't be sent after two days is dropped.
    private static let giveUpSeconds: TimeInterval = 2 * 86400
    private let folder = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        .appendingPathComponent("PorchOutbox", isDirectory: true)
    private var manifest: URL { folder.appendingPathComponent("outbox.json") }
    private var items: [Item] = []
    private var uploaders: [String: MessageUploader] = [:]
    private var sending = false
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        items = ((try? Data(contentsOf: manifest)).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? [])
            .filter { FileManager.default.fileExists(atPath: file(for: $0).path) }
        NotificationCenter.default.addObserver(self, selector: #selector(send), name: .porchFamilyChanged, object: nil)
        send()
    }
    func add(_ recording: MessageRecording, to memberID: String) throws {
        start()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        let name = "\(id).\(recording.file.pathExtension)"
        try FileManager.default.moveItem(at: recording.file, to: folder.appendingPathComponent(name))
        items.append(Item(id: id, file: name, to: memberID, mode: recording.mode, contentType: recording.contentType, duration: recording.duration, createdAt: Date()))
        save(); send()
    }
    private func file(for item: Item) -> URL { folder.appendingPathComponent(item.file) }
    private func save() { try? JSONEncoder().encode(items).write(to: manifest, options: .atomic) }

    /// Sends the next message that's due, one at a time. Runs again after each bedside poll.
    @objc private func send() {
        guard !sending, PorchDevice.experience == .bedside, let credential = PorchDevice.credential(for: .bedside),
              // Don't compete with a call for bandwidth.
              FamilyCoordinator.shared.state?.busy != true,
              let item = items.first(where: { $0.retryAt <= Date() }) else { return }
        sending = true
        let uploader = uploaders[item.id] ?? MessageUploader()
        uploaders[item.id] = uploader
        let recording = MessageRecording(file: file(for: item), mode: item.mode, contentType: item.contentType, duration: item.duration)
        Task { [weak self] in
            var failure: Error?
            do { _ = try await uploader.send(recording, kind: "voicemail", credential: credential, to: item.to) } catch { failure = error }
            self?.finished(item, failure)
        }
    }
    private func finished(_ item: Item, _ failure: Error?) {
        sending = false
        let error = failure as? FamilyServiceError
        // Sent, or refused for good: the person no longer has access, or the recording can't be accepted.
        let refused = error?.code != "upload" && [400, 401, 403, 404, 413].contains(error?.status ?? 0)
        if failure == nil || refused || item.createdAt.addingTimeInterval(Self.giveUpSeconds) < Date() {
            try? FileManager.default.removeItem(at: file(for: item))
            items.removeAll { $0.id == item.id }; uploaders[item.id] = nil
        } else if let index = items.firstIndex(where: { $0.id == item.id }) {
            // An expired or rejected upload starts over with a new message.
            if error?.code == "upload" || error?.status == 409 { uploaders[item.id] = nil }
            items[index].attempts += 1
            items[index].retryAt = Date().addingTimeInterval(min(900, 15 * pow(2, Double(items[index].attempts - 1))))
        }
        save(); send()
    }
}

/// After a Porch call isn't answered, records a message for that person the way a phone's voicemail
/// does: a spoken prompt, a beep, then up to two minutes of audio or video, matching the call.
/// Finishing (the button, the hang-up key or the time limit) sends it. Saying nothing sends nothing.
final class BedsideVoicemailViewController: UIViewController {
    enum Reason: CaseIterable {
        case unanswered, unavailable
        /// What the bedside says before recording a message for this person.
        func prompt(for name: String) -> String {
            BedsideText.string(self == .unanswered ? "%@ didn't answer. Please leave a message after the beep." : "%@ isn't available right now. Please leave a message after the beep.", name)
        }
    }
    var onFinish: (() -> Void)?
    private let contact: CallContact
    private let memberID: String
    private let reason: Reason
    private let recorder: BedsideMessageRecorder
    private let staticPreview: Bool
    private let announcer = MessageAnnouncer()
    private let beep = PorchTonePlayer()
    private var session: SessionRequirementHandle?
    private enum Phase { case starting, prompting, recording, stopping, done }
    private var phase = Phase.starting
    private var timer: Timer?
    private var keypad = CallTrigger()
    private var observers: [NSObjectProtocol] = []
    private var closing: (() -> Void)?
    private var dismissed = false

    private let previewView = UIView()
    private let panel = UIStackView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let timerLabel = UILabel()
    private let recordingDot = UIImageView(image: UIImage(systemName: "record.circle.fill"))
    private lazy var timerRow = UIStackView(arrangedSubviews: [recordingDot, timerLabel])
    /// Their photo, or a microphone, while recording audio. Video shows the camera instead.
    private lazy var identity: UIImageView = RecipientAppearance.photo(contact.photoData) != nil
        ? RecipientAppearance.photoView(contact.photoData) : UIImageView(image: UIImage(systemName: "mic.fill"))
    private let hintLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let controls = UIStackView()
    private lazy var centered = panel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -60)
    private lazy var atTop = panel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)

    override var canBecomeFirstResponder: Bool { true }
    override var prefersStatusBarHidden: Bool { true }

    init(contact: CallContact, memberID: String, mode: NativeCall.Mode, reason: Reason, staticPreview: Bool = false) {
        self.contact = contact; self.memberID = memberID; self.reason = reason; self.staticPreview = staticPreview
        recorder = BedsideMessageRecorder(video: mode == .video)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen; isModalInPresentation = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(contact:memberID:mode:reason:)") }

    private var reasonText: String { BedsideText.string(reason == .unanswered ? "%@ didn't answer." : "%@ isn't available right now.", contact.name) }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark; view.backgroundColor = PorchStyle.night
        let large = UIDevice.current.userInterfaceIdiom == .pad
        previewView.layer.addSublayer(recorder.previewLayer)
        previewView.isHidden = true; previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.accessibilityLabel = BedsideText.string("Your camera preview")
        view.addSubview(previewView)
        titleLabel.text = BedsideText.string("Leave a message for %@", contact.name)
        titleLabel.font = PorchStyle.font(large ? 60 : 36, weight: .semibold)
        statusLabel.text = "\(reasonText)\n\(BedsideText.string("Speak after the beep."))"
        statusLabel.font = PorchStyle.font(large ? 38 : 26)
        timerLabel.font = .monospacedDigitSystemFont(ofSize: large ? 64 : 44, weight: .semibold)
        hintLabel.font = PorchStyle.font(large ? 32 : 22)
        for label in [titleLabel, statusLabel, timerLabel, hintLabel] {
            label.textColor = label === hintLabel ? PorchStyle.nightSecondary : PorchStyle.nightText
            label.textAlignment = .center; label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = true
        }
        statusLabel.accessibilityTraits.insert(.updatesFrequently)
        recordingDot.tintColor = .systemRed
        recordingDot.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: large ? 48 : 32)
        timerRow.spacing = 12; timerRow.alignment = .center
        timerRow.isHidden = true
        if RecipientAppearance.photo(contact.photoData) != nil {
            identity.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([identity.widthAnchor.constraint(equalToConstant: large ? 240 : 160), identity.heightAnchor.constraint(equalTo: identity.widthAnchor)])
        } else {
            identity.tintColor = PorchStyle.nightText
            identity.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: large ? 120 : 80)
            identity.contentMode = .scaleAspectFit
        }
        panel.axis = .vertical; panel.spacing = 16; panel.alignment = .center
        for subview in [titleLabel, statusLabel, timerRow, identity] { panel.addArrangedSubview(subview) }
        panel.setCustomSpacing(32, after: timerRow)
        panel.isLayoutMarginsRelativeArrangement = true
        panel.directionalLayoutMargins = .init(top: 20, leading: 24, bottom: 20, trailing: 24)
        panel.layer.cornerRadius = 24; panel.layer.cornerCurve = .continuous
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        configure(sendButton, title: "Send message", symbol: "paperplane.fill", color: UIColor(red: 0.18, green: 0.5, blue: 0.34, alpha: 1), size: large ? 40 : 28)
        configure(cancelButton, title: "Don't send", symbol: "xmark", color: PorchStyle.nightSurface, size: large ? 40 : 28)
        sendButton.accessibilityIdentifier = "voicemail.send"; cancelButton.accessibilityIdentifier = "voicemail.cancel"
        sendButton.isEnabled = false
        sendButton.addAction(UIAction { [weak self] _ in self?.finish(send: true) }, for: .touchUpInside)
        cancelButton.addAction(UIAction { [weak self] _ in self?.finish(send: false) }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [cancelButton, sendButton])
        buttons.spacing = 16; buttons.distribution = .fillEqually
        [hintLabel, buttons].forEach { controls.addArrangedSubview($0) }
        controls.axis = .vertical; controls.spacing = 12
        controls.layer.cornerRadius = 24; controls.layer.cornerCurve = .continuous
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        let slots = (try? CallSlots.load()) ?? CallSlots()
        hintLabel.text = slots.digit(for: .callControl).map { BedsideText.string("Press %d when you're finished.", $0) }
        hintLabel.isHidden = hintLabel.text == nil

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor), previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor), previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.topAnchor.constraint(greaterThanOrEqualTo: guide.topAnchor, constant: 24),
            panel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 860),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: controls.topAnchor, constant: -24),
            controls.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            controls.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            controls.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -32),
            sendButton.heightAnchor.constraint(greaterThanOrEqualToConstant: large ? 112 : 80),
        ])
        centered.priority = .defaultHigh; centered.isActive = true
        BedsideText.applyAccessibilityLanguage(to: view)
        #if DEBUG
        if staticPreview {
            phase = .recording; sendButton.isEnabled = true; timerRow.isHidden = false
            statusLabel.text = BedsideText.string("Recording your message…"); timerLabel.text = "0:12 / 2:00"
            if recorder.video { previewView.backgroundColor = PorchStyle.nightSecondary; showCamera() }
            return
        }
        #endif
        // Like a call, the message ends when Porch leaves the screen; what was said is still sent.
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.interrupt(then: {}) }
        })
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        recorder.previewLayer.frame = previewView.bounds
        if let orientation = view.window?.windowScene?.interfaceOrientation { recorder.orient(orientation) }
    }

    /// Video shows Mom her camera, with the text at the top and the controls on dark panels, like a video call.
    private func showCamera() {
        previewView.isHidden = false; identity.isHidden = true
        for overlay in [panel, controls] { overlay.backgroundColor = UIColor.black.withAlphaComponent(0.65) }
        controls.isLayoutMarginsRelativeArrangement = true
        controls.directionalLayoutMargins = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
        centered.isActive = false; atTop.isActive = true
        view.setNeedsLayout()
    }

    private func configure(_ button: UIButton, title: String, symbol: String, color: UIColor, size: CGFloat) {
        var config = UIButton.Configuration.filled()
        config.title = BedsideText.string(title)
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 12
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: size * 0.8)
        config.baseBackgroundColor = color; config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = .init(top: 20, leading: 20, bottom: 20, trailing: 20)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(size, weight: .semibold); return attributes
        }
        button.configuration = config
        button.titleLabel?.numberOfLines = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keypad.resetKeys(); becomeFirstResponder()
        guard phase == .starting, !staticPreview else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                // Speech, the beep and recording share LiveKit's session; releasing it never interrupts a call.
                self.session = try AudioManager.shared.audioSession.acquire(requirement: .playbackAndRecording)
                try await self.recorder.prepare()
            } catch {
                self.complete(BedsideText.string("Couldn't record a message.")); return
            }
            guard self.phase == .starting else { self.recorder.cancel(); return }
            if self.recorder.video { self.showCamera() }
            self.phase = .prompting
            self.announcer.announce(self.reason.prompt(for: self.contact.name)) { [weak self] in self?.beepThenRecord() }
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); resignFirstResponder() }

    private func beepThenRecord() {
        guard phase == .prompting else { return }
        beep.play(.beep)
        _ = Timer.scheduledTimer(withTimeInterval: CallTone.beep.duration + 0.1, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.record() }
        }
    }
    private func record() {
        guard phase == .prompting else { return }
        recorder.onFinish = { [weak self] recording in self?.recorded(recording) }
        guard recorder.start(orientation: view.window?.windowScene?.interfaceOrientation ?? .landscapeRight) else {
            complete(BedsideText.string("Couldn't record a message.")); return
        }
        phase = .recording
        sendButton.isEnabled = true
        statusLabel.text = BedsideText.string("Recording your message…")
        timerRow.isHidden = false
        updateTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recorder.sample(); self?.updateTimer() }
        }
    }
    private func updateTimer() {
        let seconds = Int(min(CallPreferences.messageSeconds, recorder.elapsed))
        timerLabel.text = String(format: "%d:%02d / %d:%02d", seconds / 60, seconds % 60, Int(CallPreferences.messageSeconds) / 60, Int(CallPreferences.messageSeconds) % 60)
    }

    /// Sending keeps what was recorded; before the beep, or with Don't send, nothing is kept.
    private func finish(send: Bool) {
        switch phase {
        case .starting, .prompting:
            phase = .done; announcer.stop(); beep.stop(); recorder.cancel()
            complete(BedsideText.string("Message not sent."))
        case .recording:
            phase = .stopping; timer?.invalidate(); sendButton.isEnabled = false; cancelButton.isEnabled = false
            if send { recorder.stop() } else { recorder.cancel(); complete(BedsideText.string("Message not sent.")) }
        case .stopping, .done: break
        }
    }
    private func recorded(_ recording: MessageRecording?) {
        guard phase != .done else { return }
        phase = .done; timer?.invalidate()
        guard let recording else { complete(BedsideText.string("No message was recorded.")); return }
        do {
            try BedsideOutbox.shared.add(recording, to: memberID)
            complete(BedsideText.string("Your message is on its way to %@.", contact.name), speak: true)
        } catch {
            try? FileManager.default.removeItem(at: recording.file)
            complete(BedsideText.string("Couldn't record a message."))
        }
    }
    /// Shows (and for a sent message, says) how it ended, then returns to the clock.
    private func complete(_ text: String, speak: Bool = false) {
        phase = .done; timer?.invalidate()
        sendButton.isEnabled = false; cancelButton.isEnabled = false
        statusLabel.text = text
        timerRow.isHidden = true
        if let next = closing { closing = nil; close(animated: false, then: next); return }
        let later = { [weak self] in
            _ = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.close() } }
        }
        if speak { announcer.announce(text, completion: later) } else { later() }
    }
    /// Closes at once for an incoming call or leaving Porch, keeping anything already said.
    func interrupt(then next: @escaping () -> Void) {
        switch phase {
        case .recording, .stopping:
            closing = next
            if phase == .recording { finish(send: true) }
            // The call mustn't wait on a recorder that never reports back.
            _ = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let next = self.closing else { return }
                    self.closing = nil; self.phase = .done; self.close(animated: false, then: next)
                }
            }
        case .starting, .prompting: phase = .done; announcer.stop(); beep.stop(); recorder.cancel(); close(animated: false, then: next)
        case .done: close(animated: false, then: next)
        }
    }
    private func close(animated: Bool = true, then next: (() -> Void)? = nil) {
        guard !dismissed else { next?(); return }
        dismissed = true
        timer?.invalidate(); announcer.stop(); beep.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        try? session?.release(); session = nil
        let finished = onFinish
        if presentingViewController != nil { dismiss(animated: animated) { finished?(); next?() } } else { finished?(); next?() }
    }

    /// The hang-up key finishes the message, as hanging up does on a phone: before the beep, nothing is sent.
    fileprivate func finishFromKeypad() { finish(send: true) }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let digit = CallTrigger.slot(for: Int(key.keyCode.rawValue)),
                  key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty else { unhandled.insert(press); continue }
            if keypad.keyDown(Int(key.keyCode.rawValue)), (try? CallSlots.load())?.action(for: digit) == .callControl { finishFromKeypad() }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { keypad.keyUp(Int(key.keyCode.rawValue)) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        keypad.resetKeys(); super.pressesCancelled(presses, with: event)
    }
}

extension BedsideVoicemailViewController: Cell2JackDigitReceiving {
    func receiveCell2JackDigit(_ digit: Int) -> String {
        guard (try? CallSlots.load())?.action(for: digit) == .callControl else { return "message key ignored" }
        finishFromKeypad(); return "message finished"
    }
}

/// Notices someone sitting in front of the bedside iPad: the front camera runs at a low rate and
/// Apple's on-device face detection looks at a few frames a second. Nothing is recorded, kept or sent.
/// Callers run it only while messages are waiting and stop it before anything else uses the camera.
final class BedsidePresence: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on the main thread once someone has been in front of the iPad for a couple of seconds.
    var onPresent: (() -> Void)?
    /// Main-thread state.
    private(set) var running = false
    // Starting, stopping and setup happen on the session queue; frames are analyzed on the video
    // queue, so waiting for a stop never holds up frame delivery.
    private let sessionQueue = DispatchQueue(label: "porch.presence.session")
    private let videoQueue = DispatchQueue(label: "porch.presence.video")
    private let session = AVCaptureSession()
    private var connection: AVCaptureConnection?
    private var configured = false
    private var trigger = PresenceTrigger()
    private var lastAnalysis: TimeInterval = 0
    private let faces = VNDetectFaceRectanglesRequest()
    /// Main-thread count of session-queue jobs. Start and stop bounce to the main thread, so a
    /// caller must not block on this queue waiting for them.
    private var sessionJobs = 0
    /// Invalidates a failed start's "not running" callback once a newer start or a stop has begun.
    private var startToken = 0

    deinit {
        let capture = session
        sessionQueue.async { if capture.isRunning { capture.stopRunning() } }
    }

    /// Starts watching, or keeps watching with the iPad's current orientation.
    func start(orientation: UIInterfaceOrientation) {
        dispatchPrecondition(condition: .onQueue(.main))
        // Permission revoked while watching: stop, instead of leaving the camera running.
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { stop(); return }
        if !running { videoQueue.async { [self] in trigger.reset(); lastAnalysis = 0 } }
        running = true
        startToken += 1
        let token = startToken
        enqueueSession { [self] in
            if !configured { configured = configure() }
            guard configured else {
                DispatchQueue.main.async { if self.startToken == token { self.running = false } }
                return
            }
            // Upright frames, whichever way the iPad is standing, including after it's turned.
            if let connection, connection.isVideoOrientationSupported {
                switch orientation {
                case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                case .landscapeRight: connection.videoOrientation = .landscapeRight
                default: connection.videoOrientation = .portrait
                }
            }
            if !session.isRunning { session.startRunning() }
        }
    }
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        startToken += 1
        guard running else { return }
        running = false
        enqueueSession { [self] in if session.isRunning { session.stopRunning() } }
    }
    /// Stops if needed, then calls `done` on the main thread once the camera is free.
    /// Never blocks: start and stop can synchronously need the main thread, so waiting
    /// for them there deadlocks (a call or the player would freeze while the camera stops).
    func stopThen(_ done: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        startToken += 1
        running = false
        if sessionJobs == 0, !session.isRunning { done(); return }
        sessionJobs += 1
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async {
                self.sessionJobs -= 1
                done()
            }
        }
    }
    private func enqueueSession(_ work: @escaping () -> Void) {
        sessionJobs += 1
        sessionQueue.async { [self] in
            work()
            DispatchQueue.main.async { self.sessionJobs -= 1 }
        }
    }
    private func configure() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }
        session.beginConfiguration(); defer { session.commitConfiguration() }
        // Video only. LiveKit owns the shared audio session; taking it over cuts off the spoken notice and calls.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .low
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input); session.addOutput(output)
        connection = output.connection(with: .video)
        return true
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        // About three looks a second is plenty, and keeps the iPad cool.
        guard time - lastAnalysis >= 0.3, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = time
        guard (try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([faces])) != nil else { return }
        let largest = (faces.results ?? []).map { Double($0.boundingBox.height) }.max()
        if trigger.observe(faceHeight: largest, at: time) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.onPresent?()
            }
        }
    }
}

/// The glow and spoken notice when someone sits down in front of the iPad with messages waiting.
/// When the notice finishes, playback starts; Not now (or the messages or call key) waits instead.
final class MessageNoticeView: UIView {
    var onNotNow: (() -> Void)?
    var onFinished: (() -> Void)?
    private let text: String
    private let glow = UIView()
    private let messageLabel = UILabel()
    private let announcer = MessageAnnouncer()
    private var session: SessionRequirementHandle?
    private var ended = false
    private static let warm = UIColor(red: 1, green: 0.74, blue: 0.32, alpha: 1)

    init(count: Int) {
        text = count == 1 ? BedsideText.string("You have 1 new message.") : BedsideText.string("You have %d new messages.", count)
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        accessibilityViewIsModal = true
        glow.isUserInteractionEnabled = false
        glow.layer.borderColor = Self.warm.cgColor; glow.layer.borderWidth = 16
        glow.layer.shadowColor = Self.warm.cgColor; glow.layer.shadowRadius = 36; glow.layer.shadowOpacity = 1; glow.layer.shadowOffset = .zero
        let icon = UIImageView(image: UIImage(systemName: "envelope.open.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 72, weight: .semibold)))
        icon.tintColor = Self.warm; icon.contentMode = .scaleAspectFit; icon.isAccessibilityElement = false
        messageLabel.text = text; messageLabel.font = PorchStyle.font(44, weight: .semibold); messageLabel.textColor = PorchStyle.nightText
        messageLabel.textAlignment = .center; messageLabel.numberOfLines = 0; messageLabel.adjustsFontSizeToFitWidth = true; messageLabel.minimumScaleFactor = 0.5
        messageLabel.accessibilityIdentifier = "messages.notice"
        let notNowButton = PorchStyle.button(BedsideText.string("Not now"), symbol: "xmark")
        notNowButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes); attributes.font = PorchStyle.font(32, weight: .semibold); return attributes
        }
        notNowButton.configuration?.contentInsets = .init(top: 20, leading: 40, bottom: 20, trailing: 40)
        notNowButton.configuration?.baseBackgroundColor = UIColor(white: 0.32, alpha: 1)
        notNowButton.configuration?.baseForegroundColor = .white
        notNowButton.accessibilityIdentifier = "messages.notNow"
        notNowButton.addAction(UIAction { [weak self] _ in self?.notNow() }, for: .touchUpInside)
        let card = UIStackView(arrangedSubviews: [icon, messageLabel, notNowButton])
        card.axis = .vertical; card.spacing = 28; card.alignment = .center
        card.isLayoutMarginsRelativeArrangement = true; card.directionalLayoutMargins = .init(top: 40, leading: 48, bottom: 40, trailing: 48)
        card.backgroundColor = PorchStyle.night.withAlphaComponent(0.94); card.layer.cornerRadius = 32; card.layer.cornerCurve = .continuous
        for view in [glow, card] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            glow.leadingAnchor.constraint(equalTo: leadingAnchor), glow.trailingAnchor.constraint(equalTo: trailingAnchor),
            glow.topAnchor.constraint(equalTo: topAnchor), glow.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor), card.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 32),
            card.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -32),
            notNowButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 88)
        ])
        BedsideText.applyAccessibilityLanguage(to: self)
    }
    required init?(coder: NSCoder) { fatalError("Use init(count:)") }

    func begin() {
        if !UIAccessibility.isReduceMotionEnabled {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1; pulse.toValue = 0.3; pulse.duration = 0.9
            pulse.autoreverses = true; pulse.repeatCount = .infinity
            glow.layer.add(pulse, forKey: "pulse")
        }
        UIAccessibility.post(notification: .screenChanged, argument: messageLabel)
        session = try? AudioManager.shared.audioSession.acquire(requirement: .playbackOnly)
        announcer.announce(text) { [weak self] in
            guard let self, !self.ended else { return }
            self.end(); self.onFinished?()
        }
    }
    func notNow() {
        guard !ended else { return }
        end(); onNotNow?()
    }
    /// Removes the notice without starting anything, for example when a call arrives.
    func end() {
        guard !ended else { return }
        ended = true
        announcer.stop(); glow.layer.removeAllAnimations()
        try? session?.release(); session = nil
        removeFromSuperview()
    }
}
