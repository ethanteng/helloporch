import Foundation

/// How the bedside's desk phone reaches it: a Cell2Jack that Porch talks to itself (its driver on an iPad with an M chip,
/// or USB on an Android tablet), or the Porch phone adapter, which an iPad sees as a keyboard. The adapter knows whether
/// its Cell2Jack answers but doesn't tell the iPad, so through it Porch only knows the adapter is plugged in.
public enum BedsidePhoneKind: String, Equatable {
    case cell2jack, adapter
}

/// Family caregivers: the bedside's desk phone, once it's been out long enough that caregivers were told, until it's
/// back. `since` is when it went out, in server time. A kind a later server adds reads as `nil` in `phoneKind`.
public struct BedsidePhone: Codable, Equatable {
    public let since: TimeInterval
    public let kind: String
    public init(since: TimeInterval, kind: String) { self.since = since; self.kind = kind }
    public var phoneKind: BedsidePhoneKind? { BedsidePhoneKind(rawValue: kind) }
}

/// What the bedside's check-in says about its desk phone (`phone` in the poll).
public enum BedsidePhoneReport: Equatable {
    /// No phone set up here, as when a caregiver turned the phone keypad off.
    case none
    case phone(BedsidePhoneKind, connected: Bool)

    /// The report, or nil to say nothing: while Porch isn't on screen it doesn't connect to the Cell2Jack, so it can't
    /// tell, and the server keeps the last report. The rest follows This iPad's "The phone is connected": the driver's
    /// Cell2Jack answers, or a keyboard is plugged in once the adapter has been heard on this iPad.
    public static func make(onScreen: Bool, driver: Bool, driverOn: Bool, driverAnswering: Bool, keyboard: Bool, adapterHeard: Bool) -> BedsidePhoneReport? {
        guard onScreen else { return nil }
        if driver && driverAnswering { return .phone(.cell2jack, connected: true) }
        if keyboard && adapterHeard { return .phone(.adapter, connected: true) }
        if driver && driverOn { return .phone(.cell2jack, connected: false) }
        if adapterHeard { return .phone(.adapter, connected: false) }
        return BedsidePhoneReport.none
    }

    /// As the poll sends it: null for none.
    public var json: Any {
        switch self {
        case .none: return NSNull()
        case .phone(let kind, let connected): return ["kind": kind.rawValue, "connected": connected]
        }
    }
}

/// What a caregiver checks when the bedside's phone isn't connected, as What to check lists it and Share sends it.
public enum PhoneChecks {
    /// The plugs to check for how the phone is plugged in, at an iPad or an Android tablet (`device`).
    public static func steps(kind: BedsidePhoneKind?, device: String) -> [String] {
        switch kind {
        case .adapter: return ["Phone cord into the Cell2Jack", "Cell2Jack into the adapter", "Adapter into the hub by the \(device)"]
        default: return ["Phone cord into the Cell2Jack", device == "iPad" ? "Cell2Jack into the iPad or its hub" : "Cell2Jack into the hub by the \(device)"]
        }
    }

    /// "At Rose’s iPad, check each plug:"
    public static func lead(name: String, device: String) -> String { "At \(name)’s \(device), check each plug:" }

    /// The steps as a text to send whoever is at the bedside.
    public static func shareText(name: String, device: String, kind: BedsidePhoneKind?, guide: URL) -> String {
        let steps = steps(kind: kind, device: device).enumerated().map { "\($0.offset + 1). \($0.element)" }
        return (["\(name)’s phone isn’t connected to Porch. At \(name)’s \(device), please check each plug:"] + steps
            + ["Step-by-step: \(guide.absoluteString)"]).joined(separator: "\n")
    }
}
