import Foundation

/// A pure description of a key's meaning. It has no call, media, URL-launch,
/// network, settings-write, or action-execution dependency.
public struct KeypadActionPreview {
    public enum Context: String, CaseIterable, Codable {
        case clock, incoming, voiceCall, videoCall, dropIn, messages
        public var title: String {
            switch self {
            case .clock: return "Clock"
            case .incoming: return "Incoming call"
            case .voiceCall: return "Voice call"
            case .videoCall: return "Video call"
            case .dropIn: return "Drop-in countdown"
            case .messages: return "Playing messages"
            }
        }
    }
    public struct Result: Equatable, Codable {
        public enum Kind: String, Codable {
            case person, unassigned, needsSetup, answer, hangUp, cancelDropIn
            case camera, playMessages, stopMessages, unmapped, ignored
        }
        public let symbol: String
        public let context: Context
        public let action: KeypadAction?
        public let kind: Kind
        public let title: String
        public let detail: String
        public let contactName: String?
        public let selectedDigit: Int?
        public let cameraOn: Bool?
    }
    public let slots: CallSlots
    public private(set) var context: Context = .clock
    public private(set) var cameraOn = true
    public init(slots: CallSlots) { self.slots = slots }
    public mutating func setContext(_ context: Context) { self.context = context; cameraOn = true }

    public mutating func receive(_ symbol: String) -> Result {
        func result(_ kind: Result.Kind, _ title: String, _ detail: String,
                    action: KeypadAction? = nil, name: String? = nil, selected: Int? = nil,
                    camera: Bool? = nil) -> Result {
            Result(symbol: symbol, context: context, action: action, kind: kind,
                   title: title, detail: detail, contactName: name, selectedDigit: selected, cameraOn: camera)
        }
        guard let digit = CallSlots.digit(forSymbol: symbol), let action = slots.action(for: digit) else {
            return result(.unmapped, "No action assigned to \(symbol)", "Only saved key assignments are previewed. No action was performed.")
        }
        if action == .callControl {
            switch context {
            case .incoming: return result(.answer, "Would answer the incoming call", "Tap behavior only. These digit reports do not provide hold/release timing for declining.", action: action)
            case .voiceCall, .videoCall: return result(.hangUp, "Would hang up", "The simulated call would end. No real call is active in this preview.", action: action)
            case .dropIn: return result(.cancelDropIn, "Would stop the drop-in", "The simulated countdown would be cancelled.", action: action)
            case .messages: return result(.stopMessages, "Would stop the message", "No message audio is played in this preview.", action: action)
            case .clock: return result(.ignored, "No call to answer or end", "This is the saved call-control key. Choose a simulated call state to test it.", action: action)
            }
        }
        if action == .toggleVideo {
            if context == .videoCall {
                cameraOn.toggle()
                return result(.camera, "Would turn the camera \(cameraOn ? "on" : "off")", "Preview state only. The iPad camera is never opened.", action: action, camera: cameraOn)
            }
            return result(.ignored, "Camera key · no video call", "This key toggles the camera during a Porch video call.", action: action)
        }
        if context == .messages, action == .messages {
            return result(.stopMessages, "Would stop the message", "No message audio is played in this preview.", action: action)
        }
        guard context == .clock else {
            return result(.ignored, "Key \(symbol) has no action in this state", action == .unassigned ? "This key is set to No action." : "The saved \(action.title.lowercased()) action is available from the clock.", action: action)
        }
        if action == .messages {
            return result(.playMessages, "Would open messages", "Message availability is not fetched or changed in this preview.", action: action)
        }
        guard let person = slots.contact(for: digit) else {
            return result(.unassigned, "No action assigned to \(symbol)", "This key is set to No action in the saved HelloPorch setup.", action: action, selected: digit)
        }
        guard let call = person.nativeCall else {
            return result(.needsSetup, "\(person.name) · finish Porch setup", "This saved person needs Porch calling setup before the normal app can call them.", action: action, name: person.name, selected: digit)
        }
        return result(.person, "Would call \(person.name)", "\(call.mode == .video ? "Video" : "Voice") call selected from the saved HelloPorch assignment. No call was placed.", action: action, name: person.name, selected: digit)
    }
}
