import Foundation

public enum PollingPolicy {
    public static let presets = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 360, 720, 1440]
    public static func valid(_ minutes: Int) -> Bool { (5...1440).contains(minutes) }
    public static func delay(minutes: Int, jitterUnit: Double = Double.random(in: 0...1)) -> TimeInterval {
        let seconds = Double(max(5, min(1440, minutes))) * 60
        return seconds + min(30, seconds * 0.02) * max(0, min(1, jitterUnit))
    }
    public static func title(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return minutes == 60 ? "Every hour" : "Every \(minutes / 60) hours" }
        return "Every \(minutes) minutes"
    }
}
