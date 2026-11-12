import Foundation

/// Which iPads have no M chip. A Cell2Jack plugged straight into an iPad needs the driver, and iPadOS runs drivers only on
/// an M chip; every other iPad takes the phone through the Porch phone adapter. iPadOS can't be asked for the chip, so
/// Porch goes by the model identifier, such as "iPad13,16".
public enum IPadChip {
    /// The iPads from iPad13 on that have an A chip: the M1 iPads were the first iPad13 models after the iPad Air
    /// (4th generation), and the standard iPad and the iPad mini have kept A chips since.
    private static let aChip: Set<String> = [
        "iPad13,1", "iPad13,2",   // iPad Air (4th generation), A14
        "iPad13,18", "iPad13,19", // iPad (10th generation), A14
        "iPad14,1", "iPad14,2",   // iPad mini (6th generation), A15
        "iPad15,7", "iPad15,8",   // iPad (A16)
        "iPad16,1", "iPad16,2",   // iPad mini (A17 Pro)
    ]

    /// True only for an iPad known to have no M chip. A model this doesn't know, such as one newer than the list, or an
    /// identifier that isn't an iPad's, could have one, so it isn't counted out: it gets the driver too, as every iPad
    /// did before Porch looked.
    public static func lacksMChip(model: String) -> Bool {
        guard model.hasPrefix("iPad"), let comma = model.firstIndex(of: ","),
              let major = Int(model[model.index(model.startIndex, offsetBy: 4)..<comma]),
              Int(model[model.index(after: comma)...]) != nil else { return false }
        // Every iPad before iPad13 has an A chip.
        return major < 13 || aChip.contains(model)
    }
}
