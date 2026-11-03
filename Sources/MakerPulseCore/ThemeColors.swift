import Foundation

public struct ThemeRGB: Equatable, Sendable {
    public var red: Double, green: Double, blue: Double
    public init(_ hex: UInt32) { red = Double((hex >> 16) & 255) / 255; green = Double((hex >> 8) & 255) / 255; blue = Double(hex & 255) / 255 }
    public var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrast(with other: Self) -> Double { (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05) }
}
public enum ThemeColors {
    public static let freshPill = ThemeRGB(0x1D456C)
    public static let printPill = ThemeRGB(0x4B328A)
    public static let lightSurface = ThemeRGB(0xFFFFFF), darkSurface = ThemeRGB(0x28292D)
    public static let lightCanvas = ThemeRGB(0xF5F5F2), darkCanvas = ThemeRGB(0x1B1C1F)
    public static let lightAccent = ThemeRGB(0x805D0A), darkAccent = ThemeRGB(0xE6C64D)
    public static let lightControlFill = ThemeRGB(0x805D0A), darkControlFill = ThemeRGB(0x957100)
    public static let lightSecondary = ThemeRGB(0x525560), darkSecondary = ThemeRGB(0xC6C7CA)
    public static let lightSidebar = ThemeRGB(0xECECE7), darkSidebar = ThemeRGB(0x202124)
    public static let lightPositive = ThemeRGB(0x08714F), darkPositive = ThemeRGB(0x58D69C)
    public static let lightNegative = ThemeRGB(0xB3253F), darkNegative = ThemeRGB(0xFF8397)
    public static let lightOrange = ThemeRGB(0x9D5011), darkOrange = ThemeRGB(0xEFB05F)
    public static let lightLikes = ThemeRGB(0xB12B63), darkLikes = ThemeRGB(0xFF94BC)
    public static let lightPrints = ThemeRGB(0x6347B5), darkPrints = ThemeRGB(0xB5A4FF)
    public static let lightCollections = ThemeRGB(0x8740A1), darkCollections = ThemeRGB(0xD1A2EE)
    public static let lightFollowers = ThemeRGB(0x1A6283), darkFollowers = ThemeRGB(0x7ACCEB)
    public static var lightTextColors: [ThemeRGB] { [lightAccent, lightSecondary, lightPositive, lightNegative, lightOrange, lightLikes, lightPrints, lightCollections, lightFollowers] }
    public static var darkTextColors: [ThemeRGB] { [darkAccent, darkSecondary, darkPositive, darkNegative, darkOrange, darkLikes, darkPrints, darkCollections, darkFollowers] }
}
