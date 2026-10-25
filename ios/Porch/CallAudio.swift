import UIKit
import AVFoundation
import CryptoKit
import LiveKit
import PorchCore

@MainActor final class PorchTonePlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var session: SessionRequirementHandle?
    private var tone: CallTone?
    var isPlaying: Bool { player?.isPlaying == true }
    static var isSilentPreview: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--family-silent")
        #else
        return false
        #endif
    }
    @discardableResult func play(_ tone: CallTone) -> Bool {
        if Self.isSilentPreview { return true }
        if self.tone == tone, isPlaying { return true }
        stop()
        do {
            // Share ownership with LiveKit. Releasing a cue must not deactivate a call.
            session = try AudioManager.shared.audioSession.acquire(requirement: .playbackOnly)
            let audio = try AVAudioPlayer(data: tone.wave())
            audio.delegate = self; audio.numberOfLoops = tone.loops ? -1 : 0; audio.volume = 0.7
            audio.prepareToPlay()
            guard audio.play() else { stop(); return false }
            player = audio; self.tone = tone
            return true
        } catch { stop(); return false }
    }
    func stop() {
        player?.stop(); player = nil; tone = nil
        try? session?.release(); session = nil
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in if self?.player === player { self?.stop() } }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in if self?.player === player { self?.stop() } }
    }
}

@MainActor protocol IncomingCallAudioPlaying: AnyObject {
    func ring() -> Bool
    func announce(name: String, video: Bool, language: BedsideLanguage, completion: @escaping (Bool) -> Void)
    func stop()
}

@MainActor enum PorchAnnouncementVoice {
    static func available(for language: BedsideLanguage) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { isOffered($0, for: language) }
            .sorted { label($0).localizedStandardCompare(label($1)) == .orderedAscending }
    }
    /// Novelty voices (Bubbles, Zarvox…) don't suit a bedside warning; personal voices need separate authorization.
    static func isOffered(_ voice: AVSpeechSynthesisVoice, for language: BedsideLanguage) -> Bool {
        if #available(iOS 17.0, *), !voice.voiceTraits.isDisjoint(with: [.isNoveltyVoice, .isPersonalVoice]) { return false }
        return language.supportsSpeechVoice(language: voice.language)
    }
    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        let region = Locale(identifier: "en").localizedString(forIdentifier: voice.language) ?? voice.language
        let quality: String
        if #available(iOS 16.0, *), voice.quality == .premium { quality = " · Premium" }
        else { quality = voice.quality == .enhanced ? " · Enhanced" : "" }
        return "\(voice.name) · \(region)\(quality)"
    }
    static func resolve(for language: BedsideLanguage, identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier),
           isOffered(voice, for: language) { return voice }
        guard let fallback = AVSpeechSynthesisVoice(language: language.speechLanguage),
              language.supportsSpeechVoice(language: fallback.language) else { return nil }
        return fallback
    }
}

