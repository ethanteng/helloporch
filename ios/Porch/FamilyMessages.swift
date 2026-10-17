import UIKit
import AVFoundation
import AVKit
import AudioToolbox
import PorchCore

struct MessageRecording { let file: URL; let mode: String; let contentType: String; let duration: TimeInterval }

/// Sends a recording: the server signs a one-time upload URL and the file goes straight to storage.
/// A retry reuses the same message, so a dropped connection doesn't use up another queue slot.
@MainActor final class MessageUploader {
    private var pending: (file: URL, message: SentMessage, target: MessageUploadTarget, uploaded: Bool)?

    func send(_ recording: MessageRecording, kind: String, credential: FamilyCredential) async throws -> SentMessage {
        let service = FamilyService(credential)
        if pending?.file != recording.file || (pending?.uploaded == false && (pending?.target.expiresAt ?? 0) < Date().timeIntervalSince1970 + 60) {
            let size = try recording.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let created = try await service.send("createMessage", ["mode": recording.mode, "kind": kind, "contentType": recording.contentType, "sizeBytes": size, "durationSeconds": max(1, recording.duration)])
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
            guard (200..<300).contains(status) else { throw FamilyServiceError(message: "The upload didn't finish. Check the connection and try again.", status: status) }
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
    private var audioPreview: AVAudioPlayer?
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
        audioPreview?.stop()
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
            content.addArrangedSubview(section("Message for \(recipient)", detail: "Up to two minutes. It waits on their Porch until they play it, and you'll see when it's played.", views: kind == "voicemail" ? [audio, video] : [video, audio]))
        case .recordingAudio:
            let stop = PorchStyle.button("Stop recording", symbol: "stop.fill")
            stop.addAction(UIAction { [weak self] _ in self?.recorder?.stop() }, for: .touchUpInside)
            updateTimer()
            content.addArrangedSubview(section("Recording for \(recipient)…", detail: "Speak after the beep. Recording stops on its own at two minutes.", views: [timerLabel, stop]))
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
            content.addArrangedSubview(section(recording?.mode == "video" ? "Video message · \(length)" : "Audio message · \(length)", detail: sending ? "Keep Porch open until it finishes sending." : nil, views: [play, send, again]))
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
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }

    private func preview() {
        guard let recording else { return }
        if recording.mode == "video" {
            let player = AVPlayerViewController(); player.player = AVPlayer(url: recording.file)
            present(player, animated: true) { player.player?.play() }
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            audioPreview = try? AVAudioPlayer(contentsOf: recording.file)
            audioPreview?.play()
        }
    }
    private func discard() {
        audioPreview?.stop()
        if let file = recording?.file { try? FileManager.default.removeItem(at: file) }
        recording = nil; phase = .idle; render()
    }
    private func send() {
        guard let recording, phase == .recorded, let credential = PorchDevice.credential(for: .family) else { return }
        audioPreview?.stop()
        phase = .sending; render()
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.uploader.send(recording, kind: self.kind, credential: credential)
                try? FileManager.default.removeItem(at: recording.file)
                self.recording = nil; self.phase = .idle
                let done = UIAlertController(title: "Message sent", message: "It's waiting on \(self.recipient)'s Porch. See when it's played in Your messages.", preferredStyle: .alert)
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
}

/// This phone's own messages and voicemails, with whether each was played. Others' messages aren't shown.
final class SentMessagesViewController: CaregiverFormViewController {
    private let list = UIStackView()
    private var loading = false
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Your messages"
        list.axis = .vertical; list.spacing = 20
        form.addArrangedSubview(list)
        hideKeyboardControl()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reloadMessages))
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reloadMessages() }
    @objc private func reloadMessages() {
        guard !loading, let credential = PorchDevice.credential(for: .family) else { return }
        loading = true
        Task { [weak self] in
            defer { self?.loading = false }
            do {
                let messages = try await FamilyService(credential).send("listMessages").messages ?? []
                self?.render(messages)
            } catch {
                guard let self else { return }
                self.show([PorchStyle.label(error.localizedDescription)])
            }
        }
    }
    private func show(_ views: [UIView]) {
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        views.forEach { list.addArrangedSubview($0) }
    }
    private func render(_ messages: [SentMessage]) {
        guard !messages.isEmpty else { show([PorchStyle.label("You haven't sent any messages yet.")]); return }
        show(messages.map { (message: SentMessage) -> UIView in
            let type = message.kind == "voicemail" ? "Voicemail" : message.mode == "video" ? "Video message" : "Audio message"
            var views: [UIView] = []
            if message.state == "uploading" || message.state == "queued" {
                let unsend = PorchStyle.button("Unsend", symbol: "arrow.uturn.backward", filled: false)
                unsend.configuration?.baseForegroundColor = .systemRed
                unsend.addAction(UIAction { [weak self] _ in self?.confirmUnsend(message) }, for: .touchUpInside)
                views.append(unsend)
            }
            return section("\(type) · \(MessageText.length(message.durationSeconds))", detail: status(message), views: views)
        })
    }
    private func status(_ message: SentMessage) -> String {
        let sent = "Sent \(MessageText.when(message.sentAt ?? message.createdAt))"
        switch message.state {
        case "uploading": return "Still sending. Open it again if it doesn't finish."
        case "queued": return message.deliveredAt != nil ? "\(sent). On their Porch, not played yet." : "\(sent). Waiting for their Porch to download it."
        case "played": return "\(sent). Played \(MessageText.when(message.playedAt))."
        case "expired": return "\(sent). Not played within a week, so it was removed."
        case "removed": return "\(sent). A caregiver removed it."
        case "unsent": return "You unsent this message."
        default: return "This message didn't finish sending."
        }
    }
    private func confirmUnsend(_ message: SentMessage) {
        let alert = UIAlertController(title: "Unsend this message?", message: "It will be removed from their Porch before it plays.", preferredStyle: .alert)
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

/// Caregiver review of the waiting queue, on the bedside iPad or from an approved phone.
final class MessageQueueViewController: CaregiverFormViewController {
    var onChange: ((FamilyAdminState) -> Void)?
    private let remote: FamilyCredential?
    private var messages: [FamilyMessage]
    private let list = UIStackView()
    private var busy = false
    init(remote: FamilyCredential?, messages: [FamilyMessage]) {
        self.remote = remote; self.messages = messages; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(remote:messages:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Waiting messages"
        list.axis = .vertical; list.spacing = 20
        form.addArrangedSubview(list)
        hideKeyboardControl()
        render()
    }
    private func render() {
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard !messages.isEmpty else { list.addArrangedSubview(PorchStyle.label("No messages are waiting.")); return }
        for message in messages.sorted(by: { $0.sentAt < $1.sentAt }) {
            let preview = PorchStyle.button("Preview", symbol: "play.fill", filled: false)
            preview.addAction(UIAction { [weak self] _ in Task { await self?.preview(message) } }, for: .touchUpInside)
            let remove = PorchStyle.button("Remove", symbol: "trash", filled: false)
            remove.configuration?.baseForegroundColor = .systemRed
            remove.addAction(UIAction { [weak self] _ in self?.confirmRemove(message) }, for: .touchUpInside)
            let type = message.kind == "voicemail" ? "Voicemail" : message.mode == "video" ? "Video message" : "Audio message"
            list.addArrangedSubview(section("\(type) from \(message.fromName)", detail: "\(MessageText.length(message.durationSeconds)) · Sent \(MessageText.when(message.sentAt)) · \(message.delivered ? "Downloaded to the iPad" : "Not downloaded yet")", views: [preview, remove]))
        }
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
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let player = AVPlayerViewController(); player.player = AVPlayer(url: url)
            present(player, animated: true) { player.player?.play() }
        } catch { showPorchError(error, on: self) }
    }
    private func confirmRemove(_ message: FamilyMessage) {
        let alert = UIAlertController(title: "Remove this message?", message: "It won't play on the bedside Porch. \(message.fromName) will see that a caregiver removed it.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            Task { [weak self] in
                guard let self, !self.busy else { return }
                self.busy = true; defer { self.busy = false }
                do {
                    guard let admin = try await self.request("removeMessage", ["messageID": message.id])?.admin else { return }
                    self.messages = admin.messages ?? []; self.render(); self.onChange?(admin)
                } catch { showPorchError(error, on: self) }
            }
        })
        present(alert, animated: true)
    }
}
