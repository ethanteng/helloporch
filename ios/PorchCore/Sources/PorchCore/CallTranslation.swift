import Foundation

/// What the call translator (translator/ in this repository, a LiveKit agent) sends the people on a call, on the
/// `porch-translation` data topic. Each side of the call hears the translator on its own track: the bedside on
/// `porch-translation-bedside`, family on `porch-translation-family`.
public enum CallTranslationMessage: Equatable {
    /// Something someone said. Family receive every line; the bedside only lines said to it, as they're said.
    case line(CallTranslationLine)
    /// Translation started, changed language or stopped.
    case state(on: Bool, language: String)
    /// The translator started or stopped speaking to this side, so the app can lower the other voices under it.
    case speaking(Bool)

    public static let topic = "porch-translation"
    public static func trackName(forBedside bedside: Bool) -> String { bedside ? "porch-translation-bedside" : "porch-translation-family" }
    /// Attributes the translator sets on itself.
    public static let attribute = "porch.translator"

    public static func decode(_ data: Data) -> CallTranslationMessage? {
        struct Envelope: Decodable { let type: String; let on: Bool?; let language: String? }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch envelope.type {
        case "line": return (try? JSONDecoder().decode(CallTranslationLine.self, from: data)).map { .line($0) }
        case "state": return envelope.on.flatMap { on in envelope.language.map { .state(on: on, language: $0) } }
        case "speaking": return envelope.on.map { .speaking($0) }
        default: return nil
        }
    }
}

/// One thing someone said on a translated call.
public struct CallTranslationLine: Codable, Equatable, Identifiable {
    public let id: String
    /// The speaker's LiveKit identity: their member ID, or a phone guest's leg.
    public let speaker: String
    public let name: String
    /// "bedside" or "family": the side of the call the speaker is on.
    public let side: String
    /// What speech recognition heard.
    public let heard: String
    /// What the translator said to the other side, in `language`. Nil when it was already in their language.
    public let said: String?
    public let language: String
    public let at: TimeInterval
    public var fromBedside: Bool { side == "bedside" }
    public init(id: String, speaker: String, name: String, side: String, heard: String, said: String?, language: String, at: TimeInterval) {
        self.id = id; self.speaker = speaker; self.name = name; self.side = side; self.heard = heard; self.said = said; self.language = language; self.at = at
    }
}
