import UIKit
import AVFoundation
import AVKit
import AudioToolbox
import UserNotifications
import PorchCore

struct MessageRecording { let file: URL; let mode: String; let contentType: String; let duration: TimeInterval; var poster: UIImage? = nil }

/// Preview frames for video messages. Saved on this phone when a video is sent, or made
/// once from the stored video (reading only the start of it) and kept by message ID.
enum MessagePosters {
    private static let folder = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        .appendingPathComponent("PorchMessagePosters", isDirectory: true)
    private static func file(_ id: String) -> URL { folder.appendingPathComponent("\(id).jpg") }
    static func cached(_ id: String) -> UIImage? { UIImage(contentsOfFile: file(id).path) }
    static func save(_ image: UIImage, for id: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(id), options: .atomic)
    }
    static func frame(from url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = .positiveInfinity; generator.requestedTimeToleranceAfter = .positiveInfinity
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0.5, preferredTimescale: 600))]) { _, image, _, _, _ in
                _ = generator // Kept alive until the frame is ready.
                continuation.resume(returning: image.map { UIImage(cgImage: $0) })
            }
        }
    }
}

/// A video message's preview frame, with a play symbol when it can be watched.
final class MessagePosterView: UIControl {
    private let imageView = UIImageView()
    var image: UIImage? { get { imageView.image } set { imageView.image = newValue } }
    init(image: UIImage?, playable: Bool) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemFill
        layer.cornerRadius = 16; layer.cornerCurve = .continuous; clipsToBounds = true
        imageView.image = image; imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let glyph = UIImageView(image: UIImage(systemName: "play.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 56)))
        glyph.tintColor = .white; glyph.isHidden = !playable; glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.layer.shadowColor = UIColor.black.cgColor; glyph.layer.shadowOpacity = 0.4; glyph.layer.shadowRadius = 6; glyph.layer.shadowOffset = .zero
        addSubview(imageView); addSubview(glyph)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor), imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor), imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor), glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 200)
        ])
        isEnabled = playable
        isAccessibilityElement = true
        accessibilityLabel = playable ? "Play video message" : "Video message preview"
        accessibilityTraits = playable ? .button : .image
    }
    required init?(coder: NSCoder) { fatalError("Use init(image:playable:)") }
}

/// Plays a message: a stored one from a short-lived signed link, or a recording before it's sent.
@MainActor func playMessage(from url: URL, on presenter: UIViewController) {
    try? AVAudioSession.sharedInstance().setCategory(.playback)
    let player = AVPlayerViewController(); player.player = AVPlayer(url: url)
    presenter.present(player, animated: true) { player.player?.play() }
}

/// Sends a recording: the server signs a one-time upload URL and the file goes straight to storage.
/// A retry reuses the same message, so a dropped connection doesn't use up another queue slot.
@MainActor final class MessageUploader {
    private var pending: (file: URL, message: SentMessage, target: MessageUploadTarget, uploaded: Bool)?

    /// `to` names the family member a bedside message is for; family devices always send to the bedside.
    func send(_ recording: MessageRecording, kind: String, credential: FamilyCredential, to recipient: String? = nil) async throws -> SentMessage {
        let service = FamilyService(credential)
        if pending?.file != recording.file || (pending?.uploaded == false && (pending?.target.expiresAt ?? 0) < Date().timeIntervalSince1970 + 60) {
            let size = try recording.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            var values: [String: Any] = ["mode": recording.mode, "kind": kind, "contentType": recording.contentType, "sizeBytes": size, "durationSeconds": max(1, recording.duration)]
            if let recipient { values["to"] = recipient }
            let created = try await service.send("createMessage", values)
            guard let message = created.message, let target = created.upload else { throw FamilyServiceError(message: "Couldn't send the message. Try again.", status: 503) }
            pending = (recording.file, message, target, false)
        }
        guard let current = pending, let url = URL(string: current.target.url) else { throw FamilyServiceError(message: "Couldn't send the message. Try again.", status: 503) }
        // The signed URL never overwrites, so a finished upload is only completed on retry.
        if !current.uploaded {
            var request = URLRequest(url: url)
            request.httpMethod = current.target.method; request.timeoutInterval = 600
            for (field, value) in current.target.headers { request.setValue(value, forHTTPHeaderField: field) }
            let (_, response) = try await URLSession.shared.upload(for: request, fromFile: recording.file)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw FamilyServiceError(message: "The upload didn't finish. Check the connection and try again.", status: status, code: "upload") }
            pending?.uploaded = true
        }
        let sent = try await service.send("completeMessage", ["messageID": current.message.id]).message ?? current.message
        pending = nil
        return sent
    }
}

/// Records an audio or video message (up to two minutes) for the bedside device and sends it.
final class MessageComposerViewController: CaregiverFormViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, AVAudioRecorderDelegate {
    private enum Phase: Equatable { case idle, recordingAudio, recorded, sending }
    private let recipient: String
    private let kind: String
    private let startAudioImmediately: Bool
    private let content = UIStackView()
    private let uploader = MessageUploader()
    private var phase = Phase.idle
    private var recording: MessageRecording?
    private var recorder: AVAudioRecorder?
    private var recordStarted = Date()
    private var recordTimer: Timer?
    private var startedAutomatically = false
    private let timerLabel = PorchStyle.label("", size: 28, color: PorchStyle.ink, weight: .semibold)

