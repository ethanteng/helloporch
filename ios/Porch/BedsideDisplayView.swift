import UIKit
import PorchCore

enum BedsideText {
    static var language: BedsideLanguage {
        guard PorchDevice.experience == .bedside else { return .english }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--preview-language"), args.count > i + 1,
           let language = BedsideLanguage(rawValue: args[i + 1]) { return language }
        if args.contains("--preview-chinese") { return .traditionalChinese }
        #endif
        return BedsidePreferences.load().language
    }
    static func string(_ english: String, _ arguments: CVarArg...) -> String {
        arguments.isEmpty ? language.text(english) : language.format(english, arguments: arguments)
    }
    static func error(_ description: String) -> String {
        let translated = language.text(description)
        return language != .english && translated == description ? string("Please ask your caregiver for help, then try again.") : translated
    }
    static func applyAccessibilityLanguage(to view: UIView) {
        if view is UILabel || view is UIButton { view.accessibilityLanguage = language.speechLanguage }
        view.subviews.forEach { applyAccessibilityLanguage(to: $0) }
    }
}

/// A bright daytime palette and a quiet nighttime palette, following the
/// caregiver's schedule. Sky keyframes meet at dawn/dusk without a color jump.
struct BedsideScenePalette {
    let skyTop: UIColor
    let skyBottom: UIColor
    let foreground: UIColor
    let clockWash: UIColor
    let controlBackground: UIColor
    let controlForeground: UIColor
    let illumination: Double
    let usesDarkText: Bool

    static func blend(_ a: UIColor, _ b: UIColor, _ amount: Double) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = CGFloat(max(0, min(1, amount)))
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: aa + (ba - aa) * t)
    }
    init(scene: BedsideScene) {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        func ramp(_ stops: [(Double, UIColor)], _ progress: Double) -> UIColor {
            for index in 1..<stops.count where progress <= stops[index].0 {
                let lower = stops[index - 1], upper = stops[index]
                return Self.blend(lower.1, upper.1, (progress - lower.0) / (upper.0 - lower.0))
            }
            return stops.last!.1
        }
        let dawnTop = rgb(0.86, 0.69, 0.70), dawnBottom = rgb(1, 0.82, 0.65)
        let duskTop = rgb(0.86, 0.61, 0.59), duskBottom = rgb(0.99, 0.72, 0.49)
        if scene.isDay {
            skyTop = ramp([(0, dawnTop), (0.18, rgb(0.64, 0.81, 0.94)), (0.5, rgb(0.35, 0.68, 0.91)), (0.8, rgb(0.67, 0.77, 0.91)), (1, duskTop)], scene.progress)
            skyBottom = ramp([(0, dawnBottom), (0.18, rgb(0.94, 0.95, 0.87)), (0.5, rgb(0.78, 0.91, 0.96)), (0.8, rgb(0.99, 0.86, 0.68)), (1, duskBottom)], scene.progress)
        } else {
            skyTop = ramp([(0, duskTop), (0.12, rgb(0.25, 0.25, 0.44)), (0.25, rgb(0.025, 0.045, 0.11)), (0.8, rgb(0.025, 0.045, 0.11)), (0.93, rgb(0.37, 0.30, 0.43)), (1, dawnTop)], scene.progress)
            skyBottom = ramp([(0, duskBottom), (0.12, rgb(0.38, 0.28, 0.39)), (0.25, rgb(0.07, 0.12, 0.19)), (0.8, rgb(0.07, 0.12, 0.19)), (0.93, rgb(0.62, 0.40, 0.40)), (1, dawnBottom)], scene.progress)
        }
        usesDarkText = scene.isDay
        foreground = scene.isDay ? PorchStyle.ink : PorchStyle.nightText
        clockWash = scene.isDay ? rgb(1, 0.99, 0.95).withAlphaComponent(0.66) : UIColor.black.withAlphaComponent(0.80)
        controlBackground = scene.isDay ? rgb(0.97, 0.98, 0.94) : PorchStyle.nightSurface
        controlForeground = scene.isDay ? PorchStyle.ink : PorchStyle.nightText
        illumination = scene.isDay ? 0.4 + 0.6 * sin(.pi * scene.progress) : 0.4 * (1 - min(1, min(scene.progress, 1 - scene.progress) / 0.16))
    }
}

