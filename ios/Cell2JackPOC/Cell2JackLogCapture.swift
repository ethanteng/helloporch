import Foundation

/// Owns the user client, bounded polling, parser, and capture files on one queue.
/// No HelloPorch action handler is connected to these diagnostic events.
final class Cell2JackLogCapture {
    struct Update {
        enum Kind { case status, packet, finished }
        let kind: Kind
        let message: String
        var bytes = Data()
        var digits: [Cell2JackDigitEvent] = []
        var received = 0
    }
    private let queue = DispatchQueue(label: "com.ethanteng.helloporch.cell2jack.logs")
    private let callback: (Update) -> Void
    private var session: Cell2JackLogSession?
    private var timer: DispatchSourceTimer?
    private var rawFile: FileHandle?
    private var eventsFile: FileHandle?
    private var folder: URL?
    private var parser = Cell2JackDTMFParser()
    private var started = false
    private var finished = false
    private var startTime = 0.0
    private var attemptTime = 0.0
    private var attempts = 0
    private var attemptBytes = 0
    private var received = 0
    private var rawBytes = 0
    private var digitCount = 0
    private var digitTail = ""
    private let formatter = ISO8601DateFormatter()
    private let maximumBytes = 4 * 1024 * 1024
    private let maximumSeconds = 120.0

    init(onUpdate: @escaping (Update) -> Void) { callback = onUpdate }
    func start() {
        queue.async { [self] in
            guard !self.started, !self.finished else { return }
            self.started = true
            self.startTime = ProcessInfo.processInfo.systemUptime
            do {
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let folder = documents.appendingPathComponent("keypad-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                self.folder = folder
                try folder.lastPathComponent.write(to: documents.appendingPathComponent("keypad-latest.txt"), atomically: true, encoding: .utf8)
                for name in ["received.bin", "events.jsonl"] {
                    guard FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: nil) else {
                        throw self.error("Could not create the keypad capture files.")
                    }
                }
                self.rawFile = try FileHandle(forWritingTo: folder.appendingPathComponent("received.bin"))
                self.eventsFile = try FileHandle(forWritingTo: folder.appendingPathComponent("events.jsonl"))
                try self.event(["kind": "start", "baud": 2000000, "durationLimit": self.maximumSeconds])
                self.session = try Cell2JackLogSession.open()
                try self.beginAttempt()
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(30))
                timer.setEventHandler { [weak self] in self?.poll() }
                self.timer = timer
                timer.resume()
            } catch { self.finish("Could not start keypad test: \(error.localizedDescription)") }
        }
    }
    func stop(reason: String = "Stopped by you") { queue.async { self.finish(reason) } }
    private func emit(_ update: Update) { DispatchQueue.main.async { self.callback(update) } }
    private func error(_ text: String) -> NSError {
        NSError(domain: "PorchCell2JackCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private func unpack(_ data: Data) throws -> (PorchC2JReply, Data) {
        let reply = data.withUnsafeBytes { $0.loadUnaligned(as: PorchC2JReply.self) }
        guard reply.usbStatus == 0 else {
            throw error("USB stage \(reply.stage): \(String(format: "0x%08x", reply.usbStatus))")
        }
        var packet = reply.bytes
        let bytes = withUnsafeBytes(of: &packet) { Data($0.prefix(Int(reply.count))) }
        return (reply, bytes)
    }
    private func event(_ values: [String: Any]) throws {
        var values = values
        values["utc"] = formatter.string(from: Date())
        values["elapsed"] = ProcessInfo.processInfo.systemUptime - startTime
        var data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        data.append(10)
        try eventsFile?.write(contentsOf: data)
    }
    private func record(_ bytes: Data, phase: String) throws {
        guard rawBytes + bytes.count <= maximumBytes else { throw error("Capture size limit reached") }
        try rawFile?.write(contentsOf: bytes)
        rawBytes += bytes.count
        if !bytes.isEmpty { try event(["kind": "rx", "phase": phase, "bytes": bytes.count, "rawOffset": rawBytes - bytes.count]) }
    }
    private func beginAttempt() throws {
        guard let session else { throw error("USB session is closed") }
        attempts += 1
        attemptBytes = 0
        parser.resetPartialLine()
        try event(["kind": "enable", "attempt": attempts, "sequence": "/v, read, 500ms, /d"])
        let (_, bytes) = try unpack(session.beginLogs())
        try record(bytes, phase: "version")
        attemptTime = ProcessInfo.processInfo.systemUptime
        emit(Update(kind: .status, message: "Waiting for device logs (attempt \(attempts)/3)…"))
    }
    private func poll() {
        guard !finished, let session else { return }
        do {
            if ProcessInfo.processInfo.systemUptime - startTime >= maximumSeconds {
                finish("Two-minute test complete"); return
            }
            let (_, bytes) = try unpack(session.pollLogs())
            if !bytes.isEmpty {
                try record(bytes, phase: "logs")
                received += bytes.count
                attemptBytes += bytes.count
                let digits = parser.append(bytes)
                for digit in digits {
                    if digit.kind == .digit { digitCount += 1; digitTail = String((digitTail + digit.digit).suffix(128)) }
                    try event(["kind": digit.kind.rawValue, "digit": digit.digit, "line": digit.line, "digitCount": digitCount])
                }
                emit(Update(kind: .packet, message: "Receiving logs · \(digitCount) digit events · \(received) bytes",
                            bytes: bytes, digits: digits, received: received))
            } else if attemptBytes == 0 && ProcessInfo.processInfo.systemUptime - attemptTime >= 2 {
                guard attempts < 3 else { finish("No log bytes received after three attempts"); return }
                _ = try unpack(session.endLogs())
                try event(["kind": "retry", "command": "/q"])
                try beginAttempt()
            }
        } catch { finish("Keypad test ended: \(error.localizedDescription)") }
    }
    private func finish(_ reason: String) {
        guard !finished else { return }
        finished = true
        timer?.cancel(); timer = nil
        var stopResult = "No logging session was opened."
        if let session {
            do {
                let (reply, _) = try unpack(session.endLogs())
                stopResult = reply.stage == UInt32(PorchC2JLogStop.rawValue) ? "/q sent; USB session closed." : "No active driver logging session; USB session closed."
            }
            catch { stopResult = "Could not confirm /q: \(error.localizedDescription). Disconnect Cell2Jack's power if logging persists." }
            session.close()
        }
        session = nil
        try? event(["kind": "stop", "reason": reason, "stopResult": stopResult, "digitCount": digitCount, "logBytes": received])
        let summary = "\(reason)\n\(stopResult)\n\(digitCount) digit events; \(received) log bytes.\nLast digits: \(digitTail)\nCapture: \(folder?.lastPathComponent ?? "unavailable")"
        if let folder { try? summary.write(to: folder.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8) }
        try? rawFile?.close(); rawFile = nil
        try? eventsFile?.close(); eventsFile = nil
        emit(Update(kind: .finished, message: summary, received: received))
    }
}