    init(recipient: String, kind: String = "message", startAudioImmediately: Bool = false) {
        self.recipient = recipient; self.kind = kind; self.startAudioImmediately = startAudioImmediately
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(recipient:kind:startAudioImmediately:)") }

    override func viewDidLoad() {
        super.viewDidLoad(); title = kind == "voicemail" ? "Leave a message" : "Send a message"
        content.axis = .vertical; content.spacing = 20
        timerLabel.textAlignment = .center
        form.addArrangedSubview(content)
        hideKeyboardControl()
        render()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if startAudioImmediately && !startedAutomatically { startedAutomatically = true; startAudio() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            recordTimer?.invalidate(); recorder?.stop(); _ = recorder?.deleteRecording()
            if let file = recording?.file, phase != .sending { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func render() {
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        switch phase {
        case .idle:
            let video = PorchStyle.button("Record a video", symbol: "video.fill")
            video.addAction(UIAction { [weak self] _ in self?.startVideo() }, for: .touchUpInside)
            video.isEnabled = UIImagePickerController.isSourceTypeAvailable(.camera)
            let audio = PorchStyle.button("Record audio", symbol: "mic.fill", filled: kind == "voicemail")
            audio.addAction(UIAction { [weak self] _ in self?.startAudio() }, for: .touchUpInside)
            content.addArrangedSubview(section("Message for \(recipient)", detail: "Up to two minutes. It waits on their Porch until they play it.", views: kind == "voicemail" ? [audio, video] : [video, audio]))
        case .recordingAudio:
            let stop = PorchStyle.button("Stop recording", symbol: "stop.fill")
            stop.addAction(UIAction { [weak self] _ in self?.recorder?.stop() }, for: .touchUpInside)
            updateTimer()
            content.addArrangedSubview(section("Recording for \(recipient)…", detail: "Speak after the beep. You have two minutes.", views: [timerLabel, stop]))
        case .recorded, .sending:
            let sending = phase == .sending
            let play = PorchStyle.button("Play it back", symbol: "play.fill", filled: false)
            play.addAction(UIAction { [weak self] _ in self?.preview() }, for: .touchUpInside)
            let send = PorchStyle.button(sending ? "Sending…" : "Send to \(recipient)", symbol: "paperplane.fill")
            send.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
            let again = PorchStyle.button("Record again", symbol: "arrow.counterclockwise", filled: false)
            again.addAction(UIAction { [weak self] _ in self?.discard() }, for: .touchUpInside)
            [play, send, again].forEach { $0.isEnabled = !sending }
            let length = recording.map { duration($0.duration) } ?? ""
            var views: [UIView] = [play, send, again]
            if recording?.mode == "video" {
                let poster = MessagePosterView(image: recording?.poster, playable: !sending)
                poster.addAction(UIAction { [weak self] _ in self?.preview() }, for: .touchUpInside)
                views.insert(poster, at: 0)
            }
            content.addArrangedSubview(section(recording?.mode == "video" ? "Video message · \(length)" : "Audio message · \(length)", detail: sending ? "Keep Porch open until it finishes sending." : nil, views: views))
        }
    }
    private func duration(_ seconds: TimeInterval) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    private func updateTimer() { timerLabel.text = "\(duration(Date().timeIntervalSince(recordStarted))) / 2:00" }

    private func startAudio() {
        guard phase == .idle else { return }
        Task { [weak self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard let self else { return }
            guard allowed else { showPorchError(FamilyServiceError(message: "Allow microphone access in iPhone Settings → Porch to record a message.", status: 403), on: self); return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("message-\(UUID().uuidString).m4a")
                let recorder = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
                recorder.delegate = self
                // The beep marks the start, like a voicemail greeting.
                AudioServicesPlaySystemSound(1113)
                try await Task.sleep(nanoseconds: 700_000_000)
                guard recorder.record(forDuration: 120) else { throw FamilyServiceError(message: "Couldn't start recording. Try again.", status: 0) }
                self.recorder = recorder; self.recordStarted = Date(); self.phase = .recordingAudio; self.render()
                self.recordTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.updateTimer() } }
            } catch { showPorchError(error, on: self) }
        }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.finishedAudio(recorder, successfully: flag) }
    }
    private func finishedAudio(_ finished: AVAudioRecorder, successfully: Bool) {
        guard finished === recorder else { return }
        recordTimer?.invalidate(); recordTimer = nil; recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let length = Date().timeIntervalSince(recordStarted)
        guard successfully, length >= 1 else { _ = finished.deleteRecording(); phase = .idle; render(); return }
        recording = MessageRecording(file: finished.url, mode: "audio", contentType: "audio/mp4", duration: min(120, length))
        phase = .recorded; render()
    }

    private func startVideo() {
        guard phase == .idle, UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        Task { [weak self] in
            let camera = await AVCaptureDevice.requestAccess(for: .video)
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            guard let self else { return }
            guard camera && microphone else { showPorchError(FamilyServiceError(message: "Allow camera and microphone access in iPhone Settings → Porch to record a video message.", status: 403), on: self); return }
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.mediaTypes = ["public.movie"]
            picker.cameraCaptureMode = .video
            if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
            picker.videoMaximumDuration = 120
            picker.videoQuality = .typeMedium
            picker.delegate = self
            self.present(picker, animated: true)
        }
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let source = info[.mediaURL] as? URL else { return }
        // Copy out of the picker's folder, which the system may clear.
        let ext = source.pathExtension.lowercased() == "mp4" ? "mp4" : "mov"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("message-\(UUID().uuidString).\(ext)")
        do { try FileManager.default.copyItem(at: source, to: file) } catch { showPorchError(error, on: self); return }
        let seconds = CMTimeGetSeconds(AVURLAsset(url: file).duration)
        recording = MessageRecording(file: file, mode: "video", contentType: ext == "mp4" ? "video/mp4" : "video/quicktime", duration: seconds.isFinite ? min(120, seconds) : 1)
        phase = .recorded; render()
        Task { [weak self] in
            let poster = await MessagePosters.frame(from: file)
            guard let self, self.recording?.file == file else { return }
            self.recording?.poster = poster; self.render()
        }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }

    /// Audio and video use the same on-screen player as Listen again, so playing it back always shows something.
    private func preview() {
        guard let recording else { return }
        playMessage(from: recording.file, on: self)
    }
    private func discard() {
        if let file = recording?.file { try? FileManager.default.removeItem(at: file) }
        recording = nil; phase = .idle; render()
    }
    private func send() {
        guard let recording, phase == .recorded, let credential = PorchDevice.credential(for: .family) else { return }
        phase = .sending; render()
        Task { [weak self] in
            guard let self else { return }
            do {
                let sent = try await self.uploader.send(recording, kind: self.kind, credential: credential)
                if let poster = self.recording?.poster ?? recording.poster { MessagePosters.save(poster, for: sent.id) }
                try? FileManager.default.removeItem(at: recording.file)
                self.recording = nil; self.phase = .idle
                let done = UIAlertController(title: "Message sent", message: "It's waiting on \(self.recipient)'s Porch. See when it's played in Messages with \(self.recipient).", preferredStyle: .alert)
                done.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.navigationController?.popViewController(animated: true) })
                self.present(done, animated: true)
            } catch {
                self.phase = .recorded; self.render()
                showPorchError(error, on: self)
            }
        }
    }
}