/// Natural announcement voices: the server reads each sentence in the household's chosen voice
/// (lib/family/speech.ts) and this iPad keeps the clip. Until a clip is here, announcements use the built-in voice.
@MainActor enum PorchNaturalVoice {
    /// The household's natural voice for a language, when this paired bedside has one.
    static func selected(for language: BedsideLanguage) -> String? {
        guard PorchDevice.experience == .bedside else { return nil }
        return FamilyCoordinator.shared.state?.speech?.choices(for: language)?.selected
    }
    private static var folder: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PorchSpeech", isDirectory: true) }
    private static func file(_ text: String, language: BedsideLanguage, voiceID: String) -> URL {
        let key = SHA256.hash(data: Data("\(voiceID)|\(language.rawValue)|\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent("\(key).mp3")
    }
    static func cached(_ text: String, language: BedsideLanguage, voiceID: String) -> URL? {
        let url = file(text, language: language, voiceID: voiceID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    /// A clip that wouldn't play is fetched again next time.
    static func discard(_ url: URL) { try? FileManager.default.removeItem(at: url) }
    private static var loading: [URL: Task<URL?, Never>] = [:]
    /// The clip for a sentence, asking the server to read it if this iPad doesn't have it yet. nil when it isn't available.
    static func load(_ text: String, language: BedsideLanguage, voiceID: String) async -> URL? {
        let destination = file(text, language: language, voiceID: voiceID)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        if let task = loading[destination] { return await task.value }
        guard let credential = PorchDevice.credential(for: .bedside) else { return nil }
        let task = Task<URL?, Never> {
            do {
                // The server waits up to 15s for ElevenLabs, then stores the clip. The shared 12s limit
                // would drop that response, and prefetch would not try the sentence again for ten minutes.
                let response = try await FamilyService(credential).send("speech", ["language": language.rawValue, "text": text, "voiceID": voiceID], timeout: 30)
                guard let clip = response.clip, clip.voiceID == voiceID, let url = URL(string: clip.url), url.scheme == "https" else { return nil }
                let session = URLSession(configuration: .ephemeral)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: url); request.timeoutInterval = 15
                let (data, http) = try await session.data(for: request)
                guard (http as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty, data.count <= 2_000_000 else { return nil }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
                return destination
            } catch { return nil }
        }
        loading[destination] = task
        let result = await task.value
        loading[destination] = nil
        return result
    }
    /// The clip if it's here within `seconds`. One that arrives later is kept for next time.
    static func clip(_ text: String, language: BedsideLanguage, voiceID: String, within seconds: TimeInterval) async -> URL? {
        if let cached = cached(text, language: language, voiceID: voiceID) { return cached }
        let pending = Task { await load(text, language: language, voiceID: voiceID) }
        guard seconds > 0 else { return nil }
        return await first(of: pending, within: seconds)
    }
    /// A task's result if it finishes within `seconds`, otherwise nil right at the deadline.
    /// The task keeps running either way. (A task group would wait for it to finish.)
    static func first<Value: Sendable>(of task: Task<Value?, Never>, within seconds: TimeInterval) async -> Value? {
        let race = Race<Value>()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            race.deadline = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                race.finish(nil)
            }
            Task { @MainActor in race.finish(await task.value) }
        }
    }
    /// Resumes its waiter once, with whichever result arrives first.
    @MainActor private final class Race<Value: Sendable> {
        var continuation: CheckedContinuation<Value?, Never>?
        var deadline: Task<Void, Never>?
        func finish(_ value: Value?) {
            deadline?.cancel(); deadline = nil
            continuation?.resume(returning: value); continuation = nil
        }
    }
    private static var attempted: [URL: Date] = [:]
    private static var prefetching: Task<Void, Never>?
    /// Set when a newer snapshot arrives while a pass is already reading sentences, so that pass runs once more.
    private static var prefetchAgain = false
    /// Prepares what the bedside may say next, one sentence at a time: drop-in announcements for everyone
    /// who may drop in, who it's calling for everyone on its keypad, prompts and confirmations for leaving
    /// family a message, and the notice and announcements for waiting messages.
    /// A drop-in or a call never waits for a clip, so this is how its announcement gets the natural voice.
    /// A sentence that couldn't be prepared is tried again after ten minutes.
    static func prefetch(_ state: FamilySnapshot, slots: CallSlots) {
        let language = BedsideText.language
        guard let voiceID = state.speech?.choices(for: language)?.selected else { return }
        // A poll starts this before the download queue updates. Keep the newer count instead of dropping it.
        if prefetching != nil { prefetchAgain = true; return }
        let contacts = slots.contacts.compactMap { $0 }
        var texts: [String] = []
        if state.dropInEnabled {
            for person in state.people where person.role == .family {
                let name = contacts.first { $0.familyMemberID == person.id }?.name ?? person.name
                if person.permissions.video { texts.append(PorchIncomingAudio.message(name: name, video: true, language: language)) }
                if person.permissions.audio { texts.append(PorchIncomingAudio.message(name: name, video: false, language: language)) }
            }
            for approval in state.phoneDropIns ?? [] {
                let name = contacts.first { $0.nativeCall != nil && $0.phoneNumbers.contains(approval.number) }?.name ?? approval.name
                texts.append(PorchIncomingAudio.message(name: name, video: false, language: language))
            }
        }
        for contact in contacts where contact.nativeCall != nil { texts.append(OutgoingCallAnnouncement.message(name: contact.name, language: language)) }
        if state.messagesEnabled != false {
            for contact in contacts where contact.familyMemberID != nil {
                texts += BedsideVoicemailViewController.Reason.allCases.map { $0.prompt(for: contact.name) }
                texts.append(BedsideVoicemailViewController.sentConfirmation(to: contact.name))
            }
            let waiting = (state.messages ?? []).filter { $0.held != true }
            // The notice speaks `ready` (downloaded and unplayed), which is below the inbox count while a
            // message is still downloading or was played here before the server drops it. That count goes first.
            var noticeCounts: [Int] = []
            let readyCount = BedsideMessages.shared.ready.count
            if waiting.count > 1, (1..<waiting.count).contains(readyCount) { noticeCounts.append(readyCount) }
            if !waiting.isEmpty { noticeCounts.append(waiting.count) }
            for count in noticeCounts { texts.append(MessageNoticeView.text(count: count)) }
            for message in waiting { texts.append(MessagePlayerViewController.announcement(for: message, slots: slots)) }
        }
        let now = Date()
        var seen = Set<String>()
        let pending = texts.filter { seen.insert($0).inserted }.filter { text in
            let url = file(text, language: language, voiceID: voiceID)
            return !FileManager.default.fileExists(atPath: url.path) && attempted[url].map { now.timeIntervalSince($0) > 600 } ?? true
        }
        guard !pending.isEmpty else { return }
        for text in pending { attempted[file(text, language: language, voiceID: voiceID)] = now }
        prefetching = Task {
            for text in pending { _ = await load(text, language: language, voiceID: voiceID) }
            prefetching = nil
            guard prefetchAgain, let latest = FamilyCoordinator.shared.state else { prefetchAgain = false; return }
            prefetchAgain = false
            prefetch(latest, slots: (try? CallSlots.load()) ?? slots)
        }
    }
}

/// Plays one natural voice clip.
@MainActor final class PorchClipPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: ((Bool) -> Void)?
    /// false when the clip can't be played, so the caller can speak with the built-in voice instead.
    func play(_ url: URL, completion: @escaping (Bool) -> Void) -> Bool {
        stop()
        guard let audio = try? AVAudioPlayer(contentsOf: url) else { return false }
        audio.delegate = self; audio.prepareToPlay()
        guard audio.play() else { return false }
        player = audio; self.completion = completion
        return true
    }
    func stop() { player?.stop(); player = nil; completion = nil }
    private func finished(_ audio: AVAudioPlayer, _ success: Bool) {
        guard player === audio else { return }
        let callback = completion; player = nil; completion = nil; callback?(success)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.finished(player, flag) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.finished(player, false) }
    }
}

