import UIKit
import LiveKit
import PorchCore

/// Live translation on a Porch call with the bedside (lib/family/translation.ts, and the translator in translator/).
/// The family member on the call taps Translate, among the call's buttons, when they can't get something across: it
/// starts at once, in the bedside's language. Another tap on the button, now Translating, stops it; every call starts
/// with it off. While it's on, a card above the buttons says which language the bedside hears and shows the latest
/// exchange. Tapping the card opens a sheet to change the language for this call, read back the conversation (so they
/// can tell when something was misheard) or stop. The bedside shows "Translation on" and, large, what the translator
/// says to it. Each side hears only its own translation track, with the other voices lowered under it.
///
/// The call screen forwards its room's events here: data, subscribed tracks and people coming and going.
/// Which translation track each side hears isn't up to the screen: see `CallTranslationTracks`.
@MainActor final class CallTranslation {
    /// Family: the card above the call's buttons while translation is on. Bedside: the banner and caption.
    let panel = UIStackView()
    /// Family: Translate, among the call's buttons. Hidden until the bedside's app can show translation. Nil on the bedside.
    let button: UIButton?
    private let isBedside: Bool
    private let credential: FamilyCredential
    private let callID: String
    /// What the family calls the bedside's person, such as "Mom".
    let peerName: String
    private let room: () -> Room?
    private let call: () -> FamilyCallRecord?
    private var myID: String { credential.credential.split(separator: ".").first.map(String.init) ?? "" }
    /// The translator is in the call, as it last said or as the room shows.
    private var translatorOn = false

    // Family
    private let header = CallTranslationHeader()
    private let hint = PorchStyle.systemLabel("", size: 16, color: PorchStyle.nightSecondary)
    private let notice = PorchStyle.systemLabel("", size: 15, color: PorchStyle.nightSecondary)
    private let transcript = UIStackView()
    /// The last few things said, newest last.
    private(set) var lines: [CallTranslationLine] = []
    /// The language chosen on this phone for this call, before the server confirms it.
    private var chosen: BedsideLanguage?
    /// On or off as last asked, until the call record catches up.
    private var requested: Bool?
    private(set) var sending = false
    /// Why the last change didn't go through, for a few seconds.
    private(set) var problem: String?
    private var problemTask: Task<Void, Never>?
    private weak var sheet: CallTranslationSheet?

    // Bedside
    private let banner = PorchStyle.systemLabel("", size: 17, color: PorchStyle.nightSecondary, weight: .semibold)
    private let caption = PorchStyle.systemLabel("", size: 30, color: .white, weight: .semibold)
    private var captionTask: Task<Void, Never>?
    /// How long a caption stays after the translator stops adding to it.
    private static let captionSeconds: UInt64 = 30

    init(bedside: Bool, credential: FamilyCredential, callID: String, peerName: String, room: @escaping () -> Room?, call: @escaping () -> FamilyCallRecord?) {
        isBedside = bedside; self.credential = credential; self.callID = callID; self.peerName = peerName; self.room = room; self.call = call
        button = bedside ? nil : UIButton(type: .system)
        panel.axis = .vertical; panel.spacing = 6
        panel.accessibilityIdentifier = "call.translation"
        if bedside {
            banner.text = BedsideText.string("Translation on")
            banner.textAlignment = .center
            caption.textAlignment = .center
            caption.accessibilityIdentifier = "call.translation.caption"
            panel.addArrangedSubview(banner); panel.addArrangedSubview(caption)
        } else {
            panel.spacing = 4
            if let button {
                CallScreenLayout.configure(button, title: "Translate", symbol: "character.bubble")
                button.accessibilityIdentifier = "call.translation.toggle"
                button.addAction(UIAction { [weak self] _ in self?.tapped() }, for: .touchUpInside)
            }
            header.accessibilityIdentifier = "call.translation.language"
            header.addAction(UIAction { [weak self] _ in self?.openSheet() }, for: .touchUpInside)
            transcript.axis = .vertical; transcript.spacing = 8
            transcript.accessibilityIdentifier = "call.translation.transcript"
            panel.addArrangedSubview(header); panel.addArrangedSubview(hint); panel.addArrangedSubview(transcript); panel.addArrangedSubview(notice)
            panel.setCustomSpacing(8, after: hint)
        }
        refresh()
    }

