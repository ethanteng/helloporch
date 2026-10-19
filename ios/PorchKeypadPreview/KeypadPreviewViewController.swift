import UIKit
import PorchCore

final class KeypadPreviewViewController: UIViewController {
    private var preview: KeypadActionPreview?
    private let heading = PorchStyle.label("Waiting for a key", size: 36, weight: .semibold)
    private let detail = PorchStyle.label("Start preview, lift the handset, then press a phone key.", size: 20)
    private let key = PorchStyle.label("—", size: 72, weight: .semibold)
    private let photo = RecipientAppearance.photoView(nil)
    private let connection = PorchStyle.label("USB preview stopped", size: 17)
    private let setup = PorchStyle.label("Loading the saved HelloPorch setup…", size: 16)
    private let stateButton = PorchStyle.button("Test state: Clock", filled: false)
    private let start = PorchStyle.button("Start phone preview", symbol: "play.fill")
    private let stop = PorchStyle.button("Stop", symbol: "stop.fill", filled: false)
    private let history = UITextView()
    private var keyButtons: [String: UIButton] = [:]
    private var capture: Cell2JackLogCapture?
    private var captureID: UUID?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var records: [[String: Any]] = []
    private var historyLines: [String] = []
    private var inputCount = 0
    private var keyboard = CallTrigger()
    private let reportQueue = DispatchQueue(label: "com.ethanteng.helloporch.keypad-preview.report")
    private let stamp = ISO8601DateFormatter()
    private let reportURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("porch-preview-actions.json")

