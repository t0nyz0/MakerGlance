import SwiftUI
import MakerPulseCore

struct DashboardView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    var body: some View {
        GeometryReader { bounds in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    performance(columns: bounds.size.width >= 900 * textScale ? 6 : bounds.size.width >= 600 * textScale ? 3 : 2)
                    DashboardRewards(columns: bounds.size.width >= 900 * textScale ? 5 : bounds.size.width >= 650 * textScale ? 3 : 2)
                    momentum
                    inbox
                    HistoryMosaic(samples: model.histories["profile"] ?? [], compact: true)
                }.padding(30).frame(maxWidth: 1600, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
            }.frame(width: bounds.size.width, height: bounds.size.height)
        }
    }
    var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Overview").appFont(size: 32, weight: .semibold)
                Text("@\(model.state.profile?.handle ?? model.state.preferences.handle)  ·  \(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                    .appFont(size: 13).foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            Label(model.state.lastProfileSync == nil ? "Awaiting sync" : model.profileLive && model.issues.isEmpty ? "Live public data" : "Saved observations", systemImage: model.profileLive ? "checkmark.circle" : "clock")
                .appFont(size: 12, weight: .medium).foregroundStyle(Palette.secondaryText)
        }
    }
    func performance(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Lifetime performance").appFont(size: 16, weight: .semibold)
                Spacer()
                Text("Change today").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                ContextInfo("Today's observation coverage") {
                    Text("Today is your Mac's local calendar day, from midnight to midnight. Growth starts with each metric's first actual observation; missing time is not estimated.")
                    ForEach(Metric.allCases) { metric in
                        HStack { Text(metric.title); Spacer(); Text(model.profileDayGrowth(metric).baselineDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Unavailable") }.appFont(size: 12)
                    }
                    Text("Collection saves are aggregate counts. The API does not identify individual collection additions or original follower dates.")
                }
            }
            Surface(inset: 18) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns), alignment: .leading, spacing: 26) {
                    ForEach(Metric.allCases) { metric in
                        Button { model.openAnalytics(metric) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(metric == .collections ? "Saves" : metric.title, systemImage: metric.symbol).appFont(size: 12, weight: .medium).foregroundStyle(Palette.secondaryText)
                                Text(model.state.profile?.counts[metric].map { $0.formatted() } ?? "—").appFont(size: 32, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                                GrowthIndicator(growth: model.profileDayGrowth(metric), compact: true, metric: metric)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("\(metric.title). Open \(metric == .followers ? "followers" : "history"). \(model.profileDayGrowth(metric).isPartial ? "Today has partial observation coverage." : "A midnight baseline is available.")")
                    }
                }
            }
        }
    }
    var momentum: some View { WatchedModelsSection() }
    var inbox: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                StudioSectionHeading(title: "Recent activity", subtitle: "Your inbox, milestones and watched changes")
                Spacer()
                Button { model.destination = .activity } label: { Label("View inbox", systemImage: "arrow.up.right") }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            Surface(inset: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    if model.state.activity.isEmpty { EmptyPanel(title: "You're caught up", detail: "New updates appear here after the quiet initial import.", symbol: "checkmark.circle") }
                    ForEach(model.state.activity.prefix(4)) { item in ActivityRow(activity: item); if item.id != model.state.activity.prefix(4).last?.id { Divider().opacity(0.35) } }
                    Divider().padding(.vertical, 14)
                    HStack {
                        Button { model.openAnalytics(.followers) } label: { Label("Followers", systemImage: "person.2") }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                        Text("\(model.state.followers.filter { !$0.baseline }.count) first seen since setup").foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Text(model.restoringSession ? "Saved inbox · awaiting Keychain" : model.state.account?.lastEventSync.map { "Verified \($0.formatted(date: .omitted, time: .shortened))" } ?? "Connect in Settings").foregroundStyle(Palette.secondaryText)
                    }.appFont(size: 12)
                }
            }
        }
    }
}

