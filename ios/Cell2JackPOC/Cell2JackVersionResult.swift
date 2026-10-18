import Foundation

/// Preserve raw bytes and recognize only the observed CJ Version header.
/// Unrelated digits, debug lines and partial headers cannot report success.
struct Cell2JackVersionResult {
    let bytes: Data
    var version: String? {
        let pattern = #"CJ Version\s*=\s*([A-Za-z0-9]{3})(?=\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let text = String(data: bytes, encoding: .ascii),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    var displayText: String {
        bytes.map { byte in
            if byte == 10 { return "\n" }
            if byte == 13 { return "\\r" }
            if (32...126).contains(byte) { return String(UnicodeScalar(byte)) }
            return String(format: "\\x%02x", byte)
        }.joined()
    }
    var hex: String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }
}
