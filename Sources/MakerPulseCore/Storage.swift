import Foundation
import CSQLite

private final class Connection: @unchecked Sendable {
    let db: OpaquePointer
    init(url: URL) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw PulseError.database("Could not open the database")
        }
        db = pointer
        sqlite3_busy_timeout(db, 5000)
    }
    deinit { sqlite3_close(db) }
}

public actor Storage {
    private let connection: Connection
    private var db: OpaquePointer { connection.db }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        connection = try Connection(url: url)
        var message: UnsafeMutablePointer<CChar>?
        let schema = "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS samples (entity TEXT NOT NULL, time REAL NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(entity,time)); CREATE INDEX IF NOT EXISTS samples_time ON samples(time); CREATE TABLE IF NOT EXISTS balance_samples (time REAL PRIMARY KEY, payload BLOB NOT NULL);"
        guard sqlite3_exec(connection.db, schema, nil, nil, &message) == SQLITE_OK else {
            let error = message.map { String(cString: $0) } ?? "schema"; sqlite3_free(message); throw PulseError.database(error)
        }
        guard sqlite3_exec(connection.db, "CREATE TABLE IF NOT EXISTS daily_baselines (entity TEXT NOT NULL, metric TEXT NOT NULL, day_start REAL NOT NULL, zone TEXT NOT NULL, sample_time REAL NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(entity,metric,day_start,zone))", nil, nil, nil) == SQLITE_OK else { throw PulseError.database("Could not create daily baselines") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path + suffix)
        }
    }
    public func load() throws -> LibraryState {
        let statement = try prepare("SELECT payload FROM state WHERE id=1")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return LibraryState() }
        var state = try decoder.decode(LibraryState.self, from: blob(statement, column: 0))
        if state.schema == 1 { try migrateDesignCounts(&state) }
        guard state.schema == 2 else { throw PulseError.database("This library was created by a newer MakerGlance version") }
        return state
    }

    private func migrateDesignCounts(_ state: inout LibraryState) throws {
        // v1 used the separate top-level API downloadCount. Preserve that raw
        // observation, but never chart it as MakerWorld's design-download total.
        if let count = state.profile?.counts.downloads {
            state.profile?.counts.apiDownloads = count; state.profile?.counts.downloads = nil
        }
        state.highWater = state.highWater.filter { !($0.key.hasPrefix("profile:") && $0.key.hasSuffix(":downloads")) }
        state.schema = 2
        let select = try prepare("SELECT time,payload FROM samples WHERE entity='profile'")
        var rows: [(Double, Counts)] = []
        while sqlite3_step(select) == SQLITE_ROW {
            var counts = try decoder.decode(Counts.self, from: blob(select, column: 1))
            counts.apiDownloads = counts.downloads; counts.downloads = nil
            rows.append((sqlite3_column_double(select, 0), counts))
        }
        sqlite3_finalize(select)
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM daily_baselines WHERE entity='profile' AND metric='downloads'")
            for (time, counts) in rows {
                let update = try prepare("UPDATE samples SET payload=? WHERE entity='profile' AND time=?")
                defer { sqlite3_finalize(update) }
                try bind(try encoder.encode(counts), to: update, index: 1); sqlite3_bind_double(update, 2, time)
                guard sqlite3_step(update) == SQLITE_DONE else { throw error() }
            }
            let update = try prepare("UPDATE state SET payload=? WHERE id=1")
            defer { sqlite3_finalize(update) }
            try bind(try encoder.encode(state), to: update, index: 1)
            guard sqlite3_step(update) == SQLITE_DONE else { throw error() }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    public func commit(_ state: LibraryState, samples: [String: Sample] = [:], balance: BalanceSample? = nil) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let statement = try prepare("INSERT OR REPLACE INTO state(id,payload) VALUES(1,?)")
            defer { sqlite3_finalize(statement) }
            try bind(try encoder.encode(state), to: statement, index: 1)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
            for (entity, sample) in samples {
                let s = try prepare("INSERT OR REPLACE INTO samples(entity,time,payload) VALUES(?,?,?)")
                defer { sqlite3_finalize(s) }
                sqlite3_bind_text(s, 1, entity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_double(s, 2, sample.date.timeIntervalSince1970)
                try bind(try encoder.encode(sample.counts), to: s, index: 3)
                guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
                let calendar = Calendar.autoupdatingCurrent
                if let day = calendar.dateInterval(of: .day, for: sample.date) {
                    for metric in Metric.allCases where sample.counts[metric] != nil {
                        try persistDailyBaseline(entity: entity, metric: metric, day: day, zone: calendar.timeZone.identifier, sample: sample)
                    }
                }
            }
            if let balance {
                let s = try prepare("INSERT OR REPLACE INTO balance_samples(time,payload) VALUES(?,?)")
                defer { sqlite3_finalize(s) }
                sqlite3_bind_double(s, 1, balance.date.timeIntervalSince1970)
                try bind(try encoder.encode(balance.balance), to: s, index: 2)
                guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
            }
            // Keep one year at full sampling fidelity. At the default 15-minute
            // interval a 41-model account uses roughly 1.5M small indexed rows/year.
            let cutoff = Date().addingTimeInterval(-366 * 86400).timeIntervalSince1970
            try execute("DELETE FROM samples WHERE time < \(cutoff)")
            try execute("DELETE FROM balance_samples WHERE time < \(cutoff)")
            try execute("DELETE FROM daily_baselines WHERE day_start < \(cutoff)")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func persistDailyBaseline(entity: String, metric: Metric, day: DateInterval, zone: String, sample: Sample) throws {
        let s = try prepare("INSERT INTO daily_baselines(entity,metric,day_start,zone,sample_time,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(entity,metric,day_start,zone) DO UPDATE SET sample_time=excluded.sample_time,payload=excluded.payload WHERE excluded.sample_time<daily_baselines.sample_time")
        defer { sqlite3_finalize(s) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(s, 1, entity, -1, transient); sqlite3_bind_text(s, 2, metric.rawValue, -1, transient)
        sqlite3_bind_double(s, 3, day.start.timeIntervalSince1970); sqlite3_bind_text(s, 4, zone, -1, transient)
        sqlite3_bind_double(s, 5, sample.date.timeIntervalSince1970); try bind(try encoder.encode(sample.counts), to: s, index: 6)
        guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
    }
    public func dailyBaseline(entity: String, metric: Metric, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) throws -> Sample? {
        let day = calendar.dateInterval(of: .day, for: now)!
        // Query the first actual observation containing this metric. This also
        // reconstructs a baseline after timezone changes or metric migrations.
        let s = try prepare("SELECT time,payload FROM samples WHERE entity=? AND time>=? AND time<? AND json_type(CAST(payload AS TEXT),?) IN ('integer','real') ORDER BY time ASC LIMIT 1")
        defer { sqlite3_finalize(s) }; let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(s, 1, entity, -1, transient); sqlite3_bind_double(s, 2, day.start.timeIntervalSince1970); sqlite3_bind_double(s, 3, day.end.timeIntervalSince1970)
        sqlite3_bind_text(s, 4, "$.\(metric.rawValue)", -1, transient)
        let result = sqlite3_step(s)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw error() }
        let sample = Sample(date: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)), counts: try decoder.decode(Counts.self, from: blob(s, column: 1)))
        try persistDailyBaseline(entity: entity, metric: metric, day: day, zone: calendar.timeZone.identifier, sample: sample)
        return sample
    }

    public func balanceHistory(limit: Int = 1000) throws -> [BalanceSample] {
        let s = try prepare("SELECT time,payload FROM balance_samples ORDER BY time DESC LIMIT ?")
        defer { sqlite3_finalize(s) }; sqlite3_bind_int(s, 1, Int32(clamping: limit))
        var output: [BalanceSample] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw error() }
            output.append(BalanceSample(date: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)), balance: try decoder.decode(RewardBalance.self, from: blob(s, column: 1))))
        }
        return output.reversed()
    }

    public func latestMetricObservations(entity: String, before: Date = Date()) throws -> [Metric: MetricObservation] {
        var output: [Metric: MetricObservation] = [:]
        for metric in ModelActivity.metrics {
            let s = try prepare("SELECT time,payload FROM samples WHERE entity=? AND time<=? AND json_type(CAST(payload AS TEXT),?) IN ('integer','real') ORDER BY time DESC LIMIT 1")
            defer { sqlite3_finalize(s) }; let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(s, 1, entity, -1, transient); sqlite3_bind_double(s, 2, before.timeIntervalSince1970)
            sqlite3_bind_text(s, 3, "$.\(metric.rawValue)", -1, transient)
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { continue }
            guard result == SQLITE_ROW else { throw error() }
            let counts = try decoder.decode(Counts.self, from: blob(s, column: 1))
            if let value = counts[metric] { output[metric] = MetricObservation(value: value, date: Date(timeIntervalSince1970: sqlite3_column_double(s, 0))) }
        }
        return output
    }

    // Activity ordering needs actual transition times, never chart buckets.
    // One preceding snapshot permits observing a change at the range boundary;
    // range deltas still start with the first observation inside the window.
    public func activityHistory(entity: String, since: Date) throws -> [Sample] {
        let s = try prepare("SELECT time,payload FROM samples WHERE entity=? AND (time>=? OR time=(SELECT MAX(time) FROM samples WHERE entity=? AND time<?)) ORDER BY time ASC")
        defer { sqlite3_finalize(s) }; let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(s, 1, entity, -1, transient); sqlite3_bind_double(s, 2, since.timeIntervalSince1970)
        sqlite3_bind_text(s, 3, entity, -1, transient); sqlite3_bind_double(s, 4, since.timeIntervalSince1970)
        var output: [Sample] = []
        while true {
            let result = sqlite3_step(s)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw error() }
            output.append(Sample(date: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)), counts: try decoder.decode(Counts.self, from: blob(s, column: 1))))
        }
        return output
    }

    public func history(entity: String, since: Date = .distantPast, limit: Int = 500) throws -> [Sample] {
        // Bucket the full requested interval instead of truncating old history.
        // SQLite's MAX(time) selects the payload from the latest row in each bin.
        let bounds = try prepare("SELECT MIN(time),MAX(time) FROM samples WHERE entity=? AND time>=?")
        defer { sqlite3_finalize(bounds) }
        sqlite3_bind_text(bounds, 1, entity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(bounds, 2, since.timeIntervalSince1970)
        guard sqlite3_step(bounds) == SQLITE_ROW else { throw error() }
        let interval = max(1, sqlite3_column_double(bounds, 1) - sqlite3_column_double(bounds, 0))
        let bucket = max(1, interval / Double(max(1, limit)))
        let s = try prepare("SELECT MAX(time),payload FROM samples WHERE entity=? AND time>=? GROUP BY CAST(time / \(bucket) AS INTEGER) ORDER BY MAX(time) ASC")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_text(s, 1, entity, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(s, 2, since.timeIntervalSince1970)
        var samples: [Sample] = []
        while true {
            let status = sqlite3_step(s)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw error() }
            samples.append(Sample(date: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)), counts: try decoder.decode(Counts.self, from: blob(s, column: 1))))
        }
        return samples
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw error() }
        return s
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    private func bind(_ data: Data, to statement: OpaquePointer, index: Int32) throws {
        let result = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard result == SQLITE_OK else { throw error() }
    }
    private func blob(_ s: OpaquePointer, column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(s, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, column)))
    }
    private func error() -> PulseError { .database(String(cString: sqlite3_errmsg(db))) }
}
