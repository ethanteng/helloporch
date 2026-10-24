import UIKit
import PorchCore

/// Phone digits share Porch's existing actions; keyboard input remains independent.
protocol Cell2JackDigitReceiving: AnyObject {
    func receiveCell2JackDigit(_ digit: Int) -> String
    /// The receiver went back on the cradle. Only screens with a call to end act on it.
    func receiveCell2JackHangUp() -> String
}
extension Cell2JackDigitReceiving {
    func receiveCell2JackHangUp() -> String { "hang-up ignored" }
}

enum Cell2JackDigitRouter {
    static let transitioning = "screen transitioning"
    static func route(_ symbol: String, root: UIViewController) -> String {
        guard let digit = CallSlots.digit(forSymbol: symbol) else { return "unassigned symbol" }
        return deliver(root: root) { $0.receiveCell2JackDigit(digit) }
    }
    static func routeHangUp(root: UIViewController) -> String {
        deliver(root: root) { $0.receiveCell2JackHangUp() }
    }
    private static func deliver(root: UIViewController, _ action: (Cell2JackDigitReceiving) -> String) -> String {
        var screen = root
        while true {
            guard !screen.isBeingDismissed, !screen.isBeingPresented, screen.transitionCoordinator == nil else { return transitioning }
            if let presented = screen.presentedViewController { screen = presented }
            else if let nav = screen as? UINavigationController, let top = nav.topViewController { screen = top }
            else if let tabs = screen as? UITabBarController, let selected = tabs.selectedViewController { screen = selected }
            else if screen is PorchContainerViewController, let child = screen.children.first { screen = child }
            else { break }
        }
        // An unknown modal (PIN, settings, alert, permission UI) blocks input.
        guard let receiver = screen as? Cell2JackDigitReceiving else { return "screen does not accept phone keys" }
        return action(receiver)
    }
}

extension Notification.Name { static let cell2JackKeypadChanged = Notification.Name("porch.cell2jack.changed") }

enum Cell2JackKeypadUpdate {
    case ready, digits([Cell2JackDigitEvent], TimeInterval), finished(String)
    case health(bytes: Int, packets: Int, primaryDigits: Int)
}
protocol Cell2JackKeypadConnection: AnyObject {
    var supportsRecovery: Bool { get }
    func start()
    func stop()
}
extension Cell2JackKeypadConnection { var supportsRecovery: Bool { true } }

/// Main-thread owner. Stale callbacks cannot act after stopping/backgrounding.
final class Cell2JackKeypad {
    static let shared = Cell2JackKeypad()
    // The prototype's automatic test opt-in is deliberately not migrated.
    static let enabledKey = "porch.cell2jack.enabled"
    // On unless a caregiver turns it off, for someone who sets the receiver down
    // right after pressing a key because the sound comes from the iPad.
    static let receiverHangUpKey = "porch.cell2jack.receiverHangUp"
    weak var root: UIViewController?
    weak var windowScene: UIWindowScene?
    private(set) var status = "Phone keypad off"
    private var worker: Cell2JackKeypadConnection?
    private var stopping = false
    private var wanted = false
    private var sceneActive = false
    private var generation = UUID()
    // Unlike generation, this identity survives stop() until that client finishes cleanup.
    private var connectionID: UUID?
    private var retryWork: DispatchWorkItem?
    private var retryID = UUID()
    private var nextRetryDelay: TimeInterval = 1
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private(set) var records: [[String: Any]] = []
    private let reportQueue = DispatchQueue(label: "porch.cell2jack.actions")
    private let defaults: UserDefaults
    private let isBedside: () -> Bool
    private let uptime: () -> TimeInterval
    private let enqueueRetry: (TimeInterval, DispatchWorkItem) -> Void
    private let makeConnection: (@escaping (Cell2JackKeypadUpdate) -> Void) -> Cell2JackKeypadConnection
    var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var receiverHangUp: Bool { defaults.object(forKey: Self.receiverHangUpKey) as? Bool ?? true }

