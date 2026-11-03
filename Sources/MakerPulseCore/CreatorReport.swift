import Foundation

public enum CreatorScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case models, profiles
    public var id: String { rawValue }
    public var title: String { self == .models ? "Models" : "Print profiles" }
    public var path: String { self == .models ? "design" : "instance" }
}
public enum CreatorMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case views, impressions, followers, likes, saves, downloads, prints, boosts, points, reportedRegularPoints, reportedExclusivePoints, regularPoints, exclusivePoints, regularPointsCN, exclusivePointsCN, ratings
    public var id: String { rawValue }
    public var title: String {
        switch self { case .views: "Views"; case .impressions: "Impressions"; case .followers: "Follower activity (API)"; case .likes: "Likes"; case .saves: "Saves"; case .downloads: "Downloads"; case .prints: "Prints"; case .boosts: "Boosts"; case .points: "Reported points"; case .reportedRegularPoints: "Regular points · reported total"; case .reportedExclusivePoints: "Exclusive points · reported total"; case .regularPoints: "Regular points · global"; case .exclusivePoints: "Exclusive points · global"; case .regularPointsCN: "Regular points · China"; case .exclusivePointsCN: "Exclusive points · China"; case .ratings: "Ratings" }
    }
}
public struct CreatorPeriod: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public static var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    public init(days: Int = 30, now: Date = Date()) {
        let calendar = Self.calendar
        end = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        start = calendar.date(byAdding: .day, value: -(max(1, min(366, days)) - 1), to: end)!
    }
    public init(start: Date, end: Date) throws {
        self.start = Self.calendar.startOfDay(for: start); self.end = Self.calendar.startOfDay(for: end)
        guard self.start <= self.end, Self.calendar.dateComponents([.day], from: self.start, to: self.end).day! < 366 else { throw PulseError.malformed("Creator report date range") }
    }
    public var startText: String { Self.text(start) }
    public var endText: String { Self.text(end) }
    private static func text(_ date: Date) -> String { let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
}
public struct CreatorRow: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var modelID: String
    public var title: String
    public var modelTitle: String?
    public var cover: String?
    public var metrics: [CreatorMetric: Decimal]
}
public struct CreatorReport: Codable, Equatable, Sendable {
    public var scope: CreatorScope
    public var period: CreatorPeriod
    public var fetchedAt: Date
    public var rows: [CreatorRow]
    public var history: [CreatorDaily]?
    public var historyStatus: String?
    public var availableMetrics: [CreatorMetric] { CreatorMetric.allCases.filter { key in rows.contains { $0.metrics[key] != nil } } }
}
public struct CreatorDaily: Codable, Identifiable, Equatable, Sendable {
    public var date: Date
    public var metrics: [CreatorMetric: Decimal]
    public var id: Date { date }
}
public enum CreatorParser {
    public static func report(_ data: Data, scope: CreatorScope, period: CreatorPeriod, at date: Date = Date()) throws -> CreatorReport {
        let root = try JSONDecoder().decode(JSONNode.self, from: data)
        guard let rows = root[scope == .models ? "modelList" : "instList"].array else { throw PulseError.malformed("Creator Center \(scope.title)") }
        var seen = Set<String>()
        let parsed = try rows.map { row -> CreatorRow in
            guard let id = row[scope == .models ? "designId" : "id"].string, let modelID = row["designId"].string, let title = row["title"].string else { throw PulseError.malformed("Creator Center row identifiers") }
            var metrics: [CreatorMetric: Decimal] = [:]
            for (metric, field) in [(CreatorMetric.views,"view"),(.likes,"like"),(.saves,"collect"),(.downloads,"download"),(.prints,"print"),(.boosts,"boost"),(.points,"point"),(.ratings,"dailyRated")] { metrics[metric] = row[field].decimal }
            let regular = row[scope == .models ? "pointRegular" : "pointSyncSourceRegular"]
            let exclusive = row[scope == .models ? "pointExclusive" : "pointSyncSourceExclusive"]
            metrics[.regularPoints] = regular["default"].decimal; metrics[.regularPointsCN] = regular["cn"].decimal
            metrics[.exclusivePoints] = exclusive["default"].decimal; metrics[.exclusivePointsCN] = exclusive["cn"].decimal
            return CreatorRow(id: id, modelID: modelID, title: title, modelTitle: row["designTitle"].string, cover: row["cover"].string, metrics: metrics)
        }.filter { seen.insert($0.id).inserted }
        return CreatorReport(scope: scope, period: period, fetchedAt: date, rows: parsed)
    }
}

public enum CreatorHistoryParser {
    public static func nextData(from html: Data) throws -> Data {
        guard let text = String(data: html, encoding: .utf8), let expression = try? NSRegularExpression(pattern: "<script[^>]*id=[\"']__NEXT_DATA__[\"'][^>]*>(.*?)</script>", options: [.dotMatchesLineSeparators]),
            let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { throw PulseError.challenge }
        return Data(text[range].utf8)
    }
    public static func history(_ data: Data, period: CreatorPeriod) throws -> [CreatorDaily] {
        let root = try JSONDecoder().decode(JSONNode.self, from: data)
        let props = root["props"]["pageProps"].object != nil ? root["props"]["pageProps"] : root["pageProps"]
        guard props["__N_REDIRECT"].string == nil, let rows = props["statisticalData"]["dateList"].array else { throw PulseError.authentication }
        let formatter = DateFormatter(); formatter.calendar = CreatorPeriod.calendar; formatter.timeZone = CreatorPeriod.calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        var seen = Set<Date>()
        return try rows.compactMap { row -> CreatorDaily? in
            guard let text = row["intervalVal"].string, let date = formatter.date(from: String(text.prefix(10))) else { throw PulseError.malformed("Creator Center UTC daily dates") }
            guard date >= period.start, date <= period.end, seen.insert(date).inserted else { return nil }
            var values: [CreatorMetric: Decimal] = [:]
            for (metric, field) in [(CreatorMetric.views,"view"),(.impressions,"impression"),(.followers,"follower"),(.likes,"like"),(.saves,"collect"),(.downloads,"download"),(.prints,"print"),(.boosts,"boost"),(.points,"point"),(.reportedRegularPoints,"pointRegular"),(.reportedExclusivePoints,"pointExclusive")] { values[metric] = row[field].decimal }
            let regular = row["pointFromSyncSourceRegular"].object != nil ? row["pointFromSyncSourceRegular"] : row["pointSyncSourceRegular"]
            let exclusive = row["pointFromSyncSourceExclusive"].object != nil ? row["pointFromSyncSourceExclusive"] : row["pointSyncSourceExclusive"]
            values[.regularPoints] = regular["default"].decimal; values[.regularPointsCN] = regular["cn"].decimal
            values[.exclusivePoints] = exclusive["default"].decimal; values[.exclusivePointsCN] = exclusive["cn"].decimal
            return CreatorDaily(date: date, metrics: values)
        }.sorted { $0.date < $1.date }
    }
}
