import Foundation

/// Whether a call for this device can ring now. A device takes one call at a time, so it can't while another call is
/// up, whether a ringing or answered CallKit call (`current`) or a call of its own that CallKit doesn't know about, such
/// as one a family phone started to another of its families (`onAnotherCall`). Nor can a call this device already
/// finished, which its family can still list as ringing until it next checks in.
///
/// A check-in lists a ringing call every second or so, from every family a phone is in, so one that can't ring isn't
/// reported at all: otherwise it would ring again on every check-in. It rings once the other call is over.
public enum IncomingCallRinging {
    public static func canRing(_ callID: UUID, current: UUID?, onAnotherCall: Bool, finished: [UUID]) -> Bool {
        current == nil && !onAnotherCall && !finished.contains(callID)
    }

    /// A VoIP push has to be reported to CallKit at once, even when another call is up. CallKit then ends that report,
    /// and the same call can't be reported again later, so it counts as finished. A check-in that only saw such a call,
    /// and never reported it, is not finished: that call rings once the other one is over.
    public static func pushBlocked(_ callID: UUID, current: UUID?, onAnotherCall: Bool, finished: [UUID]) -> Bool {
        guard current != callID, current != nil || onAnotherCall else { return false }
        return !finished.contains(callID)
    }
}