struct DashboardModelRow: View {
    @EnvironmentObject var model: AppModel
    let item: ObservedModelActivity
    let window: ModelActivityWindow
    var design: Design { item.design }
    var overlayMetrics: [Metric] {
        let changed = item.changedMetrics
        return (item.deltas[.prints] ?? 0) > 0 ? [.prints] + changed.filter { $0 != .prints } : changed
    }
    var body: some View {
        Button { model.selectedModel = design } label: {
            VStack(alignment: .leading, spacing: 0) {
                RemoteImage(url: design.cover, pixelWidth: 640).frame(height: 200).frame(maxWidth: .infinity).contentShape(Rectangle()).clipped()
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(overlayMetrics.prefix(2)) { metric in
                                if let delta = item.deltas[metric] { ModelGrowthBadge(metric: metric, delta: delta, fresh: model.latestModelIncreases[design.id]?[metric], period: window.title) }
                            }
                            if item.changedMetrics.isEmpty {
                                Label(item.lastActivityAt != nil ? "New activity" : item.hasComparison ? "No observed change" : item.baselineDate == nil ? "Awaiting observation" : "Baseline captured", systemImage: item.lastActivityAt != nil ? "waveform.path" : "clock")
                                    .appFont(size: 11, weight: .semibold).padding(.horizontal, 10).padding(.vertical, 7).foregroundStyle(.white).background(Color.black.opacity(0.82), in: Capsule())
                            }
                        }.padding(12)
                    }
                VStack(alignment: .leading, spacing: 15) {
                    Text(design.title).appFont(size: 15, weight: .semibold).lineLimit(2).frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    HStack(spacing: 6) {
                        Image(systemName: item.lastActivityAt == nil ? "clock" : "waveform.path").foregroundStyle(Palette.accent)
                        if let date = item.lastActivityAt { Text("Activity \(date.formatted(window == .today ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day().hour().minute()))") }
                        else { Text(item.hasComparison ? "No change in this window" : "Awaiting comparison") }
                        Spacer(minLength: 0)
                    }.appFont(size: 12).foregroundStyle(Palette.secondaryText).help(item.lastActivityAt.map { "Last actual activity: " + $0.formatted(date: .complete, time: .standard) } ?? "No actual change has been observed in this window.")
                    ModelMetricRows(design: design, deltas: item.deltas, period: window.title)
                    if let event = item.latestEvent, event.date >= (item.lastMetricChangeAt ?? .distantPast) { Label(event.title, systemImage: event.symbol).appFont(size: 12).foregroundStyle(Palette.secondaryText).lineLimit(1).help(event.detail) }
                    HStack {
                        if let baseline = item.baselineDate { Label("From \(baseline.formatted(window == .today ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day().hour().minute()))", systemImage: "clock"); Spacer(); Text(baseline > window.interval(now: Date()).start.addingTimeInterval(1) ? "Partial coverage" : "Full coverage") }
                        else { Text("No observations in this window") }
                    }.appFont(size: 11).foregroundStyle(Palette.secondaryText).padding(.top, 2)
                        .help(item.baselineDate.map { "First actual observation: " + $0.formatted(date: .complete, time: .standard) + ". No earlier values are estimated." } ?? "This window has no observation baseline.")
                }.padding(18)
            }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Open \(design.title) insights and notification controls")
    }
}

struct ModelGrowthBadge: View {
    let metric: Metric
    let delta: Int
    var fresh: LatestMetricIncrease? = nil
    var period = "Today"
    var printIncrease: Bool { metric == .prints && delta > 0 }
    var body: some View {
        HStack(spacing: 5) {
            Label("\(delta > 0 ? "+" : "")\(delta.formatted()) \(metric == .collections ? "saves" : metric.title.lowercased())", systemImage: printIncrease ? "printer.fill" : delta > 0 ? "arrow.up.right" : "arrow.down.right")
            if fresh != nil { Text("NEW").appFont(size: 9, weight: .bold).padding(.horizontal, printIncrease ? 4 : 0).padding(.vertical, printIncrease ? 2 : 0).background(printIncrease ? Palette.freshPill : .clear, in: Capsule()).accessibilityHidden(true) }
        }
            .appFont(size: 11, weight: .semibold).monospacedDigit().padding(.horizontal, 9).padding(.vertical, 6)
            .foregroundStyle(.white).background(printIncrease ? Palette.printPill : fresh == nil ? Color.black.opacity(0.82) : Palette.freshPill, in: Capsule())
            .overlay(Capsule().strokeBorder(fresh == nil ? .clear : Color(red: 0.47, green: 0.72, blue: 1), lineWidth: 1))
            .help(tooltip).accessibilityElement(children: .ignore).accessibilityLabel(tooltip)
    }
    var tooltip: String {
        let total = "\(period): \(delta > 0 ? "+" : "")\(delta.formatted()) \(metric.title.lowercased())."
        guard let fresh else { return total + " A blue NEW marker identifies an increase found by the latest comparable check this session." }
        return total + " +\(fresh.delta.formatted()) since last comparable check. Checked \(fresh.checkedAt.formatted(date: .abbreviated, time: .shortened)); previous check \(fresh.previousCheckAt.formatted(date: .abbreviated, time: .shortened))."
    }
}

