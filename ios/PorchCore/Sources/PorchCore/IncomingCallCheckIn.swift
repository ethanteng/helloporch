import Foundation

/// Which ringing calls a check-in hands to CallKit. A VoIP push is always reported, even for a call Porch can't take,
/// because iOS requires it. A check-in lists a ringing call every second or so, though, and a phone in several
/// families hears from each of them. So a check-in reports a call only while no other call is up and this device
/// hasn't already finished it: otherwise another family's call during a call, or a call hung up here before its
/// family's next check-in, would ring again on every check-in.
public enum IncomingCallCheckIn {
    public static func reports(_ callID: UUID, current: UUID?, finished: [UUID]) -> Bool {
        current == nil && !finished.contains(callID)
    }
}