enum MessageText {
    static func when(_ time: TimeInterval?) -> String {
        guard let time else { return "" }
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true; formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: time))
    }
    static func length(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
    /// The time alone, for a message under its day's heading.
    static func time(_ time: TimeInterval) -> String {
        DateFormatter.localizedString(from: Date(timeIntervalSince1970: time), dateStyle: .none, timeStyle: .short)
    }
    /// When a message was played, short enough for its tag: "today at 4:02 PM", "Oct 25 at 6:04 PM".
    static func played(_ time: TimeInterval?) -> String {
        guard let time else { return "" }
        let date = Date(timeIntervalSince1970: time), calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "MMMdy")
        let day = calendar.isDateInToday(date) ? "today" : calendar.isDateInYesterday(date) ? "yesterday" : formatter.string(from: date)
        return "\(day) at \(self.time(time))"
    }
    /// Today, Yesterday, or the weekday and date, over that day's messages.
    static func day(_ time: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: time), calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "EEEEMMMMd" : "EEEEMMMMdy")
        return formatter.string(from: date)
    }
}

/// Whether a message has been played, shown as a colored tag under it rather than words in a sentence.
struct MessageStatus {
    enum Tone { case new, played, waiting, ended, failed }
    let text: String
    let symbol: String
    let tone: Tone
    /// More about it, when there's more to say.
    var note: String? = nil

    static func sent(_ message: SentMessage, to name: String) -> MessageStatus {
        switch message.state {
        case "uploading": return MessageStatus(text: "Still sending", symbol: "arrow.up.circle", tone: .waiting, note: "Keep Porch open until it finishes.")
        case "queued": return MessageStatus(text: "Not played yet", symbol: "clock", tone: .waiting, note: message.deliveredAt != nil ? "Waiting on \(name)'s Porch." : "Waiting for \(name)'s Porch to download it.")
        case "played": return MessageStatus(text: "Played \(MessageText.played(message.playedAt))", symbol: "checkmark.circle.fill", tone: .played, note: message.replayable == true ? nil : "The recording was deleted after 90 days.")
        case "expired": return MessageStatus(text: "Never played", symbol: "xmark.circle", tone: .ended, note: "Not played within a week, so it was removed.")
        case "removed": return MessageStatus(text: "Removed by a caregiver", symbol: "minus.circle", tone: .ended)
        case "unsent": return MessageStatus(text: "You unsent it", symbol: "arrow.uturn.backward.circle", tone: .ended)
        default: return MessageStatus(text: "Didn't send", symbol: "exclamationmark.circle", tone: .failed, note: "This message didn't finish sending.")
        }
    }
    static func received(_ message: ReceivedMessage) -> MessageStatus {
        switch message.state {
        case "queued": return message.available ? MessageStatus(text: "New", symbol: "circle.fill", tone: .new)
            : MessageStatus(text: "Never played", symbol: "xmark.circle", tone: .ended, note: "It was deleted after 90 days.")
        case "played": return MessageStatus(text: "Played \(MessageText.played(message.playedAt))", symbol: "checkmark.circle.fill", tone: .played, note: message.available ? nil : "The recording was deleted after 90 days.")
        default: return MessageStatus(text: "Never played", symbol: "xmark.circle", tone: .ended, note: "Not played within 90 days, so it was deleted.")
        }
    }

