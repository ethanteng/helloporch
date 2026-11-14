import UIKit
import LiveKit
import PorchCore

/// Live translation on a Porch call with the bedside (lib/family/translation.ts, and the translator in translator/).
/// The family member on the call turns it on when they can't get something across, and off again; every call starts
/// with it off. They can change the language the bedside hears for this call, and see what the translator heard and
/// said, so they can tell when something was misheard. The bedside shows "Translation on" and, large, what the
/// translator says to it. Each side hears only its own translation track, with the other voices lowered under it.
///
/// The call screen forwards its room's events here: data, subscribed tracks and people coming and going.
@MainActor final class CallTranslation {
    /// Family: the switch, the language and the conversation. Bedside: the banner and caption. Hidden until needed.
    let panel = UIStackView()
    private let isBedside: Bool
    private let credential: FamilyCredential
    private let callID: String
    /// What the family calls the bedside's person, such as "Mom".
    private let peerName: String
    private let room: () -> Room?
    private let call: () -> FamilyCallRecord?
    private var myID: String { credential.credential.split(separator: ".").first.map(String.init) ?? "" }
    /// The translator is in the call, as it last said or as the room shows.
    private var translatorOn = false

    // Family
    private let toggle = UISwitch()
    private let languageButton = UIButton(type: .system)
    private let notice = PorchStyle.label("", size: 15, color: PorchStyle.nightSecondary)
    private let transcript = UIStackView()
    private var lines: [CallTranslationLine] = []
    /// The language chosen on this phone for this call, before the server confirms it.
    private var chosen: BedsideLanguage?
    /// On or off as last asked, until the call record catches up.
    private var requested: Bool?
    private var sending = false

    // Bedside
    private let banner = PorchStyle.label("", size: 17, color: PorchStyle.nightSecondary, weight: .semibold)
    private let caption = PorchStyle.label("", size: 30, color: .white, weight: .semibold)
    private var captionTask: Task<Void, Never>?
    /// How long a caption stays after the translator stops adding to it.
    private static let captionSeconds: UInt64 = 30

    init(bedside: Bool, credential: FamilyCredential, callID: String, peerName: String, room: @escaping () -> Room?, call: @escaping () -> FamilyCallRecord?) {
        isBedside = bedside; self.credential = credential; self.callID = callID; self.peerName = peerName; self.room = room; self.call = call
        panel.axis = .vertical; panel.spacing = 6
        panel.accessibilityIdentifier = "call.translation"
        if bedside {
            banner.text = BedsideText.string("Translation on")
            banner.textAlignment = .center
            caption.textAlignment = .center
            caption.accessibilityIdentifier = "call.translation.caption"
            panel.addArrangedSubview(banner); panel.addArrangedSubview(caption)
        } else {
            let icon = UIImageView(image: UIImage(systemName: "character.bubble"))
            icon.tintColor = .white
            icon.setContentHuggingPriority(.required, for: .horizontal)
            let title = PorchStyle.label("Translate", size: 17, color: .white, weight: .semibold)
            var language = UIButton.Configuration.gray()
            language.cornerStyle = .capsule
            language.baseForegroundColor = .white
            language.image = UIImage(systemName: "chevron.up.chevron.down")
            language.imagePlacement = .trailing; language.imagePadding = 4
            language.titleLineBreakMode = .byTruncatingTail
            languageButton.configuration = language
            languageButton.showsMenuAsPrimaryAction = true
            languageButton.accessibilityIdentifier = "call.translation.language"
            languageButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            toggle.accessibilityLabel = "Translate"
            toggle.accessibilityIdentifier = "call.translation.toggle"
            toggle.setContentHuggingPriority(.required, for: .horizontal)
            toggle.addAction(UIAction { [weak self] _ in self?.switched() }, for: .valueChanged)
            let row = UIStackView(arrangedSubviews: [icon, title, languageButton, toggle])
            row.spacing = 8; row.alignment = .center
            transcript.axis = .vertical; transcript.spacing = 8
            transcript.accessibilityIdentifier = "call.translation.transcript"
            notice.textAlignment = .center
            panel.addArrangedSubview(transcript); panel.addArrangedSubview(row); panel.addArrangedSubview(notice)
        }
        refresh()
    }

    /// The language the bedside hears: chosen here, or confirmed by the server, or the bedside's own.
    private var language: BedsideLanguage? {
        chosen ?? call()?.translation.flatMap { BedsideLanguage(rawValue: $0.language) }
    }
    private var isOn: Bool { requested ?? call()?.translation?.on ?? translatorOn }