    init(defaults: UserDefaults = .standard,
         isBedside: @escaping () -> Bool = { PorchDevice.experience == .bedside },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         enqueueRetry: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         },
         makeConnection: @escaping (@escaping (Cell2JackKeypadUpdate) -> Void) -> Cell2JackKeypadConnection = { Cell2JackKeypad.makeDefaultConnection($0) }) {
        self.defaults = defaults; self.isBedside = isBedside; self.makeConnection = makeConnection
        self.uptime = uptime; self.enqueueRetry = enqueueRetry
    }
    static var supportsDriverPlatform: Bool {
        #if PORCH_NO_CELL2JACK
        return false
        #else
        if #available(iOS 16.0, *) { return UIDevice.current.userInterfaceIdiom == .pad }
        return false
        #endif
    }
    private static func makeDefaultConnection(_ update: @escaping (Cell2JackKeypadUpdate) -> Void) -> Cell2JackKeypadConnection {
        #if !PORCH_NO_CELL2JACK
        if #available(iOS 16.0, *), supportsDriverPlatform { return Cell2JackKeypadTransport(update) }
        #endif
        return Cell2JackUnavailableConnection(update)
    }

    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.enabledKey)
        refresh()
    }
    func setReceiverHangUp(_ value: Bool) { defaults.set(value, forKey: Self.receiverHangUpKey) }
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
        cancelRetry()
        let token = UUID(); generation = token; connectionID = token
        let startedAt = uptime()
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
                                 "hangUp": digits.contains { $0.kind == .hangUp },
                                 "callbackAge": age, "generationMatches": self.generation == token,
                                 "wanted": self.wanted, "stopping": self.stopping,
                                 "sceneActive": self.sceneActive, "bedside": self.isBedside()])
                    return
                }
                // A full-screen call detaches the presenting clock view from
                // its window. The owning scene, not that view, stays active.
                guard let root = self.root, self.windowScene?.activationState == .foregroundActive else {
                    self.record(["kind": "digitIgnored", "reason": "window scene inactive or root missing",
                                 "hangUp": digits.contains { $0.kind == .hangUp },
                                 "sceneState": self.windowScene?.activationState.rawValue ?? -99])
                    return
                }
                for event in digits {
                    if event.kind == .pulse {
                        self.record(["kind": "pulseDigitIgnored", "symbol": event.digit, "rawLine": event.line])
                    }
                    if event.kind == .hangUp { self.deliverHangUp(event.line, root: root, token: token) }
                    guard event.kind == .digit else { continue }
                    let outcome = Cell2JackDigitRouter.route(event.digit, root: root)
                    self.record(["kind": "digit", "symbol": event.digit, "outcome": outcome,
                                 "rawLine": event.line, "embeddedInLine": event.embeddedInLine,
                                 "rootViewAttached": root.viewIfLoaded?.window != nil])
                }
            case .health(let bytes, let packets, let primaryDigits):
                guard self.generation == token, self.wanted, !self.stopping else { return }
                // A briefly responsive but faulty adapter must not reset the backoff on every attempt.
                if bytes > 0, self.uptime() - startedAt >= 30 { self.nextRetryDelay = 1 }
                self.record(["kind": "usbHealth", "bytes": bytes, "packets": packets,
                             "primaryDigits": primaryDigits,
                             "sceneState": self.windowScene?.activationState.rawValue ?? -99])
            case .finished(let message):
                guard self.connectionID == token else { return }
                let restart = self.stopping && self.wanted
                let recoverable = self.worker?.supportsRecovery == true
                self.worker = nil; self.connectionID = nil; self.stopping = false
                self.generation = UUID()
                self.changeStatus(message); self.record(["kind": "usbStopped", "result": message])
                if self.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid }
                if restart { self.refresh() }
                else if self.wanted, recoverable { self.scheduleRetry() }
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
        cancelRetry(); nextRetryDelay = 1
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
    private func cancelRetry() {
        retryID = UUID(); retryWork?.cancel(); retryWork = nil
    }
    private func scheduleRetry() {
        guard wanted, enabled, sceneActive, isBedside(), worker == nil, retryWork == nil else { return }
        let delay = nextRetryDelay
        nextRetryDelay = min(delay * 2, 15)
        let token = UUID(); retryID = token
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.retryID == token else { return }
            self.retryWork = nil
            self.refresh() // Recheck foreground, preference and bedside mode before opening USB.
        }
        retryWork = work
        record(["kind": "usbRetryScheduled", "delaySeconds": delay])
        enqueueRetry(delay, work)
    }
    /// The receiver can't repeat a hang-up the way a key can be pressed again, so one that
    /// lands while a screen is opening or closing is tried again for about two seconds.
    private func deliverHangUp(_ line: String, root: UIViewController, token: UUID, attempt: Int = 1) {
        let outcome = receiverHangUp ? Cell2JackDigitRouter.routeHangUp(root: root) : "receiver hang-up off"
        record(["kind": "hangUp", "outcome": outcome, "rawLine": line, "attempt": attempt])
        guard outcome == Cell2JackDigitRouter.transitioning, attempt < 6 else { return }
        enqueueRetry(0.4, DispatchWorkItem { [weak self, weak root] in
            guard let self else { return }
            guard let root, self.generation == token, self.wanted, !self.stopping, self.sceneActive,
                  self.windowScene?.activationState == .foregroundActive else {
                self.record(["kind": "hangUp", "outcome": "dropped: session or foreground gate", "rawLine": line, "attempt": attempt + 1])
                return
            }
            self.deliverHangUp(line, root: root, token: token, attempt: attempt + 1)
        })
    }
    private func changeStatus(_ text: String) {
        status = text
        NotificationCenter.default.post(name: .cell2JackKeypadChanged, object: nil)
    }
    func record(_ values: [String: Any]) {
        guard enabled || worker != nil else { return }
        var values = values; values["utc"] = ISO8601DateFormatter().string(from: Date())
        // Health repeats every five seconds and its counts are cumulative; keeping only the
        // latest one stops it pushing key and call history out of the 200 records.
        if values["kind"] as? String == "usbHealth", records.last?["kind"] as? String == "usbHealth" { records.removeLast() }
        records.append(values); records = Array(records.suffix(200))
        guard let data = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cell2jack-call-actions.json")
        reportQueue.async { try? data.write(to: url, options: .atomic) }
    }
}

private final class Cell2JackUnavailableConnection: Cell2JackKeypadConnection {
    let supportsRecovery = false
    private let update: (Cell2JackKeypadUpdate) -> Void
    init(_ update: @escaping (Cell2JackKeypadUpdate) -> Void) { self.update = update }
    func start() { DispatchQueue.main.async { self.update(.finished("Cell2Jack requires an M-series iPad with iPadOS 16 or later. USB keypads and touch controls remain available.")) } }
    func stop() {}
}

#if !PORCH_NO_CELL2JACK
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
#endif
