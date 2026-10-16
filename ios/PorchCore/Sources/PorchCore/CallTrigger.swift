import Foundation

/// A physical press produces at most one request, with a short cooldown shared
/// by keypad and touch input. The controller separately guards URL launches.
public struct CallTrigger {
    private var heldKeys = Set<Int>()
    private var lastLaunch: TimeInterval?
    public init() {}

    public static func supports(_ keyCode: Int) -> Bool {
        slot(for: keyCode) != nil
    }

    public static func slot(for keyCode: Int) -> Int? {
        switch keyCode {
        case 0x59...0x61: return keyCode - 0x59 + 1 // keypad 1–9
        case 0x62: return 0 // keypad 0
        case 0x1E...0x26: return keyCode - 0x1E + 1 // keyboard 1–9
        case 0x27: return 0 // keyboard 0
        default: return nil
        }
    }

    public mutating func keyDown(_ keyCode: Int) -> Bool {
        guard Self.supports(keyCode) else { return false }
        return heldKeys.insert(keyCode).inserted
    }

    public mutating func keyUp(_ keyCode: Int) { heldKeys.remove(keyCode) }
    public mutating func resetKeys() { heldKeys.removeAll() }

    public mutating func allowLaunch(at now: TimeInterval) -> Bool {
        guard lastLaunch.map({ now - $0 >= 2 }) ?? true else { return false }
        lastLaunch = now
        return true
    }
}

/// Decide on key release so a long press can decline without answering first.
public struct IncomingCallKey {
    public enum Decision: Equatable { case answer, decline }
    private var pressedKey: Int?
    public init() {}
    public mutating func begin(_ key: Int, dropIn: Bool) -> Decision? {
        guard pressedKey == nil else { return nil }
        if dropIn { return .decline }
        pressedKey = key; return nil
    }
    public mutating func held(_ key: Int) -> Decision? {
        guard pressedKey == key else { return nil }
        pressedKey = nil; return .decline
    }
    public mutating func release(_ key: Int) -> Decision? {
        guard pressedKey == key else { return nil }
        pressedKey = nil; return .answer
    }
    public mutating func cancel() { pressedKey = nil }
}