    /// Call whenever the household's call or the room changes.
    func refresh() {
        if let requested, call()?.translation?.on == requested { self.requested = nil }
        if isBedside {
            panel.isHidden = !translatorOn
            return
        }
        let record = call()
        panel.isHidden = !(record?.translationAvailable == true || isOn)
        toggle.isOn = isOn
        toggle.isEnabled = !sending
        languageButton.isEnabled = !sending
        languageButton.configuration?.title = language?.choiceLabel ?? "\(peerName)'s language"
        languageButton.menu = UIMenu(title: "\(peerName) hears", children: BedsideLanguage.allCases.map { option in
            UIAction(title: option.choiceLabel, state: option == language ? .on : .off) { [weak self] _ in self?.choose(option) }
        })
        notice.isHidden = notice.text?.isEmpty != false
        showTranscript()
    }

    // MARK: Room events

    /// Data on the call. Only the translator's messages are used, so no one on the call can put words on the bedside.
    func receive(_ data: Data, topic: String, from participant: RemoteParticipant?) {
        guard topic == CallTranslationMessage.topic, participant?.kind == .agent, let message = CallTranslationMessage.decode(data) else { return }
        switch message {
        case .state(let on, _):
            translatorOn = on
            if !on { ended() }
        case .line(let line):
            if isBedside { if let said = line.said { showCaption(said) } }
            else { lines.append(line); if lines.count > 20 { lines.removeFirst() } }
        case .speaking(let speaking):
            lowerVoices(speaking)
        }
        refresh()
    }

    /// The translator speaks to each side on its own track. Leave the other side's track, in case the room didn't.
    func subscribed(_ publication: RemoteTrackPublication, of participant: RemoteParticipant) {
        guard participant.kind == .agent, publication.kind == .audio else { return }
        translatorOn = true
        if publication.name != CallTranslationMessage.trackName(forBedside: isBedside) {
            Task { try? await publication.set(subscribed: false) }
        }
        refresh()
    }

    /// Someone joined or left. When the translator leaves, captions go and voices return to normal.
    func peopleChanged() {
        let present = room()?.remoteParticipants.values.contains { $0.kind == .agent } == true
        if translatorOn && !present { translatorOn = false; ended() }
        refresh()
    }

    private func ended() {
        lowerVoices(false)
        captionTask?.cancel(); caption.text = nil
    }

    private func lowerVoices(_ lower: Bool) {
        guard let room = room() else { return }
        for participant in room.remoteParticipants.values where participant.kind != .agent {
            for publication in participant.audioTracks { (publication.track as? RemoteAudioTrack)?.volume = lower ? 0.3 : 1 }
        }
    }

    // MARK: Bedside

    private func showCaption(_ text: String) {
        caption.text = text
        UIAccessibility.post(notification: .announcement, argument: nil)
        captionTask?.cancel()
        captionTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: Self.captionSeconds * 1_000_000_000) } catch { return }
            self?.caption.text = nil
        }
    }

    // MARK: Family

    private func switched() { send(on: toggle.isOn, language: chosen) }

    private func choose(_ option: BedsideLanguage) {
        chosen = option
        if isOn { send(on: true, language: option) } else { refresh() }
    }

    private func send(on: Bool, language: BedsideLanguage?) {
        requested = on; sending = true
        notice.text = on ? "Starting translation…" : "Turning translation off…"
        refresh()
        Task { [weak self, credential, callID] in
            var values: [String: Any] = ["callID": callID, "on": on]
            if let language { values["language"] = language.rawValue }
            do {
                let response = try await FamilyService(credential).send("setCallTranslation", values)
                FamilyCoordinator.shared.update(response)
                self?.notice.text = nil
            } catch {
                self?.requested = nil
                self?.notice.text = error.localizedDescription
            }
            self?.sending = false
            self?.refresh()
        }
    }

    /// The last few things said, newest at the bottom: what the translator heard and what it said for the other side.
    private func showTranscript() {
        transcript.arrangedSubviews.forEach { $0.removeFromSuperview() }
        transcript.isHidden = lines.isEmpty || !isOn
        for line in lines.suffix(3) {
            let entry = UIStackView(); entry.axis = .vertical; entry.spacing = 2
            if line.fromBedside {
                // Their words in your language first; what they actually said below.
                entry.addArrangedSubview(PorchStyle.label("\(line.name): \(line.said ?? line.heard)", size: 17, color: .white, weight: .semibold))
                if line.said != nil { entry.addArrangedSubview(PorchStyle.label(line.heard, size: 15, color: PorchStyle.nightSecondary)) }
            } else {
                let who = line.speaker == myID ? "You" : line.name
                entry.addArrangedSubview(PorchStyle.label("\(who): \(line.heard)", size: 15, color: PorchStyle.nightSecondary))
                if let said = line.said { entry.addArrangedSubview(PorchStyle.label("\(peerName) hears: \(said)", size: 17, color: .white, weight: .semibold)) }
            }
            for case let label as UILabel in entry.arrangedSubviews { label.numberOfLines = 3; label.textAlignment = .natural }
            transcript.addArrangedSubview(entry)
        }
    }
}
