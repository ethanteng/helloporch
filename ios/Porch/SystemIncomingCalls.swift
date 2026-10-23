import UIKit
import PushKit
import CallKit
import AVFoundation
import LiveKit
import PorchCore

extension Notification.Name {
    static let porchSystemCallChanged = Notification.Name("porch.systemCall.changed")
}

/// Owns ordinary incoming calls independently of scenes and view controllers.
/// PushKit must report to CallKit immediately, before any network request.
@MainActor final class SystemIncomingCalls: NSObject, @preconcurrency PKPushRegistryDelegate, @preconcurrency CXProviderDelegate, RoomDelegate {
    static let shared = SystemIncomingCalls()
    private let provider: CXProvider
    private let controller = CXCallController()
    private var registry: PKPushRegistry?
    private var pushToken: String?
    private var registrationTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var mediaTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var credential: FamilyCredential?
    private var uuid: UUID?
    private var expiry: TimeInterval = 0
    private var ending = false
    private var audioActive = false
    private var connected = false
    private var recentIDs: [UUID] = []
    private var mute = false
    /// Whether this call's camera belongs on while Porch is open. Leaving Porch turns
    /// the camera off; returning turns it back on unless the person turned it off.
    private var wantsCamera = false
    /// Leaving and returning to Porch change the camera in order, so a quick round
    /// trip can't leave it off once the earlier shutdown finishes.
    private var cameraTask: Task<Void, Never>?
    private var inactivity = CallInactivityTimer(timeout: nil)
    private(set) var room: Room?
    private(set) var call: FamilyCallRecord?
    private(set) var answered = false
    private(set) var pushReady = false
    private(set) var status = "Incoming Porch call"
    /// Family caregivers: this call can add a regular phone, such as a bank (see CallGuests.swift).
    private(set) var canAddPhoneGuests = false
    var familyCredential: FamilyCredential? { credential }
    var hasCall: Bool { uuid != nil }
    func owns(_ callID: String) -> Bool { uuid?.uuidString.lowercased() == callID.lowercased() }
    var callerContact: CallContact? {
        guard let call, let state = FamilyCoordinator.shared.state else { return nil }
        return ((try? CallSlots.load()) ?? CallSlots()).incomingContact(for: call, in: state)
    }
    var callerName: String { callerContact?.name ?? call?.callerName ?? incomingName }
    private var incomingName = "Family"
    private var mode: NativeCall.Mode = .voice
    var isVideo: Bool { mode == .video }

    private override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    func start() {
        guard registry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        self.registry = registry
        registry.desiredPushTypes = [.voIP]
    }

    func registerDevice() {
        let previous = registrationTask
        registrationTask?.cancel()
        guard let token = pushToken else { return }
        let profile = PorchDevice.credential(for: PorchDevice.experience)
        // Migrate existing installations while unlocked, before a locked launch.
        if let profile { try? PorchDevice.save(profile) }
        let environment = Bundle.main.object(forInfoDictionaryKey: "PorchAPNsEnvironment") as? String ?? "production"
        registrationTask = Task {
            do {
                await previous?.value
                try Task.checkCancellation()
                for role in [PorchExperience.bedside, .family] where role != profile?.role {
                    if let other = PorchDevice.credential(for: role) {
                        _ = try? await FamilyService(other).send("registerVoIP", ["token": NSNull()])
                    }
                }
                guard let profile else { pushReady = false; changed(); return }
                var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
                if microphone == .notDetermined && UIApplication.shared.applicationState == .active {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    microphone = AVCaptureDevice.authorizationStatus(for: .audio)
                }
                try Task.checkCancellation()
                let enabled = PorchDevice.experience == profile.role && microphone == .authorized
                let values: [String: Any] = enabled ? ["token": token, "environment": environment] : ["token": NSNull()]
                let response = try await FamilyService(profile).send("registerVoIP", values)
                pushReady = response.pushReady == true
            } catch { if !Task.isCancelled { pushReady = false } }
            changed()
        }
    }

