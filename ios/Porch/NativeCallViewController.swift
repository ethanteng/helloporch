import UIKit
import AVFoundation
import LiveKit
import PorchCore

/// One video-first layout for foreground calls and CallKit-owned sessions.
@MainActor enum CallScreenLayout {
    static func configure(_ button: UIButton, title: String, symbol: String, isEnd: Bool = false) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .top
        configuration.imagePadding = 6
        configuration.titleAlignment = .center
        configuration.baseBackgroundColor = isEnd
            ? UIColor(red: 0.68, green: 0.19, blue: 0.19, alpha: 1) : PorchStyle.nightSurface
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = .init(top: 12, leading: 8, bottom: 12, trailing: 8)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = PorchStyle.centeredTextAttributes(attributes)
            attributes.font = PorchStyle.font(16, weight: .semibold)
            return attributes
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { PorchStyle.centeredTextAttributes($0) }
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
    }

    static func install(in view: UIView, video: VideoView, preview: VideoView? = nil,
                        placeholder: UILabel? = nil, title: UILabel, status: UILabel,
                        hint: UILabel? = nil, photo: UIImageView? = nil, buttons: [UIButton]) {
        view.backgroundColor = .black
        video.layoutMode = .fill
        video.clipsToBounds = true
        video.accessibilityIdentifier = "call.remoteVideo"
        video.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(video)
        // The video extends behind the safe areas; only the overlays are inset.
        NSLayoutConstraint.activate([
            video.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            video.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            video.topAnchor.constraint(equalTo: view.topAnchor),
            video.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Normally the overlays sit at opposite edges. If large text needs more
        // height, scroll the overlays together without shrinking the video.
        let scroll = UIScrollView()
        scroll.accessibilityIdentifier = "call.overlays"
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let content = scroll.contentLayoutGuide
        let frame = scroll.frameLayoutGuide
        let fittedHeight = content.heightAnchor.constraint(equalTo: frame.heightAnchor)
        fittedHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: frame.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: frame.heightAnchor), fittedHeight,
        ])

        title.textAlignment = .center
        status.textAlignment = .center
        hint?.textAlignment = .center
        placeholder?.textAlignment = .center
        var headingViews: [UIView] = [title, status]
        if let photo, let image = photo.image {
            let avatar = RecipientAppearance.photoView(nil)
            avatar.image = image; avatar.layer.cornerRadius = 12
            NSLayoutConstraint.activate([avatar.widthAnchor.constraint(equalToConstant: 64), avatar.heightAnchor.constraint(equalToConstant: 64)])
            let identity = UIStackView(arrangedSubviews: [avatar, title])
            identity.spacing = 16; identity.alignment = .center
            headingViews = [identity, status]
        }
        let heading = UIStackView(arrangedSubviews: headingViews)
        heading.axis = .vertical
        heading.spacing = 4
        heading.accessibilityIdentifier = "call.heading"
        let row = UIStackView(arrangedSubviews: buttons)
        row.distribution = .fillEqually
        row.spacing = 8
        let controls = UIStackView(arrangedSubviews: (hint.map { [$0 as UIView] } ?? []) + [row])
        controls.axis = .vertical
        controls.spacing = 8
        controls.accessibilityIdentifier = "call.controls"
        for overlay in [heading, controls] {
            overlay.backgroundColor = UIColor.black.withAlphaComponent(0.65)
            overlay.layer.cornerRadius = 16
            overlay.isLayoutMarginsRelativeArrangement = true
            overlay.directionalLayoutMargins = .init(top: 10, leading: 10, bottom: 10, trailing: 10)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(overlay)
            let width = overlay.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -24)
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                overlay.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                overlay.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 12),
                overlay.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
                overlay.widthAnchor.constraint(lessThanOrEqualToConstant: 560), width,
            ])
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            controls.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            controls.topAnchor.constraint(greaterThanOrEqualTo: heading.bottomAnchor, constant: 16),
        ])
        if let placeholder {
            let space = UILayoutGuide()
            scroll.addLayoutGuide(space)
            let identity = UIStackView(arrangedSubviews: (photo.map { [$0 as UIView] } ?? []) + [placeholder])
            identity.axis = .vertical; identity.alignment = .center; identity.spacing = 16
            identity.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(identity)
            NSLayoutConstraint.activate([
                space.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
                space.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -12),
                identity.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                identity.centerYAnchor.constraint(equalTo: space.centerYAnchor),
                identity.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -48),
                identity.topAnchor.constraint(greaterThanOrEqualTo: space.topAnchor),
                identity.bottomAnchor.constraint(lessThanOrEqualTo: space.bottomAnchor),
                placeholder.widthAnchor.constraint(equalTo: identity.widthAnchor),
            ])
            if let photo {
                let width = photo.widthAnchor.constraint(equalTo: identity.widthAnchor, multiplier: 0.85)
                // Fit ordinary calls on screen before growing the scrollable
                // overlays; the image's intrinsic size must not force overflow.
                width.priority = UILayoutPriority(249)
                photo.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
                photo.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
                NSLayoutConstraint.activate([
                    photo.widthAnchor.constraint(lessThanOrEqualTo: identity.widthAnchor),
                    photo.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
                    photo.heightAnchor.constraint(equalTo: photo.widthAnchor), width,
                ])
            }
        }
        if let preview {
            preview.layoutMode = .fill
            preview.clipsToBounds = true
            preview.layer.cornerRadius = 12
            preview.accessibilityIdentifier = "call.localPreview"
            preview.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(preview)
            let width = preview.widthAnchor.constraint(equalTo: frame.widthAnchor, multiplier: 0.12)
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                preview.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -12),
                preview.topAnchor.constraint(greaterThanOrEqualTo: heading.bottomAnchor, constant: 12),
                preview.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
                preview.widthAnchor.constraint(lessThanOrEqualToConstant: 112), width,
                preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.75),
            ])
        }
    }
}

