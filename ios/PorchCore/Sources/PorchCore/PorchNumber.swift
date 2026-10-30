import Foundation

/// A household's own phone number, which anyone can call its Porch on.
public enum PorchNumber {
    /// "(510) 567-7039" for a US number in E.164, or the number as it came otherwise.
    public static func display(_ number: String) -> String {
        guard number.hasPrefix("+1") else { return number }
        let digits = number.dropFirst(2)
        guard digits.count == 10, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return number }
        return "(\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.suffix(4))"
    }
    /// A US area code Porch can look for numbers in: three digits, not starting with 0 or 1, and not a service code
    /// such as 411. The server checks the same.
    public static func isAreaCode(_ text: String) -> Bool {
        text.range(of: "^[2-9][0-9]{2}$", options: .regularExpression) != nil && !text.hasSuffix("11")
    }
}
