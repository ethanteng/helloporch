import Foundation

/// Original local cues, never published as a media track.
public enum CallTone: CaseIterable, Equatable {
    /// `beep` starts a voicemail recording, as on a telephone.
    case ringback, incoming, announcement, connected, beep
    public var loops: Bool { self == .ringback || self == .incoming }
    public var duration: Double {
        switch self { case .ringback: return 6; case .incoming: return 3; case .announcement: return 0.6; case .connected: return 0.5; case .beep: return 0.5 }
    }
    public func wave() -> Data {
        let rate = 16_000, samples = Int(duration * 16_000)
        var data = Data()
        func ascii(_ text: String) { data.append(contentsOf: text.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        ascii("RIFF"); integer(UInt32(36 + samples * 2)); ascii("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(rate))
        integer(UInt32(rate * 2)); integer(UInt16(2)); integer(UInt16(16)); ascii("data"); integer(UInt32(samples * 2))
        for index in 0..<samples {
            let t = Double(index) / Double(rate)
            let start: Double, end: Double, first: Double, second: Double
            switch self {
            case .ringback: (start, end, first, second) = (0, 2, 440, 480)
            case .incoming: (start, end, first, second) = t < 0.8 ? (0, 0.6, 440, 480) : (0.8, 1.4, 440, 480)
            case .announcement: (start, end, first, second) = t < 0.3 ? (0, 0.25, 660, 660) : (0.3, 0.6, 880, 880)
            case .connected: (start, end, first, second) = t < 0.2 ? (0, 0.18, 660, 660) : (0.2, 0.5, 880, 880)
            case .beep: (start, end, first, second) = (0, 0.45, 1000, 1000)
            }
            let fade = max(0, min(1, (t - start) / 0.015, (end - t) / 0.015))
            let sample = (sin(2 * .pi * first * t) + sin(2 * .pi * second * t)) * 0.35 * fade
            integer(Int16(sample * Double(Int16.max)))
        }
        return data
    }
}
