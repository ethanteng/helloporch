import Foundation

/// Which iPads can use a desk phone through the Cell2Jack. iPadOS runs USB drivers only on iPads with an M chip, so
/// iPads known to have an A-series chip can't. Anything else, including iPads newer than this list, gets a try.
public enum Cell2JackModels {
    /// iPads from 2020 on with an A-series chip, by model identifier: iPad Air (4th generation), iPad (10th generation),
    /// iPad mini (6th generation), iPad (A16) and iPad mini (A17 Pro). Every earlier iPad has a lower first number.
    static let aSeries: Set<String> = ["iPad13,1", "iPad13,2", "iPad13,18", "iPad13,19", "iPad14,1", "iPad14,2",
                                       "iPad15,7", "iPad15,8", "iPad16,1", "iPad16,2"]
    /// False for an iPad known to have an A-series chip, from its model identifier (`hw.machine`, such as "iPad14,8").
    public static func mayWork(model: String) -> Bool {
        guard model.hasPrefix("iPad"), let major = Int(model.dropFirst(4).prefix { $0.isASCII && $0.isNumber }) else { return true }
        return major >= 13 && !aSeries.contains(model)
    }
}