    /// The tag itself: filled for new, green once played, amber while it waits, gray once it's gone.
    func tag() -> UIButton {
        let colors: (foreground: UIColor, background: UIColor)
        switch tone {
        case .new: colors = (.white, PorchStyle.accent)
        case .played: colors = (PorchStyle.accent, PorchStyle.accent.withAlphaComponent(0.12))
        case .waiting: colors = (UIColor(red: 0.52, green: 0.32, blue: 0, alpha: 1), UIColor(red: 0.98, green: 0.74, blue: 0.24, alpha: 0.26))
        case .ended: colors = (PorchStyle.secondary, PorchStyle.border.withAlphaComponent(0.45))
        case .failed: colors = (UIColor(red: 0.68, green: 0.13, blue: 0.1, alpha: 1), UIColor.systemRed.withAlphaComponent(0.12))
        }
        var config = UIButton.Configuration.filled()
        config.title = text
        config.image = UIImage(systemName: symbol); config.imagePadding = 6
        // New is a small dot, like an unheard voicemail.
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: tone == .new ? 8 : 13, weight: .bold)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes; attributes.font = PorchStyle.font(15, weight: .semibold); return attributes
        }
        config.cornerStyle = .capsule
        config.contentInsets = .init(top: 6, leading: 10, bottom: 6, trailing: 12)
        config.baseForegroundColor = colors.foreground; config.baseBackgroundColor = colors.background
        // Large text wraps rather than cutting off the time.
        config.titleLineBreakMode = .byWordWrapping
        let tag = UIButton(configuration: config)
        tag.titleLabel?.numberOfLines = 0
        // The bubble above reads it out.
        tag.isUserInteractionEnabled = false; tag.isAccessibilityElement = false
        return tag
    }
}

/// One message in the thread; tapping it plays the message. This phone's own are green.
final class MessageBubble: UIControl {
    private(set) var poster: MessagePosterView?
    private var labels: [UILabel] = []
    init(mine: Bool, title: String, length: String, video: Bool, poster image: UIImage?, showsPoster: Bool, playable: Bool, new: Bool) {
        super.init(frame: .zero)
        let ink = mine ? UIColor.white : PorchStyle.ink
        backgroundColor = mine ? PorchStyle.accent : PorchStyle.surface
        layer.cornerRadius = 22; layer.cornerCurve = .continuous
        if !mine { layer.borderWidth = new ? 2 : 1; layer.borderColor = (new ? PorchStyle.accent : PorchStyle.border).cgColor }
        let icon = UIImageView(image: UIImage(systemName: video ? "video.fill" : playable ? "play.circle.fill" : "waveform", withConfiguration: UIImage.SymbolConfiguration(pointSize: video ? 22 : 34)))
        icon.tintColor = ink
        icon.setContentHuggingPriority(.required, for: .horizontal); icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        labels = [PorchStyle.label(title, size: 17, color: ink, weight: .semibold), PorchStyle.label(length, size: 15, color: ink.withAlphaComponent(0.8))]
        let words = UIStackView(arrangedSubviews: labels)
        words.axis = .vertical; words.spacing = 2
        let line = UIStackView(arrangedSubviews: [icon, words])
        line.spacing = 12; line.alignment = .center
        let stack = UIStackView(arrangedSubviews: [line])
        stack.axis = .vertical; stack.spacing = 12
        if showsPoster {
            let poster = MessagePosterView(image: image, playable: playable)
            poster.layer.cornerRadius = 12
            stack.insertArrangedSubview(poster, at: 0); self.poster = poster
        }
        // Taps anywhere in the bubble play it.
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        isEnabled = playable
        isAccessibilityElement = true
        accessibilityTraits = playable ? .button : .staticText
    }
    required init?(coder: NSCoder) { fatalError("Use init(mine:title:length:video:poster:showsPoster:playable:new:)") }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.7 : 1 } }
    /// Beside the icon, the words only get their width after a layout pass, so with large text they'd cut off
    /// instead of wrapping. Wrapping at that width makes the bubble grow on the next pass.
    override func layoutSubviews() {
        super.layoutSubviews()
        for label in labels where label.bounds.width > 0 && label.preferredMaxLayoutWidth != label.bounds.width {
            label.preferredMaxLayoutWidth = label.bounds.width
        }
    }
}

