import Foundation

public enum DisplayNumber {
    // Decimal.FormatStyle receives Decimal directly; display formatting never
    // converts a balance through Double or truncates fractional point amounts.
    public static func decimal(_ value: Decimal) -> String { decimal(value, locale: .autoupdatingCurrent) }
    public static func decimal(_ value: Decimal, locale: Locale) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0...38)).grouping(.automatic))
    }
}
