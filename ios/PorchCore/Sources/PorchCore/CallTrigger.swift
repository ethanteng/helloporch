import Foundation

/// A physical press produces at most one request, with a short cooldown shared
/// by keypad and touch input. The controller separately guards URL launches.
public struct CallTrigger {
    private var heldKeys = Set<Int>()
    private var lastLaunch: TimeInterval?
    public init() {}

    public static func supports(_ keyCode: Int) -> Bool {
        keyCode == 0x59 || keyCode == 0x1E // keypad 1, keyboard 1
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