/// Decorative artwork stays behind the real clock. No flashing, parallax, or
/// perpetual animation: the sky follows local time at the clock's minute tick.
final class BedsideSceneView: UIView {
    var scene = BedsideScene(date: Date(), preferences: .init()) { didSet { setNeedsDisplay() } }
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; isAccessibilityElement = false; isOpaque = true }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = bounds.width, h = bounds.height
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        let palette = BedsideScenePalette(scene: scene)
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [palette.skyTop.cgColor, palette.skyBottom.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        func ellipse(_ rect: CGRect, _ c: UIColor) { c.setFill(); UIBezierPath(ovalIn: rect).fill() }
        if !scene.isDay {
            for i in 0..<24 {
                let x = CGFloat((i * 157 + 37) % 997) / 997 * w
                let y = CGFloat((i * 73 + 11) % 211) / 1000 * h
                ellipse(CGRect(x: x, y: y, width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 3 : 2), UIColor(white: 0.85, alpha: 0.45 * (1 - palette.illumination / 0.4)))
            }
        }
        let radius = min(w, h) * 0.047
        let point = CGPoint(x: w * (0.09 + 0.82 * scene.progress), y: h * (0.87 - 0.77 * sin(.pi * scene.progress)))
        if scene.isDay {
            ellipse(CGRect(x: point.x - radius * 1.4, y: point.y - radius * 1.4, width: radius * 2.8, height: radius * 2.8), UIColor(red: 1, green: 0.79, blue: 0.39, alpha: 0.08))
            ellipse(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2), color(1, 0.83, 0.48))
        } else {
            // A crescent cut out with the local sky color; a symbolic moon,
            // rather than a forecast of the astronomical lunar phase.
            ctx.saveGState()
            let outer = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            UIBezierPath(ovalIn: outer).addClip()
            let moon = UIBezierPath(ovalIn: outer)
            moon.append(UIBezierPath(ovalIn: CGRect(x: point.x - radius * 0.25, y: point.y - radius * 1.2, width: radius * 1.7, height: radius * 1.7)))
            moon.usesEvenOddFillRule = true; moon.addClip()
            color(0.91, 0.89, 0.73).setFill(); UIRectFill(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)); ctx.restoreGState()
        }
        // Quiet rolling hills frame the clock, with a seasonal tree at the edge.
        func hill(_ base: CGFloat, _ c: UIColor, _ offset: CGFloat) {
            let path = UIBezierPath(); path.move(to: CGPoint(x: 0, y: h * base))
            path.addCurve(to: CGPoint(x: w, y: h * (base + offset)), controlPoint1: CGPoint(x: w * 0.36, y: h * (base - 0.09)), controlPoint2: CGPoint(x: w * 0.65, y: h * (base + 0.05)))
            path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.close(); c.setFill(); path.fill()
        }
        let snow = scene.season == .winter
        hill(0.86, BedsideScenePalette.blend(snow ? color(0.24, 0.31, 0.36) : color(0.10, 0.23, 0.22), snow ? color(0.80, 0.88, 0.91) : color(0.51, 0.72, 0.48), palette.illumination), -0.01)
        hill(0.94, BedsideScenePalette.blend(snow ? color(0.33, 0.39, 0.41) : color(0.065, 0.17, 0.16), snow ? color(0.91, 0.94, 0.93) : color(0.34, 0.59, 0.40), palette.illumination), -0.025)
        ctx.saveGState(); ctx.translateBy(x: w * 0.87, y: h * 0.92)
        let unit = min(w, h) * 0.18
        let branches = UIBezierPath(); branches.move(to: .zero); branches.addLine(to: CGPoint(x: -unit * 0.04, y: -unit))
        for (x,y) in [(-0.35,-0.85),(0.3,-0.72),(-0.27,-0.54),(0.26,-1.03)] {
            branches.move(to: CGPoint(x: -unit * 0.02, y: unit * y * 0.7)); branches.addLine(to: CGPoint(x: unit * x, y: unit * y))
        }
        color(0.33, 0.28, 0.23).setStroke(); branches.lineWidth = max(3, unit * 0.04); branches.lineCapStyle = .round; branches.stroke()
        if !snow {
            let foliage: UIColor = scene.season == .fall ? color(0.65, 0.34, 0.18) : scene.season == .spring ? color(0.46, 0.55, 0.37) : color(0.23, 0.41, 0.28)
            for (x,y,r) in [(-0.24,-0.83,0.26),(0.19,-0.85,0.27),(0.0,-1.07,0.28),(-0.15,-0.58,0.23),(0.23,-0.62,0.21)] {
                ellipse(CGRect(x: unit * (x-r), y: unit * (y-r), width: unit * r * 2, height: unit * r * 2), foliage)
            }
            if scene.season == .spring {
                for (x,y) in [(-0.24,-0.9),(0.19,-0.9),(-0.02,-1.15),(0.22,-0.64)] { ellipse(CGRect(x: unit*x, y: unit*y, width: unit*0.07, height: unit*0.07), color(0.85,0.66,0.63)) }
            }
        } else {
            color(0.75, 0.79, 0.79).setStroke(); branches.lineWidth = max(1, unit * 0.014); branches.stroke()
        }
        ctx.restoreGState()
        // A light wash with dark lettering by day; a dark wash at night.
        // The sun, moon and seasonal art cannot obscure the large clock.
        let transparentWash = palette.clockWash.withAlphaComponent(0)
        let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [transparentWash.cgColor, palette.clockWash.cgColor, palette.clockWash.cgColor, transparentWash.cgColor] as CFArray, locations: [0, 0.18, 0.78, 1])!
        ctx.drawLinearGradient(shade, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    }
}

