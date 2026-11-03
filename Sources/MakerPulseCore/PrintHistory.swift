import Foundation
import CoreFoundation

public enum PrintOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, succeeded, stopped, unfinished, unknown
    public var id: String { rawValue }
    public var title: String { switch self { case .all: "All prints"; case .succeeded: "Finished"; case .stopped: "Canceled / failed"; case .unfinished: "Unfinished"; case .unknown: "Unknown status" } }
}
public struct PrintJob: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var designTitle: String?
    public var cover: String?
    public var status: Int?
    public var deviceID: String?
    public var deviceName: String?
    public var plateIndex: Int?
    public var plateName: String?
    public var startTime: Date?
    public var endTime: Date?
    public var estimatedSeconds: Double?
    public var mode: String?
    public var isPublicProfile: Bool?
    public var inLatestCloudCrawl: Bool?
    public var firstObservedAt: Date?
    public var lastObservedAt: Date?
    public init(id: String, title: String? = nil, status: Int? = nil) { self.id = id; self.title = title; self.status = status }
    public var displayTitle: String { designTitle ?? title ?? "Untitled print" }
    // These codes describe cloud task records, not live printer telemetry.
    // The stop codes do not reliably identify user cancellation vs failure.
    public var outcome: PrintOutcome { switch status { case 2: .succeeded; case 3, 4: .stopped; case 0, 1: .unfinished; default: .unknown } }
    public var isTerminal: Bool { outcome == .succeeded || outcome == .stopped }
    public var elapsedSeconds: Double? {
        guard isTerminal, let startTime, let endTime, endTime >= startTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    public var plateLabel: String? { plateName ?? plateIndex.map { "Plate \($0)" } }
}
public struct PrintHistory: Codable, Equatable, Sendable {
    public var accountID: String
    public var jobs: [PrintJob] = []
    public var cloudTotal: Int?
    public var lastSync: Date?
    public var lastFullSync: Date?
    public init(accountID: String) { self.accountID = accountID }
    public mutating func merge(_ batch: PrintTaskBatch, accountID: String, at date: Date) throws {
        guard self.accountID == accountID else { throw PulseError.accountMismatch }
        var saved = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if batch.complete { for key in Array(saved.keys) { saved[key]?.inLatestCloudCrawl = false } }
        for var job in batch.jobs {
            job.inLatestCloudCrawl = true
            job.firstObservedAt = saved[job.id]?.firstObservedAt ?? date; job.lastObservedAt = date
            saved[job.id] = job
        }
        jobs = saved.values.sorted { a,b in
            if a.startTime != b.startTime { return (a.startTime ?? .distantPast) > (b.startTime ?? .distantPast) }
            return a.id < b.id
        }
        cloudTotal = batch.cloudTotal; lastSync = date
        if batch.complete { lastFullSync = date }
    }
}
public struct PrintTaskBatch: Sendable {
    public var jobs: [PrintJob]
    public var cloudTotal: Int?
    public var complete: Bool
    public init(jobs: [PrintJob], cloudTotal: Int?, complete: Bool) { self.jobs = jobs; self.cloudTotal = cloudTotal; self.complete = complete }
}
public enum PrintTaskParser {
    public static func page(_ data: Data) throws -> Page<PrintJob> {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let hits = root["hits"] as? [[String: Any]] else { throw PulseError.malformed("print history") }
        func text(_ o: [String: Any], _ key: String) -> String? { (o[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
        func number(_ o: [String: Any], _ key: String) -> Double? {
            if let n = o[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue.isFinite ? n.doubleValue : nil }
            return (o[key] as? String).flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        }
        func integer(_ o: [String: Any], _ key: String) -> Int? { number(o,key).flatMap { $0 >= Double(Int.min) && $0 < Double(Int.max) && $0.rounded() == $0 ? Int($0) : nil } }
        let total = integer(root,"total")
        if root["total"] != nil && (total == nil || total! < 0) { throw PulseError.malformed("print history total") }
        let jobs = try hits.map { o -> PrintJob in
            let id: String?
            if let n = o["id"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.rounded() == n.doubleValue, n.doubleValue > 0 { id = n.stringValue }
            else { id = text(o,"id") }
            guard let id, id.count <= 128, id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw PulseError.malformed("print task identifier") }
            var job = PrintJob(id: id, title: text(o,"title"), status: integer(o,"status"))
            job.designTitle = text(o,"designTitle"); job.cover = text(o,"cover")
            job.deviceID = text(o,"deviceId"); job.deviceName = text(o,"deviceName")
            job.plateIndex = integer(o,"plateIndex"); job.plateName = text(o,"plateName")
            job.startTime = date(text(o,"startTime")); job.endTime = date(text(o,"endTime"))
            job.estimatedSeconds = number(o,"costTime").flatMap { $0 >= 0 ? $0 : nil }
            job.mode = text(o,"mode"); job.isPublicProfile = o["isPublicProfile"] as? Bool
            return job
        }
        return Page(items: jobs, total: total)
    }
    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

public enum PrintTaskPagination {
    public static func collect(known: PrintHistory?, forceFull: Bool, limit: Int = 20, maxPages: Int = 500,
        fetch: @Sendable (Int,Int) async throws -> Page<PrintJob>) async throws -> PrintTaskBatch {
        var rows: [PrintJob] = [], seen = Set<String>(), offset = 0, expected: Int?
        let oldIDs = Set(known?.jobs.map(\.id) ?? [])
        var awaiting = Set(known?.jobs.filter { !$0.isTerminal && $0.inLatestCloudCrawl != false }.map(\.id) ?? [])
        for _ in 0..<maxPages {
            try Task.checkCancellation()
            let page = try await fetch(offset, limit)
            if let total = page.total {
                if let expected, expected != total { throw PulseError.incomplete("changing print history total") }
                expected = total
            }
            let overlap = page.items.contains { oldIDs.contains($0.id) }
            let fresh = page.items.filter { seen.insert($0.id).inserted }
            for job in page.items { awaiting.remove(job.id) }
            rows += fresh
            if let expected, seen.count > expected { throw PulseError.incomplete("print history count") }
            if page.items.isEmpty {
                if let expected, seen.count < expected { throw PulseError.incomplete("print history") }
                return PrintTaskBatch(jobs: rows, cloudTotal: expected, complete: true)
            }
            guard !fresh.isEmpty else { throw PulseError.incomplete("repeating print history page") }
            offset += page.items.count
            if let expected, seen.count >= expected { return PrintTaskBatch(jobs: rows, cloudTotal: expected, complete: true) }
            // Incremental checks revisit the newest page and every previously
            // unfinished task. A complete crawl is still performed hourly.
            if !forceFull, overlap, awaiting.isEmpty { return PrintTaskBatch(jobs: rows, cloudTotal: expected, complete: false) }
        }
        throw PulseError.incomplete("print history page limit")
    }
}

public enum PrintHistoryOrder: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest, elapsed
    public var id: String { rawValue }
    public var title: String { switch self { case .newest: "Newest first"; case .oldest: "Oldest first"; case .elapsed: "Longest elapsed" } }
}
public enum PrintHistoryRange: Int, CaseIterable, Identifiable, Sendable {
    case all = 0, week = 7, month = 30, quarter = 90
    public var id: Int { rawValue }
    public var title: String { self == .all ? "Any date" : "Last \(rawValue) days" }
}
public enum PrintHistoryQuery {
    public static func select(_ jobs: [PrintJob], search: String = "", outcome: PrintOutcome = .all, printer: String? = nil, range: PrintHistoryRange = .all, order: PrintHistoryOrder = .newest, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> [PrintJob] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = range == .all ? nil : calendar.date(byAdding: .day, value: -range.rawValue, to: now)
        return jobs.filter { job in
            (outcome == .all || job.outcome == outcome) && (printer == nil || job.deviceName == printer) &&
            (query.isEmpty || [job.title,job.designTitle,job.deviceName,job.plateName].compactMap { $0 }.contains { $0.localizedStandardContains(query) }) &&
            (start == nil || job.startTime.map { $0 >= start! && $0 <= now } == true)
        }.sorted { a,b in
            if order == .elapsed, a.elapsedSeconds != b.elapsedSeconds { return (a.elapsedSeconds ?? -1) > (b.elapsedSeconds ?? -1) }
            if a.startTime != b.startTime {
                if a.startTime == nil { return false }; if b.startTime == nil { return true }
                return order == .oldest ? a.startTime! < b.startTime! : a.startTime! > b.startTime!
            }
            return a.id < b.id
        }
    }
}
