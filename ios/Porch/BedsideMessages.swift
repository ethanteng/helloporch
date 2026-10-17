import UIKit
import AVFoundation
import LiveKit
import PorchCore

extension Notification.Name {
    static let porchMessagesReady = Notification.Name("porch.messages.ready")
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
        // Phone voicemail plays only once it's released: by a caregiver, or here when the
        // caller's number is saved on the keypad. Unknown callers wait for a caregiver.
        let slots: CallSlots? = all.contains(where: { $0.held == true }) ? (try? CallSlots.load()) : nil
        for message in all where message.held == true && !releasing.contains(message.id) && slots?.contact(forPhoneNumber: message.callerNumber) != nil {
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
    /// first, then the family member's name, or the caller's number for phone voicemail.
    static func sender(of message: FamilyMessage, slots: CallSlots) -> (name: String, contact: CallContact?) {
        let contact = message.fromPhone ? slots.contact(forPhoneNumber: message.callerNumber)
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

/// A chime, then who the message is from and when, in the bedside language and voice.
@MainActor final class MessageAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    private let tone = PorchTonePlayer()
    private let speech = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var completion: (() -> Void)?
    private var timers: [Timer] = []

    override init() { super.init(); speech.delegate = self; speech.usesApplicationAudioSession = true }
    func announce(_ text: String, completion: @escaping () -> Void) {
        stop()
        self.completion = completion
        if PorchTonePlayer.isSilentPreview { finish(); return }
        tone.play(.announcement)
        let language = BedsideText.language
        guard let voice = PorchAnnouncementVoice.resolve(for: language, identifier: BedsidePreferences.load().announcementVoiceIdentifier(for: language)) else {
            // No voice for this language: the screen still shows who it's from.
            timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.finish() } })
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        self.utterance = utterance
        timers.append(Timer.scheduledTimer(withTimeInterval: CallTone.announcement.duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self, let utterance = self.utterance else { return }; self.speech.speak(utterance) }
        })
        // A stuck speech service must not hold up the message.
        timers.append(Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.finish() } })
    }
    func stop() {
        completion = nil; utterance = nil
        timers.forEach { $0.invalidate() }; timers = []
        speech.stopSpeaking(at: .immediate); tone.stop()
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
        if RecipientAppearance.photo(contact?.photoData) != nil {
            photo = RecipientAppearance.photoView(contact?.photoData)
            photo.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([photo.widthAnchor.constraint(equalToConstant: 240), photo.heightAnchor.constraint(equalToConstant: 240)])
            identity.addArrangedSubview(photo)
        }
        identity.addArrangedSubview(nameLabel); identity.addArrangedSubview(detailLabel)
        identity.isHidden = false; videoView.isHidden = true; bannerView.isHidden = true
        BedsideText.applyAccessibilityLanguage(to: view)
        announcer.announce(BedsideText.string(message.kind == "voicemail" ? "Voicemail from %@. Sent %@." : "Message from %@. Sent %@.", name, sent)) { [weak self] in
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
    func interrupt(then next: @escaping () -> Void) { close(animated: false, then: next) }
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
