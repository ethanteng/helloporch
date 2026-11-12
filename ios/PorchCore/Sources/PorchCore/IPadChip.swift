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
        "iPad19,1", "iPad19,2",   // iPad mini (A20 Pro)
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

    /// The iPads known to have an M chip, each a pair of Wi-Fi and cellular models, checked against Xcode's simulators.
    private static let mChip: [(major: Int, minors: ClosedRange<Int>)] = [
        (13, 4...11),  // iPad Pro 11-inch (3rd generation) and 12.9-inch (5th generation), M1
        (13, 16...17), // iPad Air (5th generation), M1
        (14, 3...6),   // iPad Pro 11-inch (4th generation) and 12.9-inch (6th generation), M2
        (14, 8...11),  // iPad Air 11-inch and 13-inch, M2
        (15, 3...6),   // iPad Air 11-inch and 13-inch, M3
        (16, 3...6),   // iPad Pro 11-inch and 13-inch, M4
        (16, 8...11),  // iPad Air 11-inch and 13-inch, M4
        (17, 1...4),   // iPad Pro 11-inch and 13-inch, M5
    ]

    /// True only for an iPad known to have an M chip, so Porch can say it doesn't need the Porch phone adapter. A model
    /// this doesn't know could be a standard iPad, which does, so it isn't counted in.
    public static func hasMChip(model: String) -> Bool {
        guard model.hasPrefix("iPad"), let comma = model.firstIndex(of: ","),
              let major = Int(model[model.index(model.startIndex, offsetBy: 4)..<comma]),
              let minor = Int(model[model.index(after: comma)...]) else { return false }
        return mChip.contains { $0.major == major && $0.minors.contains(minor) }
    }
}
