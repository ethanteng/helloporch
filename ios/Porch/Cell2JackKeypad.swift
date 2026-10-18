import UIKit
import PorchCore

/// Phone digits share Porch's existing actions; keyboard input remains independent.
protocol Cell2JackDigitReceiving: AnyObject {
    func receiveCell2JackDigit(_ digit: Int) -> String
}

enum Cell2JackDigitRouter {
    static func route(_ symbol: String, root: UIViewController) -> String {
        guard symbol.utf8.count == 1, let byte = symbol.utf8.first, (48...57).contains(byte) else { return "unassigned symbol" }
        var screen = root
        while true {
            guard !screen.isBeingDismissed, !screen.isBeingPresented, screen.transitionCoordinator == nil else { return "screen transitioning" }
            if let presented = screen.presentedViewController { screen = presented }
            else if let nav = screen as? UINavigationController, let top = nav.topViewController { screen = top }
            else if let tabs = screen as? UITabBarController, let selected = tabs.selectedViewController { screen = selected }
            else if screen is PorchContainerViewController, let child = screen.children.first { screen = child }
            else { break }
        }
        // An unknown modal (PIN, settings, alert, permission UI) blocks input.
        guard let receiver = screen as? Cell2JackDigitReceiving else { return "screen does not accept phone keys" }
        return receiver.receiveCell2JackDigit(Int(byte - 48))
    }
}

extension Notification.Name { static let cell2JackKeypadChanged = Notification.Name("porch.cell2jack.changed") }

enum Cell2JackKeypadUpdate {
    case ready, digits([Cell2JackDigitEvent], TimeInterval), finished(String)
    case health(bytes: Int, packets: Int, primaryDigits: Int)
}
protocol Cell2JackKeypadConnection: AnyObject {
    func start()
    func stop()
}