/// Messages between this phone and the bedside in one thread, oldest first like a text conversation: theirs
/// on the left, this phone's own on the right, each tagged with whether it's been played. Others' messages
/// to the bedside aren't shown. Playing one of theirs marks it played; each can be played again while the
/// recording is kept (90 days).
final class MessageThreadViewController: CaregiverFormViewController {
    private enum Entry {
        case sent(SentMessage), received(ReceivedMessage)
        var id: String { switch self { case .sent(let message): return message.id; case .received(let message): return message.id } }
        var time: TimeInterval { switch self { case .sent(let message): return message.sentAt ?? message.createdAt; case .received(let message): return message.sentAt } }
        /// One of theirs that hasn't been played.
        var isNew: Bool { if case .received(let message) = self { return message.state == "queued" && message.available }; return false }
        var mediaAction: String { if case .received = self { return "receivedMessageMedia" }; return "sentMessageMedia" }
    }
    private let list = UIStackView()
    private let record = PorchStyle.button("Record a message", symbol: "mic.fill")
    private let footer = PorchStyle.label("", size: 15)
    private var loading = false
    private var opening = false
    private var posterTask: Task<Void, Never>?
    /// The bedside's name, from the family snapshot or their messages, whichever loads first.
    private var loadedName: String?
    /// The messages last shown, so a reload keeps the place and moves to one that's just arrived.
    private var shown: [String]?
    private var unplayed: Int?
    /// A reload asked for while one was loading.
    private var reloadQueued = false
    /// The refresh button was tapped, so a failed load is reported rather than left for the next poll.
    private var reportFailure = false
    private var name: String {
        let state = FamilyCoordinator.shared.state
        return state?.people.first(where: { $0.role == .bedside })?.name ?? loadedName ?? state?.householdName ?? "your loved one"
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        list.axis = .vertical; list.spacing = 16
        footer.textAlignment = .center
        record.accessibilityIdentifier = "messages.record"
        record.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(MessageComposerViewController(recipient: self.name), animated: true)
        }, for: .touchUpInside)
        [list, record, footer].forEach { form.addArrangedSubview($0) }
        hideKeyboardControl()
        familyChanged()
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshTapped))
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reloadMessages() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if isMovingFromParent { posterTask?.cancel() } }
    /// Reloads when a new message from the bedside arrives while this is open.
    @objc private func familyChanged() {
        updateName()
        guard let count = FamilyCoordinator.shared.state?.newMessages, let unplayed else { return }
        // A new one counts as seen only once a load succeeds, so a failed load is tried again on the next poll.
        if count > unplayed { reloadMessages() } else { self.unplayed = count }
    }
    private func updateName() {
        title = "Messages with \(name)"
        record.configuration?.title = "Record a message for \(name)"
        record.isHidden = FamilyCoordinator.shared.state?.messagesEnabled == false
        footer.text = "Your messages wait on \(name)'s Porch until they're played. When you miss a Porch call from \(name), they can leave you a message here."
    }
    @objc private func reloadMessages() {
        guard let credential = PorchDevice.credential(for: .family) else { return }
        // The load already running may have started before the newest message, so another follows it.
        guard !loading else { reloadQueued = true; return }
        loading = true
        let count = FamilyCoordinator.shared.state?.newMessages
        Task { [weak self] in
            defer {
                self?.loading = false
                if self?.reloadQueued == true { self?.reloadQueued = false; self?.reloadMessages() }
            }
            do {
                let response = try await FamilyService(credential).send("listMessages")
                guard let self else { return }
                let received = response.received ?? []
                if let sender = received.first?.fromName { self.loadedName = sender; self.updateName() }
                self.render((response.messages ?? []).map(Entry.sent) + received.map(Entry.received))
                self.unplayed = count ?? self.unplayed; self.reportFailure = false
            } catch {
                guard let self else { return }
                // Messages already on screen stay; only a refresh someone asked for says it failed.
                if self.shown == nil { self.show([PorchStyle.label(error.localizedDescription)]) }
                else if self.reportFailure { showPorchError(error, on: self) }
                self.reportFailure = false
            }
        }
    }
    @objc private func refreshTapped() { reportFailure = true; reloadMessages() }
    private func show(_ views: [UIView]) {
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        views.forEach { list.addArrangedSubview($0) }
    }
    private func render(_ unsorted: [Entry]) {
        let entries = unsorted.sorted { $0.time < $1.time }
        defer { shown = entries.map(\.id) }
        guard !entries.isEmpty else {
            let empty = PorchStyle.label("No messages yet.", size: 17, color: PorchStyle.ink, weight: .semibold)
            empty.textAlignment = .center
            show([empty]); return
        }
        var views: [UIView] = [], days: [UIView] = [], rows: [String: UIView] = [:]
        var missing: [(Entry, MessagePosterView)] = []
        for entry in entries {
            let day = MessageText.day(entry.time)
            if (days.last as? UILabel)?.text != day {
                let heading = PorchStyle.label(day, size: 15, weight: .semibold)
                heading.textAlignment = .center; heading.accessibilityTraits = .header
                days.append(heading); views.append(heading)
            }
            let (row, poster) = self.row(entry)
            if let poster, poster.image == nil { missing.append((entry, poster)) }
            rows[entry.id] = row; views.append(row)
        }
        show(views)
        for heading in days {
            list.setCustomSpacing(10, after: heading)
            if let index = views.firstIndex(of: heading), index > 0 { list.setCustomSpacing(36, after: views[index - 1]) }
        }
        loadPosters(missing)
        // Opening goes to the first of theirs that hasn't been played, or else to the newest.
        if shown == nil { reveal(entries.first(where: \.isNew).flatMap { rows[$0.id] }) }
        else if entries.last?.id != shown?.last { reveal(nil) }
    }
    private func row(_ entry: Entry) -> (UIView, MessagePosterView?) {
        switch entry {
        case .sent(let message):
            let playable = message.replayable == true, video = message.mode == "video"
            let cached = video ? MessagePosters.cached(message.id) : nil
            let type = message.kind == "voicemail" ? "Voicemail" : video ? "Video message" : "Audio message"
            let bubble = MessageBubble(mine: true, title: type, length: MessageText.length(message.durationSeconds), video: video, poster: cached,
                                       showsPoster: video && (cached != nil || playable), playable: playable, new: false)
            bubble.accessibilityLabel = "Your \(type.lowercased()), \(MessageText.length(message.durationSeconds)), sent \(MessageText.when(entry.time))"
            bubble.addAction(UIAction { [weak self] _ in self?.play(entry) }, for: .touchUpInside)
            var actions: [UIView] = []
            if message.state == "uploading" || message.state == "queued" {
                let unsend = PorchStyle.button("Unsend", symbol: "arrow.uturn.backward", filled: false)
                unsend.configuration?.baseForegroundColor = .systemRed
                unsend.configuration?.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 2)
                unsend.addAction(UIAction { [weak self] _ in self?.confirmUnsend(message) }, for: .touchUpInside)
                actions.append(unsend)
            }
            return (layout(mine: true, caption: "You · \(MessageText.time(entry.time))", bubble: bubble, status: .sent(message, to: name), actions: actions), bubble.poster)
        case .received(let message):
            let video = message.mode == "video"
            let type = video ? "Video message" : "Audio message"
            let bubble = MessageBubble(mine: false, title: type, length: MessageText.length(message.durationSeconds), video: video,
                                       poster: video ? MessagePosters.cached(message.id) : nil, showsPoster: video && message.available, playable: message.available, new: entry.isNew)
            bubble.accessibilityLabel = "\(type) from \(message.fromName), \(MessageText.length(message.durationSeconds)), left \(MessageText.when(entry.time))"
            bubble.addAction(UIAction { [weak self] _ in self?.play(entry) }, for: .touchUpInside)
            return (layout(mine: false, caption: "\(message.fromName) · \(MessageText.time(entry.time))", bubble: bubble, status: .received(message), actions: []), bubble.poster)
        }
    }
    /// Who and when over the bubble, then whether it's been played. Theirs keep to the left, this phone's to the right.
    private func layout(mine: Bool, caption: String, bubble: MessageBubble, status: MessageStatus, actions: [UIView]) -> UIView {
        let top = PorchStyle.label(caption, size: 14, weight: .semibold)
        var views: [UIView] = [top, bubble, status.tag()]
        if let note = status.note { views.append(PorchStyle.label(note, size: 15)) }
        views += actions
        for case let label as UILabel in views { label.textAlignment = mine ? .right : .left; label.isAccessibilityElement = false }
        bubble.accessibilityValue = [status.text, status.note].compactMap { $0 }.joined(separator: ". ")
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical; stack.spacing = 8; stack.alignment = mine ? .trailing : .leading
        stack.setCustomSpacing(6, after: top)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let row = UIView()
        row.addSubview(stack)
        let width = stack.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.84)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: row.topAnchor), stack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            width, stack.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            mine ? stack.trailingAnchor.constraint(equalTo: row.trailingAnchor) : stack.leadingAnchor.constraint(equalTo: row.leadingAnchor)
        ] + views.map { $0 is UIButton ? $0.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor) : $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
        return row
    }
    /// Scrolls to a message, or with none to the newest at the bottom.
    private func reveal(_ row: UIView?) {
        view.layoutIfNeeded()
        let inset = scroll.adjustedContentInset
        let top = -inset.top, bottom = max(top, scroll.contentSize.height + inset.bottom - scroll.bounds.height)
        let y = row.map { $0.convert($0.bounds, to: scroll).minY - 16 } ?? bottom
        scroll.setContentOffset(CGPoint(x: 0, y: min(bottom, max(top, y))), animated: false)
    }
    private func play(_ entry: Entry) {
        guard !opening, let credential = PorchDevice.credential(for: .family) else { return }
        opening = true
        Task { [weak self] in
            defer { self?.opening = false }
            do {
                let service = FamilyService(credential)
                guard let media = try await service.send(entry.mediaAction, ["messageID": entry.id]).media,
                      let url = URL(string: media.url), let self else { return }
                playMessage(from: url, on: self)
                if entry.isNew {
                    _ = try? await service.send("receivedMessagePlayed", ["messageID": entry.id])
                    self.reloadMessages()
                }
            } catch { if let self { showPorchError(error, on: self) } }
        }
    }
    /// Makes missing preview frames one at a time; each is kept, so this happens once per video.
    private func loadPosters(_ missing: [(Entry, MessagePosterView)]) {
        posterTask?.cancel()
        guard !missing.isEmpty, let credential = PorchDevice.credential(for: .family) else { return }
        posterTask = Task {
            for (entry, poster) in missing {
                guard !Task.isCancelled else { return }
                guard let media = try? await FamilyService(credential).send(entry.mediaAction, ["messageID": entry.id]).media,
                      let url = URL(string: media.url), let image = await MessagePosters.frame(from: url) else { continue }
                MessagePosters.save(image, for: entry.id)
                poster.image = image
            }
        }
    }
    private func confirmUnsend(_ message: SentMessage) {
        let alert = UIAlertController(title: "Unsend this message?", message: "It will be removed from \(name)'s Porch before it plays.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Unsend", style: .destructive) { [weak self] _ in
            guard let credential = PorchDevice.credential(for: .family) else { return }
            Task { [weak self] in
                do { _ = try await FamilyService(credential).send("unsendMessage", ["messageID": message.id]) }
                catch { if let self { showPorchError(error, on: self) } }
                self?.reloadMessages()
            }
        })
        present(alert, animated: true)
    }
}