final class BedsideDisplaySettingsViewController: CaregiverFormViewController {
    private var preferences: BedsidePreferences
    private let defaults: UserDefaults
    private let announcementVoice = PorchStyle.button("System default", symbol: "chevron.up.chevron.down", filled: false)
    private let voiceStatus = PorchStyle.label("", size: 16)
    private let voicePreviewStatus = PorchStyle.label("", size: 16)
    private let voicePreview = PorchIncomingAudio()
    /// Natural voices this family can use, from the server, and unsaved choices among them (nil: the built-in voice).
    private let naturalVoices: @MainActor () -> NaturalVoices?
    private var natural: NaturalVoices? { naturalVoices() }
    private var naturalDrafts: [BedsideLanguage: String?] = [:]
    private let appearance = UISegmentedControl(items: ["Default", "Dynamic"])
    private let hemisphere = UISegmentedControl(items: ["Northern", "Southern"])
    private var languageButtons: [BedsideLanguage: UIButton] = [:]
    private let day = UIStepper(), night = UIStepper()
    private let dayLabel = PorchStyle.label("", size: 19, color: PorchStyle.ink)
    private let nightLabel = PorchStyle.label("", size: 19, color: PorchStyle.ink)
    private let example = BedsideSceneView()
    private let previewClock = PorchStyle.label("", size: 24, color: PorchStyle.ink, weight: .semibold)
    init(defaults: UserDefaults = .standard,
         naturalVoices: @escaping @MainActor () -> NaturalVoices? = { PorchDevice.experience == .bedside ? FamilyCoordinator.shared.state?.speech : nil }) {
        self.defaults = defaults
        self.naturalVoices = naturalVoices
        preferences = BedsidePreferences.load(from: defaults)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(defaults:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Bedside display"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        appearance.selectedSegmentIndex = preferences.appearance == .dynamic ? 1 : 0
        appearance.accessibilityLabel = "Bedside view"
        hemisphere.selectedSegmentIndex = preferences.hemisphere == .northern ? 0 : 1
        hemisphere.accessibilityLabel = "Season hemisphere"
        for control in [appearance, hemisphere] {
            control.selectedSegmentTintColor = PorchStyle.accent; control.backgroundColor = PorchStyle.page
            control.setTitleTextAttributes([.foregroundColor: PorchStyle.ink], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            control.addTarget(self, action: #selector(update), for: .valueChanged)
        }
        let languages = UIStackView()
        languages.axis = .vertical; languages.spacing = 4
        languages.accessibilityIdentifier = "bedside.language"
        for choice in BedsideLanguage.allCases {
            let button = PorchStyle.button(choice.displayName, symbol: "circle", filled: false)
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "bedside.language.\(choice.rawValue)"
            button.accessibilityLanguage = choice.speechLanguage
            button.addAction(UIAction { [weak self] _ in
                self?.stopVoicePreview(); self?.preferences.language = choice; self?.update()
            }, for: .touchUpInside)
            languageButtons[choice] = button
            languages.addArrangedSubview(button)
        }
        form.addArrangedSubview(section("Clock view", detail: "Both views always show the current date and time in large, clear text. Default keeps the screen dark. Dynamic brightens with daylight, warms at sunset, and darkens at night, with a sun or moon and seasonal landscape.", views: [appearance]))
        example.heightAnchor.constraint(equalToConstant: 210).isActive = true
        example.layer.cornerRadius = 20; example.clipsToBounds = true
        previewClock.text = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        previewClock.textAlignment = .center; previewClock.translatesAutoresizingMaskIntoConstraints = false
        example.addSubview(previewClock)
        NSLayoutConstraint.activate([previewClock.centerYAnchor.constraint(equalTo: example.centerYAnchor), previewClock.leadingAnchor.constraint(equalTo: example.leadingAnchor, constant: 20), previewClock.trailingAnchor.constraint(equalTo: example.trailingAnchor, constant: -20)])
        form.addArrangedSubview(example)
        form.addArrangedSubview(section("Bedside language", detail: "Choose the language for the clock, call screens, spoken drop-in announcements and the voicemail greeting phone callers hear. The phone greeting changes when you tap Save on this iPad. Caregiver settings and family mode stay in English. 繁體中文 and 简体中文 use Mandarin; 廣東話 uses Cantonese.", views: [languages]))
        announcementVoice.accessibilityIdentifier = "bedside.announcementVoice"
        announcementVoice.accessibilityLabel = "Announcement voice"
        announcementVoice.showsMenuAsPrimaryAction = true
        let previewVoice = PorchStyle.button("Preview announcement", symbol: "speaker.wave.2", filled: false)
        previewVoice.accessibilityIdentifier = "bedside.previewAnnouncement"
        previewVoice.addTarget(self, action: #selector(previewAnnouncement), for: .touchUpInside)
        form.addArrangedSubview(section("Announcement voice", detail: "Choose a voice for the bedside language. Natural voices sound like a person; the choice is saved for this family and each announcement is prepared over the internet. Built-in voices stay on this iPad, and speak whenever a natural announcement isn't ready. Each language remembers its own choice. English and Spanish include regional accents; Taiwan Mandarin, mainland Mandarin and Cantonese have separate choices. Download more built-in voices in the iPad's Accessibility speech settings, then return here. Preview before saving; no call is placed.", views: [announcementVoice, voiceStatus, previewVoice, voicePreviewStatus]))
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAnnouncementVoices), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAnnouncementVoices), name: .porchFamilyChanged, object: nil)
        day.minimumValue = 0; day.maximumValue = 11; day.value = Double(preferences.dayStart)
        night.minimumValue = 12; night.maximumValue = 23; night.value = Double(preferences.nightStart)
        day.accessibilityLabel = "Day begins"; night.accessibilityLabel = "Night begins"
        func row(_ label: UILabel, _ stepper: UIStepper) -> UIView {
            stepper.addTarget(self, action: #selector(update), for: .valueChanged)
            let row = UIStackView(arrangedSubviews: [label, UIView(), stepper]); row.alignment = .center; row.spacing = 16; return row
        }
        form.addArrangedSubview(section("Day & night schedule", detail: "The sun and moon follow these times and the iPad's local clock. They represent your daily routine, rather than local sunrise, sunset, or moon phase. The scene updates gently each minute and respects Reduce Motion.", views: [row(dayLabel, day), row(nightLabel, night)]))
        form.addArrangedSubview(section("Seasons", detail: "Choose your hemisphere. Seasons follow the local calendar: March–May is spring in the north and fall in the south.", views: [hemisphere]))
        hideKeyboardControl(); update()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAnnouncementVoices()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopVoicePreview()
    }
    private func stopVoicePreview() {
        voicePreview.stop()
        voicePreviewStatus.text = nil
    }
    func selectAnnouncementVoice(_ identifier: String?) {
        stopVoicePreview()
        preferences.setAnnouncementVoiceIdentifier(identifier, for: preferences.language)
        if natural?.choices(for: preferences.language) != nil { naturalDrafts[preferences.language] = .some(nil) }
        refreshAnnouncementVoices()
    }
    /// The built-in voice stays saved on this iPad; it speaks while a natural announcement isn't ready.
    func selectNaturalVoice(_ id: String) {
        stopVoicePreview()
        naturalDrafts[preferences.language] = .some(id)
        refreshAnnouncementVoices()
    }
    private func naturalVoice(for language: BedsideLanguage) -> String? {
        if let draft = naturalDrafts[language] { return draft }
        return natural?.choices(for: language)?.selected
    }
    @objc private func refreshAnnouncementVoices() {
        let language = preferences.language
        let voices = PorchAnnouncementVoice.available(for: language)
        let identifier = preferences.announcementVoiceIdentifier(for: language)
        let selected = voices.first { $0.identifier == identifier }
        let choices = natural?.choices(for: language)
        let naturalChoice = naturalVoice(for: language).flatMap { id in choices?.voices.first { $0.id == id } }
        let title = naturalChoice.map { "\($0.name) · Natural" } ?? selected.map(PorchAnnouncementVoice.label) ?? "System default"
        announcementVoice.configuration?.title = title
        announcementVoice.accessibilityValue = title
        let builtIn = naturalChoice == nil
        var actions = [UIAction(title: "System default", state: builtIn && selected == nil ? .on : .off) { [weak self] _ in
            self?.selectAnnouncementVoice(nil)
        }]
        actions += voices.map { voice in
            UIAction(title: PorchAnnouncementVoice.label(voice), state: builtIn && voice.identifier == selected?.identifier ? .on : .off) { [weak self] _ in
                self?.selectAnnouncementVoice(voice.identifier)
            }
        }
        if let choices {
            let naturals = choices.voices.map { voice in
                UIAction(title: "\(voice.name) · \(voice.detail)", state: voice.id == naturalChoice?.id ? .on : .off) { [weak self] _ in
                    self?.selectNaturalVoice(voice.id)
                }
            }
            announcementVoice.menu = UIMenu(title: "\(language.displayName) announcement voice", children: [
                UIMenu(title: "Natural voices", options: .displayInline, children: naturals),
                UIMenu(title: "Built-in voices on this iPad", options: .displayInline, children: actions)])
        } else {
            announcementVoice.menu = UIMenu(title: "\(language.displayName) announcement voice", children: actions)
        }
        if naturalChoice != nil {
            voiceStatus.text = "A natural voice for \(language.displayName), saved for this family. Each announcement is prepared over the internet the first time; until it's ready, this iPad's built-in voice speaks. Tap Save to keep your choice."
        } else if PorchAnnouncementVoice.resolve(for: language, identifier: identifier) == nil {
            voiceStatus.text = "No voice is available for \(language.displayName). Download a matching voice in the iPad's Accessibility speech settings. Drop-ins will require manual acceptance until speech is available."
        } else if identifier != nil && selected == nil {
            voiceStatus.text = "The saved voice is unavailable. Announcements will use the system default for \(language.displayName) until it is available again or you save another choice."
        } else {
            voiceStatus.text = "Showing voices available for \(language.displayName) on this iPad. Tap Save to keep your choice."
        }
    }
    @objc private func previewAnnouncement() {
        stopVoicePreview()
        let language = preferences.language
        voicePreviewStatus.text = "Playing the selected voice. No call is placed."
        voicePreview.announce(name: language.text("A family member"), video: true, language: language,
                              voiceIdentifier: preferences.announcementVoiceIdentifier(for: language),
                              naturalVoice: naturalVoice(for: language), naturalWait: 8) { [weak self] success in
            self?.voicePreviewStatus.text = success ? "Preview completed. Tap Save to keep your choice." : "Couldn't play the preview. Check the iPad's audio output, media volume and installed voices."
        }
    }
    @objc private func update() {
        preferences.appearance = appearance.selectedSegmentIndex == 0 ? .default : .dynamic
        preferences.hemisphere = hemisphere.selectedSegmentIndex == 0 ? .northern : .southern
        for (choice, button) in languageButtons {
            let selected = choice == preferences.language
            button.configuration?.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
        preferences.dayStart = Int(day.value); preferences.nightStart = Int(night.value)
        func hour(_ value: Int) -> String {
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: value))!
            let formatter = DateFormatter(); formatter.setLocalizedDateFormatFromTemplate("j"); return formatter.string(from: date)
        }
        dayLabel.text = "Day begins · \(hour(preferences.dayStart))"; nightLabel.text = "Night begins · \(hour(preferences.nightStart))"
        day.accessibilityValue = hour(preferences.dayStart); night.accessibilityValue = hour(preferences.nightStart)
        example.isHidden = preferences.appearance != .dynamic
        example.scene = BedsideScene(date: Date(), preferences: preferences)
        let formatter = DateFormatter(); formatter.locale = preferences.language.locale
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        previewClock.text = formatter.string(from: Date())
        previewClock.textColor = BedsideScenePalette(scene: example.scene).foreground
        refreshAnnouncementVoices()
    }
    @objc private func save() {
        preferences.save(to: defaults)
        NotificationCenter.default.post(name: .porchBedsideDisplayChanged, object: nil)
        // Phone voicemail greets callers in the bedside language, so the server keeps a copy.
        let reportLanguage = PorchDevice.experience == .bedside ? FamilyCoordinator.shared.state?.languageToReport(preferences.language) : nil
        // Natural voice choices belong to the family, so they're saved on the server with the caregiver PIN.
        let changes = naturalDrafts.compactMap { language, draft -> (BedsideLanguage, String?)? in
            guard let choices = natural?.choices(for: language), choices.selected != draft else { return nil }
            return (language, draft)
        }
        guard reportLanguage != nil || !changes.isEmpty, let credential = PorchDevice.credential(for: .bedside) else {
            navigationController?.popViewController(animated: true); return
        }
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { [weak self] in
            do {
                if let reportLanguage {
                    let response = try await FamilyService(credential).send("setBedsideLanguage", ["language": reportLanguage.rawValue], pin: NativeCallSettings.caregiverCode)
                    FamilyCoordinator.shared.update(response)
                }
                for (language, voiceID) in changes {
                    let response = try await FamilyService(credential).send("setSpeechVoice", ["language": language.rawValue, "voiceID": voiceID.map { $0 as Any } ?? NSNull()], pin: NativeCallSettings.caregiverCode)
                    FamilyCoordinator.shared.update(response)
                }
                self?.naturalDrafts = [:]
                self?.navigationController?.popViewController(animated: true)
            } catch {
                guard let self else { return }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                showPorchError(error, on: self)
            }
        }
    }
}
extension Notification.Name { static let porchBedsideDisplayChanged = Notification.Name("porchBedsideDisplayChanged") }
