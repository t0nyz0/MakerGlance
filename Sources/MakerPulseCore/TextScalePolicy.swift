import Foundation

public enum TextScalePolicy {
    public static let defaultPercent = 100
    public static let range = 85...150
    public static func normalized(_ value: Int?) -> Int { min(range.upperBound, max(range.lowerBound, value ?? defaultPercent)) }
    public static func factor(_ value: Int?) -> Double { Double(normalized(value)) / 100 }
    public static func pointSize(_ base: Double, factor: Double) -> Double { max(11, base * min(1.5, max(0.85, factor))) }
}