/// Main-thread owner. Stale callbacks cannot act after stopping/backgrounding.
final class Cell2JackKeypad {
    static let shared = Cell2JackKeypad()
    // The prototype's automatic test opt-in is deliberately not migrated.
    static let enabledKey = "porch.cell2jack.enabled"
    weak var root: UIViewController?
    weak var windowScene: UIWindowScene?
    private(set) var status = "Phone keypad off"
    private var worker: Cell2JackKeypadConnection?
    private var stopping = false
    private var wanted = false
    private var sceneActive = false
    private var generation = UUID()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var records: [[String: Any]] = []
    private let reportQueue = DispatchQueue(label: "porch.cell2jack.actions")
    private let defaults: UserDefaults
    private let isBedside: () -> Bool
    private let makeConnection: (@escaping (Cell2JackKeypadUpdate) -> Void) -> Cell2JackKeypadConnection
    var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    init(defaults: UserDefaults = .standard,
         isBedside: @escaping () -> Bool = { PorchDevice.experience == .bedside },
         makeConnection: @escaping (@escaping (Cell2JackKeypadUpdate) -> Void) -> Cell2JackKeypadConnection = { Cell2JackKeypad.makeDefaultConnection($0) }) {
        self.defaults = defaults; self.isBedside = isBedside; self.makeConnection = makeConnection
    }
    static var supportsDriverPlatform: Bool {
        if #available(iOS 16.0, *) { return UIDevice.current.userInterfaceIdiom == .pad }
        return false
    }
    private static func makeDefaultConnection(_ update: @escaping (Cell2JackKeypadUpdate) -> Void) -> Cell2JackKeypadConnection {
        if #available(iOS 16.0, *), supportsDriverPlatform { return Cell2JackKeypadTransport(update) }
        return Cell2JackUnavailableConnection(update)
    }

    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.enabledKey)
        refresh()
    }
    func activate() {
        sceneActive = true
        if enabled { record(["kind": "sceneActive", "enabled": enabled, "bedside": isBedside(),
                "applicationState": UIApplication.shared.applicationState.rawValue,
                "sceneState": windowScene?.activationState.rawValue ?? -99]) }
        refresh()
    }
    func refresh() {
        // The scene delegate event is authoritative. UIApplication can still
        // report inactive while sceneDidBecomeActive is running.
        wanted = enabled && isBedside() && sceneActive
        if !wanted { stop(); return }
        guard worker == nil else { return }
        let token = UUID(); generation = token
        changeStatus("Connecting phone keypad…")
        record(["kind": "usbStartRequested"])
        let worker = makeConnection { [weak self] update in
            guard let self else { return }
            switch update {
            case .ready:
                guard self.generation == token, !self.stopping else { return }
                self.changeStatus("Phone keypad ready")
                self.record(["kind": "usbReady"])
            case .digits(let digits, let receivedAt):
                let age = ProcessInfo.processInfo.systemUptime - receivedAt
                guard self.generation == token, self.wanted, !self.stopping,
                      age < 1, self.sceneActive, self.isBedside() else {
                    self.record(["kind": "digitIgnored", "reason": "session or foreground gate",
                                 "symbols": digits.filter { $0.kind == .digit }.map(\.digit).joined(),
                                 "callbackAge": age, "generationMatches": self.generation == token,
                                 "wanted": self.wanted, "stopping": self.stopping,
                                 "sceneActive": self.sceneActive, "bedside": self.isBedside()])
                    return
                }
                // A full-screen call detaches the presenting clock view from
                // its window. The owning scene, not that view, stays active.
                guard let root = self.root, self.windowScene?.activationState == .foregroundActive else {
                    self.record(["kind": "digitIgnored", "reason": "window scene inactive or root missing",
                                 "sceneState": self.windowScene?.activationState.rawValue ?? -99])
                    return
                }
                for event in digits {
                    guard event.kind == .digit else { continue }
                    let outcome = Cell2JackDigitRouter.route(event.digit, root: root)
                    self.record(["kind": "digit", "symbol": event.digit, "outcome": outcome,
                                 "rawLine": event.line, "embeddedInLine": event.embeddedInLine,
                                 "rootViewAttached": root.viewIfLoaded?.window != nil])
                }
            case .health(let bytes, let packets, let primaryDigits):
                guard self.generation == token, self.wanted, !self.stopping else { return }
                self.record(["kind": "usbHealth", "bytes": bytes, "packets": packets,
                             "primaryDigits": primaryDigits,
                             "sceneState": self.windowScene?.activationState.rawValue ?? -99])
            case .finished(let message):
                let restart = self.stopping && self.wanted
                self.worker = nil; self.stopping = false
                self.changeStatus(message); self.record(["kind": "usbStopped", "result": message])
                if self.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid }
                if restart { self.refresh() }
            }
        }
        self.worker = worker; worker.start()
    }
    func pause() {
        sceneActive = false; wanted = false
        if enabled || worker != nil { record(["kind": "sceneInactive"]) }
        stop()
    }
    private func stop() {
        generation = UUID()
        guard let worker else { changeStatus(enabled ? "Phone keypad paused" : "Phone keypad off"); return }
        guard !stopping else { return }
        stopping = true; changeStatus("Stopping phone keypad…")
        if !sceneActive {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Stop Cell2Jack logs") { [weak self] in
                guard let self, self.backgroundTask != .invalid else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid
            }
        }
        worker.stop()
    }
    private func changeStatus(_ text: String) {
        status = text
        NotificationCenter.default.post(name: .cell2JackKeypadChanged, object: nil)
    }
    func record(_ values: [String: Any]) {
        guard enabled || worker != nil else { return }
        var values = values; values["utc"] = ISO8601DateFormatter().string(from: Date())
        records.append(values); records = Array(records.suffix(200))
        guard let data = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cell2jack-call-actions.json")
        reportQueue.async { try? data.write(to: url, options: .atomic) }
    }
}

private final class Cell2JackUnavailableConnection: Cell2JackKeypadConnection {
    private let update: (Cell2JackKeypadUpdate) -> Void
    init(_ update: @escaping (Cell2JackKeypadUpdate) -> Void) { self.update = update }
    func start() { DispatchQueue.main.async { self.update(.finished("Cell2Jack requires an M-series iPad with iPadOS 16 or later. USB keypads and touch controls remain available.")) } }
    func stop() {}
}