/// Caregiver review of the waiting queue, on the bedside iPad or from an approved phone: messages, and texts to the
/// Porch number with their words.
final class MessageQueueViewController: CaregiverFormViewController {
    var onChange: ((FamilyAdminState) -> Void)?
    private let remote: FamilyCredential?
    private var messages: [FamilyMessage]
    private var texts: [FamilyText]
    /// Each waiting text's words, which only the PIN-checked review fetches.
    private var words: [String: FamilyText] = [:]
    /// caregiverTexts has answered. A text missing from that answer has no words to show.
    private var wordsReady = false
    private var wordsFailed = false
    private let list = UIStackView()
    private var busy = false
    private var posterTask: Task<Void, Never>?
    init(remote: FamilyCredential?, messages: [FamilyMessage], texts: [FamilyText] = []) {
        self.remote = remote; self.messages = messages; self.texts = texts; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(remote:messages:texts:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Waiting messages"
        list.axis = .vertical; list.spacing = 20
        form.addArrangedSubview(list)
        hideKeyboardControl()
        render()
        loadWords()
    }
    private func loadWords() {
        guard !texts.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let loaded = try await self.request("caregiverTexts", [:])?.texts else {
                    self.wordsFailed = true; self.render(); return
                }
                self.words = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                self.wordsFailed = false; self.wordsReady = true
                self.render()
            } catch {
                self.wordsFailed = true; self.render()
            }
        }
    }
    static func senderName(_ text: FamilyText) -> String { text.from.hasPrefix("+") ? PhoneNumberNormalization.display(text.from) : text.from }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if isMovingFromParent { posterTask?.cancel() } }
    static func senderName(_ message: FamilyMessage) -> String {
        guard message.fromPhone else { return message.fromName }
        return message.callerNumber.map { PhoneNumberNormalization.display($0) } ?? "an unknown caller"
    }
    private func render() {
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard !messages.isEmpty || !texts.isEmpty else { list.addArrangedSubview(PorchStyle.label("No messages are waiting.")); return }
        var missing: [(String, MessagePosterView)] = []
        // Held texts first, then held phone voicemail: they're what needs a decision.
        for text in texts.sorted(by: { ($0.held ? 0 : 1, $0.sentAt) < ($1.held ? 0 : 1, $1.sentAt) }) where text.held { list.addArrangedSubview(section(for: text)) }
        for message in messages.sorted(by: { ($0.held == true ? 0 : 1, $0.sentAt) < ($1.held == true ? 0 : 1, $1.sentAt) }) {
            var views: [UIView] = []
            if message.mode == "video" {
                let poster = MessagePosterView(image: MessagePosters.cached(message.id), playable: true)
                poster.addAction(UIAction { [weak self] _ in Task { await self?.preview(message) } }, for: .touchUpInside)
                if poster.image == nil { missing.append((message.id, poster)) }
                views.append(poster)
            }
            let preview = PorchStyle.button(message.held == true ? "Listen first" : "Preview", symbol: "play.fill", filled: false)
            preview.addAction(UIAction { [weak self] _ in Task { await self?.preview(message) } }, for: .touchUpInside)
            views.append(preview)
            if message.held == true {
                let release = PorchStyle.button("Let it play on Porch", symbol: "checkmark.circle.fill")
                release.addAction(UIAction { [weak self] _ in Task { await self?.change("releaseMessage", message) } }, for: .touchUpInside)
                views.append(release)
            }
            let remove = PorchStyle.button("Remove", symbol: "trash", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addAction(UIAction { [weak self] _ in self?.confirmRemove(message) }, for: .touchUpInside)
            views.append(remove)
            let type = message.fromPhone ? "Phone voicemail" : message.kind == "voicemail" ? "Voicemail" : message.mode == "video" ? "Video message" : "Audio message"
            let state = message.held != true ? (message.delivered ? "Downloaded to the iPad" : "Not downloaded yet")
                : message.callerNumber == nil ? "Waiting for your OK: hidden number"
                : message.callerVerified == true ? "Waiting for your OK: number isn't on the keypad"
                : "Waiting for your OK: number couldn't be checked"
            list.addArrangedSubview(section("\(type) from \(Self.senderName(message))", detail: "\(MessageText.length(message.durationSeconds)) · Sent \(MessageText.when(message.sentAt)) · \(state)", views: views))
        }
        for text in texts.sorted(by: { $0.sentAt < $1.sentAt }) where !text.held { list.addArrangedSubview(section(for: text)) }
        loadPosters(missing)
    }
    /// A text with its words, and what the bedside shows when it translated them.
    private func section(for text: FamilyText) -> UIView {
        var views: [UIView] = []
        if let words = words[text.id] {
            if let body = words.body, !body.isEmpty { views.append(PorchStyle.label("“\(body)”", size: 18, color: PorchStyle.ink)) }
            if let translation = words.translation {
                let language = words.sourceLanguage.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) }
                views.append(PorchStyle.label(language.map { "Shown on Porch, translated from \($0): \(translation)" } ?? "Shown on Porch as: \(translation)", size: 15))
            }
        } else if wordsFailed {
            views.append(PorchStyle.label("Couldn't load this text. Go back and try again.", size: 15))
        } else if wordsReady {
            views.append(PorchStyle.label("The words for this text aren't available.", size: 15))
        } else { views.append(PorchStyle.label("Loading the text…", size: 15)) }
        if let pictures = text.pictures, pictures > 0 { views.append(PorchStyle.label(pictures == 1 ? "It came with a picture, which Porch doesn't show yet." : "It came with \(pictures) pictures, which Porch doesn't show yet.", size: 15)) }
        // Not until the words are here: otherwise Let it show approves a text the caregiver hasn't read.
        if text.held, words[text.id] != nil {
            let release = PorchStyle.button("Let it show on Porch", symbol: "checkmark.circle.fill")
            release.addAction(UIAction { [weak self] _ in Task { await self?.changeText("releaseText", text) } }, for: .touchUpInside)
            views.append(release)
        }
        let remove = PorchStyle.button("Remove", symbol: "trash", filled: false)
        remove.configuration?.baseForegroundColor = .systemRed
        remove.addAction(UIAction { [weak self] _ in self?.confirmRemove(text) }, for: .touchUpInside)
        views.append(remove)
        let state = text.held ? "Waiting for your OK: number isn't saved on the keypad" : text.delivered ? "Ready on the iPad" : "Not on the iPad yet"
        return section("Text from \(Self.senderName(text))", detail: "Sent \(MessageText.when(text.sentAt)) · \(state)", views: views)
    }
    private func changeText(_ action: String, _ text: FamilyText) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let admin = try await request(action, ["textID": text.id])?.admin else { return }
            messages = admin.messages ?? []; texts = admin.texts ?? []; render(); onChange?(admin)
        } catch { showPorchError(error, on: self) }
    }
    private func confirmRemove(_ text: FamilyText) {
        let alert = UIAlertController(title: "Remove this text?", message: "It won't show on the bedside Porch, and its words are deleted.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            Task { [weak self] in await self?.changeText("removeText", text) }
        })
        present(alert, animated: true)
    }
    private func loadPosters(_ missing: [(String, MessagePosterView)]) {
        posterTask?.cancel()
        guard !missing.isEmpty else { return }
        posterTask = Task { [weak self] in
            for (id, poster) in missing {
                guard !Task.isCancelled, let self else { return }
                guard let media = try? await self.request("caregiverMessageMedia", ["messageID": id])?.media,
                      let url = URL(string: media.url), let image = await MessagePosters.frame(from: url) else { continue }
                MessagePosters.save(image, for: id)
                poster.image = image
            }
        }
    }
    private func change(_ action: String, _ message: FamilyMessage) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let admin = try await request(action, ["messageID": message.id])?.admin else { return }
            messages = admin.messages ?? []; texts = admin.texts ?? []; render(); onChange?(admin)
        } catch { showPorchError(error, on: self) }
    }
    private func request(_ action: String, _ values: [String: Any]) async throws -> FamilyResponse? {
        guard let credential = remote ?? PorchDevice.credential(for: .bedside) else { return nil }
        let pin: String
        if remote != nil {
            guard let active = RemoteCaregiverSession.shared.activePIN else { navigationController?.popToRootViewController(animated: true); return nil }
            pin = active
        } else { pin = NativeCallSettings.caregiverCode }
        return try await FamilyService(credential).send(action, values, pin: pin)
    }
    private func preview(_ message: FamilyMessage) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let media = try await request("caregiverMessageMedia", ["messageID": message.id])?.media, let url = URL(string: media.url) else { return }
            playMessage(from: url, on: self)
        } catch { showPorchError(error, on: self) }
    }
    private func confirmRemove(_ message: FamilyMessage) {
        let alert = UIAlertController(title: "Remove this message?", message: message.fromPhone ? "It won't play on the bedside Porch, and the recording is deleted." : "It won't play on the bedside Porch. \(message.fromName) will see that a caregiver removed it.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            Task { [weak self] in await self?.change("removeMessage", message) }
        })
        present(alert, animated: true)
    }
}

