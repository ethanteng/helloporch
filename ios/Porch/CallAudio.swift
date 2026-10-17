import UIKit
import AVFoundation
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

/// Plays only on this device, before joining a room or enabling its camera/mic.
@MainActor final class PorchIncomingAudio: NSObject, IncomingCallAudioPlaying, AVSpeechSynthesizerDelegate {
    private let tone = PorchTonePlayer()
    private let speech = AVSpeechSynthesizer()
    private var session: SessionRequirementHandle?
    private var startTimer: Timer?
    private var timeout: Timer?
    private var utterance: AVSpeechUtterance?
    private var completion: ((Bool) -> Void)?

    override init() { super.init(); speech.delegate = self; speech.usesApplicationAudioSession = true }
    func ring() -> Bool { stop(); return tone.play(.incoming) }
    func announce(name: String, video: Bool, language: BedsideLanguage, completion: @escaping (Bool) -> Void) {
        announce(name: name, video: video, language: language,
                 voiceIdentifier: BedsidePreferences.load().announcementVoiceIdentifier(for: language), completion: completion)
    }
    /// An explicit choice lets settings preview unsaved changes, including System default.
    func announce(name: String, video: Bool, language: BedsideLanguage, voiceIdentifier: String?, completion: @escaping (Bool) -> Void) {
        stop()
        if PorchTonePlayer.isSilentPreview { completion(true); return }
        self.completion = completion
        do { session = try AudioManager.shared.audioSession.acquire(requirement: .playbackOnly) }
        catch { finish(false); return }
        guard tone.play(.announcement), let voice = PorchAnnouncementVoice.resolve(for: language, identifier: voiceIdentifier) else { finish(false); return }
        let message = language.format(video ? "%@ is dropping in with video. Connecting in five seconds." : "%@ is dropping in with audio. Connecting in five seconds.", arguments: [name])
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        self.utterance = utterance
        startTimer = Timer.scheduledTimer(withTimeInterval: CallTone.announcement.duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self, let utterance = self.utterance else { return }; self.speech.speak(utterance) }
        }
        // A failed speech service must never silently start an automatic video call.
        timeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in Task { @MainActor [weak self] in self?.finish(false) } }
    }
    func stop() {
        completion = nil; utterance = nil
        startTimer?.invalidate(); startTimer = nil; timeout?.invalidate(); timeout = nil
        speech.stopSpeaking(at: .immediate); tone.stop()
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