/// Continuous foreground input. Bounded parser, action history and 64 KiB raw
/// diagnostic tail; no time cutoff that would remove hang-up during a call.
@available(iOS 16.0, *)
private final class Cell2JackKeypadTransport: Cell2JackKeypadConnection {
    typealias Update = Cell2JackKeypadUpdate
    private let queue = DispatchQueue(label: "porch.cell2jack.real-calls.usb")
    private let callback: (Update) -> Void
    private var session: Cell2JackLogSession?
    private var timer: DispatchSourceTimer?
    private var parser = Cell2JackDTMFParser()
    private var finished = false
    private var attempts = 0
    private var attemptTime = 0.0
    private var ready = false
    private var totalBytes = 0
    private var packets = 0
    private var primaryDigits = 0
    private var rawTail = Data()
    private var lastHealth = 0.0
    private var tailDirty = false
    private let tailURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("cell2jack-usb-tail.bin")
    init(_ callback: @escaping (Update) -> Void) { self.callback = callback }
    private func emit(_ update: Update) { DispatchQueue.main.async { self.callback(update) } }
    private func unpack(_ data: Data) throws -> Data {
        guard data.count >= MemoryLayout<PorchC2JReply>.size else { throw failure("Short driver reply") }
        let reply = data.withUnsafeBytes { $0.loadUnaligned(as: PorchC2JReply.self) }
        var bytes = reply.bytes
        guard reply.usbStatus == 0, Int(reply.count) <= MemoryLayout.size(ofValue: bytes) else {
            throw failure("USB stage \(reply.stage): \(String(format: "0x%08x", reply.usbStatus))")
        }
        return withUnsafeBytes(of: &bytes) { Data($0.prefix(Int(reply.count))) }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "PorchCell2Jack", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    func start() {
        queue.async {
            guard !self.finished else { return }
            do {
                self.session = try Cell2JackLogSession.open()
                try self.begin()
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(1))
                timer.setEventHandler { [weak self] in self?.poll() }
                self.timer = timer; timer.resume()
            } catch { self.finish("Phone keypad unavailable: \(error.localizedDescription)") }
        }
    }
    private func begin() throws {
        guard let session else { throw failure("USB session closed") }
        attempts += 1; parser.resetPartialLine()
        _ = try unpack(session.beginLogs())
        attemptTime = ProcessInfo.processInfo.systemUptime
    }
    private func poll() {
        guard !finished, let session else { return }
        do {
            let bytes = try unpack(session.pollLogs())
            if !bytes.isEmpty {
                totalBytes += bytes.count; packets += 1
                rawTail.append(bytes)
                if rawTail.count > 65_536 { rawTail = Data(rawTail.suffix(65_536)) }
                tailDirty = true
                if !ready { ready = true; emit(.ready) }
                let digits = parser.append(bytes)
                primaryDigits += digits.filter { $0.kind == .digit }.count
                if !digits.isEmpty { emit(.digits(digits, ProcessInfo.processInfo.systemUptime)) }
            } else if !ready, ProcessInfo.processInfo.systemUptime - attemptTime >= 2 {
                guard attempts < 3 else { throw failure("No device logs after three attempts. Check the driver and reconnect, then tap Retry.") }
                _ = try unpack(session.endLogs()); try begin()
            }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastHealth >= 5 {
                lastHealth = now
                saveTail()
                emit(.health(bytes: totalBytes, packets: packets, primaryDigits: primaryDigits))
            }
        } catch { finish("Phone keypad stopped: \(error.localizedDescription)") }
    }
    private func saveTail() {
        guard tailDirty else { return }
        do {
            try rawTail.write(to: tailURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            tailDirty = false
        } catch { /* Diagnostic storage never disables the call controls. */ }
    }
    func stop() { queue.async { self.finish("Phone keypad stopped") } }
    private func finish(_ message: String) {
        guard !finished else { return }
        finished = true; timer?.cancel(); timer = nil
        saveTail()
        var cleanup = ""
        if let session {
            do { _ = try unpack(session.endLogs()); cleanup = " · /q sent" }
            catch { cleanup = " · /q unconfirmed; unplug Cell2Jack if logging persists" }
            session.close()
        }
        session = nil; emit(.finished(message + cleanup))
    }
}