extension Notification.Name {
    /// A message notification was tapped: show the thread with the bedside.
    static let porchOpenReceivedMessages = Notification.Name("porch.messages.openReceived")
}

/// Ordinary notifications for messages the bedside leaves when this phone misses its call, and the
/// app badge with how many haven't been played. Calls keep ringing through VoIP pushes and CallKit.
@MainActor final class FamilyMessageAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = FamilyMessageAlerts()
    private var token: String?
    /// The token each family last accepted for this phone, by pairing; empty for none.
    private var registered: [String: String] = [:]
    private var task: Task<Void, Never>?

    func start() {
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
    }

    /// Asks once for permission on a paired family phone, then registers with APNs for every family it's in. A device
    /// used as the bedside stops receiving its families' message notifications.
    func register() {
        #if DEBUG
        // Automated simulator checks don't stop at the permission prompt.
        if ProcessInfo.processInfo.arguments.contains("--family-silent") { return }
        #endif
        guard PorchDevice.experience == .family, !PorchDevice.families.isEmpty else { send(nil); return }
        Task {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined, UIApplication.shared.applicationState == .active {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                settings = await center.notificationSettings()
            }
            if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) { UIApplication.shared.registerForRemoteNotifications() }
            else { send(nil) }
        }
    }
    func received(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        send(PorchDevice.experience == .family ? token : nil)
    }
    private func send(_ token: String?) {
        let families = PorchDevice.families.filter { registered[$0.credential] != token ?? "" }
        guard !families.isEmpty else { return }
        let environment = Bundle.main.object(forInfoDictionaryKey: "PorchAPNsEnvironment") as? String ?? "production"
        let previous = task
        task = Task { [weak self] in
            await previous?.value
            let values: [String: Any] = token.map { ["token": $0, "environment": environment] } ?? ["token": NSNull()]
            for credential in families {
                if (try? await FamilyService(credential).send("registerAlerts", values)) != nil { self?.registered[credential.credential] = token ?? "" }
            }
        }
    }
    /// The badge counts unplayed messages from every family, once each has checked in or failed to (see `MessageBadge`).
    /// A family that removed this phone counts none: its messages can't be played here any more.
    @objc private func familyChanged() {
        let unplayed = FamilyCoordinator.shared.links.filter { $0.credential.role == .family }.map { link -> Int? in
            link.accessRemoved ? 0 : link.state.map { $0.newMessages ?? 0 } ?? (link.error != nil ? 0 : nil)
        }
        guard PorchDevice.experience == .family, let count = MessageBadge.count(unplayed) else { return }
        if #available(iOS 16.0, *) { UNUserNotificationCenter.current().setBadgeCount(count) }
        else { UIApplication.shared.applicationIconBadgeNumber = count }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    /// Opens the thread with whoever left the message. Each family knows this phone by its own ID, which the
    /// notification carries.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let recipient = response.notification.request.content.userInfo["recipientID"] as? String
        await MainActor.run { NotificationCenter.default.post(name: .porchOpenReceivedMessages, object: nil, userInfo: recipient.map { ["recipientID": $0] }) }
    }
}