private struct DashboardRewards: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    let columns: Int
    let metrics: [RewardMetric] = [.regularPoints, .exclusivePoints, .cashEstimate, .cashAvailable, .cashPending]
    var balance: RewardBalance? { model.state.account?.balance?.balance }
    var body: some View {
        Surface(inset: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Rewards & wallet", systemImage: "wallet.bifold").appFont(size: 16, weight: .semibold)
                    ContextInfo("Distinct rewards and wallet balances") {
                        Text("Regular and exclusive points are separate balances. Cash estimate is MakerWorld's estimated redeemable points value, not wallet cash. Ready to transfer and pending income are separate wallet amounts. Values keep exact decimal precision and their original currency.")
                        Text(model.restoringSession ? "Keychain access is pending. Saved observations remain visible." : model.rewardsStatus)
                    }
                    Spacer()
                    Text(model.restoringSession ? "Saved · Keychain pending" : model.privateSyncing ? "Refreshing…" : (model.state.account?.balance?.date).map { "Latest check " + $0.formatted(date: .omitted, time: .shortened) } ?? "Not connected")
                        .appFont(size: 12).foregroundStyle(Palette.secondaryText).help("Individual verification times are available below. Older and unavailable fields keep their own status.")
                    Button { model.destination = .rewards } label: { Label("Wallet & history", systemImage: "arrow.up.right") }.buttonStyle(.plain).appFont(size: 12, weight: .medium).foregroundStyle(Palette.accent)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns), alignment: .leading, spacing: 22) {
                    ForEach(metrics) { metric in
                        Button { model.destination = .rewards } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(title(metric)).appFont(size: 12).foregroundStyle(Palette.secondaryText).lineLimit(1)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(balance?[metric].map(DisplayNumber.decimal) ?? "—").appFont(size: 26, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                                    if metric.isCash, let currency = balance?.currency(for: metric) { Text(currency).appFont(size: 11).foregroundStyle(Palette.secondaryText) }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).help("\(metric.title). \(model.state.account?.balanceDates[metric].map { "Verified " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not verified yet"). Open history and transaction reasons.")
                    }
                }
                DisclosureGroup("More balances & verification") {
                Divider().opacity(0.4)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 22) { auxiliary(.cashIncome); auxiliary(.cashTransferred); auxiliary(.cashWithdrawing); Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 10) { auxiliary(.cashIncome); auxiliary(.cashTransferred); auxiliary(.cashWithdrawing) }
                }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(RewardMetric.allCases) { metric in
                            HStack { Text(metric.title); Spacer(); Text(model.state.account?.balanceDates[metric].map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not verified") }
                        }
                        Text("A missing field remains unavailable. An older saved value keeps its own verification time; no currency is converted. Cash estimate and wallet funds remain separate.").padding(.top, 6)
                    }.appFont(size: 12).foregroundStyle(Palette.secondaryText).padding(.top, 12)
                }.appFont(size: 12, weight: .medium).foregroundStyle(.primary).tint(Palette.controlFill)
            }
        }
    }
    func title(_ metric: RewardMetric) -> String { switch metric { case .cashEstimate: "Cash estimate"; case .cashAvailable: "Ready to transfer"; case .cashPending: "Pending income"; default: metric.title } }
    func auxiliary(_ metric: RewardMetric) -> some View {
        HStack(spacing: 6) { Text(metric.title.replacingOccurrences(of: "Wallet ", with: "")).foregroundStyle(Palette.secondaryText); Text(balance?[metric].map(DisplayNumber.decimal) ?? "—").fontWeight(.medium).monospacedDigit(); if let currency = balance?.currency(for: metric), balance?[metric] != nil { Text(currency).foregroundStyle(Palette.secondaryText) } }.appFont(size: 12)
    }
}
