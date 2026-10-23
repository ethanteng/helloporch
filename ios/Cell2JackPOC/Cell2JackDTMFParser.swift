import Foundation

struct Cell2JackDigitEvent: Equatable {
    // hangUp carries no digit: the receiver went back on the cradle.
    enum Kind: String { case digit, doubleReport, pulse, hangUp }
    let kind: Kind
    let digit: String
    let line: String
    var embeddedInLine = false
}

/// Byte-oriented framing preserves fragmented lines and never combines an
/// overlong/binary line's suffix with the next line to invent a keypad event.
struct Cell2JackDTMFParser {
    private var line = Data()
    private var dropping = false
    // Cell2Jack reports a digit counted from hook pulses as an ordinary DTMF
    // record right after "Get PULSE". A brief line break when the handset is
    // lifted counts as one pulse, so the record that follows is a phantom 1,
    // not a key press. A hook change clears a pulse that never produced one.
    private var pulseDigitPending = false
    // Cell2Jack also reports ON_HOOK as it starts up with the receiver already
    // down. Only a pickup or key press seen in this session makes ON_HOOK a
    // hang-up; keys work only off the cradle.
    private var handsetLifted = false
    private let maximumLine = 4096
    private static let hangUpPattern = try! NSRegularExpression(pattern: #"(?:^|[^A-Z_])ON_HOOK(?:[^A-Z_]|$)"#)
    private static let pattern = try! NSRegularExpression(
        pattern: #"^[ \t]*(DTMF|RX Double DTMF|Double DTMF)[ \t]+([0-9*#ABCD])(?=[ \t:]|$)"#)
    // The full keypad capture contains " Cal DTMF 1 :0 20: 2": firmware
    // capture joined a status fragment to a genuine event. Recover only the
    // observed numeric record shape, not arbitrary mentions of a digit.
    private static let embeddedPattern = try! NSRegularExpression(
        pattern: #"(?:^|[ \t])(RX Double DTMF|Double DTMF|DTMF)[ \t]+([0-9*#ABCD])[ \t]*:[0-9]+[ \t]+[0-9]+[ \t]*:[ \t]*[0-9]+[ \t]*$"#)

    mutating func resetPartialLine() { line.removeAll(keepingCapacity: true); dropping = false }
    mutating func append(_ bytes: Data) -> [Cell2JackDigitEvent] {
        var events: [Cell2JackDigitEvent] = []
        for byte in bytes {
            if byte == 10 || byte == 13 {
                if !dropping, !line.isEmpty { events += parse(line) }
                resetPartialLine()
            } else if !dropping {
                if line.count == maximumLine { line.removeAll(keepingCapacity: true); dropping = true }
                else { line.append(byte) }
            }
        }
        return events
    }
    private mutating func parse(_ bytes: Data) -> [Cell2JackDigitEvent] {
        guard let text = String(data: bytes, encoding: .ascii) else { return [] }
        if text.contains("ON_HOOK") || text.contains("OFF_HOOK") { pulseDigitPending = false }
        if text.contains("Get PULSE") { pulseDigitPending = true }
        let range = NSRange(text.startIndex..., in: text)
        var events: [Cell2JackDigitEvent] = []
        let primary = Self.pattern.firstMatch(in: text, range: range)
        if let match = primary ?? Self.embeddedPattern.firstMatch(in: text, range: range),
           let label = Range(match.range(at: 1), in: text),
           let digit = Range(match.range(at: 2), in: text) {
            var kind: Cell2JackDigitEvent.Kind = text[label] == "DTMF" ? .digit : .doubleReport
            if kind == .digit, pulseDigitPending { kind = .pulse; pulseDigitPending = false }
            events.append(Cell2JackDigitEvent(kind: kind, digit: String(text[digit]), line: text, embeddedInLine: primary == nil))
            handsetLifted = true
        }
        // A hang-up joined to a key's line came after the key.
        if text.contains("OFF_HOOK") { handsetLifted = true }
        else if Self.hangUpPattern.firstMatch(in: text, range: range) != nil {
            if handsetLifted { events.append(Cell2JackDigitEvent(kind: .hangUp, digit: "", line: text)) }
            handsetLifted = false
        }
        return events
    }
}