/// Plays only on this device: a drop-in's announcement before joining a room or enabling its camera/mic,
/// and who the bedside is calling as its call starts.
@MainActor final class PorchIncomingAudio: NSObject, IncomingCallAudioPlaying, AVSpeechSynthesizerDelegate {
    private let tone = PorchTonePlayer()
    private let clip = PorchClipPlayer()
    private let speech = AVSpeechSynthesizer()
    private var session: SessionRequirementHandle?
    private var startTimer: Timer?
    private var timeout: Timer?
    private var utterance: AVSpeechUtterance?
    private var announcement: UUID?
    private var completion: ((Bool) -> Void)?

    override init() { super.init(); speech.delegate = self; speech.usesApplicationAudioSession = true }
    static func message(name: String, video: Bool, language: BedsideLanguage) -> String {
        language.format(video ? "%@ is dropping in with video. Connecting in five seconds." : "%@ is dropping in with audio. Connecting in five seconds.", arguments: [name])
    }
    func ring() -> Bool { stop(); return tone.play(.incoming) }
    func announce(name: String, video: Bool, language: BedsideLanguage, completion: @escaping (Bool) -> Void) {
        announce(name: name, video: video, language: language, voiceIdentifier: BedsidePreferences.load().announcementVoiceIdentifier(for: language),
                 naturalVoice: PorchNaturalVoice.selected(for: language), completion: completion)
    }
    /// An explicit choice lets settings preview unsaved changes, including System default. A preview waits a few
    /// seconds for a natural clip; a drop-in never waits, so it uses the natural voice only once the clip is here.
    func announce(name: String, video: Bool, language: BedsideLanguage, voiceIdentifier: String?, naturalVoice: String?, naturalWait: TimeInterval = 0, completion: @escaping (Bool) -> Void) {
        speak(Self.message(name: name, video: video, language: language), language: language, voiceIdentifier: voiceIdentifier,
              naturalVoice: naturalVoice, naturalWait: naturalWait, completion: completion)
    }
    /// The announcement chime, then the sentence.
    func speak(_ message: String, language: BedsideLanguage, voiceIdentifier: String?, naturalVoice: String?, naturalWait: TimeInterval = 0, completion: @escaping (Bool) -> Void) {
        stop()
        if PorchTonePlayer.isSilentPreview { completion(true); return }
        self.completion = completion
        do { session = try AudioManager.shared.audioSession.acquire(requirement: .playbackOnly) }
        catch { finish(false); return }
        let voice = PorchAnnouncementVoice.resolve(for: language, identifier: voiceIdentifier)
        guard tone.play(.announcement), voice != nil || naturalVoice != nil else { finish(false); return }
        utterance = voice.map { voice in
            let utterance = AVSpeechUtterance(string: message)
            utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            return utterance
        }
        let announcement = UUID(); self.announcement = announcement
        startTimer = Timer.scheduledTimer(withTimeInterval: CallTone.announcement.duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                var ready: URL?
                if let naturalVoice { ready = await PorchNaturalVoice.clip(message, language: language, voiceID: naturalVoice, within: naturalWait) }
                guard let self, self.announcement == announcement else { return }
                if let ready, self.clip.play(ready, completion: { [weak self] success in
                    guard let self, self.announcement == announcement else { return }
                    if success { self.finish(true) } else { PorchNaturalVoice.discard(ready); self.speakBuiltIn() }
                }) { self.armWatchdog(); return }
                if let ready { PorchNaturalVoice.discard(ready) }
                self.speakBuiltIn()
            }
        }
        // Until speech starts. A preview may spend several seconds fetching a clip; that wait must not
        // come out of the time allowed for the sentence itself. A stuck speech service still cannot
        // silently start an automatic video call.
        armWatchdog()
    }
    /// 15 seconds from when speech starts, or from the announcement if it never does.
    private func armWatchdog() {
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.finish(false) } }
    }
    private func speakBuiltIn() {
        guard let utterance else { finish(false); return }
        armWatchdog()
        speech.speak(utterance)
    }
    func stop() {
        completion = nil; utterance = nil; announcement = nil
        startTimer?.invalidate(); startTimer = nil; timeout?.invalidate(); timeout = nil
        speech.stopSpeaking(at: .immediate); clip.stop(); tone.stop()
        try? session?.release(); session = nil
    }
    private func finish(_ success: Bool) { let callback = completion; stop(); callback?(success) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in if self?.utterance === utterance { self?.finish(true) } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in if self?.utterance === utterance { self?.finish(false) } }
    }
}