    func prepareForPairing() async throws {
        registrationTask?.cancel()
        await registrationTask?.value
        if let previous = PorchDevice.credential(for: .family) {
            do { _ = try await FamilyService(previous).send("registerVoIP", ["token": NSNull()]) }
            catch { if (error as? FamilyServiceError)?.status != 401 { throw error } }
        }
        pushReady = false
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        pushToken = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        registerDevice()
    }
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        pushToken = nil; pushReady = false; registrationTask?.cancel(); changed()
        let previous = registrationTask
        registrationTask = Task {
            await previous?.value
            for role in [PorchExperience.bedside, .family] {
                if let profile = PorchDevice.credential(for: role) {
                    _ = try? await FamilyService(profile).send("registerVoIP", ["token": NSNull()])
                }
            }
        }
    }
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        let values = payload.dictionaryPayload
        // Even malformed or stale pushes must be reported, then ended after validation.
        report(id: (values["callID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
               recipient: values["recipientID"] as? String,
               name: values["callerName"] as? String ?? "Family",
               mode: values["mode"] as? String == "video" ? .video : .voice,
               expiresAt: (values["expiresAt"] as? NSNumber)?.doubleValue ?? 0, completion: completion)
    }

    func receive(_ call: FamilyCallRecord, credential: FamilyCredential) {
        guard call.kind == "call", call.state == "pending", credential.role == PorchDevice.experience,
              let id = UUID(uuidString: call.id) else { return }
        report(id: id, recipient: call.to, name: call.callerName, mode: call.mode, expiresAt: call.expiresAt, completion: {})
        if uuid == id { self.call = call }
    }

    private func report(id: UUID, recipient: String?, name: String, mode: NativeCall.Mode,
                        expiresAt: TimeInterval, completion: @escaping () -> Void) {
        if uuid == id { completion(); return }
        let rejected = uuid != nil || recentIDs.contains(id)
        if !rejected {
            uuid = id; incomingName = String(name.prefix(80)); self.mode = mode
            expiry = expiresAt; credential = PorchDevice.credential(for: PorchDevice.experience)
            inactivity = CallInactivityTimer(timeout: CallPreferences.disconnectAfterSilence() ? TimeInterval(CallPreferences.silenceSeconds()) : nil)
            ending = false; answered = false; connected = false; wantsCamera = false; status = "Incoming Porch call"
        }
        let update = CXCallUpdate()
        update.localizedCallerName = String(name.prefix(80))
        update.remoteHandle = CXHandle(type: .generic, value: "Porch family")
        update.hasVideo = mode == .video
        update.supportsHolding = false; update.supportsGrouping = false; update.supportsUngrouping = false; update.supportsDTMF = false
        provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
            completion()
            Task { @MainActor in
                guard let self else { return }
                if rejected {
                    if error == nil { self.provider.reportCall(with: id, endedAt: Date(), reason: .failed) }
                    return
                }
                guard self.uuid == id else { return }
                if error != nil { self.finish(reason: .failed); return }
                guard let profile = self.credential,
                      profile.credential.split(separator: ".").first.map(String.init) == recipient,
                      PorchDevice.experience == profile.role, expiresAt > Date().timeIntervalSince1970 else {
                    self.finish(reason: .remoteEnded); return
                }
                self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Incoming Porch call") { [weak self] in
                    self?.endBackgroundTask()
                    self?.finish(reason: .unanswered)
                }
                self.pollTask = Task { await self.poll(id: id, profile: profile) }
                self.changed()
            }
        }
    }

    private func poll(id: UUID, profile: FamilyCredential) async {
        var lastSuccess = Date()
        while !Task.isCancelled && uuid == id && !ending {
            do {
                let response = try await FamilyService(profile).send("poll", ["available": false, "receivedCallID": id.uuidString.lowercased()])
                guard uuid == id, !Task.isCancelled else { return }
                guard let state = response.state, let current = state.call, current.id == id.uuidString.lowercased(),
                      current.to == state.me.id, current.kind == "call", current.state != "ended" else {
                    finish(reason: .remoteEnded); return
                }
                call = current; expiry = current.expiresAt; lastSuccess = Date()
                canAddPhoneGuests = state.canAddPhoneGuests == true; changed()
            } catch {
                if Task.isCancelled { return }
                if (error as? FamilyServiceError)?.status == 401 || Date().timeIntervalSince(lastSuccess) > 25 {
                    finish(reason: .failed); return
                }
            }
            if Date().timeIntervalSince1970 >= expiry { finish(reason: .unanswered); return }
            if let room {
                // A bank's hold can be silent, so an added phone keeps the call from ending as quiet.
                let speaking = room.localParticipant.isSpeaking || room.remoteParticipants.values.contains { $0.isSpeaking || (call?.source == "porch" && $0.kind == .sip) }
                if inactivity.update(at: ProcessInfo.processInfo.systemUptime, connected: connected && audioActive && room.connectionState == .connected && !room.remoteParticipants.isEmpty, speaking: speaking) {
                    requestEnd(); return
                }
            }
            do { try await Task.sleep(nanoseconds: answered ? 5_000_000_000 : 1_000_000_000) } catch { return }
        }
    }

    func requestAnswer() {
        guard let uuid, !answered, !ending else { return }
        controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { [weak self] error in
            if error != nil { Task { @MainActor in self?.finish(reason: .failed) } }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard uuid == action.callUUID, !ending, let profile = credential else { action.fail(); return }
        connectionTask = Task {
            do {
                // Permission prompts must be completed during foreground setup.
                guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                    throw FamilyServiceError(message: "Allow microphone access in Settings to answer Porch calls.", status: 403)
                }
                let response = try await FamilyService(profile).send("acceptCall", ["callID": action.callUUID.uuidString.lowercased(), "available": true])
                try Task.checkCancellation()
                guard uuid == action.callUUID, let accepted = response.state?.call, accepted.state == "accepted" else { action.fail(); return }
                call = accepted; answered = true; status = "Connecting…"
                wantsCamera = isVideo && CallPreferences.startVideoWithCamera(as: profile.role)
                AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
                try AudioManager.shared.setEngineAvailability(.none)
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: mode == .video ? .videoChat : .voiceChat,
                                                               options: [.allowBluetoothHFP])
                let join = try await FamilyService(profile).send("joinCall", ["callID": accepted.id])
                try Task.checkCancellation()
                guard let token = join.token, let url = join.serverUrl, URL(string: url)?.scheme == "wss" else {
                    throw FamilyServiceError(message: "Couldn't connect this call.", status: 503)
                }
                let room = Room(); self.room = room; room.add(delegate: self)
                try await room.connect(url: url, token: token)
                try Task.checkCancellation()
                guard uuid == action.callUUID else { await room.disconnect(); action.fail(); return }
                connected = true
                action.fulfill()
                enableMedia()
                changed()
            } catch {
                action.fail()
                if uuid == action.callUUID { finish(reason: .failed) }
            }
        }
    }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        guard hasCall, !ending else { return }
        do {
            try AudioManager.shared.setEngineAvailability(.default)
            audioActive = true; enableMedia()
        } catch { finish(reason: .failed) }
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        audioActive = false
        if hasCall { try? AudioManager.shared.setEngineAvailability(.none) }
    }
    private func enableMedia() {
        guard connected, audioActive, let room, mediaTask == nil else { return }
        mediaTask = Task {
            do {
                try await room.localParticipant.setMicrophone(enabled: !mute)
                try Task.checkCancellation()
                status = "Call connected"
                endBackgroundTask()
                changed()
                resumeCamera()
            } catch { if !Task.isCancelled { finish(reason: .failed) } }
        }
    }
    func setCamera(enabled: Bool) async throws {
        guard let room, answered, connected, isVideo else { return }
        wantsCamera = enabled
        // The camera only runs in the foreground, so answering from the lock
        // screen starts audio and it can never start behind the lock screen.
        guard !enabled || UIApplication.shared.applicationState == .active else { return }
        if enabled {
            guard await AVCaptureDevice.requestAccess(for: .video) else { return }
        }
        guard !enabled || (wantsCamera && UIApplication.shared.applicationState == .active) else { return }
        try await room.localParticipant.setCamera(enabled: enabled)
        if enabled && UIApplication.shared.applicationState != .active { try await room.localParticipant.setCamera(enabled: false) }
        changed()
    }
    /// Starts the camera once Porch is open, when this call wants it.
    func resumeCamera() {
        guard wantsCamera, room != nil else { return }
        let previous = cameraTask
        cameraTask = Task {
            await previous?.value
            guard self.wantsCamera, let room = self.room, !room.localParticipant.isCameraEnabled(),
                  UIApplication.shared.applicationState == .active else { return }
            try? await self.setCamera(enabled: true)
        }
    }
    func enterBackground() {
        guard let room else { return }
        let previous = cameraTask
        cameraTask = Task {
            await previous?.value
            _ = try? await room.localParticipant.setCamera(enabled: false); changed()
        }
    }
    func requestEnd() {
        guard let uuid else { return }
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
            if error != nil { Task { @MainActor in self?.finish(reason: .failed) } }
        }
    }
    func requestMute() {
        guard let uuid else { return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: !mute))) { _ in }
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard action.callUUID == uuid, let room else { action.fail(); return }
        Task {
            do { try await room.localParticipant.setMicrophone(enabled: !action.isMuted); mute = action.isMuted; action.fulfill(); changed() }
            catch { action.fail() }
        }
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard action.callUUID == uuid else { action.fail(); return }
        finish(reason: nil); action.fulfill()
    }
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fail(); finish(reason: .failed)
    }
    func providerDidReset(_ provider: CXProvider) { finish(reason: nil) }

    private func finish(reason: CXCallEndedReason?) {
        guard let id = uuid, !ending else { return }
        ending = true; status = "Call ended"; changed()
        if reason != .unanswered && backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "End incoming Porch call") { [weak self] in self?.endBackgroundTask() }
        }
        if let reason { provider.reportCall(with: id, endedAt: Date(), reason: reason) }
        pollTask?.cancel(); connectionTask?.cancel(); mediaTask?.cancel()
        let connection = connectionTask, media = mediaTask, room = room, profile = credential
        recentIDs.append(id); recentIDs = Array(recentIDs.suffix(32))
        Task {
            await connection?.value; await media?.value
            await room?.disconnect()
            // Let the caller's existing wait/fallback timer own unanswered calls.
            // iOS ending our ringing execution window must not cancel phone fallback.
            if let profile, reason != .unanswered || profile.role == .bedside {
                // Disconnect locally first, then retry server cleanup of the SIP leg.
                for attempt in 0..<3 {
                    do { _ = try await FamilyService(profile).send("endCall", ["callID": id.uuidString.lowercased()]); break }
                    catch {
                        if (error as? FamilyServiceError)?.status == 404 { break }
                        if attempt < 2 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
                    }
                }
            }
            // Do not restore automatic audio handling until this room has stopped.
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
            try? AudioManager.shared.setEngineAvailability(.default)
            self.room = nil; call = nil; uuid = nil; credential = nil; answered = false
            connected = false; audioActive = false; mute = false; wantsCamera = false; mediaTask = nil; cameraTask = nil
            endBackgroundTask(); changed()
        }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    private func changed() { NotificationCenter.default.post(name: .porchSystemCallChanged, object: self) }
    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        // The bedside is never left on with only a phone a family caregiver added; the caregiver stays on with it.
        Task { @MainActor in
            let bedside = self.credential?.role == .bedside && self.call?.source == "porch"
            if room === self.room && self.connected && !room.remoteParticipants.values.contains(where: { !bedside || $0.kind != .sip }) { self.finish(reason: .remoteEnded) }
            else { self.changed() }
        }
    }
    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in if room === self.room && self.connected { self.finish(reason: .failed) } }
    }
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        guard !participants.isEmpty else { return }
        Task { @MainActor in if room === self.room { self.inactivity.reset() } }
    }
}