/// Foreground LiveKit media for paired calls, legacy rooms and phone fallback.
final class NativeCallViewController: UIViewController, RoomDelegate {
    private let contact: CallContact
    private let call: NativeCall
    private let server: NativeCallServer
    private(set) var room = Room()
    private let statusLabel = UILabel()
    private let keypadHint = PorchStyle.label("", size: 16, color: PorchStyle.nightSecondary)
    private let remoteVideo = VideoView()
    private let localVideo = VideoView()
    private let placeholder = UILabel()
    private lazy var personPhoto = RecipientAppearance.photoView(contact.photoData)
    private let microphoneButton = UIButton(type: .system)
    private let cameraButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)
    private var connectionTask: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var inactivityTask: Task<Void, Never>?
    private var inactivity = CallInactivityTimer(timeout: CallPreferences.disconnectAfterSilence() ? TimeInterval(CallPreferences.silenceSeconds()) : nil)
    private var phoneControlToken: String?
    private var isPhoneCall = false
    private var isSwitchingToPhone = false
    private var cleanupBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private(set) var isEnding = false
    private var hasFailed = false
    private var hasConnectedPeer = false
    private var mediaReady = false
    private let ringback = PorchRingback()
    private let connectionCue = PorchTonePlayer()
    private var connectionCuePlayed = false
    private let fallbackSeconds = CallPreferences.fallbackSeconds()
    private var familySession: FamilyCallSession?
    private var familyAccepted = false
    /// Runs after the screen closes when the other person never answered (declined, timed out
    /// or unreachable) and the caller didn't hang up first. Family phones offer voicemail here.
    var onUnanswered: (() -> Void)?
    private var endedByCaller = false
    private var beginWithPhoneFallback = false
    private var keypad = CallTrigger()
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); keypad.resetKeys(); becomeFirstResponder()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-outgoing-call") { return }
        #endif
        if !familyAccepted && !hasConnectedPeer && !isEnding && !hasFailed { ringback.start() }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); keypad.resetKeys(); resignFirstResponder() }
    func performKeypadDigit(_ digit: Int) {
        guard UIApplication.shared.applicationState == .active, presentedViewController == nil,
              let action = (try? CallSlots.load())?.action(for: digit) else { return }
        switch action {
        case .callControl: endCall()
        case .toggleVideo:
            if call.mode == .video && !isPhoneCall && cameraButton.isEnabled { toggleCamera() }
        case .person, .messages: break
        }
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let digit = CallTrigger.slot(for: Int(key.keyCode.rawValue)), key.modifierFlags.intersection([.command, .control, .alternate, .shift]).isEmpty else { unhandled.insert(press); continue }
            if keypad.keyDown(Int(key.keyCode.rawValue)) { performKeypadDigit(digit) }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { keypad.keyUp(Int(key.keyCode.rawValue)) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) { keypad.resetKeys(); super.pressesCancelled(presses, with: event) }

    init(contact: CallContact, call: NativeCall, server: NativeCallServer) {
        self.contact = contact
        self.call = call
        self.server = server
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        isModalInPresentation = true
    }

    static func paired(_ session: FamilyCallSession, contact original: CallContact? = nil) throws -> NativeCallViewController {
        let call = try NativeCall(room: "paired-\(session.call.id.prefix(8))", mode: session.call.mode)
        let saved = original ?? session.peerContact ?? FamilyCoordinator.shared.state.flatMap { state in
            ((try? CallSlots.load()) ?? CallSlots()).incomingContact(for: session.call, in: state)
        }
        let contact = try CallContact(name: session.peerName, nativeCall: call, phoneNumber: session.call.source == "phone" ? nil : saved?.phoneNumber,
            buttonColorHex: saved?.buttonColorHex, photoData: saved?.photoData)
        let server = try NativeCallServer(url: session.credential.origin.absoluteString, accessCode: session.credential.credential)
        let controller = NativeCallViewController(contact: contact, call: call, server: server)
        controller.familySession = session
        controller.familyAccepted = session.call.state == "accepted"
        return controller
    }

    static func phoneFallback(_ contact: CallContact, server: NativeCallServer? = nil) throws -> NativeCallViewController {
        guard let call = contact.nativeCall else { throw CallError(message: "Choose a Porch contact.") }
        let configuration = try server ?? NativeCallSettings.loadForPhone()
        let controller = NativeCallViewController(contact: contact, call: call, server: configuration)
        controller.beginWithPhoneFallback = true
        controller.isPhoneCall = true
        return controller
    }

    required init?(coder: NSCoder) { fatalError("Use init(contact:call:server:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = PorchStyle.night
        room.add(delegate: self)
        let title = UILabel()
        title.text = contact.name
        title.font = PorchStyle.font(40, weight: .semibold)
        title.textColor = PorchStyle.nightText
        title.textAlignment = .center
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        statusLabel.text = BedsideText.string("Connecting…")
        statusLabel.font = PorchStyle.font(17)
        statusLabel.textColor = PorchStyle.nightText
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityTraits.insert(.updatesFrequently)

        localVideo.isHidden = true
        localVideo.accessibilityLabel = BedsideText.string("Your camera preview")
        placeholder.text = BedsideText.string(call.mode == .voice ? "Voice call\nCamera is off" : "Waiting for video")
        placeholder.textColor = .white
        placeholder.font = PorchStyle.font(28)
        placeholder.textAlignment = .center
        placeholder.numberOfLines = 0
        placeholder.adjustsFontForContentSizeCategory = true
        configure(microphoneButton, title: "Mute", symbol: "mic.slash", action: #selector(toggleMicrophone))
        configure(cameraButton, title: "Camera off", symbol: "video.slash", action: #selector(toggleCamera))
        configure(endButton, title: "End call", symbol: "phone.down.fill", action: #selector(endCall))
        cameraButton.isHidden = call.mode == .voice
        microphoneButton.isEnabled = false
        cameraButton.isEnabled = false

        keypadHint.textAlignment = .center
        updateKeypadHint()
        CallScreenLayout.install(in: view, video: remoteVideo, preview: localVideo,
                                 placeholder: placeholder, title: title, status: statusLabel,
                                 hint: keypadHint, photo: personPhoto.image == nil ? nil : personPhoto, buttons: [microphoneButton, cameraButton, endButton])
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-outgoing-call") {
            statusLabel.text = BedsideText.string("Calling %@ on Porch…", contact.name)
            return // Static preview: never request media access or connect a call.
        }
        #endif
        // This first version intentionally ends when leaving the foreground.
        NotificationCenter.default.addObserver(self, selector: #selector(endCall), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(familyChanged), name: .porchFamilyChanged, object: nil)
        BedsideText.applyAccessibilityLanguage(to: view)
        if inactivity.timeout != nil {
            inactivityTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                    guard let self, !self.isEnding, !self.hasFailed else { return }
                    self.checkInactivity()
                }
            }
        }
        connectionTask = Task { if beginWithPhoneFallback { await switchToPhone() } else { await connect() } }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configure(_ button: UIButton, title: String, symbol: String, action: Selector) {
        CallScreenLayout.configure(button, title: BedsideText.string(title), symbol: symbol, isEnd: button === endButton)
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
            let join: JoinResponse
            if let session = familySession {
                let response = try await session.service.send("joinCall", ["callID": session.call.id])
                guard let token = response.token, let url = response.serverUrl else { throw CallError(message: "The call invitation is no longer valid.") }
                join = JoinResponse(token: token, serverUrl: url, controlToken: nil)
            } else {
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
            join = try JSONDecoder().decode(JoinResponse.self, from: data)
            }
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
            #if DEBUG && targetEnvironment(simulator)
            let microphoneEnabled = !ProcessInfo.processInfo.arguments.contains("--family-silent")
            #else
            let microphoneEnabled = true
            #endif
            try await room.localParticipant.setMicrophone(enabled: microphoneEnabled)
            microphoneButton.configuration?.title = BedsideText.string(microphoneEnabled ? "Mute" : "Unmute")
            try Task.checkCancellation()
            if call.mode == .video { try await room.localParticipant.setCamera(enabled: true) }
            try Task.checkCancellation()
            mediaReady = true
            microphoneButton.isEnabled = true
            cameraButton.isEnabled = true
            refresh()
            waitTask = Task { [weak self] in
                let seconds: UInt64 = self?.familyAccepted == true ? 30 : self?.contact.phoneNumber == nil ? (self?.familySession == nil ? 90 : 45) : UInt64(self?.fallbackSeconds ?? CallPreferences.defaultFallbackSeconds)
                do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
                guard let self, !self.hasConnectedPeer else { return }
                if self.contact.phoneNumber != nil && !self.familyAccepted {
                    self.fallbackTask = Task { await self.switchToPhone() }
                } else {
                    self.finish(message: "No one joined. Returning to the clock…")
                }
            }
        } catch {
            if Task.isCancelled || isEnding { return }
            if contact.phoneNumber != nil, !hasConnectedPeer, !familyAccepted {
                fallbackTask = Task { await switchToPhone() }
                return
            }
            hasFailed = true
            ringback.stop()
            await room.disconnect()
            remoteVideo.track = nil
            localVideo.track = nil
            localVideo.isHidden = true
            statusLabel.text = BedsideText.string("Couldn't start the call.")
            placeholder.isHidden = false
            personPhoto.isHidden = false
            placeholder.text = BedsideText.error(error.localizedDescription)
            microphoneButton.isEnabled = false
            cameraButton.isEnabled = false
            endButton.configuration?.title = BedsideText.string("Back to clock")
        }
    }

    private func updateKeypadHint() {
        let slots = (try? CallSlots.load()) ?? CallSlots()
        keypadHint.text = [slots.digit(for: .callControl).map { BedsideText.string("Key %d: hang up", $0) }, call.mode == .video && !isPhoneCall && !beginWithPhoneFallback ? slots.digit(for: .toggleVideo).map { BedsideText.string("Key %d: video off / on", $0) } : nil].compactMap { $0 }.joined(separator: " · ")
        keypadHint.isHidden = keypadHint.text?.isEmpty != false
    }
    private func refresh(source: Room? = nil) {
        guard !isEnding, !hasFailed, source == nil || source === room else { return }
        defer { checkInactivity() }
        updateKeypadHint()
        let peers = Array(room.remoteParticipants.values)
        if familySession?.call.source == "phone" {
            let status = peers.first?.attributes["sip.callStatus"]
            if status == "hangup" { finishPhoneCall(); return }
            if status == "active" {
                hasConnectedPeer = true; waitTask?.cancel(); ringback.stop(); playConnectionCue()
                statusLabel.text = BedsideText.string("Phone call connected")
            } else { statusLabel.text = BedsideText.string("Connecting audio…") }
            return
        }
        if isPhoneCall {
            let status = peers.first { $0.identity?.stringValue == "phone" }?.attributes["sip.callStatus"]
            if status == "hangup" { finishPhoneCall(); return }
            if status == "active" || status == "automation" {
                hasConnectedPeer = true
                waitTask?.cancel()
                ringback.stop()
                playConnectionCue()
                statusLabel.text = BedsideText.string("Phone call connected")
            } else {
                if mediaReady && !hasConnectedPeer { ringback.start() }
                statusLabel.text = hasConnectedPeer ? BedsideText.string("Reconnecting phone call…") : BedsideText.string("Calling %@'s phone…", contact.name)
            }
            return
        }
        if !peers.isEmpty { hasConnectedPeer = true; waitTask?.cancel(); ringback.stop() }
        else if mediaReady && !hasConnectedPeer && !isSwitchingToPhone && !familyAccepted { ringback.start() }
        statusLabel.text = peers.isEmpty
            ? BedsideText.string("Waiting for %@…", contact.name)
            : BedsideText.string(mediaReady ? (call.mode == .voice ? "Voice call connected" : "Video call connected") : "Connecting audio…")
        if peers.isEmpty, familySession != nil { statusLabel.text = familyAccepted ? BedsideText.string("Connecting with %@…", contact.name) : BedsideText.string("Calling %@ on Porch…", contact.name) }
        if peers.isEmpty, contact.phoneNumber != nil, !familyAccepted {
            statusLabel.text = BedsideText.string("Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered.", contact.name)
        }
        if call.mode == .video {
            let remoteTrack = peers.flatMap(\.videoTracks).first { !$0.isMuted && $0.track is VideoTrack }?.track as? VideoTrack
            remoteVideo.track = remoteTrack
            placeholder.isHidden = remoteTrack != nil
            personPhoto.isHidden = remoteTrack != nil
            localVideo.track = room.localParticipant.videoTracks.first { !$0.isMuted }?.track as? VideoTrack
            localVideo.isHidden = localVideo.track == nil
        }
        if hasConnectedPeer && mediaReady { playConnectionCue() }
    }

    private func playConnectionCue() {
        guard !connectionCuePlayed else { return }
        connectionCuePlayed = true; connectionCue.play(.connected)
    }

    @objc private func familyChanged() {
        guard let session = familySession, let state = FamilyCoordinator.shared.state, !isEnding, !isSwitchingToPhone else { return }
        guard let call = state.call, call.id == session.call.id, call.state != "ended" else {
            finish(message: BedsideText.language != .english ? "Call ended. Returning to Porch…" : state.call?.reason ?? "Call ended. Returning to Porch…"); return
        }
        if call.state == "accepted", !familyAccepted {
            familyAccepted = true; waitTask?.cancel(); ringback.stop(); refresh()
            waitTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard let self, !self.hasConnectedPeer else { return }
                self.finish(message: "Couldn't connect the call. Please try again.")
            }
        }
    }

    @objc private func toggleMicrophone() { changeMedia(camera: false) }
    @objc private func toggleCamera() { changeMedia(camera: true) }

    private func changeMedia(camera: Bool) {
        guard controlTask == nil, mediaReady, !isEnding, !isSwitchingToPhone, !camera || (call.mode == .video && !isPhoneCall) else { return }
        microphoneButton.isEnabled = false
        cameraButton.isEnabled = false
        controlTask = Task {
            defer { controlTask = nil }
            do {
                if camera {
                    try await room.localParticipant.setCamera(enabled: !room.localParticipant.isCameraEnabled())
                } else {
                    try await room.localParticipant.setMicrophone(enabled: !room.localParticipant.isMicrophoneEnabled())
                }
                guard !isEnding else { return }
                if camera && room.localParticipant.isCameraEnabled() { connectionCue.play(.connected) }
                microphoneButton.configuration?.title = BedsideText.string(room.localParticipant.isMicrophoneEnabled() ? "Mute" : "Unmute")
                cameraButton.configuration?.title = BedsideText.string(room.localParticipant.isCameraEnabled() ? "Camera off" : "Camera on")
                refresh()
            } catch {
                if !isEnding { statusLabel.text = BedsideText.string(camera ? "Couldn't change camera. Try again." : "Couldn't change microphone. Try again.") }
            }
            if !isEnding { microphoneButton.isEnabled = true; cameraButton.isEnabled = true }
        }
    }

    private func checkInactivity(speaking: Bool = false) {
        let peers = Array(room.remoteParticipants.values)
        let inboundPhone = familySession?.call.source == "phone"
        let phoneStatus = (inboundPhone ? peers.first : peers.first { $0.identity?.stringValue == "phone" })?.attributes["sip.callStatus"]
        let connected = mediaReady && !isEnding && !hasFailed && !isSwitchingToPhone
            && room.connectionState == .connected && !peers.isEmpty
            && (!(isPhoneCall || inboundPhone) || phoneStatus == "active" || phoneStatus == "automation")
        let speech = speaking || room.localParticipant.isSpeaking || peers.contains { $0.isSpeaking }
        if inactivity.update(at: ProcessInfo.processInfo.systemUptime, connected: connected, speaking: speech) {
            finish(message: "Call ended. Returning to the clock…")
        }
    }

    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        // Snapshot before the SDK changes these participants again. Even a brief
        // utterance between timer ticks should restart the silence interval.
        let speaking = !participants.isEmpty
        Task { @MainActor [weak self] in
            guard let self, room === self.room else { return }
            self.checkInactivity(speaking: speaking)
        }
    }

    private func finishPhoneCall() {
        finish(message: hasConnectedPeer ? "Call ended. Returning to the clock…" : "The phone call ended before it was answered.")
    }

    @objc private func endCall() { endedByCaller = true; finish() }

    private func finish(message: String? = nil) {
        guard !isEnding else { return }
        isEnding = true
        let unanswered = !endedByCaller && !hasConnectedPeer && !familyAccepted ? onUnanswered : nil
        ringback.stop()
        connectionCue.stop()
        connectionTask?.cancel()
        fallbackTask?.cancel()
        waitTask?.cancel()
        inactivityTask?.cancel()
        controlTask?.cancel()
        microphoneButton.isEnabled = false
        cameraButton.isEnabled = false
        endButton.isEnabled = false
        statusLabel.text = BedsideText.string(message ?? "Ending call…")
        if isPhoneCall || familySession?.call.source == "phone" || fallbackTask != nil {
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
            if let family = familySession, family.call.source == "phone" {
                do {
                    do { try await family.endConfirmed() }
                    catch { try await family.endConfirmed() }
                } catch {
                    hasFailed = true; isEnding = false; endButton.isEnabled = true
                    endButton.configuration?.title = BedsideText.string("Retry ending phone call")
                    statusLabel.text = BedsideText.string("Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again.")
                    return
                }
            } else { await familySession?.end() }
            familySession = nil
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
                    endButton.configuration?.title = BedsideText.string("Retry ending phone call")
                    statusLabel.text = BedsideText.string("Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again.")
                    return
                }
            }
            if message != nil { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            dismiss(animated: true) { unanswered?() }
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
        handleParticipantDisconnect(participant, in: room)
    }

    nonisolated func handleParticipantDisconnect(_ participant: Participant, in room: Room) {
        // LiveKit resets participant state after this callback returns.
        let identity = participant.identity?.stringValue
        Task { @MainActor [weak self] in
            guard let self, room === self.room else { return }
            if self.isPhoneCall, identity == "phone" {
                self.finishPhoneCall()
                return
            }
            guard !self.isSwitchingToPhone, !self.isPhoneCall else { return }
            if self.hasConnectedPeer, self.room.remoteParticipants.isEmpty {
                self.finish(message: "Call ended. Returning to the clock…")
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
            if state != .connected { self.inactivity.reset() }
            if state == .reconnecting { self.statusLabel.text = BedsideText.string("Reconnecting…") }
            if state == .connected { self.refresh() }
        }
    }

    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor [weak self] in
            guard let self, room === self.room, !self.isEnding, !self.isSwitchingToPhone, self.mediaReady else { return }
            self.finish(message: "The call disconnected. Returning to the clock…")
        }
    }

    nonisolated func room(_ room: Room, didStartReconnectWithMode mode: ReconnectMode) {
        Task { @MainActor [weak self] in
            guard let self, room === self.room, !self.isEnding, !self.hasFailed else { return }
            self.inactivity.reset()
            self.statusLabel.text = BedsideText.string("Reconnecting…")
        }
    }

    nonisolated func room(_ room: Room, didCompleteReconnectWithMode mode: ReconnectMode) {
        Task { @MainActor [weak self] in self?.refresh(source: room) }
    }

    nonisolated func room(_ room: Room, participant: Participant, didUpdateAttributes attributes: [String: String]) {
        let identity = participant.identity?.stringValue
        let status = attributes["sip.callStatus"]
        Task { @MainActor [weak self] in
            guard let self, room === self.room else { return }
            if self.isPhoneCall, identity == "phone", status == "hangup" { self.finishPhoneCall() }
            else { self.refresh(source: room) }
        }
    }

    private func phoneRequest(_ action: String, body: [String: Any]) async throws -> Data {
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
        guard let phoneNumber = contact.phoneNumber, !isEnding, !hasFailed, !hasConnectedPeer, !familyAccepted else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            hasFailed = true; ringback.stop()
            statusLabel.text = BedsideText.string("Microphone access is required.")
            placeholder.text = BedsideText.string("Allow Porch's microphone in Settings to make a phone call.")
            endButton.configuration?.title = BedsideText.string("Back to clock")
            return
        }
        await controlTask?.value
        guard !Task.isCancelled, !isEnding, !hasConnectedPeer else { return }
        // Prefer a Porch answer delivered just as the fallback timer fires.
        guard room.remoteParticipants.isEmpty else { refresh(); return }
        if let session = familySession {
            isSwitchingToPhone = true
            do {
                let response = try await session.service.send("fallback", ["callID": session.call.id])
                familySession = nil
                FamilyCoordinator.shared.update(response)
            } catch {
                isSwitchingToPhone = false
                if (error as? FamilyServiceError)?.code == "answered" {
                    familyAccepted = true; waitTask?.cancel()
                    if !mediaReady { finish(message: "They answered Porch, but this device couldn't connect. Please try again.") }
                    else {
                        waitTask = Task { [weak self] in
                            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                            guard let self, !self.hasConnectedPeer else { return }
                            self.finish(message: "Couldn't finish connecting the Porch call.")
                        }
                    }
                } else {
                    hasFailed = true; ringback.stop()
                    statusLabel.text = BedsideText.string("Couldn't switch to their phone.")
                    placeholder.text = BedsideText.error(error.localizedDescription)
                    endButton.configuration?.title = BedsideText.string("Back to clock")
                }
                return
            }
        }
        guard !Task.isCancelled, !isEnding else { return }
        let microphoneEnabled = !mediaReady || room.localParticipant.isMicrophoneEnabled()
        isSwitchingToPhone = true
        ringback.stop()
        mediaReady = false
        microphoneButton.isEnabled = false
        cameraButton.isEnabled = false
        cameraButton.isHidden = true
        statusLabel.text = BedsideText.string("Porch wasn't answered. Trying %@'s phone…", contact.name)
        // Disconnect releases camera/mic before joining a separate voice room.
        // Late Porch joins cannot connect to the phone conversation.
        let porchRoom = room
        room = Room()
        room.add(delegate: self)
        await porchRoom.disconnect()
        if !isEnding && !Task.isCancelled { ringback.start() }
        let family = familySession; familySession = nil
        await family?.end()
        remoteVideo.track = nil
        localVideo.track = nil
        localVideo.isHidden = true
        placeholder.isHidden = false
        personPhoto.isHidden = false
        placeholder.text = BedsideText.string("Phone call\nCamera is off")
        isPhoneCall = true
        updateKeypadHint()
        do {
            try Task.checkCancellation()
            var details: [String: Any] = ["phoneNumber": phoneNumber, "name": contact.name, "localRingback": true]
            if !NativeCallSettings.caregiverCode.isEmpty {
                details["contactAuthorization"] = try await NativeCallSettings.authorizePhone(phoneNumber, server: server)
            }
            try Task.checkCancellation()
            let data = try await phoneRequest("prepare", body: details)
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
            microphoneButton.configuration?.title = BedsideText.string(microphoneEnabled ? "Mute" : "Unmute")
            ringback.start()
            try await phoneAction("start", ticket: ticket)
            try Task.checkCancellation()
            isSwitchingToPhone = false
            mediaReady = true
            microphoneButton.isEnabled = true
            refresh()
            waitTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                guard let self, !self.hasConnectedPeer else { return }
                self.finish(message: "Their phone didn't answer. Returning to the clock…")
            }
        } catch {
            if Task.isCancelled || isEnding { return }
            hasFailed = true
            ringback.stop()
            await room.disconnect()
            isSwitchingToPhone = false
            statusLabel.text = BedsideText.string("Couldn't connect their phone.")
            placeholder.text = BedsideText.error(error.localizedDescription)
            endButton.configuration?.title = BedsideText.string("Back to clock")
            // End call also cleans up any telephone leg created before failure.
        }
    }
}