@MainActor protocol OutgoingCallSpeaking: AnyObject {
    func speak(_ message: String, language: BedsideLanguage, completion: @escaping (Bool) -> Void)
    func stop()
}
extension PorchIncomingAudio: OutgoingCallSpeaking {
    /// In the bedside's saved voice. Like a drop-in, a call never waits for a natural clip that isn't here yet.
    func speak(_ message: String, language: BedsideLanguage, completion: @escaping (Bool) -> Void) {
        speak(message, language: language, voiceIdentifier: BedsidePreferences.load().announcementVoiceIdentifier(for: language),
              naturalVoice: PorchNaturalVoice.selected(for: language), completion: completion)
    }
}

/// Says who the bedside is calling the moment a key is pressed, while the call is still being set up.
/// The call screen's ringing, and the message screen for someone who can't take calls, wait for the sentence.
@MainActor final class OutgoingCallAnnouncement {
    static func message(name: String, language: BedsideLanguage) -> String { language.format("Calling %@.", arguments: [name]) }
    private let audio: OutgoingCallSpeaking
    /// Not stored on self. Speech can finish before init returns, and a weak capture of self is nil until
    /// then, which would leave ringback and the message screen waiting for a sentence that already ended.
    private let outcome = Outcome()
    var isFinished: Bool { outcome.isFinished }
    init(calling name: String, audio: OutgoingCallSpeaking? = nil) {
        let speaker = audio ?? PorchIncomingAudio()
        self.audio = speaker
        let language = BedsideText.language
        let outcome = self.outcome
        speaker.speak(Self.message(name: name, language: language), language: language) { _ in outcome.finish() }
    }
    /// Runs `next` once the sentence is over: said, couldn't be said, or stopped.
    func then(_ next: @escaping () -> Void) {
        if outcome.isFinished { next() } else { outcome.waiting.append(next) }
    }
    func finished() async { await withCheckedContinuation { continuation in then { continuation.resume() } } }
    func stop() { audio.stop(); outcome.finish() }

    private final class Outcome {
        var waiting: [() -> Void] = []
        private(set) var isFinished = false
        func finish() {
            guard !isFinished else { return }
            isFinished = true
            let next = waiting
            waiting = []
            next.forEach { $0() }
        }
    }
}