    /// The language the bedside hears: chosen here, or confirmed by the server. Nil until then: the bedside's own.
    var language: BedsideLanguage? {
        chosen ?? call()?.translation.flatMap { BedsideLanguage(rawValue: $0.language) }
    }
    var isOn: Bool { requested ?? call()?.translation?.on ?? translatorOn }
    /// Whether a line was said by this phone's person, for "You".
    func isMine(_ line: CallTranslationLine) -> Bool { line.speaker == myID }

    /// Call whenever the household's call or the room changes.
    func refresh() {
        if let requested, call()?.translation?.on == requested { self.requested = nil }
        // The call screen can open after the translator is already in the room, such as a call answered on the
        // lock screen. Its first state message and track subscription are not delivered again, and the bedside
        // hides its captions until it has heard one of those.
        if room()?.remoteParticipants.values.contains(where: { $0.kind == .agent }) == true { translatorOn = true }
        if isBedside {
            panel.isHidden = !translatorOn
            return
        }
        let on = isOn
        if let button {
            let wasHidden = button.isHidden
            button.isHidden = !(call()?.translationAvailable == true || on)
            button.isEnabled = !sending
            button.configuration?.title = on ? "Translating" : "Translate"
            button.configuration?.image = UIImage(systemName: on ? "character.bubble.fill" : "character.bubble")
            button.configuration?.baseBackgroundColor = on ? CallTranslationColors.on : PorchStyle.nightSurface
            button.configuration?.baseForegroundColor = on ? PorchStyle.ink : .white
            button.accessibilityHint = on ? "Stops translating." : "Translates what you say for \(peerName), and what \(peerName) says for you."
            // The words got longer or shorter, so the call's buttons may wrap differently.
            if wasHidden == button.isHidden { CallButtonRows.relayout(containing: button) }
        }
        let starting = sending && requested == true
        header.isHidden = !on
        header.isEnabled = !sending
        header.change.forEach { $0.isHidden = starting }
        if let language, !starting {
            header.title.text = "\(peerName) hears \(language.displayName)"
            header.accessibilityLabel = "\(peerName) hears \(language.choiceLabel)"
            header.accessibilityHint = "Change the language, see the conversation or stop translating."
        } else {
            header.title.text = "Starting translation…"
            header.accessibilityLabel = header.title.text; header.accessibilityHint = nil
        }
        notice.text = problem
        notice.isHidden = problem == nil
        hint.isHidden = !on || starting || !lines.isEmpty || language == nil || problem != nil
        hint.text = language.map { "Talk as you usually do, even mixing languages. \(peerName) hears it in \($0.displayName) and sees the words on screen." }
        transcript.isHidden = !on || lines.isEmpty
        showTranscript()
        panel.isHidden = !(on || problem != nil)
        if on { sheet?.update() } else { sheet?.dismiss(animated: true) }
    }