    override var canBecomeFirstResponder: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "HelloPorch · Keypad Preview"
        view.backgroundColor = PorchStyle.page
        let banner = PorchStyle.label("PREVIEW ONLY · CALLS DISABLED", size: 17, color: PorchStyle.accent, weight: .bold)
        banner.accessibilityIdentifier = "keypadPreview.safety"
        let instruction = PorchStyle.label("Use the phone keypad to see which person or action HelloPorch would select. You can also tap the keys below.", size: 19)
        key.textAlignment = .center
        key.accessibilityIdentifier = "keypadPreview.key"
        heading.accessibilityIdentifier = "keypadPreview.action"
        detail.accessibilityIdentifier = "keypadPreview.detail"
        photo.isHidden = true
        photo.widthAnchor.constraint(equalToConstant: 92).isActive = true
        photo.heightAnchor.constraint(equalToConstant: 92).isActive = true
        key.widthAnchor.constraint(greaterThanOrEqualToConstant: 82).isActive = true
        let words = UIStackView(arrangedSubviews: [heading, detail]); words.axis = .vertical; words.spacing = 10
        let result = UIStackView(arrangedSubviews: [key, photo, words]); result.spacing = 20; result.alignment = .center
        let resultCard = UIStackView(arrangedSubviews: [result]); resultCard.axis = .vertical
        resultCard.isLayoutMarginsRelativeArrangement = true
        resultCard.directionalLayoutMargins = .init(top: 22, leading: 20, bottom: 22, trailing: 20)
        resultCard.backgroundColor = PorchStyle.surface; resultCard.layer.cornerRadius = 22
        resultCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        start.accessibilityIdentifier = "keypadPreview.start"
        stop.accessibilityIdentifier = "keypadPreview.stop"
        start.addTarget(self, action: #selector(startPhone), for: .touchUpInside)
        stop.addTarget(self, action: #selector(stopPhone), for: .touchUpInside); stop.isEnabled = false
        let controls = UIStackView(arrangedSubviews: [start, stop]); controls.distribution = .fillEqually; controls.spacing = 14
        stateButton.accessibilityIdentifier = "keypadPreview.context"
        let settings = PorchStyle.button("Driver settings", symbol: "gearshape", filled: false)
        settings.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
        let stateRow = UIStackView(arrangedSubviews: [stateButton, settings]); stateRow.distribution = .fillEqually; stateRow.spacing = 12
        let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 12
        let keys = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
        for symbols in keys {
            let row = UIStackView(); row.distribution = .fillEqually; row.spacing = 12
            for symbol in symbols {
                let button = PorchStyle.button(symbol, filled: false)
                button.configuration?.baseBackgroundColor = PorchStyle.surface
                button.configuration?.background.backgroundColor = PorchStyle.surface
                button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = attributes; attributes.font = PorchStyle.font(26, weight: .semibold); return attributes
                }
                button.accessibilityIdentifier = "keypadPreview.key.\(symbol)"
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
                button.addAction(UIAction { [weak self] _ in self?.receive(symbol, source: "Screen") }, for: .touchUpInside)
                keyButtons[symbol] = button; row.addArrangedSubview(button)
            }
            grid.addArrangedSubview(row)
        }
        history.isEditable = false; history.backgroundColor = PorchStyle.surface; history.layer.cornerRadius = 16
        history.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        history.accessibilityIdentifier = "keypadPreview.history"
        history.heightAnchor.constraint(equalToConstant: 160).isActive = true
        let copy = PorchStyle.button("Copy preview results", symbol: "doc.on.doc", filled: false)
        copy.addAction(UIAction { [weak self] _ in UIPasteboard.general.string = self?.historyLines.joined(separator: "\n") }, for: .touchUpInside)
        let limits = PorchStyle.label("USB tests run for two minutes and stop when you leave this app. Call states are simulated. Phone keys still have their usual Cell2Jack behavior.", size: 15)
        let stack = UIStackView(arrangedSubviews: [banner, instruction, setup, resultCard, stateRow, controls, connection, grid, history, copy, limits])
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(leavingForeground), name: UIApplication.willResignActiveNotification, object: nil)
        loadSetup()
        if ProcessInfo.processInfo.arguments.contains("--start-keypad-preview") { startPhone() }
        #if targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--preview-context"), args.count > index + 1,
           let context = KeypadActionPreview.Context(rawValue: args[index + 1]) { choose(context) }
        if let index = args.firstIndex(of: "--preview-key-sequence"), args.count > index + 1 {
            for symbol in args[index + 1] { receive(String(symbol), source: "Simulator") }
        }
        #endif
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }
    private func loadSetup() {
        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let file = documents.appendingPathComponent("porch-preview-slots.json")
            let photoStore = ContactPhotoStore(directoryURL: documents.appendingPathComponent("porch-preview-photos", isDirectory: true))
            let slots: CallSlots
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--sample-keypad-setup") {
                var sample = CallSlots()
                try sample.setContact(CallContact(name: "Sample Alex", nativeCall: NativeCall(room: "preview-alex", mode: .voice), buttonColorHex: "DCEAE0"), for: 1)
                try sample.setContact(CallContact(name: "Sample Sam", nativeCall: NativeCall(room: "preview-sam", mode: .video), buttonColorHex: "E9E0D0"), for: 2)
                slots = sample; setup.text = "Sample contacts · simulator only"
            } else {
                slots = try CallSlots.snapshot(from: Data(contentsOf: file), photoStore: photoStore)
                setup.text = "Saved HelloPorch setup · read-only snapshot"
            }
            #else
            slots = try CallSlots.snapshot(from: Data(contentsOf: file), photoStore: photoStore)
            setup.text = "Saved HelloPorch setup · \(slots.contacts.compactMap { $0 }.count) people · read-only snapshot"
            #endif
            preview = KeypadActionPreview(slots: slots)
            for symbol in keyButtons.keys {
                guard let button = keyButtons[symbol] else { continue }
                let digit = CallSlots.digit(forSymbol: symbol)
                let action = digit.flatMap { slots.action(for: $0) }
                let person = digit.flatMap { slots.contact(for: $0) }
                button.configuration?.subtitle = person?.name ?? (action == .person ? "Unassigned" : action?.title ?? "No action")
                button.accessibilityLabel = "Key \(symbol), \(button.configuration?.subtitle ?? "")"
                if let person {
                    let color = RecipientAppearance.color(hex: person.buttonColorHex)
                    button.configuration?.baseBackgroundColor = color
                    button.configuration?.background.backgroundColor = color
                    button.configuration?.baseForegroundColor = RecipientAppearance.foreground(on: color)
                }
            }
            refreshContextMenu()
            record(["kind": "previewStart", "callingEngineLinked": false, "snapshotPeople": slots.contacts.compactMap { $0 }.count])
        } catch {
            setup.text = "Could not load the saved HelloPorch setup: \(error.localizedDescription)"
            start.isEnabled = false; stateButton.isEnabled = false
            keyButtons.values.forEach { $0.isEnabled = false }
            heading.text = "Saved setup needed"
            detail.text = "This preview needs a copy of the iPad's HelloPorch keypad assignments. No sample contacts are substituted on the iPad."
        }
    }
    private func choose(_ context: KeypadActionPreview.Context) {
        preview?.setContext(context); refreshContextMenu()
        heading.text = "Test state: \(context.title)"; detail.text = "This state is simulated. No call, camera, or message playback is started."
        key.text = "—"; photo.isHidden = true
        highlight(nil)
        record(["kind": "context", "context": context.rawValue])
    }
    private func refreshContextMenu() {
        guard let preview else { return }
        stateButton.configuration?.title = "Test state: \(preview.context.title)"
        stateButton.showsMenuAsPrimaryAction = true
        stateButton.menu = UIMenu(children: KeypadActionPreview.Context.allCases.map { context in
            UIAction(title: context.title, state: context == preview.context ? .on : .off) { [weak self] _ in self?.choose(context) }
        })
    }
    private func highlight(_ symbol: String?) {
        for (value, button) in keyButtons {
            button.layer.cornerRadius = 14
            button.layer.borderColor = PorchStyle.accent.cgColor
            button.layer.borderWidth = value == symbol ? 4 : 0
        }
    }
    private func receive(_ symbol: String, source: String, rawLine: String? = nil, embedded: Bool = false) {
        guard let result = preview?.receive(symbol) else { return }
        inputCount += 1
        key.text = symbol; heading.text = result.title; detail.text = result.detail
        highlight(symbol)
        let person = result.selectedDigit.flatMap { preview?.slots.contact(for: $0) }
        photo.image = RecipientAppearance.photo(person?.photoData); photo.isHidden = photo.image == nil
        let text = "\(inputCount). \(source) \(symbol) → \(result.title)\(embedded ? " [joined line]" : "")"
        historyLines.append(text); historyLines = Array(historyLines.suffix(100))
        history.text = historyLines.joined(separator: "\n")
        history.scrollRangeToVisible(NSRange(location: max(0, history.text.utf16.count - 1), length: 1))
        var values: [String: Any] = ["kind": "actionPreview", "source": source, "symbol": symbol,
            "context": result.context.rawValue, "outcome": result.kind.rawValue, "title": result.title,
            "detail": result.detail, "inputCount": inputCount, "embeddedInLine": embedded]
        if let name = result.contactName { values["contactName"] = name }
        if let rawLine { values["rawLine"] = rawLine }
        if let camera = result.cameraOn { values["simulatedCameraOn"] = camera }
        record(values)
        UIAccessibility.post(notification: .announcement, argument: result.title)
    }
    private func record(_ values: [String: Any]) {
        var values = values; values["utc"] = stamp.string(from: Date())
        records.append(values); records = Array(records.suffix(1000))
        guard let data = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = reportURL
        reportQueue.async { try? data.write(to: url, options: .atomic) }
    }
    @objc private func startPhone() {
        guard capture == nil, preview != nil else { return }
        let id = UUID(); captureID = id
        start.isEnabled = false; stop.isEnabled = true
        connection.text = "Starting Cell2Jack logs…"
        UIApplication.shared.isIdleTimerDisabled = true
        let capture = Cell2JackLogCapture { [weak self] update in
            guard let self, self.captureID == id else { return }
            self.connection.text = update.message
            for event in update.digits where event.kind == .digit {
                self.receive(event.digit, source: "USB", rawLine: event.line, embedded: event.embeddedInLine)
            }
            if update.kind == .finished {
                self.capture = nil; self.captureID = nil; self.start.isEnabled = true; self.stop.isEnabled = false
                UIApplication.shared.isIdleTimerDisabled = false
                self.record(["kind": "usbStopped", "result": update.message])
                if self.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid }
            }
        }
        self.capture = capture; capture.start()
        record(["kind": "usbStart", "context": preview!.context.rawValue])
    }
    @objc private func stopPhone() { stop.isEnabled = false; connection.text = "Stopping device logs…"; capture?.stop() }
    @objc private func leavingForeground() {
        keyboard.resetKeys()
        guard let capture else { return }
        stop.isEnabled = false
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Stop preview USB logs") { [weak self] in
                guard let self else { return }
                self.capture?.stop(reason: "Preview left the foreground")
                if self.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid }
            }
        }
        capture.stop(reason: "Preview left the foreground")
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var other = Set<UIPress>()
        for press in presses {
            guard let key = press.key, key.modifierFlags.isDisjoint(with: [.command, .control, .alternate]),
                  let digit = CallTrigger.slot(for: Int(key.keyCode.rawValue), characters: key.characters, shift: key.modifierFlags.contains(.shift)) else { other.insert(press); continue }
            if keyboard.keyDown(Int(key.keyCode.rawValue)) { receive(CallSlots.symbol(for: digit), source: "Keyboard") }
        }
        if !other.isEmpty { super.pressesBegan(other, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { keyboard.keyUp(Int(key.keyCode.rawValue)) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        keyboard.resetKeys(); super.pressesCancelled(presses, with: event)
    }
}
