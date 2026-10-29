import Foundation

/// The app badge on a phone in several families: unplayed messages from all of them. A message notification's badge
/// already counted every family, so the badge waits until each one has checked in, or failed to. Otherwise the first
/// family to check in would lower it to its own count.
public enum MessageBadge {
    /// `unplayed` has one count per family, nil for one that hasn't checked in yet. Nil while any is still waiting.
    public static func count(_ unplayed: [Int?]) -> Int? {
        guard !unplayed.isEmpty, !unplayed.contains(where: { $0 == nil }) else { return nil }
        return unplayed.reduce(0) { $0 + ($1 ?? 0) }
    }
}