    #if DEBUG
    /// `--preview-translation bedside|family|family-start|family-off|family-sheet` with `--preview-outgoing-call`:
    /// the bedside's caption, or the family's card partway through a call, just turned on, off, or with its sheet open.
    static func preview(peerName: String) -> CallTranslation? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--preview-translation"), args.count > i + 1 else { return nil }
        let mode = args[i + 1]
        let bedside = mode == "bedside"
        let on = mode != "family-off"
        let json = #"{"id":"preview","from":"preview-family","to":"preview-bedside","mode":"video","kind":"call","state":"accepted","createdAt":1,"expiresAt":9007199254740991,"callerName":"Preview","translationAvailable":true,"translation":{"on":\#(on),"language":"zh-Hant","by":"preview-family","at":1}}"#
        let record = try! JSONDecoder().decode(FamilyCallRecord.self, from: Data(json.utf8))
        let translation = CallTranslation(bedside: bedside, credential: FamilyCredential(origin: URL(string: "https://example.invalid")!, credential: "preview-family.preview",
            role: bedside ? .bedside : .family), callID: "preview", peerName: peerName, room: { nil }, call: { record })
        translation.translatorOn = on
        if bedside {
            translation.caption.text = "Lily 進了足球隊，她超興奮的。這個星期六十點，我們可以視訊給你看。"
        } else if mode == "family" || mode == "family-sheet" {
            translation.lines = [
                CallTranslationLine(id: "1", speaker: "preview-family", name: "Ethan", side: "family", heard: "Lily made the soccer team, 她超 excited 的。",
                                    said: "Lily 進了足球隊，她超興奮的。", language: "zh-Hant", at: 1),
                CallTranslationLine(id: "2", speaker: "preview-bedside", name: peerName, side: "bedside", heard: "真的嗎？她什麼時候比賽？",
                                    said: "Really? When is her game?", language: "en", at: 2),
                CallTranslationLine(id: "3", speaker: "preview-family", name: "Ethan", side: "family", heard: "This Saturday at ten. 我們可以 video call 給你看。",
                                    said: "這個星期六十點，我們可以視訊給你看。", language: "zh-Hant", at: 3),
            ]
        }
        translation.refresh()
        if mode == "family-sheet" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { translation.openSheet() }
        }
        return translation
    }
    #endif

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

    /// The translator's voice arriving means it's on.
    func subscribed(_ publication: RemoteTrackPublication, of participant: RemoteParticipant) {
        guard participant.kind == .agent, publication.kind == .audio else { return }
        translatorOn = true
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
        // The translator says it aloud already, so VoiceOver doesn't announce it again.
        caption.text = text
        captionTask?.cancel()
        captionTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: Self.captionSeconds * 1_000_000_000) } catch { return }
            self?.caption.text = nil
        }
    }

    // MARK: Family

    /// Translate starts translating in the language last chosen on this call, or the bedside's own; Translating stops it.
    private func tapped() { send(on: !isOn, language: chosen) }

    func stop() { send(on: false, language: chosen) }

    func choose(_ option: BedsideLanguage) {
        let previous = chosen
        chosen = option
        // A change the server didn't take leaves the language as it was.
        if isOn { send(on: true, language: option) { [weak self] in self?.chosen = previous } } else { refresh() }
    }

    private func send(on: Bool, language: BedsideLanguage?, onFailure: @escaping () -> Void = {}) {
        guard !sending else { return }
        requested = on; sending = true
        show(problem: nil)
        Task { [weak self, credential, callID] in
            var values: [String: Any] = ["callID": callID, "on": on]
            if let language { values["language"] = language.rawValue }
            do {
                let response = try await FamilyService(credential).send("setCallTranslation", values)
                FamilyCoordinator.shared.update(response)
            } catch {
                self?.requested = nil
                onFailure()
                self?.show(problem: error.localizedDescription)
            }
            self?.sending = false
            self?.refresh()
        }
    }

    private func show(problem: String?) {
        self.problem = problem
        problemTask?.cancel()
        if problem != nil {
            problemTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                self?.problem = nil
                self?.refresh()
            }
        }
        refresh()
    }

    private func openSheet() {
        guard sheet == nil, isOn, var host = sequence(first: panel as UIResponder, next: { $0.next }).first(where: { $0 is UIViewController }) as? UIViewController else { return }
        while let presented = host.presentedViewController, !presented.isBeingDismissed { host = presented }
        let sheet = CallTranslationSheet(translation: self)
        self.sheet = sheet
        host.present(sheet, animated: true)
    }

    /// The latest exchange, newest at the bottom: what the translator heard and what it said for the other side.
    private func showTranscript() {
        transcript.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for line in lines.suffix(2) { transcript.addArrangedSubview(entry(for: line, maxLines: 3)) }
    }

    /// One thing said. Their words in your language first, what they actually said below; your words, then what the
    /// bedside heard.
    func entry(for line: CallTranslationLine, maxLines: Int) -> UIView {
        let entry = UIStackView(); entry.axis = .vertical; entry.spacing = 2
        if line.fromBedside {
            entry.addArrangedSubview(PorchStyle.systemLabel("\(line.name): \(line.said ?? line.heard)", size: 17, color: .white, weight: .semibold))
            if line.said != nil { entry.addArrangedSubview(PorchStyle.systemLabel(line.heard, size: 15, color: PorchStyle.nightSecondary)) }
        } else {
            let who = isMine(line) ? "You" : line.name
            entry.addArrangedSubview(PorchStyle.systemLabel("\(who): \(line.heard)", size: 15, color: PorchStyle.nightSecondary))
            if let said = line.said { entry.addArrangedSubview(PorchStyle.systemLabel("\(peerName) hears: \(said)", size: 17, color: .white, weight: .semibold)) }
        }
        for case let label as UILabel in entry.arrangedSubviews {
            label.numberOfLines = maxLines
            label.textAlignment = BedsideLanguage.readsRightToLeft(label.text ?? "") ? .right : .natural
        }
        return entry
    }
}

