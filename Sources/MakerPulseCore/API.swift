import Foundation

public struct HTTPResult: Sendable {
    public var data: Data
    public var status: Int
    public var headers: [String: String]
    public init(data: Data, status: Int, headers: [String: String] = [:]) { self.data = data; self.status = status; self.headers = headers }
}
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30; c.timeoutIntervalForResource = 60
        c.httpMaximumConnectionsPerHost = 2; c.httpShouldSetCookies = false
        c.httpCookieStorage = nil; c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: c, delegate: SameOriginRedirects(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PulseError.malformed("HTTP") }
        let headers = Dictionary(response.allHeaderFields.map { (String(describing: $0.key).lowercased(), String(describing: $0.value)) }, uniquingKeysWith: { a, _ in a })
        return HTTPResult(data: data, status: response.statusCode, headers: headers)
    }
}

public actor MakerWorldAPI: SessionBackend {
    private let transport: any HTTPTransport
    private let minimumInterval: TimeInterval
    private var nextRequest = Date.distantPast
    private var sessionToken: String?
    public private(set) var schemaDiagnostics: [String: String] = [:]
    public init(transport: any HTTPTransport = URLSessionTransport(), minimumInterval: TimeInterval = 0.4) {
        self.transport = transport; self.minimumInterval = minimumInterval
    }
    public func useSession(_ token: String?) { sessionToken = token }
    public var hasSession: Bool { sessionToken != nil }

    public func accountEvents() async throws -> [AccountEvent] {
        guard let token = sessionToken else { throw PulseError.authentication }
        // These six category values are verified in MakerWorld's own pages.
        var events: [AccountEvent] = []
        for (type, kind) in [(1, EventKind.comment), (2, .model), (3, .system), (4, .device), (5, .community), (6, .crowdfunding)] {
            let rows: [AccountEvent] = try await Pagination.collect { offset, limit in
                try AccountParser.events(await self.request(path: "/v1/user-service/my/messages", query: ["type": "\(type)", "offset": "\(offset)", "limit": "\(limit)"], token: token), group: kind)
            }
            events += rows
        }
        var seen = Set<String>()
        return events.filter { seen.insert($0.id).inserted }
    }
    public func printTasks(known: PrintHistory?, forceFull: Bool) async throws -> PrintTaskBatch {
        guard let token = sessionToken else { throw PulseError.authentication }
        return try await PrintTaskPagination.collect(known: known, forceFull: forceFull) { offset, limit in
            try await self.printTaskPage(offset: offset, limit: limit, token: token)
        }
    }
    private func printTaskPage(offset: Int, limit: Int, token: String) async throws -> Page<PrintJob> {
        let data = try await request(path: "/v1/user-service/my/tasks", query: ["offset": "\(offset)", "limit": "\(limit)"], token: token)
        schemaDiagnostics["my-prints"] = SchemaDiagnostics.describe(data)
        return try PrintTaskParser.page(data)
    }

    public func pointsBalance() async throws -> RewardBalance {
        guard let token = sessionToken else { throw PulseError.authentication }
        return try AccountParser.points(await request(path: "/v1/point-service/point-bill/progress", token: token))
    }
    public func creatorReport(scope: CreatorScope, period: CreatorPeriod) async throws -> CreatorReport {
        guard let token = sessionToken else { throw PulseError.authentication }
        let data = try await request(path: "/v1/design-user-service/my/creatortools/\(scope.path)/list", query: ["startDate": period.startText, "endDate": period.endText, "keyword": ""], token: token)
        schemaDiagnostics["creator-\(scope.rawValue)"] = SchemaDiagnostics.describe(data)
        var report = try CreatorParser.report(data, scope: scope, period: period)
        do {
            let html = try await request(path: "/en/my/data-overview/\(scope == .models ? "model" : "printProfile")", query: ["startDate": period.startText, "endDate": period.endText], token: token, website: true)
            let next = try CreatorHistoryParser.nextData(from: html)
            report.history = try CreatorHistoryParser.history(next, period: period)
            report.historyStatus = "Verified daily Creator Center data · UTC+0."
        } catch { report.historyStatus = "Daily web report unavailable: \(error.localizedDescription) The API period table is preserved." }
        return report
    }
    public func cashEstimate(into balance: RewardBalance) async throws -> RewardBalance {
        guard let token = sessionToken else { throw PulseError.authentication }
        return try AccountParser.cashProgress(await request(path: "/v1/point-service/cash-redeem/progress", token: token), into: balance)
    }
    public func walletBalance(into balance: RewardBalance) async throws -> RewardBalance {
        guard let token = sessionToken else { throw PulseError.authentication }
        return try AccountParser.wallet(await request(path: "/v1/wallet-service/summary", token: token), into: balance)
    }
    public func walletTransactions() async throws -> [WalletTransaction] {
        guard let token = sessionToken else { throw PulseError.authentication }
        return try await Pagination.collect { offset, limit in
            try await self.walletTransactionPage(offset: offset, limit: limit, token: token)
        }
    }
    private func walletTransactionPage(offset: Int, limit: Int, token: String) async throws -> Page<WalletTransaction> {
        let data = try await request(path: "/v1/wallet-service/income/details", query: ["offset": "\(offset)", "limit": "\(limit)"], token: token)
        schemaDiagnostics["wallet-ledger"] = SchemaDiagnostics.describe(data)
        return try WalletParser.transactions(data)
    }
    public func rewardTransactions(userID: String) async throws -> [RewardTransaction] {
        try validateID(userID)
        guard let token = sessionToken else { throw PulseError.authentication }
        return try await LedgerPagination.collect { offset, limit in
            try await self.transactionPage(offset: offset, limit: limit, token: token, userID: userID)
        }
    }
    private func transactionPage(offset: Int, limit: Int, token: String, userID: String) async throws -> Page<RewardTransaction> {
        let data = try await request(path: "/v1/point-service/point-bill/my", query: ["offset": "\(offset)", "limit": "\(limit)", "filter": "all"], token: token)
        schemaDiagnostics["ledger"] = SchemaDiagnostics.describe(data)
        return try AccountParser.transactions(data, accountID: userID)
    }

    public func profile(userID: String) async throws -> Profile {
        try validateID(userID)
        return try APIParser.profile(await request(path: "/v1/design-user-service/user/profile/\(userID)"))
    }
    public func models(userID: String) async throws -> [Design] {
        try validateID(userID)
        return try await Pagination.collect { offset, limit in
            try await self.modelPage(userID: userID, offset: offset, limit: limit)
        }
    }
    public func followers(userID: String) async throws -> [Follower] {
        try validateID(userID)
        return try await Pagination.collect { offset, limit in
            try await self.followerPage(userID: userID, offset: offset, limit: limit)
        }
    }
    private func modelPage(userID: String, offset: Int, limit: Int) async throws -> Page<Design> {
        try APIParser.models(await request(path: "/v1/design-service/publisheddesigns/\(userID)", query: ["offset": "\(offset)", "limit": "\(limit)", "type": "3D"]))
    }
    private func followerPage(userID: String, offset: Int, limit: Int) async throws -> Page<Follower> {
        try APIParser.followers(await request(path: "/v1/design-user-service/user/\(userID)/fans", query: ["offset": "\(offset)", "limit": "\(limit)"]))
    }

    public func validate(token: String) async throws -> Profile {
        try APIParser.profile(await request(path: "/v1/design-user-service/my/profile", token: token))
    }
    public func sendEmailCode(email: String) async throws {
        _ = try await request(path: "/v1/user-service/user/sendemail/code", body: ["email": email, "type": "codeLogin"])
    }
    public func login(email: String, code: String) async throws -> AuthResult {
        let data = try await request(path: "/v1/user-service/user/login", body: ["account": email, "code": code])
        return try APIParser.auth(data)
    }
    public func mfa(key: String, code: String) async throws -> AuthResult {
        let data = try await request(path: "/v1/user-service/user/tfa/login", body: ["tfaKey": key, "tfaCode": code])
        return try APIParser.auth(data)
    }

    private func validateID(_ id: String) throws {
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { throw PulseError.malformed("numeric user ID") }
    }

    private func request(path: String, query: [String: String] = [:], token: String? = nil, body: [String: String]? = nil, website: Bool = false) async throws -> Data {
        var components = URLComponents(string: website ? "https://makerworld.com" : "https://api.bambulab.com")!
        components.path = path; components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: components.url!)
        req.setValue("MakerGlance (macOS; local analytics)", forHTTPHeaderField: "User-Agent")
        req.setValue(website ? "text/html" : "application/json", forHTTPHeaderField: "Accept")
        if let token {
            if website { req.setValue("token=\(token)", forHTTPHeaderField: "Cookie") }
            else { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        }
        if let body { req.httpMethod = "POST"; req.httpBody = try JSONEncoder().encode(body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        var usedSavedSession = false
        for attempt in 0..<4 {
            try Task.checkCancellation()
            let slot = max(nextRequest, Date())
            nextRequest = slot.addingTimeInterval(minimumInterval)
            let pause = slot.timeIntervalSinceNow
            if pause > 0 { try await Task.sleep(for: .seconds(pause)) }
            let response: HTTPResult
            do { response = try await transport.send(req) }
            catch {
                guard body == nil, attempt < 3, !(error is CancellationError) else { throw error }
                try await Task.sleep(for: .seconds(pow(2, Double(attempt)))); continue
            }
            if response.status == 429 || (500...599).contains(response.status) {
                guard attempt < 3, body == nil else { throw PulseError.http(response.status) }
                let delay = Self.retryDelay(header: response.headers["retry-after"], attempt: attempt)
                nextRequest = max(nextRequest, Date().addingTimeInterval(delay))
                continue
            }
            if !website, (response.status == 401 || response.status == 403), body == nil, token == nil, !usedSavedSession, let sessionToken {
                req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
                usedSavedSession = true
                continue
            }
            if response.status == 401 { throw PulseError.authentication }
            if response.status == 403 { throw PulseError.challenge }
            guard (200...299).contains(response.status) else { throw PulseError.http(response.status) }
            guard !response.data.isEmpty else { throw PulseError.malformed("empty") }
            return response.data
        }
        throw PulseError.incomplete("request")
    }

    public static func retryDelay(header: String?, attempt: Int, now: Date = Date()) -> TimeInterval {
        if let header {
            if let seconds = Double(header) { return min(300, max(0, seconds)) }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header) { return min(300, max(0, date.timeIntervalSince(now))) }
        }
        return min(60, pow(2, Double(attempt)) + Double.random(in: 0...0.25))
    }
}

public struct AuthResult: Sendable {
    public var token: String?
    public var tfaKey: String?
}

public enum APIParser {
    private static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PulseError.malformed("JSON") }
        return value
    }
    private static func id(_ object: [String: Any], key: String) throws -> String {
        let value = (object[key] as? String) ?? (object[key] as? NSNumber)?.stringValue
        guard let value, !value.isEmpty else { throw PulseError.malformed("identifier") }
        return value
    }
    private static func integer(_ object: [String: Any], _ key: String) -> Int? {
        if let value = object[key] as? NSNumber { return value.intValue }
        if let value = object[key] as? String { return Int(value) }
        return nil
    }
    private static func counts(_ o: [String: Any], model: Bool = false) -> Counts {
        let makerCounts = o["MWCount"] as? [String: Any] ?? [:]
        return Counts(likes: integer(o, "likeCount"),
            downloads: model ? integer(o, "downloadCount") : integer(makerCounts, "myDesignDownloadCount"),
            prints: model ? integer(o, "printCount") : integer(makerCounts, "myDesignPrintCount"),
            apiDownloads: model ? nil : integer(o, "downloadCount"),
            boosts: integer(o, model ? "boostCnt" : "boostGained"), collections: integer(o, "collectionCount"), followers: model ? nil : integer(o, "fanCount"))
    }
    public static func profile(_ data: Data) throws -> Profile {
        let o = try object(data)
        guard let handle = o["handle"] as? String, o["fanCount"] != nil else { throw PulseError.malformed("profile") }
        return Profile(id: try id(o, key: "uid"), name: o["name"] as? String ?? handle, handle: handle, avatar: o["avatar"] as? String, counts: counts(o))
    }
    public static func models(_ data: Data) throws -> Page<Design> {
        let o = try object(data)
        guard let hits = o["hits"] as? [[String: Any]] else { throw PulseError.malformed("models") }
        let formatter = ISO8601DateFormatter()
        return Page(items: try hits.map { item in
            guard let title = item["title"] as? String else { throw PulseError.malformed("model title") }
            return Design(id: try id(item, key: "id"), title: title, cover: item["coverUrl"] as? String, counts: counts(item, model: true), publishedAt: (item["publishTime"] as? String).flatMap(formatter.date(from:)))
        }, total: integer(o, "total"))
    }
    public static func followers(_ data: Data) throws -> Page<Follower> {
        let o = try object(data)
        guard let hits = o["hits"] as? [[String: Any]] else { throw PulseError.malformed("followers") }
        return Page(items: try hits.map { item in
            let name = item["name"] as? String ?? "Maker"
            return Follower(id: try id(item, key: "uid"), name: name, handle: item["handle"] as? String ?? name, avatar: item["avatar"] as? String)
        }, total: integer(o, "total"))
    }
    public static func auth(_ data: Data) throws -> AuthResult {
        let o = try object(data)
        let token = o["accessToken"] as? String
        let key = o["tfaKey"] as? String
        guard token != nil || key != nil else { throw PulseError.authentication }
        return AuthResult(token: token, tfaKey: key)
    }
}