/// Foreground controls for the session that CallKit owns. Dismissing/backgrounding
/// this screen never disconnects its room.
final class SystemCallViewController: UIViewController, RoomDelegate {
    private let status = UILabel()
    private let stage = CallVideoStage()
    private let placeholder = UILabel()
    private lazy var personPhoto = RecipientAppearance.photoView(SystemIncomingCalls.shared.callerContact?.photoData)
    private let microphone = PorchStyle.button("Mute", symbol: "mic.slash")
    private let camera = PorchStyle.button("Camera on", symbol: "video")
    private var cameraEnabled = false
    private weak var observedRoom: Room?
    private var keypad = CallTrigger()
    private var guests: CallGuestControls?
    private var leftNotice: String?
    private var leftNoticeTask: Task<Void, Never>?
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); keypad.resetKeys(); becomeFirstResponder()
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        let slots = (try? CallSlots.load()) ?? CallSlots()
        for press in presses {
            guard PorchDevice.experience == .bedside, let key = press.key, let digit = key.keypadDigit else { unhandled.insert(press); continue }
            let action = slots.action(for: digit)
            guard action == .callControl || action == .toggleVideo else { unhandled.insert(press); continue }
            guard keypad.keyDown(Int(key.keyCode.rawValue)) else { continue }
            if action == .callControl { SystemIncomingCalls.shared.requestEnd() }
            else { camera.sendActions(for: .touchUpInside) }
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
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = PorchStyle.night
        overrideUserInterfaceStyle = .dark
        modalPresentationStyle = .fullScreen; isModalInPresentation = true
        let title = PorchStyle.label(SystemIncomingCalls.shared.callerName, size: 40, color: .white, weight: .semibold)
        status.font = PorchStyle.font(17); status.adjustsFontForContentSizeCategory = true
        status.textColor = .white; status.textAlignment = .center; status.numberOfLines = 0
        microphone.addAction(UIAction { _ in SystemIncomingCalls.shared.requestMute() }, for: .touchUpInside)
        let end = PorchStyle.button("End call", symbol: "phone.down.fill")
        end.addAction(UIAction { _ in SystemIncomingCalls.shared.requestEnd() }, for: .touchUpInside)
        CallScreenLayout.configure(microphone, title: "Mute", symbol: "mic.slash")
        CallScreenLayout.configure(camera, title: "Camera on", symbol: "video")
        CallScreenLayout.configure(end, title: "End call", symbol: "phone.down.fill", isEnd: true)
        camera.isHidden = !SystemIncomingCalls.shared.isVideo
        camera.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    let enabled = !self.cameraEnabled
                    try await SystemIncomingCalls.shared.setCamera(enabled: enabled)
                    self.cameraEnabled = SystemIncomingCalls.shared.room?.localParticipant.isCameraEnabled() == true
                    self.camera.configuration?.title = self.cameraEnabled ? "Camera off" : "Camera on"
                } catch { showPorchError(error, on: self) }
            }
        }, for: .touchUpInside)
        placeholder.text = "Voice call"; placeholder.textColor = .white; placeholder.textAlignment = .center
        placeholder.font = PorchStyle.font(28)
        // On the bedside's call, family can ring in another family member and caregivers can add a phone. Someone
        // who was rung in themselves can't add anyone.
        let calls = SystemIncomingCalls.shared
        if let credential = calls.familyCredential, credential.role == .family, let call = calls.call, call.source == "porch", call.guest != true {
            guests = CallGuestControls(host: self, credential: credential, callID: call.id, room: { SystemIncomingCalls.shared.room }) {
                .init(call: SystemIncomingCalls.shared.call, canAddPhone: SystemIncomingCalls.shared.canAddPhoneGuests, family: FamilyCoordinator.shared.state?.family ?? [])
            }
        }
        CallScreenLayout.install(in: view, video: stage, placeholder: placeholder, title: title, status: status,
                                 photo: personPhoto.image == nil ? nil : personPhoto, accessory: guests?.bar,
                                 buttons: [microphone, camera] + (guests.map { [$0.addButton] } ?? []) + [end])
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .porchSystemCallChanged, object: nil)
        refresh()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func refresh() {
        let calls = SystemIncomingCalls.shared
        guard calls.hasCall else { stage.show([]); dismiss(animated: true); return }
        if let room = calls.room, room !== observedRoom {
            room.add(delegate: self); observedRoom = room
        }
        status.text = calls.status
        guests?.refresh()
        let peers = calls.room?.remoteParticipants.values.map { $0 } ?? []
        let bedside = PorchDevice.experience == .bedside
        // Family see Mom first. The bedside sees whoever called it first.
        let mom = FamilyCoordinator.shared.state?.people.first { $0.role == .bedside }
        if calls.call?.source == "porch", calls.answered {
            if bedside {
                let lines = CallPeople.bedsideLines(peers, call: calls.call) + (leftNotice.map { [$0] } ?? [])
                if !lines.isEmpty { status.text = ([status.text ?? ""] + lines).joined(separator: "\n") }
            } else if let mom, !peers.isEmpty, !peers.contains(where: { $0.identity?.stringValue == mom.id }) {
                status.text = "\(mom.name) left the call."
            }
        }
        cameraEnabled = calls.room?.localParticipant.isCameraEnabled() == true
        camera.configuration?.title = cameraEnabled ? "Camera off" : "Camera on"
        microphone.configuration?.title = calls.room?.localParticipant.isMicrophoneEnabled() == true ? "Mute" : "Unmute"
        let tiles = CallPeople.tiles(peers, first: bedside ? calls.call?.from : mom?.id)
        stage.show(tiles)
        let showing = stage.isSplit || tiles.first?.track != nil
        personPhoto.isHidden = showing
        placeholder.isHidden = showing
        placeholder.text = calls.isVideo ? "Waiting for video" : "Voice call"
    }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in self?.refresh() }
    }
    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor [weak self] in self?.refresh() }
    }
    /// The bedside says when someone leaves a call that goes on, such as Ethan leaving Mom and David talking.
    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        let name = participant.name, kind = participant.kind
        Task { @MainActor [weak self] in
            guard let self, PorchDevice.experience == .bedside, kind != .sip, let name, !name.isEmpty,
                  SystemIncomingCalls.shared.room?.remoteParticipants.isEmpty == false else { return }
            self.leftNotice = BedsideText.string("%@ left the call", name); self.leftNoticeTask?.cancel()
            self.leftNoticeTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 6_000_000_000) } catch { return }
                self?.leftNotice = nil; self?.refresh()
            }
            self.refresh()
        }
    }
    nonisolated func room(_ room: Room, participant: Participant, didUpdateAttributes attributes: [String: String]) {
        Task { @MainActor [weak self] in self?.refresh() }
    }
}

extension SystemCallViewController: Cell2JackDigitReceiving {
    func receiveCell2JackDigit(_ digit: Int) -> String {
        switch (try? CallSlots.load())?.action(for: digit) {
        case .callControl:
            SystemIncomingCalls.shared.requestEnd()
            Cell2JackKeypad.shared.record(["kind": "callEndRequested", "screen": "systemCall"])
            return "system call end requested"
        case .toggleVideo: camera.sendActions(for: .touchUpInside); return "system camera key dispatched"
        default: return "system call key ignored"
        }
    }
}