enum CallTranslationColors {
    /// Translating: the cream page, with ink words, lit up among the dark call buttons.
    static let on = PorchStyle.page
    /// Live stays green: it means it's on.
    static let live = UIColor(red: 0.37, green: 0.82, blue: 0.54, alpha: 1)
    /// Change: the site's honey.
    static let link = PorchStyle.honey
    // Warm darks, each as bright as the green-tinted one it replaced.
    static let sheet = PorchStyle.rgb(0x27201B)
    static let well = PorchStyle.rgb(0x312823)
    static let title = PorchStyle.rgb(0xF0E9DD)
    static let chipBorder = PorchStyle.rgb(0x4D423A)
    static let chipChosen = PorchStyle.rgb(0x644839)
    static let stop = UIColor(red: 0.79, green: 0.29, blue: 0.29, alpha: 1)
    static let stopText = UIColor(red: 0.96, green: 0.76, blue: 0.75, alpha: 1)

    static func liveDot() -> UIView {
        let dot = UIView()
        dot.backgroundColor = live
        dot.layer.cornerRadius = 4.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 9), dot.heightAnchor.constraint(equalToConstant: 9)])
        return dot
    }
}

/// The top of the family's card: which language the bedside hears, and Change, which opens the sheet.
private final class CallTranslationHeader: UIControl {
    let title = PorchStyle.systemLabel("", size: 16, color: .white, weight: .semibold)
    /// Change and its arrow, hidden while translation is starting.
    private(set) var change: [UIView] = []

    init() {
        super.init(frame: .zero)
        let words = PorchStyle.systemLabel("Change", size: 15, color: CallTranslationColors.link, weight: .semibold)
        words.numberOfLines = 1
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = CallTranslationColors.link
        change = [words, chevron]
        // The language takes the room and wraps if it must; Change stays beside its arrow at the end.
        for view in change {
            view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            view.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
        }
        title.setContentHuggingPriority(UILayoutPriority(249), for: .horizontal)
        let row = UIStackView(arrangedSubviews: [CallTranslationColors.liveDot(), title, words, chevron])
        row.setCustomSpacing(2, after: words)
        row.spacing = 8; row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.55 : 1 } }
    override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.6 } }
}

