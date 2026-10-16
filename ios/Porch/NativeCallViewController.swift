import UIKit
import AVFoundation
import LiveKit
import PorchCore

/// Foreground, manually joined prototype. The server owns all API credentials.
final class NativeCallViewController: UIViewController, RoomDelegate {
    private let contact: CallContact
    private let call: NativeCall
    private let server: NativeCallServer
    private var room = Room()
    private let statusLabel = UILabel()
    private let remoteVideo = VideoView()
    private let localVideo = VideoView()
    private let placeholder = UILabel()
    private let microphoneButton = UIButton(type: .system)
    private let cameraButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)
    private var connectionTask: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var phoneControlToken: String?
    private var isPhoneCall = false
    private var isSwitchingToPhone = false
    private var cleanupBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isEnding = false
    private var hasFailed = false
    private var hasConnectedPeer = false
    private var mediaReady = false

    init(contact: CallContact, call: NativeCall, server: NativeCallServer) {
        self.contact = contact
        self.call = call
        self.server = server
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        isModalInPresentation = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(contact:call:server:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = PorchStyle.cream
        room.add(delegate: self)
        let title = UILabel()
        title.text = contact.name
        title.font = PorchStyle.font(36, weight: .semibold)
        title.textColor = PorchStyle.ink
        title.textAlignment = .center
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        statusLabel.text = "Connecting…"
        statusLabel.font = PorchStyle.font(22)
        statusLabel.textColor = PorchStyle.ink
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityTraits.insert(.updatesFrequently)

        let stage = UIView()
        stage.backgroundColor = UIColor(white: 0.15, alpha: 1)
        stage.layer.cornerRadius = 24
        stage.clipsToBounds = true
        remoteVideo.layoutMode = .fit
        localVideo.layoutMode = .fill
        localVideo.isHidden = true
        localVideo.accessibilityLabel = "Your camera preview"
        placeholder.text = call.mode == .voice ? "Voice call\nCamera is off" : "Waiting for video"
        placeholder.textColor = .white
        placeholder.font = PorchStyle.font(28)
        placeholder.textAlignment = .center
        placeholder.numberOfLines = 0
        placeholder.adjustsFontForContentSizeCategory = true
        [remoteVideo, placeholder, localVideo].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            stage.addSubview($0)
        }
        NSLayoutConstraint.activate([
            remoteVideo.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            remoteVideo.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            remoteVideo.topAnchor.constraint(equalTo: stage.topAnchor),
            remoteVideo.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
            placeholder.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: stage.leadingAnchor, constant: 16),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: stage.trailingAnchor, constant: -16),
            localVideo.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -16),
            localVideo.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -16),
            localVideo.widthAnchor.constraint(equalTo: stage.widthAnchor, multiplier: 0.22),
            localVideo.heightAnchor.constraint(equalTo: localVideo.widthAnchor, multiplier: 0.75),
        ])
        configure(microphoneButton, title: "Mute", action: #selector(toggleMicrophone))
        configure(cameraButton, title: "Camera off", action: #selector(toggleCamera))
        configure(endButton, title: "End call", action: #selector(endCall))
        endButton.configuration?.baseBackgroundColor = .systemRed
        cameraButton.isHidden = call.mode == .voice
        microphoneButton.isEnabled = false
        cameraButton.isEnabled = false

        let controls = UIStackView(arrangedSubviews: [microphoneButton, cameraButton, endButton])
        controls.axis = .vertical
        controls.spacing = 12
        let scroll = UIScrollView()
        let stack = UIStackView(arrangedSubviews: [title, statusLabel, stage])
        stack.axis = .vertical
        stack.spacing = 16
        [scroll, stack, controls].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll)
        view.addSubview(controls)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -16),
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
            stage.heightAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.5),
        ])
        // This first version intentionally ends when leaving the foreground.
        NotificationCenter.default.addObserver(self, selector: #selector(endCall), name: UIApplication.didEnterBackgroundNotification, object: nil)
        connectionTask = Task { await connect() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configure(_ button: UIButton, title: String, action: Selector) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = PorchStyle.terracotta
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 24, bottom: 18, trailing: 24)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = PorchStyle.font(24, weight: .semibold)
            return attributes
        }
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 0
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private struct JoinResponse: Decodable { let token: String; let serverUrl: String; let controlToken: String? }
    private struct ServerError: Decodable { let error: String }
    private struct CallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func connect() async {
        do {
            var request = URLRequest(url: server.tokenURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(server.accessCode)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["room": call.room, "mode": call.mode.rawValue, "name": "Porch iPad"])
            // Ephemeral sessions don't retain call tokens in a disk cache.
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                let message = (try? JSONDecoder().decode(ServerError.self, from: data).error)
                    ?? "Couldn't reach the calling server. Check the server address and try again."
                throw CallError(message: message)
            }
            let join = try JSONDecoder().decode(JoinResponse.self, from: data)
            guard URL(string: join.serverUrl)?.scheme == "wss" else {
                throw CallError(message: "The calling server returned an invalid LiveKit address.")
            }
            try Task.checkCancellation()
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw CallError(message: "Allow microphone access in iPad Settings → Privacy & Security → Microphone to make calls.")
            }
            try Task.checkCancellation()
            if call.mode == .video {
                guard await AVCaptureDevice.requestAccess(for: .video) else {
                    throw CallError(message: "Allow camera access in iPad Settings → Privacy & Security → Camera, or choose Voice in this person's setup.")
                }
            }
            try Task.checkCancellation()
            try await room.connect(url: join.serverUrl, token: join.token)
            try Task.checkCancellation()
            try await room.localParticipant.setMicrophone(enabled: true)
            try Task.checkCancellation()
            if call.mode == .video { try await room.localParticipant.setCamera(enabled: true) }
            try Task.checkCancellation()
            mediaReady = true
            microphoneButton.isEnabled = true
            cameraButton.isEnabled = true
            refresh()
            waitTask = Task { [weak self] in
                let seconds: UInt64 = self?.contact.phoneNumber == nil ? 90 : 20
                do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
                guard let self, !self.hasConnectedPeer else { return }
                if self.contact.phoneNumber != nil {
                    self.fallbackTask = Task { await self.switchToPhone() }
                } else {
                    self.finish(message: "No one joined. Returning to your people…")
                }
            }
        } catch {
            if Task.isCancelled || isEnding { return }
            if contact.phoneNumber != nil, !hasConnectedPeer {
                fallbackTask = Task { await switchToPhone() }
                return
            }
            hasFailed = true
            await room.disconnect()
            remoteVideo.track = nil
            localVideo.track = nil
            localVideo.isHidden = true
            statusLabel.text = "Couldn't start the call."
            placeholder.isHidden = false
            placeholder.text = error.localizedDescription
            microphoneButton.isEnabled = false
            cameraButton.isEnabled = false
            endButton.configuration?.title = "Back to your people"
        }
    }

    private func refresh(source: Room? = nil) {
        guard !isEnding, !hasFailed, source == nil || source === room else { return }
        let peers = Array(room.remoteParticipants.values)
        if isPhoneCall {
            let status = peers.first { $0.identity?.stringValue == "phone" }?.attributes["sip.callStatus"]
            if status == "active" || status == "automation" {
                hasConnectedPeer = true
                waitTask?.cancel()
                statusLabel.text = "Phone call connected"
            } else {
                statusLabel.text = "Calling \(contact.name)'s phone…"
            }
            return
        }
        if !peers.isEmpty { hasConnectedPeer = true; waitTask?.cancel() }
        statusLabel.text = peers.isEmpty
            ? "Waiting for \(contact.name)…\nJoin room \(call.room) in \(call.mode.rawValue) mode."
            : (mediaReady ? "\(call.mode == .voice ? "Voice" : "Video") call connected" : "Connecting audio…")
        if peers.isEmpty, contact.phoneNumber != nil {
            statusLabel.text = "Trying \(contact.name) on Porch…\nTheir phone will ring if Porch isn't answered."
        }
        if call.mode == .video {
            let remoteTrack = peers.flatMap(\.videoTracks).first { !$0.isMuted && $0.track is VideoTrack }?.track as? VideoTrack
            remoteVideo.track = remoteTrack
            placeholder.isHidden = remoteTrack != nil
            localVideo.track = room.localParticipant.videoTracks.first { !$0.isMuted }?.track as? VideoTrack
            localVideo.isHidden = localVideo.track == nil
        }
    }

    @objc private func toggleMicrophone() { changeMedia(camera: false) }
    @objc private func toggleCamera() { changeMedia(camera: true) }

    private func changeMedia(camera: Bool) {
        guard mediaReady, !isEnding, !isSwitchingToPhone, !camera || (call.mode == .video && !isPhoneCall) else { return }
        microphoneButton.isEnabled = false
        cameraButton.isEnabled = false
        controlTask = Task {
            do {
                if camera {
                    try await room.localParticipant.setCamera(enabled: !room.localParticipant.isCameraEnabled())
                } else {
                    try await room.localParticipant.setMicrophone(enabled: !room.localParticipant.isMicrophoneEnabled())
                }
                guard !isEnding else { return }
                microphoneButton.configuration?.title = room.localParticipant.isMicrophoneEnabled() ? "Mute" : "Unmute"
                cameraButton.configuration?.title = room.localParticipant.isCameraEnabled() ? "Camera off" : "Camera on"
                refresh()
            } catch {
                if !isEnding { statusLabel.text = "Couldn't change \(camera ? "camera" : "microphone"). Try again." }
            }
            if !isEnding { microphoneButton.isEnabled = true; cameraButton.isEnabled = true }
        }
    }

    @objc private func endCall() { finish() }

    private func finish(message: String? = nil) {
        guard !isEnding else { return }
        isEnding = true
        connectionTask?.cancel()
        fallbackTask?.cancel()
        waitTask?.cancel()
        controlTask?.cancel()
        microphoneButton.isEnabled = false
        cameraButton.isEnabled = false
        endButton.isEnabled = false
        statusLabel.text = message ?? "Ending call…"
        if isPhoneCall || fallbackTask != nil {
            cleanupBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "End Porch phone call") { [weak self] in
                self?.endCleanupBackgroundTask()
            }
        }
        Task {
            defer { endCleanupBackgroundTask() }
            await connectionTask?.value
            await fallbackTask?.value
            await controlTask?.value
            await room.disconnect()
            remoteVideo.track = nil
            localVideo.track = nil
            if let ticket = phoneControlToken {
                do {
                    // A separate uncancelled request hangs up the telephone leg.
                    do { try await phoneAction("end", ticket: ticket) }
                    catch { try await phoneAction("end", ticket: ticket) }
                    phoneControlToken = nil
                } catch {
                    hasFailed = true
                    isEnding = false
                    endButton.isEnabled = true
                    endButton.configuration?.title = "Retry ending phone call"
                    statusLabel.text = "Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again."
                    return
                }
            }
            if message != nil { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            dismiss(animated: true)
        }
    }

    private func endCleanupBackgroundTask() {
        guard cleanupBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(cleanupBackgroundTask)
        cleanupBackgroundTask = .invalid
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in self?.refresh(source: room) }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in
            guard let self, room === self.room else { return }
            if self.isPhoneCall, participant.identity?.stringValue == "phone" {
                self.finish(message: self.hasConnectedPeer ? "Call ended. Returning to your people…" : "The phone call ended before it was answered.")
                return
            }
            guard !self.isSwitchingToPhone, !self.isPhoneCall else { return }
            if self.hasConnectedPeer, self.room.remoteParticipants.isEmpty {
                self.finish(message: "Call ended. Returning to your people…")
            } else { self.refresh() }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in self?.refresh(source: room) }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in self?.refresh(source: room) }
    }

    nonisolated func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        Task { @MainActor [weak self] in self?.refresh(source: room) }
    }

    nonisolated func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        Task { @MainActor [weak self] in self?.refresh(source: room) }
    }

    nonisolated func room(_ room: Room, didUpdateConnectionState state: ConnectionState, from old: ConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, room === self.room, !self.isEnding, !self.hasFailed else { return }
            if state == .reconnecting { self.statusLabel.text = "Reconnecting…" }
            if state == .connected { self.refresh() }
        }
    }

    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor [weak self] in
            guard let self, room === self.room, !self.isEnding, !self.isSwitchingToPhone, self.mediaReady else { return }
            self.finish(message: "The call disconnected. Returning to your people…")
        }
    }

    nonisolated func room(_ room: Room, didStartReconnectWithMode mode: ReconnectMode) {
        Task { @MainActor [weak self] in
            guard let self, room === self.room, !self.isEnding, !self.hasFailed else { return }
            self.statusLabel.text = "Reconnecting…"
        }
    }

    nonisolated func room(_ room: Room, didCompleteReconnectWithMode mode: ReconnectMode) {
        Task { @MainActor [weak self] in self?.refresh(source: room) }
    }

    nonisolated func room(_ room: Room, participant: Participant, didUpdateAttributes attributes: [String: String]) {
        Task { @MainActor [weak self] in self?.refresh(source: room) }
    }

    private func phoneRequest(_ action: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: server.baseURL.appendingPathComponent("api/calls/phone/\(action)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(server.accessCode)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CallError(message: (try? JSONDecoder().decode(ServerError.self, from: data).error)
                ?? "Couldn't reach the phone calling server. Check your connection and try again.")
        }
        return data
    }

    private func phoneAction(_ action: String, ticket: String) async throws {
        _ = try await phoneRequest(action, body: ["controlToken": ticket])
    }

    private func switchToPhone() async {
        guard let phoneNumber = contact.phoneNumber, !isEnding, !hasFailed, !hasConnectedPeer else { return }
        await controlTask?.value
        guard !Task.isCancelled, !isEnding, !hasConnectedPeer else { return }
        // Prefer a Porch answer delivered just as the fallback timer fires.
        guard room.remoteParticipants.isEmpty else { refresh(); return }
        let microphoneEnabled = !mediaReady || room.localParticipant.isMicrophoneEnabled()
        isSwitchingToPhone = true
        mediaReady = false
        microphoneButton.isEnabled = false
        cameraButton.isEnabled = false
        cameraButton.isHidden = true
        statusLabel.text = "Porch wasn't answered. Trying \(contact.name)'s phone…"
        // Disconnect releases camera/mic before joining a separate voice room.
        // Late Porch joins cannot connect to the phone conversation.
        let porchRoom = room
        room = Room()
        room.add(delegate: self)
        await porchRoom.disconnect()
        remoteVideo.track = nil
        localVideo.track = nil
        localVideo.isHidden = true
        placeholder.isHidden = false
        placeholder.text = "Phone call\nCamera is off"
        isPhoneCall = true
        do {
            try Task.checkCancellation()
            let data = try await phoneRequest("prepare", body: ["phoneNumber": phoneNumber, "name": contact.name])
            let join = try JSONDecoder().decode(JoinResponse.self, from: data)
            guard let ticket = join.controlToken, URL(string: join.serverUrl)?.scheme == "wss" else {
                throw CallError(message: "The calling server returned invalid phone call settings.")
            }
            phoneControlToken = ticket
            try Task.checkCancellation()
            try await room.connect(url: join.serverUrl, token: join.token)
            try Task.checkCancellation()
            try await room.localParticipant.setMicrophone(enabled: microphoneEnabled)
            try Task.checkCancellation()
            microphoneButton.configuration?.title = microphoneEnabled ? "Mute" : "Unmute"
            try await phoneAction("start", ticket: ticket)
            try Task.checkCancellation()
            isSwitchingToPhone = false
            mediaReady = true
            microphoneButton.isEnabled = true
            refresh()
            waitTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                guard let self, !self.hasConnectedPeer else { return }
                self.finish(message: "Their phone didn't answer. Returning to your people…")
            }
        } catch {
            if Task.isCancelled || isEnding { return }
            hasFailed = true
            await room.disconnect()
            isSwitchingToPhone = false
            statusLabel.text = "Couldn't connect their phone."
            placeholder.text = error.localizedDescription
            endButton.configuration?.title = "Back to your people"
            // End call also cleans up any telephone leg created before failure.
        }
    }
}
