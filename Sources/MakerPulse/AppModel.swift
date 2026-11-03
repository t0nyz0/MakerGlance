import AppKit
import Foundation
import MakerPulseCore
import UserNotifications
import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Dashboard", models = "Models", myPrints = "My Prints", creator = "Analytics", followers = "Followers", activity = "Activity", rewards = "Rewards", settings = "Settings"
    var id: String { rawValue }
    static var sidebar: [Self] { [.overview, .models, .myPrints, .creator, .settings] }
    var sidebarParent: Self { switch self { case .activity, .rewards: .overview; case .followers: .creator; default: self } }
    var symbol: String {
        switch self { case .overview: "square.grid.2x2"; case .models: "cube.transparent"; case .myPrints: "printer"; case .creator: "chart.bar.xaxis"; case .followers: "person.2"; case .activity: "waveform.path"; case .rewards: "sparkles"; case .settings: "slider.horizontal.3" }
    }
}
enum AnalyticsSection: String, CaseIterable, Identifiable {
    case local = "Local trends", creator = "Creator Center", community = "Followers"
    var id: String { rawValue }
}

@MainActor final class AppModel: ObservableObject {
    @Published var state = LibraryState()
    @Published var histories: [String: [Sample]] = [:]
    @Published var modelActivityReports: [ModelActivityWindow: [ObservedModelActivity]] = [:]
    @Published var latestModelIncreases: [String: [Metric: LatestMetricIncrease]] = [:]
    private var modelCheckRecency = ModelCheckRecency()
    @Published var dashboardActivityWindow: ModelActivityWindow = .today
    @Published var dashboardShowsAllModels = false
    var dashboardModelSelection: WatchedModelSelection {
        WatchedModelSelection(ranked: WatchedModelSorting.ordered(modelActivityReports[dashboardActivityWindow] ?? [], by: state.preferences.dashboardSort, basis: state.preferences.dashboardSortBasis), watches: state.watches, expanded: dashboardShowsAllModels)
    }
    private var modelActivitySamples: [String: [Sample]] = [:]
    private var modelActivityTask: Task<Void, Never>?
    @Published var destination: Destination = .overview
    @Published var analyticsSection: AnalyticsSection = .local
    @Published var analyticsMetric: Metric = .likes
    @Published var syncing = false
    @Published var loaded = false
    @Published var status = "Opening your local library…"
    @Published var issues: [String] = []
    @Published var connection = "Public API"
    @Published var selectedModel: Design?
    @Published var auditWatchFilter: ModelWatchFilter?
    @Published var nextRefreshDate: Date?
    @Published var privateIssues: [String] = []
    var openWindowAction: (() -> Void)?
    @Published var notificationStatus = "Not enabled"
    @Published var auditScheme: ColorScheme? { didSet { applyAppearance() } }
    @Published var auditAppearance: AppearanceChoice? { didSet { applyAppearance() } }
    @Published var accountSessionAvailable = false
    @Published var restoringSession = true
    @Published var profileLive = false
    @Published var printSearch = ""
    @Published var printOutcome = PrintOutcome.all
    @Published var printPrinter = ""
    @Published var printRange = PrintHistoryRange.all
    @Published var printOrder = PrintHistoryOrder.newest
    var visiblePrintJobs: [PrintJob] { PrintHistoryQuery.select(myPrints?.jobs ?? [], search: printSearch, outcome: printOutcome, printer: printPrinter.isEmpty ? nil : printPrinter, range: printRange, order: printOrder) }
    @Published var printsLoading = false
    @Published var printsStatus = "Connect your existing Bambu session to load private cloud print history."
    private var livePrintHistory = false
    var myPrints: PrintHistory? { state.printHistory?.accountID == state.preferences.userID ? state.printHistory : nil }
    @Published var privateSyncing = false
    @Published var inboxStatus = "Connect a Bambu session in Settings to load the private inbox."
    @Published var rewardsStatus = "Connect a Bambu session in Settings to load private balances."
    @Published var walletStatus = "Wallet data has not been verified."
    @Published var balanceHistory: [BalanceSample] = []
    @Published var dailyBaselines: [String: [Metric: Sample]] = [:]
    @Published var authenticationStatus = "Public data works without signing in."
    @Published var creatorLoading = false
    @Published var creatorStatus = "Choose a UTC period to load the private Creator Center report."
    private var auditInProgress = false
    private var liveInbox = false, liveRewards = false, livePointsLedger = false, liveWalletLedger = false, liveCreator = false, liveCreatorDaily = false, liveCreatorProfiles = false, liveCreatorProfilesDaily = false
    var api = MakerWorldAPI()
    let databaseURL: URL
    var isolatedQA: Bool { CommandLine.arguments.contains("--qa-library") }
    var isDemo: Bool { CommandLine.arguments.contains("--demo") }
    private var storage: Storage?
    private var verificationWindow: NSWindow?
    private var pollingTask: Task<Void, Never>?
    private var calendarObservers: [NSObjectProtocol] = []
    private var wakeObserver: NSObjectProtocol?
    private var scheduledRefreshQueued = false
    var unread: Int { state.activity.filter { !$0.isRead }.count }
    var watching: Int { ModelWatchFilter.watched.count(state.models, watches: state.watches) }
    var isRefreshing: Bool { syncing || privateSyncing || printsLoading }
    var menuStatus: MenuStatus { MenuStatus(unread: unread, refreshing: isRefreshing || restoringSession, attention: !issues.isEmpty || !privateIssues.isEmpty) }
    func showMain(_ section: Destination = .overview, modelID: String? = nil) {
        destination = section
        selectedModel = modelID.flatMap { id in state.models.first { $0.id == id } }
        if let window = NSApp.windows.first(where: { $0.title == AppIdentity.displayName && $0.contentView != nil && !($0 is NSPanel) }) ?? verificationWindow { window.makeKeyAndOrderFront(nil) }
        else { openWindowAction?() }
        NSApp.activate(ignoringOtherApps: true)
    }
    var activeFollowers: [Follower] { state.followers.filter(\.isFollowing) }
    var appearance: AppearanceChoice { state.preferences.appearance }
    var effectiveColorScheme: ColorScheme? {
        let choice = auditAppearance ?? appearance
        return auditScheme ?? (choice == .system ? nil : choice == .light ? .light : .dark)
    }
    func setAppearance(_ choice: AppearanceChoice) { state.preferences.appearanceChoice = choice; applyAppearance(); save() }
    func setTextSize(_ percent: Int) { state.preferences.textScalePercent = TextScalePolicy.normalized(percent); save() }
    func setDashboardSort(_ sort: WatchedModelSort) { state.preferences.watchedModelSort = sort; save() }
    func setDashboardSortBasis(_ basis: WatchedSortBasis) { state.preferences.watchedSortBasis = basis; save() }
    func setWatchedLayout(_ layout: WatchedModelLayout) { state.preferences.watchedModelLayout = layout; save() }
    private func applyAppearance() {
        NSApp.appearance = effectiveColorScheme.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua)! }
    }
    func openAnalytics(_ metric: Metric? = nil) {
        if metric == .followers { analyticsSection = .community }
        else { analyticsSection = .local; analyticsMetric = metric ?? .likes }
        destination = .creator
    }

    init() {
        if CommandLine.arguments.contains("--demo") {
            databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("MakerGlance-Demo-\(UUID().uuidString)").appendingPathComponent("analytics.sqlite")
        } else if let flag = CommandLine.arguments.firstIndex(of: "--qa-library"), CommandLine.arguments.indices.contains(flag + 1) {
            databaseURL = URL(fileURLWithPath: CommandLine.arguments[flag + 1]).appendingPathComponent("analytics.sqlite")
        } else {
            databaseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true).appendingPathComponent("analytics.sqlite")
        }
        Task { await start() }
        for name in [Notification.Name.NSCalendarDayChanged, NSNotification.Name.NSSystemTimeZoneDidChange] {
            calendarObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.loadDailyBaselines(); self?.rebuildModelActivity() }
            })
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self, self.nextRefreshDate.map({ $0 <= Date() }) ?? true { self.performScheduledRefresh() } }
        }
    }
    func start() async {
        if let flag = CommandLine.arguments.firstIndex(of: "--print-history-probe"), CommandLine.arguments.indices.contains(flag + 1) {
            await PrintHistoryProbe.run(output: URL(fileURLWithPath: CommandLine.arguments[flag+1]), library: databaseURL)
            NSApp.terminate(nil); return
        }
        do {
            let store = try Storage(url: databaseURL); storage = store
            if isDemo {
                try await DemoScene.install(in: self, store: store)
                if let flag = CommandLine.arguments.firstIndex(of: "--demo-capture"), CommandLine.arguments.indices.contains(flag + 1) {
                    try await DemoScene.capture(in: self, directory: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
                    NSApp.terminate(nil)
                }
                return
            }
            if isolatedQA, CommandLine.arguments.contains("--qa-demo-fixture") {
                try await DemoScene.seedVerificationLibrary(store)
            }
            let saved = try await store.load()
            let rewardsHistory = try await store.balanceHistory()
            state = await Task.detached(priority: .userInitiated) {
                var repaired = saved; RewardLedger.repair(&repaired, history: rewardsHistory); return repaired
            }.value
            if !(state.account?.preferences.eventNotifications.contains(.device) ?? false) {
                state.activity.removeAll { $0.presentation?.kind == .device || $0.title == "Printer update" }
            }
            if state.account != nil { try await store.commit(state) }
            balanceHistory = rewardsHistory; loaded = true
            if CommandLine.arguments.contains("--open-settings") { destination = .settings }
            if state.preferences.pollingSelectionVersion == nil {
                if state.preferences.pollingMinutes == 15 { state.preferences.pollingMinutes = 10 }
                state.preferences.pollingSelectionVersion = 1
                try await store.commit(state)
            }
            applyAppearance()
            await loadHistory()
            var previousChecks: [String: [Metric: MetricObservation]] = [:]
            for design in state.models { previousChecks[design.id] = try await store.latestMetricObservations(entity: "model:\(design.id)") }
            modelCheckRecency = ModelCheckRecency(baselines: previousChecks)
            await refreshNotificationStatus()
            if isolatedQA {
                api = MakerWorldAPI(transport: UIReplayTransport(state: state), minimumInterval: 0)
                restoringSession = false; connection = "Isolated UI verification"
                authenticationStatus = "Isolated UI verification. No session is loaded."
                inboxStatus = "Local verification fixtures. No credentials loaded."
                rewardsStatus = "Local verification fixtures. No credentials loaded."
                status = "Showing local observations for UI verification"
                if let flag=CommandLine.arguments.firstIndex(of:"--dashboard-pointer-audit"),CommandLine.arguments.indices.contains(flag+1) {
                    let output=URL(fileURLWithPath:CommandLine.arguments[flag+1])
                    do {try await DashboardPointerAudit.run(model:self,directory:output)}
                    catch {try? FileManager.default.createDirectory(at:output,withIntermediateDirectories:true);try? Data(error.localizedDescription.utf8).write(to:output.appendingPathComponent("error.txt"))}
                } else if let directory = auditDirectory { await captureAudit(directory: directory) }
                NSApp.terminate(nil); return
            }
            if state.preferences.userID.isEmpty {
                restoringSession = false; connection = "Choose a profile"; destination = .settings
                status = "Set up your creator profile in Settings"
                authenticationStatus = "Connect your own account below, or enter its public numeric user ID."
                return
            }
            status = "Opening saved analytics · checking Keychain access…"
            connection = "Checking saved Keychain session…"
            inboxStatus = "Checking Keychain access. Saved inbox history remains available."
            rewardsStatus = "Checking Keychain access. Balances show the last verified observation."
            authenticationStatus = "Waiting for macOS Keychain access to your saved session…"
            creatorStatus = "Waiting for Keychain access to the saved session."
            await writeConnectionDiagnostics()
            let publicRefresh = Task { await refresh(forceFollowers: false, forceLedgers: auditDirectory != nil) }
            schedulePolling()
            if let directory = auditDirectory {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, !self.accountSessionAvailable else { return }
                    // Render saved/public UI even if macOS is waiting for user
                    // Keychain consent. The report distinguishes cached data
                    // from private feeds actually verified in this process.
                    await self.captureAudit(directory: directory)
                }
            }
            do {
                if let token = try await Task.detached(priority: .userInitiated, operation: { try SessionKeychain.read() }).value {
                    await api.useSession(token); connection = "Keychain session available"; accountSessionAvailable = true
                    authenticationStatus = "Your saved session is available. Private feeds refresh in the background."
                }
            } catch { connection = "Public API · Keychain unavailable"; privateIssues.append("Saved session unavailable: \(error.localizedDescription)") }
            restoringSession = false
            if !accountSessionAvailable { if privateIssues.isEmpty { connection = "Public API" }; authenticationStatus = privateIssues.first ?? "No saved session is available. Connect below to refresh private data." }
            await publicRefresh.value
            if accountSessionAvailable, !syncing, !liveInbox {
                let events = await refreshPrivate(forceLedgers: auditDirectory != nil)
                await notify(events)
            }
            if let flag = CommandLine.arguments.firstIndex(of: "--ui-audit"), CommandLine.arguments.indices.contains(flag + 1) {
                if accountSessionAvailable { await loadCreator(scope: .models, period: CreatorPeriod()) }
                await captureAudit(directory: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
            }
        } catch {
            loaded = true; restoringSession = false; issues = [error.localizedDescription]; status = "Local storage needs attention"
            if isDemo, CommandLine.arguments.contains("--demo-capture") {
                let output = FileManager.default.temporaryDirectory.appendingPathComponent("MakerGlance-Demo-CaptureFailure.txt")
                try? Data((error.localizedDescription + "\nOwned windows: " + NSApp.windows.map(\.title).joined(separator: ", ")).utf8).write(to: output)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
                if let flag = CommandLine.arguments.firstIndex(of: "--demo-capture"), CommandLine.arguments.indices.contains(flag + 1) {
                    let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent("CAPTURE-ERROR.txt"))
                }
                NSApp.terminate(nil)
            }
        }
    }

    func refresh(forceFollowers: Bool = true, forceLedgers: Bool = false) async {
        ImageRefresh.shared.retry()
        if isDemo { status = "Offline demo · fictional observations"; return }
        guard !syncing, !privateSyncing, !printsLoading, !state.preferences.userID.isEmpty, let storage else { return }
        syncing = true; issues = []; defer { syncing = false }
        let userID = state.preferences.userID
        var freshEvents: [Activity] = []
        var successful = 0
        status = "Updating profile…"
        do {
            let profile = try await api.profile(userID: userID)
            var next = state; let date = Date()
            let events = Analytics.ingestProfile(profile, into: &next, at: date)
            try await storage.commit(next, samples: ["profile": Sample(date: date, counts: profile.counts)])
            acceptObservation(next); freshEvents += events; successful += 1
            profileLive = !isolatedQA
        } catch { issues.append("Profile: \(error.localizedDescription)") }
        status = "Updating model library…"
        do {
            let models = try await api.models(userID: userID)
            var next = state; let date = Date()
            let events = Analytics.ingestModels(models, into: &next, at: date)
            let samples = Dictionary(models.map { ("model:\($0.id)", Sample(date: date, counts: $0.counts)) }, uniquingKeysWith: { a, _ in a })
            try await storage.commit(next, samples: samples)
            for design in models { modelActivitySamples[design.id, default: []].append(Sample(date: date, counts: design.counts)) }
            acceptObservation(next); freshEvents += events; successful += 1
            modelCheckRecency.recordSuccessful(models, at: date)
            latestModelIncreases = modelCheckRecency.increases
        } catch { issues.append("Models: \(error.localizedDescription)") }
        let followersDue = forceFollowers || state.lastFollowerSync.map { Date().timeIntervalSince($0) >= 3600 } ?? true
        if followersDue {
            status = "Checking all follower pages…"
            do {
                let followers = try await api.followers(userID: userID)
                var next = state
                let events = Analytics.ingestFollowers(followers, into: &next, at: Date())
                try await storage.commit(next)
                acceptObservation(next); freshEvents += events; successful += 1
            } catch { issues.append("Followers: \(error.localizedDescription)") }
        }
        freshEvents += await refreshPrivate(forceLedgers: forceLedgers)
        await loadHistory()
        await notify(freshEvents)
        status = issues.isEmpty ? "Up to date · saved on this Mac" : successful > 0 ? "Partially updated · saved history preserved" : "Offline · showing saved history"
        schedulePolling()
        await writeConnectionDiagnostics()
    }

    private func loadHistory() async {
        guard let storage else { return }
        do {
            var output: [String: [Sample]] = [:]
            output["profile"] = try await storage.history(entity: "profile", limit: 2000)
            for model in state.models { output["model:\(model.id)"] = try await storage.history(entity: "model:\(model.id)", limit: 2000) }
            histories = output
            var activity: [String: [Sample]] = [:]
            for design in state.models {
                activity[design.id] = try await storage.activityHistory(entity: "model:\(design.id)", since: Date().addingTimeInterval(-7 * 86400))
            }
            modelActivitySamples = activity
            rebuildModelActivity()
            balanceHistory = try await storage.balanceHistory()
            await loadDailyBaselines()
        } catch { issues.append(error.localizedDescription) }
    }
    private func loadDailyBaselines() async {
        guard let storage else { return }
        do {
            var output: [String: [Metric: Sample]] = [:]
            for entity in ["profile"] + state.models.map({ "model:\($0.id)" }) {
                var values: [Metric: Sample] = [:]
                for metric in Metric.allCases { values[metric] = try await storage.dailyBaseline(entity: entity, metric: metric) }
                output[entity] = values
            }
            dailyBaselines = output
        } catch { issues.append(error.localizedDescription) }
    }
    func dayGrowth(for design: Design, metric: Metric) -> DayGrowth {
        DayGrowth.evaluate(metric: metric, baseline: dailyBaselines["model:\(design.id)"]?[metric], current: design.counts)
    }
    func profileDayGrowth(_ metric: Metric) -> DayGrowth {
        DayGrowth.evaluate(metric: metric, baseline: dailyBaselines["profile"]?[metric], current: state.profile?.counts ?? Counts())
    }
    @discardableResult func refreshPrivate(forceLedgers: Bool = false) async -> [Activity] {
        guard !privateSyncing, let storage, await api.hasSession else { return [] }
        privateSyncing = true; defer { privateSyncing = false }
        privateIssues = []
        var alerts: [Activity] = []
        inboxStatus = "Loading account activity…"
        do {
            let events = try await api.accountEvents()
            var next = state
            let fresh = AccountAnalytics.ingestEvents(events, into: &next, at: Date())
            try await storage.commit(next); acceptObservation(next); alerts += fresh
            liveInbox = true
            inboxStatus = "Private inbox synced. Read status is local to MakerGlance."
        } catch { inboxStatus = error.localizedDescription; privateIssues.append("Inbox: \(error.localizedDescription)") }
        rewardsStatus = "Loading points and cash estimate…"
        do {
            var balance = try await api.pointsBalance()
            let balanceObservedAt = Date()
            var warnings: [String] = []
            do { balance = try await api.cashEstimate(into: balance) }
            catch { warnings.append("Cash estimate unavailable: \(error.localizedDescription)") }
            do { balance = try await api.walletBalance(into: balance); walletStatus = "Wallet remaining-to-transfer and pending-income fields verified." }
            catch { walletStatus = "Wallet unavailable: \(error.localizedDescription)"; privateIssues.append(walletStatus) }
            var transactions: [RewardTransaction]?
            let account = state.account
            let pointsChanged = [RewardMetric.regularPoints, .exclusivePoints].contains { balance[$0] != nil && balance[$0] != account?.balance?.balance[$0] }
            let pendingRetry = (account?.rewardChanges?.contains { !$0.notificationIssued && $0.matchedIDs.isEmpty } ?? false) && (account?.lastTransactionSync.map { Date().timeIntervalSince($0) >= 300 } ?? true)
            let pointsDue = pendingRetry || account?.ledgerReasonVersion != RewardLedger.version || pointsChanged || account?.transactionsImported != true || (account?.lastTransactionSync.map { Date().timeIntervalSince($0) >= 3600 } ?? true) || (account?.transactions.contains { $0.localIdentity == true && $0.id.split(separator: ":").count == 3 } ?? false)
            if pointsDue || forceLedgers {
                do { transactions = try await api.rewardTransactions(userID: state.preferences.userID); livePointsLedger = true }
                catch { warnings.append("Points ledger unavailable: \(error.localizedDescription)") }
            }
            var walletTransactions: [WalletTransaction]?
            let walletChanged = [RewardMetric.cashAvailable, .cashPending, .cashIncome].contains { balance[$0] != nil && balance[$0] != account?.balance?.balance[$0] }
            let walletDue = walletChanged || (account?.lastWalletSync.map { Date().timeIntervalSince($0) >= 3600 } ?? true)
            if walletDue || forceLedgers {
                do { walletTransactions = try await api.walletTransactions(); liveWalletLedger = true; walletStatus += " Income ledger verified." }
                catch { walletStatus += " Income ledger unavailable: \(error.localizedDescription)"; privateIssues.append("Wallet income ledger: \(error.localizedDescription)") }
            }
            let snapshot = state, observedBalance = balance, ledger = transactions, walletLedger = walletTransactions
            let date = balanceObservedAt, ledgerTime = Date()
            let result = await Task.detached(priority: .utility) {
                var next = snapshot
                let fresh = AccountAnalytics.ingestRewards(observedBalance, transactions: ledger, walletTransactions: walletLedger, into: &next, at: date, ledgerObservedAt: ledgerTime)
                return (next, fresh)
            }.value
            try await storage.commit(result.0, balance: BalanceSample(date: date, balance: balance))
            acceptObservation(result.0); alerts += result.1
            liveRewards = true
            balanceHistory = try await storage.balanceHistory()
            rewardsStatus = warnings.isEmpty ? "Balances refreshed. Ledger reasons are matched to observed changes; pending point matches retry before the hourly check." : warnings.joined(separator: "\n")
            privateIssues += warnings
        } catch { rewardsStatus = error.localizedDescription; privateIssues.append("Rewards: \(error.localizedDescription)") }
        await refreshPrintHistory(forceFull: forceLedgers, withinPrivateRefresh: true)
        await writeConnectionDiagnostics()
        return alerts
    }
    func refreshPrintHistory(forceFull: Bool = false, withinPrivateRefresh: Bool = false) async {
        guard !printsLoading, let storage, accountSessionAvailable, !isDemo else { return }
        if !withinPrivateRefresh && (syncing || privateSyncing) { return }
        printsLoading = true; printsStatus = "Reading cloud print history…"; defer { printsLoading = false }
        do {
            let known = myPrints
            let full = forceFull || known?.lastFullSync.map { Date().timeIntervalSince($0) >= 3600 } ?? true
            let batch = try await api.printTasks(known: known, forceFull: full)
            var next = state; var history = next.printHistory ?? PrintHistory(accountID: state.preferences.userID)
            try history.merge(batch, accountID: state.preferences.userID, at: Date()); next.printHistory = history
            try await storage.commit(next); acceptObservation(next); livePrintHistory = true
            printsStatus = "Last checked " + (history.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "just now") + (batch.complete ? " · complete cloud crawl saved." : " · recent and unfinished jobs checked. Full history refreshes hourly.")
        } catch { printsStatus = "Print history could not refresh: " + error.localizedDescription + " Saved jobs are preserved."; privateIssues.append("My Prints: " + error.localizedDescription) }
        await writeConnectionDiagnostics()
    }
    func setEventNotification(_ kind: EventKind, enabled: Bool) {
        var account = state.account ?? AccountState()
        if enabled { account.preferences.eventNotifications.insert(kind) } else { account.preferences.eventNotifications.remove(kind) }
        state.account = account
        if !enabled {
            let ids = state.activity.filter { $0.presentation?.kind == kind }.map(\.id)
            state.dismissedActivityIDs = (state.dismissedActivityIDs ?? []).union(ids)
            state.activity.removeAll { ids.contains($0.id) }
        }
        save()
    }
    func setBalanceNotification(_ metric: RewardMetric, enabled: Bool) {
        var account = state.account ?? AccountState()
        if enabled { account.preferences.balanceNotifications.insert(metric) } else { account.preferences.balanceNotifications.remove(metric) }
        state.account = account; save()
    }
    func delta(for model: Design, metric: Metric = .likes) -> Int? {
        let samples = histories["model:\(model.id)"] ?? []
        guard samples.count >= 2 else { return nil }
        return Analytics.delta(metric, samples: samples, current: model.counts, since: Date().addingTimeInterval(-86400))
    }
    private func rebuildModelActivity() {
        modelActivityTask?.cancel()
        let now = Date(), designs = state.models, samples = modelActivitySamples, events = state.activity
        modelActivityTask = Task { [weak self] in
            let reports = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: ModelActivityWindow.allCases.map { window in
                    (window, ModelActivity.ranked(designs: designs, samples: samples, events: events, window: window, now: now))
                })
            }.value
            guard !Task.isCancelled else { return }
            self?.modelActivityReports = reports
        }
    }
    func save() {
        guard let storage else { return }
        Task {
            let snapshot = state
            do { try await storage.commit(snapshot) }
            catch { issues.append(error.localizedDescription) }
        }
    }
    func auditStoredWatches() async throws -> [String: WatchRule] {
        guard isolatedQA, let storage else { throw PulseError.incomplete("isolated watch persistence verification") }
        return try await storage.load().watches
    }
    func auditStoredTextSize() async throws -> Int {
        guard isolatedQA, let storage else { throw PulseError.incomplete("isolated text size verification") }
        return try await storage.load().preferences.textSizePercent
    }
    func auditStoredDashboardSort() async throws -> Preferences {
        guard isolatedQA, let storage else { throw PulseError.incomplete("isolated dashboard sort verification") }
        return try await storage.load().preferences
    }
    func auditStoredWatchedLayout() async throws -> WatchedModelLayout {
        guard isolatedQA, let storage else { throw PulseError.incomplete("isolated layout persistence verification") }
        return try await storage.load().preferences.watchedLayout
    }
    func setPollingMinutes(_ minutes: Int) {
        guard PollingPolicy.valid(minutes) else { return }
        state.preferences.pollingMinutes = minutes; state.preferences.pollingSelectionVersion = 1
        save(); schedulePolling()
    }
    private func schedulePolling(after delay: TimeInterval? = nil) {
        pollingTask?.cancel()
        let seconds = delay ?? PollingPolicy.delay(minutes: state.preferences.pollingMinutes)
        nextRefreshDate = Date().addingTimeInterval(seconds)
        guard !isolatedQA else { return }
        pollingTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.performScheduledRefresh()
        }
    }
    private func performScheduledRefresh() {
        guard !scheduledRefreshQueued else { return }
        if isRefreshing { schedulePolling(after: 30); return }
        pollingTask?.cancel(); pollingTask = nil; nextRefreshDate = nil; scheduledRefreshQueued = true
        // The timer owns only its sleep. Changing an interval cannot cancel an
        // in-flight network import or start an overlapping refresh.
        Task { [weak self] in
            guard let self else { return }
            await self.refresh(forceFollowers: false)
            self.scheduledRefreshQueued = false
        }
    }
    func setAllWatches(enabled: Bool) {
        for design in state.models { var rule = state.watches[design.id] ?? WatchRule(); rule.enabled = enabled; state.watches[design.id] = rule }
        save()
    }
    private func acceptObservation(_ observation: LibraryState) {
        var next = observation
        var editedWhileSaving = LocalControls.preserve(from: state, in: &next)
        if let current = state.creatorReport, current.fetchedAt > (next.creatorReport?.fetchedAt ?? .distantPast) { next.creatorReport = current; editedWhileSaving = true }
        state = next
        rebuildModelActivity()
        if editedWhileSaving { save() }
    }
    func loadCreator(scope: CreatorScope, period: CreatorPeriod) async {
        guard !creatorLoading, let storage else { return }
        creatorLoading = true; creatorStatus = "Loading \(scope.title.lowercased()) for \(period.startText) through \(period.endText) UTC…"
        defer { creatorLoading = false }
        do {
            let report = try await api.creatorReport(scope: scope, period: period)
            var next = state; next.creatorReport = report
            try await storage.commit(next); acceptObservation(next)
            liveCreator = true; liveCreatorDaily = !(report.history?.isEmpty ?? true)
            creatorStatus = "Verified read-only report · \(report.rows.count) rows returned by MakerWorld."
        } catch { creatorStatus = error.localizedDescription + " Your last saved report is preserved." }
        await writeConnectionDiagnostics()
    }
    func updateWatch(_ id: String, _ change: (inout WatchRule) -> Void) {
        var rule = state.watches[id] ?? WatchRule(); change(&rule); state.watches[id] = rule; save()
    }
    func clearActivity(_ id: String? = nil) {
        let ids = Set(state.activity.filter { id == nil || $0.id == id }.map(\.id))
        state.dismissedActivityIDs = (state.dismissedActivityIDs ?? []).union(ids)
        state.activity.removeAll { ids.contains($0.id) }
        save()
        // Notifications are coalesced, so discard delivered summaries as well.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    func markAllRead() {
        for i in state.activity.indices { state.activity[i].isRead = true }; save()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    func enableNotifications() async {
        guard !isDemo else { return }
        do {
            state.preferences.notificationsEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            save(); await refreshNotificationStatus()
        } catch { issues.append("Notifications: \(error.localizedDescription)") }
    }
    func refreshNotificationStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = switch s.authorizationStatus { case .authorized, .provisional: "Allowed"; case .denied: "Disabled in System Settings"; default: "Not enabled" }
    }
    private func notify(_ events: [Activity]) async {
        let events = events.filter { event in
            guard !(state.dismissedActivityIDs ?? []).contains(event.id) else { return false }
            if let kind = event.presentation?.kind,
               !(state.account?.preferences.eventNotifications.contains(kind) ?? AccountPreferences().eventNotifications.contains(kind)) { return false }
            if event.id.hasPrefix("balance:") { return true }
            guard let id = event.modelID, let rule = state.watches[id] else { return true }
            if let metric = event.presentation?.metric { return rule.enabled && rule.allows(metric) }
            if event.presentation?.kind == .boost { return rule.enabled && rule.boosts }
            return true
        }
        guard !isolatedQA, !isDemo, state.preferences.notificationsEnabled, !events.isEmpty else { return }
        // Coalesce a busy polling cycle into one notification; every event remains
        // inspectable in Activity. Initial import produces no events.
        let content = UNMutableNotificationContent()
        content.title = events.count == 1 ? events[0].title : "\(events.count) MakerWorld updates"
        content.body = events.count == 1 ? events[0].detail : events.prefix(3).map { "\($0.title): \($0.detail)" }.joined(separator: "\n")
        content.sound = .default
        let id = events.map(\.id).sorted().joined(separator: "|")
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
        catch { issues.append("Update saved, notification delivery failed: \(error.localizedDescription)") }
    }
    func connect(token raw: String) async throws {
        guard !isDemo else { throw PulseError.incomplete("demo has no account connection") }
        do {
            let isFirstSetup = state.preferences.userID.isEmpty
            guard !isFirstSetup || (state.profile == nil && state.models.isEmpty && state.followers.isEmpty && state.account == nil && state.activity.isEmpty) else { throw PulseError.accountMismatch }
            let profile = try await SessionConnection.connect(raw: raw, expectedUserID: state.preferences.userID, backend: api, storage: KeychainSessionStorage()) { [weak self] stage in
                await MainActor.run { self?.authenticationStatus = stage.message }
            }
            if isFirstSetup {
                try ProfileSetup.adopt(profile, into: &state)
                try await storage?.commit(state)
                destination = .overview
            }
            connection = "Connected securely"; accountSessionAvailable = true
            await writeConnectionDiagnostics()
            if !syncing { Task { if isFirstSetup { await refresh() } else { let events = await refreshPrivate(); await notify(events) } } }
        } catch { authenticationStatus = error.localizedDescription; await writeConnectionDiagnostics(); throw error }
    }
    func configurePublicProfile(id raw: String) async throws {
        guard !isDemo else { throw PulseError.incomplete("demo has no account connection") }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProfileSetup.validID(id), state.preferences.userID.isEmpty else { throw PulseError.malformed("numeric user ID") }
        let profile = try await api.profile(userID: id)
        try ProfileSetup.adopt(profile, into: &state)
        try await storage?.commit(state)
        connection = "Public API"; destination = .overview
        Task { await refresh() }
    }
    private func writeConnectionDiagnostics() async {
        let report: [String: Any] = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Dev",
            "rewardReasonParserVerified": state.account?.transactions.allSatisfy { $0.parserVersion == RewardLedger.version } == true,
            "rewardReasonVersion": state.account?.ledgerReasonVersion ?? 0, "sessionAvailable": accountSessionAvailable, "connection": connection, "authenticationStatus": authenticationStatus,
            "inboxStatus": inboxStatus, "rewardsStatus": rewardsStatus, "walletStatus": walletStatus, "schemas": await api.schemaDiagnostics,
            "inboxVerified": state.account?.lastEventSync != nil, "rewardsVerified": state.account?.balance != nil, "ledgerVerified": state.account?.transactionsImported == true,
            "creatorStatus": creatorStatus, "creatorVerified": state.creatorReport != nil, "creatorDailyVerified": !(state.creatorReport?.history?.isEmpty ?? true), "walletLedgerVerified": state.account?.lastWalletSync != nil,
            "myPrintsVerifiedThisRun": livePrintHistory, "myPrintsSaved": myPrints?.jobs.count ?? 0, "privateFeedsVerifiedThisRun": ["inbox": liveInbox, "rewards": liveRewards, "pointsLedger": livePointsLedger, "walletLedger": liveWalletLedger, "creator": liveCreator, "creatorDaily": liveCreatorDaily, "creatorProfiles": liveCreatorProfiles, "creatorProfilesDaily": liveCreatorProfilesDaily]]
        let path = databaseURL.deletingLastPathComponent().appendingPathComponent("connection-status.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: path, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        }
    }
    func disconnect() {
        do { try SessionKeychain.delete(); Task { await api.useSession(nil) }; connection = "Public API"; accountSessionAvailable = false; inboxStatus = "Connect in Settings to refresh the private inbox."; rewardsStatus = "Connect in Settings to refresh private balances." }
        catch { issues.append(error.localizedDescription) }
    }

    // Explicit developer verification mode captures this app's own rendered
    // window; it never inspects other apps or changes real watch preferences.
    private func prepareVerificationWindow() {
        guard isolatedQA else { return }
        if let existing = NSApp.windows.first(where: { $0.title == AppIdentity.displayName && $0.contentView != nil && !($0 is NSPanel) }) {
            verificationWindow = existing
        } else {
            // A fresh accessory-only QA bundle has no restored WindowGroup.
            // Host the same production root explicitly, without live data.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = AppIdentity.displayName
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: RootView().environmentObject(self).appFont(.body)
                .environment(\.appTextScale, state.preferences.textScaleFactor).tint(Palette.controlFill))
            verificationWindow = window
        }
        AppDelegate.current?.reopenHandler = { [weak self] in self?.showMain() }
        verificationWindow?.center()
        verificationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func captureAudit(directory: URL) async {
        while auditInProgress { try? await Task.sleep(for: .milliseconds(100)) }
        auditInProgress = true; defer { auditInProgress = false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if isolatedQA { prepareVerificationWindow() }
            let nativeControls = isolatedQA ? try await NativeControlAudit.run(directory: directory) : [:]
            guard let window = NSApp.windows.first(where: { $0.title == AppIdentity.displayName }), let view = window.contentView else {
                throw PulseError.incomplete("native window verification")
            }
            var renderSizes: [String: [String: Double]] = [:]
            func snapshot(_ name: String) throws {
                view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw PulseError.incomplete("window capture") }
                view.cacheDisplay(in: view.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
                renderSizes[name] = ["width": view.bounds.width, "height": view.bounds.height]
            }
            func firstScroll(in node: NSView) -> NSScrollView? {
                if let scroll = node as? NSScrollView { return scroll }
                for child in node.subviews { if let scroll = firstScroll(in: child) { return scroll } }
                return nil
            }
            func watchControl(in node: NSView) -> NSSegmentedControl? {
                if let control = node as? NSSegmentedControl, control.identifier?.rawValue == "model-watch-filter" { return control }
                for child in node.subviews { if let found = watchControl(in: child) { return found } }
                return nil
            }
            func scroll(_ y: CGFloat) {
                guard let scroll = firstScroll(in: view), let document = scroll.documentView else { return }
                let limit = max(0, document.bounds.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(y, limit)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            func preview<V: View>(_ content: V, name: String, size: NSSize) throws {
                let host = NSHostingView(rootView: content.appFont(.body).environment(\.appTextScale, state.preferences.textScaleFactor))
                host.frame = NSRect(origin: .zero, size: size); host.appearance = NSApp.appearance
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw PulseError.incomplete("preview capture") }
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
            }
            func previewRewardRows<V: View>(_ content: V, name: String) async throws {
                let host = NSHostingView(rootView: content.appFont(.body).environment(\.appTextScale, state.preferences.textScaleFactor))
                host.frame = NSRect(x: 0, y: 0, width: 950, height: 1450); host.appearance = NSApp.appearance
                host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(650))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw PulseError.incomplete("reward row preview") }
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
            }
            window.setContentSize(NSSize(width: 1280, height: 860)); window.makeKeyAndOrderFront(nil)
            let configurations: [(String, Destination, ColorScheme, AnalyticsSection)] = [
                ("overview-light", .overview, .light, .local), ("models-light", .models, .light, .local),
                ("history-light", .creator, .light, .local), ("creator-light", .creator, .light, .creator),
                ("followers-light", .creator, .light, .community), ("settings-light", .settings, .light, .local),
                ("activity-light", .activity, .light, .local), ("rewards-light", .rewards, .light, .local),
                ("overview-dark", .overview, .dark, .local), ("models-dark", .models, .dark, .local), ("history-dark", .creator, .dark, .local),
                ("creator-dark", .creator, .dark, .creator), ("followers-dark", .creator, .dark, .community),
                ("settings-dark", .settings, .dark, .local), ("activity-dark", .activity, .dark, .local), ("rewards-dark", .rewards, .dark, .local)]
            for (name, section, scheme, analytics) in configurations {
                destination = section; analyticsSection = analytics; auditScheme = scheme
                try await Task.sleep(for: .milliseconds(900)); scroll(0)
                try snapshot(name)
                if section == .overview {
                    scroll(550); try await Task.sleep(for: .milliseconds(400)); try snapshot("dashboard-models-\(scheme == .dark ? "dark" : "light")")
                    if isolatedQA, let item = modelActivityReports[.today]?.first(where: { entry in entry.changedMetrics.contains { (entry.deltas[$0] ?? 0) > 0 } }),
                       let metric = item.changedMetrics.first(where: { (item.deltas[$0] ?? 0) > 0 }) {
                        let saved = latestModelIncreases
                        latestModelIncreases[item.id, default: [:]][metric] = LatestMetricIncrease(delta: 1, checkedAt: Date(), previousCheckAt: Date().addingTimeInterval(-600))
                        try await Task.sleep(for: .milliseconds(120)); try snapshot("dashboard-fresh-pill-fixture-\(scheme == .dark ? "dark" : "light")")
                        latestModelIncreases = saved
                    }
                    scroll(1100); try await Task.sleep(for: .milliseconds(400)); try snapshot("dashboard-more-models-\(scheme == .dark ? "dark" : "light")")
                    scroll(1900); try await Task.sleep(for: .milliseconds(400)); try snapshot("dashboard-inbox-\(scheme == .dark ? "dark" : "light")")
                    scroll(0)
                    try preview(MenuSummary().environmentObject(self).preferredColorScheme(scheme).tint(Palette.controlFill), name: "menu-\(scheme == .dark ? "dark" : "light")", size: NSSize(width: 420, height: 590))
                    try preview(GrowthStatesAuditView().preferredColorScheme(scheme), name: "growth-states-\(scheme == .dark ? "dark" : "light")", size: NSSize(width: 750, height: 350))
                    try preview(FreshPillAuditView().environmentObject(self).preferredColorScheme(scheme), name: "fresh-pills-\(scheme == .dark ? "dark" : "light")", size: NSSize(width: 750, height: 470))
                }
                if name == "creator-light" { scroll(430); try await Task.sleep(for: .milliseconds(300)); try snapshot("creator-history-light"); scroll(0) }
            }
            var mainFilterClicks = false
            var dashboardWindowClicks = false
            var watchedLayoutControls: [String: Bool] = [:]
            if isolatedQA {
                destination = .overview; auditScheme = .dark
                try await Task.sleep(for: .milliseconds(350)); scroll(550)
                func activityControl(_ node: NSView) -> NSSegmentedControl? {
                    if let control = node as? NSSegmentedControl, control.segmentCount == 3, control.label(forSegment: 0) == "Today" { return control }
                    for child in node.subviews { if let found = activityControl(child) { return found } }
                    return nil
                }
                guard let control = activityControl(view), let action = control.action else { throw PulseError.incomplete("dashboard activity window control") }
                for (index, interval) in ModelActivityWindow.allCases.enumerated() {
                    control.selectedSegment = index
                    guard control.sendAction(action, to: control.target) else { throw PulseError.incomplete("dashboard window click") }
                    try await Task.sleep(for: .milliseconds(180))
                    guard dashboardActivityWindow == interval else { throw PulseError.incomplete("dashboard window binding") }
                    try snapshot("dashboard-window-\(interval.rawValue)")
                }
                dashboardActivityWindow = .today; dashboardWindowClicks = true
                let savedLayout = state.preferences.watchedModelLayout
                let originalRows = WatchedModelSelection(ranked: modelActivityReports[.today] ?? [], watches: state.watches, expanded: dashboardShowsAllModels).visible
                func layoutControl(_ node: NSView) -> NSSegmentedControl? {
                    if let control = node as? NSSegmentedControl, control.identifier?.rawValue == "watched-model-layout" { return control }
                    return node.subviews.compactMap(layoutControl).first
                }
                guard let layout = layoutControl(view), let layoutAction = layout.action else { throw PulseError.incomplete("watched model layout control") }
                for (index, style) in WatchedModelLayout.allCases.enumerated() {
                    layout.selectedSegment = index
                    guard layout.sendAction(layoutAction, to: layout.target) else { throw PulseError.incomplete("watched layout click") }
                    try await Task.sleep(for: .milliseconds(300))
                    guard state.preferences.watchedLayout == style, try await auditStoredWatchedLayout() == style else { throw PulseError.incomplete("watched layout persistence") }
                    guard WatchedModelSelection(ranked: modelActivityReports[.today] ?? [], watches: state.watches, expanded: dashboardShowsAllModels).visible == originalRows else { throw PulseError.incomplete("shared watched model data") }
                    for scheme in [ColorScheme.dark, .light] {
                        auditScheme = scheme; scroll(480); try await Task.sleep(for: .milliseconds(200))
                        try snapshot("watched-\(style.rawValue)-\(scheme == .dark ? "dark" : "light")")
                    }
                }
                watchedLayoutControls = ["nativeCardsClick": true, "nativeCompactClick": true, "choicePersists": true, "sameOrderedObservations": true]
                for size in [NSSize(width: 950, height: 760), NSSize(width: 1600, height: 960)] {
                    window.setContentSize(size)
                    for scheme in [ColorScheme.dark, .light] {
                        auditScheme = scheme; scroll(480); try await Task.sleep(for: .milliseconds(250))
                        try snapshot("watched-compact-\(Int(size.width))-\(scheme == .dark ? "dark" : "light")")
                    }
                }
                state.preferences.watchedModelLayout = savedLayout; save()
                window.setContentSize(NSSize(width: 1280, height: 860))
                destination = .models; auditScheme = .light; auditWatchFilter = .all
                try await Task.sleep(for: .milliseconds(400))
                guard let control = watchControl(in: view), let action = control.action else { throw PulseError.incomplete("main model watch filter") }
                for filter in [ModelWatchFilter.paused, .watched, .all] {
                    control.selectedSegment = ModelWatchFilter.allCases.firstIndex(of: filter)!
                    guard control.sendAction(action, to: control.target) else { throw PulseError.incomplete("main filter click") }
                    try await Task.sleep(for: .milliseconds(200))
                    guard auditWatchFilter == filter else { throw PulseError.incomplete("main filter binding") }
                    try snapshot("models-filter-\(filter.rawValue)")
                }
                mainFilterClicks = true; auditWatchFilter = nil
            }
            if accountSessionAvailable, let original = state.creatorReport {
                await loadCreator(scope: .profiles, period: original.period)
                liveCreatorProfiles = state.creatorReport?.scope == .profiles
                liveCreatorProfilesDaily = liveCreatorProfiles && !(state.creatorReport?.history?.isEmpty ?? true)
                destination = .creator; analyticsSection = .creator; auditScheme = .light
                try await Task.sleep(for: .milliseconds(800)); scroll(0); try snapshot("creator-profiles")
                state.creatorReport = original; save()
            }
            window.setContentSize(NSSize(width: 950, height: 660))
            for scheme in [ColorScheme.light, .dark] {
                destination = .overview; auditScheme = scheme
                try await Task.sleep(for: .milliseconds(600)); scroll(0); try snapshot("dashboard-compact-\(scheme == .dark ? "dark" : "light")")
                scroll(460); try await Task.sleep(for: .milliseconds(200)); try snapshot("dashboard-models-compact-\(scheme == .dark ? "dark" : "light")")
                for section in [Destination.models, .creator, .settings] {
                    destination = section; analyticsSection = .local
                    try await Task.sleep(for: .milliseconds(350)); scroll(0); try snapshot("\(section.rawValue.lowercased())-compact-\(scheme == .dark ? "dark" : "light")")
                }
            }
            destination = .creator; analyticsSection = .community; auditScheme = .light
            try await Task.sleep(for: .milliseconds(500)); try snapshot("followers-compact")
            window.setContentSize(NSSize(width: 1600, height: 960))
            for scheme in [ColorScheme.dark, .light] {
                for section in [Destination.overview, .models, .creator, .settings] {
                    destination = section; analyticsSection = .local; auditScheme = scheme
                    try await Task.sleep(for: .milliseconds(450)); scroll(0); try snapshot("\(section.rawValue.lowercased())-wide-\(scheme == .dark ? "dark" : "light")")
                    if section == .overview { scroll(400); try await Task.sleep(for: .milliseconds(200)); try snapshot("models-wide-dashboard-\(scheme == .dark ? "dark" : "light")") }
                }
            }
            var textSizeAudit: [String: Bool] = [:]
            if isolatedQA {
                let savedTextSize = state.preferences.textScalePercent
                destination = .settings; window.setContentSize(NSSize(width: 950, height: 760))
                try await Task.sleep(for: .milliseconds(450)); scroll(0)
                func sliderIn(_ node: NSView) -> NSSlider? { if let slider = node as? NSSlider { return slider }; return node.subviews.compactMap(sliderIn).first }
                guard let slider = sliderIn(view), let action = slider.action else { throw PulseError.incomplete("native text-size slider") }
                slider.doubleValue = slider.maxValue
                guard slider.sendAction(action, to: slider.target) else { throw PulseError.incomplete("text size slider action") }
                try await Task.sleep(for: .milliseconds(250))
                guard state.preferences.textSizePercent == 150, try await auditStoredTextSize() == 150 else { throw PulseError.incomplete("text size persistence") }
                for scheme in [ColorScheme.dark, .light] {
                    auditScheme = scheme
                    for section in [Destination.overview, .models, .creator, .activity, .rewards, .settings] {
                        destination = section; analyticsSection = .local
                        try await Task.sleep(for: .milliseconds(450)); scroll(0); try snapshot("text150-\(section.rawValue.lowercased())-\(scheme == .dark ? "dark" : "light")")
                        if section == .overview { scroll(920); try await Task.sleep(for: .milliseconds(250)); try snapshot("text150-model-cards-\(scheme == .dark ? "dark" : "light")") }
                        if section == .overview {
                            let savedLayout = state.preferences.watchedModelLayout
                            setWatchedLayout(.compact); scroll(1100); try await Task.sleep(for: .milliseconds(250)); try snapshot("text150-watched-compact-\(scheme == .dark ? "dark" : "light")")
                            state.preferences.watchedModelLayout = savedLayout; save()
                        }
                    }
                    destination = .creator; analyticsSection = .community
                    try await Task.sleep(for: .milliseconds(400)); try snapshot("text150-followers-\(scheme == .dark ? "dark" : "light")")
                    analyticsSection = .creator
                    try await Task.sleep(for: .milliseconds(400)); scroll(0); try snapshot("text150-creator-report-\(scheme == .dark ? "dark" : "light")")
                    try preview(MenuSummary().environmentObject(self).preferredColorScheme(scheme).tint(Palette.controlFill), name: "text150-menu-\(scheme == .dark ? "dark" : "light")", size: NSSize(width: 630, height: 720))
                }
                if let first = state.models.first {
                    selectedModel = first; try await Task.sleep(for: .milliseconds(450))
                    if let sheetView = window.attachedSheet?.contentView, let rep = sheetView.bitmapImageRepForCachingDisplay(in: sheetView.bounds) {
                        sheetView.cacheDisplay(in: sheetView.bounds, to: rep); try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("text150-model-details.png"))
                    }
                    selectedModel = nil
                }
                destination = .settings; try await Task.sleep(for: .milliseconds(250)); scroll(0)
                func resetButton(_ node: NSView) -> NSButton? { if let button = node as? NSButton, button.title == "Reset to 100%" { return button }; return node.subviews.compactMap(resetButton).first }
                if let reset = resetButton(view) { reset.performClick(nil) } else { setTextSize(100) }
                try await Task.sleep(for: .milliseconds(250))
                guard state.preferences.textSizePercent == 100, try await auditStoredTextSize() == 100 else { throw PulseError.incomplete("text size reset") }
                textSizeAudit = ["nativeSliderChangesTo150": true, "saved150Restores": true, "reset100Persists": true]
                state.preferences.textScalePercent = savedTextSize; save()
            }
            if isolatedQA {
                let savedScale = state.preferences.textScalePercent
                let rows = ["design_reward_v2", "boost_exchange_point", "instance_reward_v2"].compactMap { type in state.account?.transactions.first { $0.type == type } }
                for theme in [ColorScheme.dark, .light] {
                    auditScheme = theme
                    for scale in [100, 150] {
                        state.preferences.textScalePercent = scale
                        let content = VStack(alignment: .leading, spacing: 18) {
                            Text("Reward reasons · native verification").appFont(.title, weight: .semibold)
                            ForEach(rows) { RewardTransactionRow(transaction: $0); Divider() }
                        }.padding(24).frame(width: 950, alignment: .leading).background(Palette.canvas).environmentObject(self).preferredColorScheme(theme)
                        try await previewRewardRows(content, name: "reward-reasons-\(scale)-\(theme == .dark ? "dark" : "light")")
                    }
                }
                state.preferences.textScalePercent = savedScale
            }
            window.setContentSize(NSSize(width: 1280, height: 860))
            auditScheme = nil; auditAppearance = .system; destination = .overview; analyticsSection = .local
            try await Task.sleep(for: .milliseconds(600)); scroll(0); try snapshot("dashboard-system")
            try preview(MenuSummary().environmentObject(self).preferredColorScheme(nil).tint(Palette.controlFill), name: "menu-system", size: NSSize(width: 420, height: 590))
            auditAppearance = nil; auditScheme = nil; destination = .overview
            var dashboardSortAudit: [String: Bool] = [:]
            if isolatedQA { dashboardSortAudit = try await DashboardSortAudit.run(model: self, view: view, directory: directory) }
            var pointerAudit: [String: Bool] = [:]
            if isolatedQA { pointerAudit = try await DashboardPointerAudit.verify(model:self,view:view,directory:directory) }
            var myPrintsAudit: [String: Bool] = [:]
            if isolatedQA { myPrintsAudit = try await MyPrintsAudit.run(model:self,view:view,directory:directory) }
            var menuActions: [String: Bool] = [:]
            if isolatedQA {
                menuActions = try await MenuActionsAudit.run(model: self)
                let oldIssues = issues; issues = ["Isolated offline/attention visual fixture"]
                try preview(MenuSummary().environmentObject(self).preferredColorScheme(.light).tint(Palette.controlFill), name: "menu-attention", size: NSSize(width: 420, height: 590))
                issues = oldIssues; syncing = true
                try preview(MenuSummary().environmentObject(self).preferredColorScheme(.dark).tint(Palette.controlFill), name: "menu-syncing", size: NSSize(width: 420, height: 590))
                syncing = false
            }
            if let icon = NSApp.applicationIconImage, let data = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: data) {
                try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("running-app-icon.png"))
            }
            let report: [String: Any] = ["profile": state.profile?.handle ?? "", "models": state.models.count,
                "followers": activeFollowers.count, "baselineDatesUnknown": state.followers.filter(\.baseline).allSatisfy { $0.firstObservedAt == nil },
                "unread": unread, "issues": issues, "windowTitle": window.title, "notificationAuthorization": notificationStatus,
                "captured": Date().ISO8601Format(), "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Dev", "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Dev", "rewardReasonParserVerified": state.account?.transactions.allSatisfy { $0.parserVersion == RewardLedger.version } == true,
            "rewardReasonVersion": state.account?.ledgerReasonVersion ?? 0, "sessionAvailable": accountSessionAvailable,
                "inboxVerified": state.account?.lastEventSync != nil, "rewardsVerified": state.account?.balance != nil, "ledgerVerified": state.account?.transactionsImported == true,
                "creatorVerified": state.creatorReport != nil, "creatorDailyVerified": !(state.creatorReport?.history?.isEmpty ?? true)]
            var verified = report
            verified["appearancePreference"] = appearance.rawValue
            verified["isolatedQA"] = isolatedQA
            verified["nativeControls"] = nativeControls
            verified["mainModelFilterClicks"] = mainFilterClicks
            verified["dashboardWindowClicks"] = dashboardWindowClicks
            verified["watchedLayoutControls"] = watchedLayoutControls
            verified["dashboardSortControls"] = dashboardSortAudit
            verified["dashboardPointerControls"] = pointerAudit
            verified["myPrintsControls"] = myPrintsAudit
            verified["dashboardModelsWatched"] = watching
            verified["dashboardRankedModelCount"] = modelActivityReports[.today]?.count ?? 0
            verified["menuActions"] = menuActions
            verified["textSizeControls"] = textSizeAudit
            verified["renderSizes"] = renderSizes
            verified["pollingMinutes"] = state.preferences.pollingMinutes
            verified["contrastRatios"] = ["lightMinimumText": ThemeColors.lightTextColors.map { $0.contrast(with: ThemeColors.lightSurface) }.min()!, "darkMinimumText": ThemeColors.darkTextColors.map { $0.contrast(with: ThemeColors.darkSurface) }.min()!]
            verified["appearanceRestoredFromStorage"] = try await storage?.load().preferences.appearance == appearance
            verified["sidebarDestinations"] = Destination.sidebar.map(\.rawValue)
            verified["activityMedia"] = ["actorImages": state.activity.filter { $0.presentation?.actorAvatar != nil }.count,
                "modelImages": state.activity.filter { $0.presentation?.modelCover != nil || $0.modelID.flatMap { id in state.models.first { $0.id == id }?.cover } != nil }.count]

            verified["privateFeedsVerifiedThisRun"] = ["inbox": liveInbox, "rewards": liveRewards, "pointsLedger": livePointsLedger, "walletLedger": liveWalletLedger, "creator": liveCreator, "creatorDaily": liveCreatorDaily, "creatorProfiles": liveCreatorProfiles, "creatorProfilesDaily": liveCreatorProfilesDaily]
            let rewardAudit: [String: Any] = ["rows": state.account?.transactions.count ?? 0,
                "parserCurrent": state.account?.transactions.allSatisfy { $0.parserVersion == RewardLedger.version } ?? false,
                "modelReferences": state.account?.transactions.filter { $0.modelID != nil }.count ?? 0,
                "donorMetadata": state.account?.transactions.filter { $0.presentation?.actorName != nil }.count ?? 0,
                "matchedChanges": state.account?.rewardChanges?.filter { !$0.matchedIDs.isEmpty }.count ?? 0,
                "misleadingNoIDMessages": state.activity.filter { $0.detail.contains("does not expose transaction IDs") }.count]
            verified["rewardReasons"] = rewardAudit
            try JSONSerialization.data(withJSONObject: verified, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("audit.json"), options: .atomic)
            await writeConnectionDiagnostics()
        } catch {
            try? Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent("audit-error.txt"))
        }
    }
    private var auditDirectory: URL? {
        guard let flag = CommandLine.arguments.firstIndex(of: "--ui-audit"), CommandLine.arguments.indices.contains(flag + 1) else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    }
}
