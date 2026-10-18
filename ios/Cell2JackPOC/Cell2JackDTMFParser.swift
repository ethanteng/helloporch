import Foundation

struct Cell2JackDigitEvent: Equatable {
    enum Kind: String { case digit, doubleReport }
    let kind: Kind
    let digit: String
    let line: String
}

/// Byte-oriented framing preserves fragmented lines and never combines an
/// overlong/binary line's suffix with the next line to invent a keypad event.
struct Cell2JackDTMFParser {
    private var line = Data()
    private var dropping = false
    private let maximumLine = 4096
    private static let pattern = try! NSRegularExpression(
        pattern: #"^[ \t]*(DTMF|RX Double DTMF|Double DTMF)[ \t]+([0-9*#ABCD])(?=[ \t:]|$)"#)

    mutating func resetPartialLine() { line.removeAll(keepingCapacity: true); dropping = false }
    mutating func append(_ bytes: Data) -> [Cell2JackDigitEvent] {
        var events: [Cell2JackDigitEvent] = []
        for byte in bytes {
            if byte == 10 || byte == 13 {
                if !dropping, !line.isEmpty, let event = parse(line) { events.append(event) }
                resetPartialLine()
            } else if !dropping {
                if line.count == maximumLine { line.removeAll(keepingCapacity: true); dropping = true }
                else { line.append(byte) }
            }
        }
        return events
    }
    private func parse(_ bytes: Data) -> Cell2JackDigitEvent? {
        guard let text = String(data: bytes, encoding: .ascii),
              let match = Self.pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let label = Range(match.range(at: 1), in: text),
              let digit = Range(match.range(at: 2), in: text) else { return nil }
        return Cell2JackDigitEvent(kind: text[label] == "DTMF" ? .digit : .doubleReport,
                                  digit: String(text[digit]), line: text)
    }
}