/// Family: what tapping the card opens. The language the bedside hears, the conversation so far and Stop translating.
private final class CallTranslationSheet: UIViewController {
    private weak var translation: CallTranslation?
    private let chips = ChipFlow()
    private var chipButtons: [(BedsideLanguage, UIButton)] = []
    private let conversation = UIStackView()
    private let scroll = UIScrollView()
    private let empty = PorchStyle.systemLabel("Nothing said yet.", size: 15, color: PorchStyle.nightSecondary)
    private let notice = PorchStyle.systemLabel("", size: 15, color: PorchStyle.nightSecondary)
    private let stop = UIButton(type: .system)
    private var shownLines: [String] = []

    init(translation: CallTranslation) {
        self.translation = translation
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        overrideUserInterfaceStyle = .dark
        if let sheet = sheetPresentationController {
            sheet.prefersGrabberVisible = true
            if #available(iOS 16.0, *) {
                sheet.detents = [.custom(identifier: .init("translation")) { $0.maximumDetentValue * 0.8 }, .large()]
                sheet.preferredCornerRadius = 24
            } else {
                sheet.detents = [.large()]
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let translation else { return }
        view.backgroundColor = CallTranslationColors.sheet
        view.accessibilityIdentifier = "call.translation.sheet"

        let title = PorchStyle.systemLabel("Translating", size: 20, color: CallTranslationColors.title, weight: .semibold)
        title.accessibilityTraits = .header
        var closeConfiguration = UIButton.Configuration.gray()
        closeConfiguration.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        closeConfiguration.cornerStyle = .capsule
        closeConfiguration.baseForegroundColor = PorchStyle.nightText
        let close = UIButton(configuration: closeConfiguration)
        close.accessibilityLabel = "Close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44)])
        let header = UIStackView(arrangedSubviews: [CallTranslationColors.liveDot(), title, close])
        header.spacing = 8; header.alignment = .center

        for option in BedsideLanguage.allCases {
            let chip = UIButton(type: .system)
            chip.accessibilityLabel = option.choiceLabel
            chip.addAction(UIAction { [weak self] _ in self?.translation?.choose(option) }, for: .touchUpInside)
            chips.addSubview(chip)
            chipButtons.append((option, chip))
        }
        chips.accessibilityIdentifier = "call.translation.languages"

        conversation.axis = .vertical; conversation.spacing = 12
        conversation.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(conversation)
        scroll.backgroundColor = CallTranslationColors.well
        scroll.layer.cornerRadius = 14
        scroll.accessibilityIdentifier = "call.translation.conversation"
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let fitted = scroll.heightAnchor.constraint(equalTo: conversation.heightAnchor, constant: 28)
        fitted.priority = UILayoutPriority(700)
        NSLayoutConstraint.activate([
            conversation.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 14),
            conversation.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -14),
            conversation.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            conversation.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            fitted, scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
        ])

        var stopConfiguration = UIButton.Configuration.filled()
        stopConfiguration.title = "Stop translating"
        stopConfiguration.baseBackgroundColor = CallTranslationColors.stop.withAlphaComponent(0.2)
        stopConfiguration.baseForegroundColor = CallTranslationColors.stopText
        stopConfiguration.background.strokeColor = CallTranslationColors.stop
        stopConfiguration.background.strokeWidth = 1.5
        stopConfiguration.cornerStyle = .large
        stopConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes; attributes.font = PorchStyle.systemFont(18, weight: .semibold); return attributes
        }
        stop.configuration = stopConfiguration
        stop.accessibilityIdentifier = "call.translation.stop"
        stop.addAction(UIAction { [weak self] _ in self?.translation?.stop() }, for: .touchUpInside)
        stop.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        let hears = section("\(translation.peerName) hears")
        let said = section("Conversation")
        let stack = UIStackView(arrangedSubviews: [header, hears, chips, said, empty, scroll, spacer, notice, stop])
        stack.axis = .vertical; stack.spacing = 14
        for label in [hears, said] { stack.setCustomSpacing(8, after: label) }
        stack.setCustomSpacing(20, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16),
        ])
        update()
    }

    private func section(_ text: String) -> UILabel {
        let label = PorchStyle.systemLabel(text.uppercased(with: Locale(identifier: "en_US")), size: 13, color: PorchStyle.nightSecondary, weight: .semibold)
        label.accessibilityLabel = text
        label.accessibilityTraits = .header
        return label
    }

    /// Whenever the translation changes: the language, what's been said, or a change on its way.
    func update() {
        guard let translation, isViewLoaded else { return }
        let current = translation.language
        for (option, chip) in chipButtons {
            let chosen = option == current
            var configuration = UIButton.Configuration.plain()
            configuration.title = option.displayName
            configuration.image = chosen ? UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)) : nil
            configuration.imagePadding = 6
            configuration.baseForegroundColor = CallTranslationColors.title
            configuration.background.backgroundColor = chosen ? CallTranslationColors.chipChosen : .clear
            configuration.background.strokeColor = chosen ? CallTranslationColors.live : CallTranslationColors.chipBorder
            configuration.background.strokeWidth = 1.5
            configuration.background.cornerRadius = 12
            configuration.contentInsets = .init(top: 11, leading: 14, bottom: 11, trailing: 14)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes; attributes.font = PorchStyle.systemFont(16); return attributes
            }
            chip.configuration = configuration
            chip.isEnabled = !translation.sending
            chip.accessibilityTraits = chosen ? [.button, .selected] : .button
        }
        chips.setNeedsLayout(); chips.invalidateIntrinsicContentSize()

        let ids = translation.lines.map(\.id)
        if ids != shownLines {
            shownLines = ids
            conversation.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for line in translation.lines { conversation.addArrangedSubview(translation.entry(for: line, maxLines: 0)) }
            view.layoutIfNeeded()
            // Newest at the bottom, in view.
            let bottom = scroll.contentSize.height - scroll.bounds.height
            if bottom > 0 { scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false) }
        }
        empty.isHidden = !translation.lines.isEmpty
        scroll.isHidden = translation.lines.isEmpty
        notice.text = translation.problem
        notice.isHidden = translation.problem == nil
        stop.isEnabled = !translation.sending
    }
}

/// Lays its subviews out left to right, wrapping onto more lines when they don't fit, as chips do.
private final class ChipFlow: UIView {
    private let spacing: CGFloat = 8
    private var laidOutWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        _ = arrange(width: bounds.width, place: true)
        if bounds.width != laidOutWidth { laidOutWidth = bounds.width; invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: arrange(width: laidOutWidth > 0 ? laidOutWidth : 320, place: false))
    }

    private func arrange(width: CGFloat, place: Bool) -> CGFloat {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews where !view.isHidden {
            var size = view.intrinsicContentSize
            size.width = min(ceil(size.width), width); size.height = max(ceil(size.height), 44)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            if place { view.frame = CGRect(x: x, y: y, width: size.width, height: size.height) }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return y + rowHeight
    }
}

/// The translator speaks to each side on its own track (`CallTranslationMessage.trackName`), and each side should hear
/// only its own. LiveKit's server can't unsubscribe someone who joined with auto-subscribe, so whoever owns the call's
/// room drops the other side's track itself, for every call: a call answered on a locked phone has no call screen,
/// and a family member rung into a call has no translation controls.
@MainActor enum CallTranslationTracks {
    static func keepOwn(_ publication: RemoteTrackPublication, of participant: RemoteParticipant, bedside: Bool) {
        guard participant.kind == .agent, publication.kind == .audio, publication.name.hasPrefix("porch-translation"),
              publication.name != CallTranslationMessage.trackName(forBedside: bedside) else { return }
        Task { try? await publication.set(subscribed: false) }
    }
    /// The same for tracks already subscribed, such as any that arrived while the room was connecting.
    static func keepOwn(in room: Room, bedside: Bool) {
        for participant in room.remoteParticipants.values where participant.kind == .agent {
            for case let publication as RemoteTrackPublication in participant.trackPublications.values where publication.isSubscribed {
                keepOwn(publication, of: participant, bedside: bedside)
            }
        }
    }
}
