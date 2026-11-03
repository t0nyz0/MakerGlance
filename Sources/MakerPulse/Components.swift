import SwiftUI
import Charts
import MakerPulseCore

enum Palette {
    private static func color(_ rgb: ThemeRGB) -> NSColor { NSColor(srgbRed: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1) }
    private static func adaptive(_ light: ThemeRGB, _ dark: ThemeRGB) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in color(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light) })
    }
    static let controlFill = adaptive(ThemeColors.lightControlFill, ThemeColors.darkControlFill)
    static let accent = adaptive(ThemeColors.lightAccent, ThemeColors.darkAccent)
    static let positive = adaptive(ThemeColors.lightPositive, ThemeColors.darkPositive)
    static let negative = adaptive(ThemeColors.lightNegative, ThemeColors.darkNegative)
    static let secondaryText = adaptive(ThemeColors.lightSecondary, ThemeColors.darkSecondary)
    static let canvas = adaptive(ThemeColors.lightCanvas, ThemeColors.darkCanvas)
    static let surface = adaptive(ThemeColors.lightSurface, ThemeColors.darkSurface)
    static let sidebar = adaptive(ThemeColors.lightSidebar, ThemeColors.darkSidebar)
    static let line = adaptive(ThemeRGB(0xDCDDE4), ThemeRGB(0x33353D))
    static let orange = adaptive(ThemeColors.lightOrange, ThemeColors.darkOrange)
    static let brandTile = Color(nsColor: color(ThemeColors.lightAccent))
    static let freshPill = Color(nsColor: color(ThemeColors.freshPill))
    static let printPill = Color(nsColor: color(ThemeColors.printPill))
    static let onAccent = adaptive(ThemeRGB(0xFFFFFF), ThemeRGB(0x000000))
    static func metric(_ metric: Metric) -> Color {
        switch metric {
        case .likes: adaptive(ThemeColors.lightLikes, ThemeColors.darkLikes)
        case .downloads: accent
        case .prints: adaptive(ThemeColors.lightPrints, ThemeColors.darkPrints)
        case .boosts: orange
        case .collections: adaptive(ThemeColors.lightCollections, ThemeColors.darkCollections)
        case .followers: adaptive(ThemeColors.lightFollowers, ThemeColors.darkFollowers)
        }
    }
}

struct Surface<Content: View>: View {
    var inset: CGFloat
    var content: Content
    init(inset: CGFloat = 20, @ViewBuilder content: () -> Content) { self.inset = inset; self.content = content() }
    var body: some View {
        content.padding(inset).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct RemoteImage: View {
    let url: String?
    var symbol = "cube.transparent"
    var pixelWidth = 480
    var contentMode: ContentMode = .fill
    @State private var loaded: NSImage?
    @ObservedObject private var imageRefresh = ImageRefresh.shared
    var body: some View {
        Group {
            if let loaded { Image(nsImage: loaded).resizable().aspectRatio(contentMode: contentMode) }
            else { ZStack { Palette.accent.opacity(0.07); Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Palette.accent.opacity(0.5)) } }
        }.accessibilityHidden(true).task(id: (url ?? "") + "@\(pixelWidth):\(imageRefresh.revision)") {
            loaded = nil
            if let demo = DemoArtwork.image(url) { loaded = demo; return }
            guard let thumbnailURL else { return }
            for delay in [0, 2, 8, 30] {
                do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) } } catch { return }
                guard !Task.isCancelled else { return }
                let image = await ImageRenderer.load(thumbnailURL, fallback: ImageURLPolicy.original(url))
                guard !Task.isCancelled else { return }
                if let image { loaded = image; return }
            }
        }
    }
    private var thumbnailURL: URL? { ImageURLPolicy.thumbnail(url, pixelWidth: pixelWidth) }
}

struct MetricCard: View {
    let metric: Metric
    let value: Int?
    let growth: DayGrowth?
    var compact = false
    var body: some View {
        Surface(inset: compact ? 16 : 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) { Image(systemName: metric.symbol).foregroundStyle(Palette.metric(metric)).font(.system(size: 12, weight: .semibold)); Text(metric.title).appFont(size: 11, weight: .medium).foregroundStyle(Palette.secondaryText); Spacer(minLength: 0) }.lineLimit(1).minimumScaleFactor(0.85)
                Text(value.map { $0.formatted() } ?? "—").appFont(size: 30, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                Group {
                    if let growth { GrowthIndicator(growth: growth, metric: metric) }
                    else { Text(value == nil ? "Not exposed by API" : "Awaiting observation").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                }.frame(height: 34, alignment: .topLeading)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct GrowthIndicator: View {
    let growth: DayGrowth
    var compact = false
    var metric: Metric? = nil
    var printIncrease: Bool { metric == .prints && (growth.value ?? 0) > 0 }
    var color: Color { guard let value = growth.value else { return .secondary }; return printIncrease ? Palette.metric(.prints) : value > 0 ? Palette.positive : value < 0 ? Palette.negative : Palette.secondaryText }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                if let value = growth.value {
                    Image(systemName: printIncrease ? "printer.fill" : value > 0 ? "arrow.up.right" : value < 0 ? "arrow.down.right" : "minus")
                    Text("\(value > 0 ? "+" : "")\(value.formatted())\(compact ? "" : " Today")").monospacedDigit()
                } else { Text(compact ? "—" : "Awaiting today's baseline") }
            }.foregroundStyle(color)
            if !compact, let baseline = growth.baselineDate, growth.isPartial {
                Text("observed since \(baseline.formatted(date: .omitted, time: .shortened))").foregroundStyle(Palette.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
            }
        }.appFont(size: 12, weight: .medium)
            .help("Today uses \(growth.timeZoneID), from local midnight to the next midnight. \(growth.baselineDate.map { "First observation: " + $0.formatted(date: .abbreviated, time: .shortened) + ". " } ?? "Baseline unavailable. ")\(growth.isPartial ? "Only observations since the first available snapshot are included." : "Midnight baseline is available.")")
            .accessibilityElement(children: .combine)
    }
}

enum HistoryRange: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, month = 30, year = 365
    var id: Int { rawValue }
    var title: String { switch self { case .day: "24H"; case .week: "7D"; case .month: "30D"; case .year: "1Y" } }
}

struct HistoryChart: View {
    var samples: [Sample]
    @State private var metric: Metric = .likes
    @State private var range: HistoryRange = .week
    var metrics: [Metric] = [.likes, .downloads, .prints, .boosts, .collections, .followers]
    init(samples: [Sample], metrics: [Metric] = [.likes, .downloads, .prints, .boosts, .collections, .followers], initialMetric: Metric = .likes) {
        self.samples = samples; self.metrics = metrics; _metric = State(initialValue: initialMetric)
    }
    var visible: [Sample] { samples.filter { $0.date >= Date().addingTimeInterval(-Double(range.rawValue) * 86400) && $0.counts[metric] != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("History").appFont(.headline)
                    Text("Recorded on this Mac · \(visible.count) \(visible.count == 1 ? "observation" : "observations")").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                Picker("Metric", selection: $metric) { ForEach(metrics) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 125)
                Picker("Time range", selection: $range) { ForEach(HistoryRange.allCases) { Text($0.title).tag($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 200)
            }
            if visible.count >= 2 {
                Chart(visible) { sample in
                    if let count = sample.counts[metric] {
                        AreaMark(x: .value("Observed", sample.date), yStart: .value("Baseline", minimum), yEnd: .value(metric.title, Double(count)))
                            .foregroundStyle(LinearGradient(colors: [Palette.metric(metric).opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Observed", sample.date), y: .value(metric.title, Double(count))).foregroundStyle(Palette.metric(metric)).lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Observed", sample.date), y: .value(metric.title, Double(count))).foregroundStyle(Palette.metric(metric)).symbolSize(visible.count > 80 ? 0 : 12)
                    }
                }
                .chartYScale(domain: minimum...maximum)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine().foregroundStyle(Palette.line); AxisValueLabel() } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(Palette.line); AxisValueLabel() } }
                .accessibilityLabel("\(metric.title) history, \(visible.count) observations")
                .frame(height: 190)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.accent)
                    Text(samples.isEmpty ? "Your history starts here" : "First snapshot saved").appFont(.headline)
                    Text("Trends appear after the next refresh. Local snapshot history starts with this installation; Creator Center reporting is separate.")
                        .appFont(size: 12).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).frame(height: 190).background(Palette.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    var minimum: Double {
        let values = visible.compactMap { $0.counts[metric] }
        let lo = values.min() ?? 0; let hi = values.max() ?? 1
        return max(0, Double(lo) - max(1, Double(hi - lo) * 0.15))
    }
    var maximum: Double {
        let values = visible.compactMap { $0.counts[metric] }
        return Double(values.max() ?? 1) + max(1, Double((values.max() ?? 1) - (values.min() ?? 0)) * 0.15)
    }
}

struct EmptyPanel: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Palette.accent)
            Text(title).appFont(.title, weight: .bold)
            Text(detail).appFont(.callout).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 410)
        }.frame(maxWidth: .infinity).padding(45)
    }
}

struct ActivityRow: View {
    @EnvironmentObject var model: AppModel
    let activity: Activity
    var compact = false
    var media: ActivityPresentation { activity.presentation ?? ActivityPresentation() }
    var design: Design? { model.state.models.first { $0.id == activity.modelID } }
    var modelCover: String? { media.modelCover ?? design?.cover }
    var modelTitle: String? { media.modelTitle ?? design?.title }
    var badgeColor: Color { media.rewardMetric == .exclusivePoints ? Palette.orange : media.metric.map(Palette.metric) ?? (media.kind == .boost ? Palette.orange : Palette.accent) }
    var printActivity: Bool { media.metric == .prints }
    var followerProfile: URL? { ActivityLinks.followerProfile(for: activity, followers: model.state.followers) }
    var body: some View {
        if let followerProfile {
            Link(destination: followerProfile) { rowContent }
                .buttonStyle(.plain).disabled(model.isDemo)
                .help("Open follower's profile on MakerWorld")
                .accessibilityIdentifier("activity-follower-profile-" + activity.id)
        } else { rowContent }
    }
    var rowContent: some View {
        HStack(alignment: .top, spacing: 13) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if let actor = media.actorName { Text(actor).fontWeight(.semibold) }
                    Text(activity.title).fontWeight(media.actorName == nil ? .semibold : .medium).foregroundStyle(printActivity ? Palette.metric(.prints) : .primary)
                    Spacer(minLength: 0)
                    if followerProfile != nil { Image(systemName: "arrow.up.right").foregroundStyle(Palette.accent).accessibilityLabel("Open profile on MakerWorld") }
                    if !activity.isRead { Circle().fill(Palette.accent).frame(width: 6, height: 6).accessibilityLabel("Unread") }
                }.appFont(size: compact ? 13 : 14).lineLimit(2)
                if let modelTitle { RewardModelLink(id: activity.modelID, title: modelTitle).appFont(size: 12, weight: .medium).lineLimit(2) }
                if let content = media.content, !content.isEmpty { Text(content).appFont(size: 12).foregroundStyle(Palette.secondaryText).lineLimit(compact ? 2 : 4) }
                else if media.kind != .boost || modelTitle == nil { Text(activity.detail).appFont(size: 12).foregroundStyle(Palette.secondaryText).lineLimit(compact ? 2 : 3) }
                HStack(spacing: 7) {
                    Label(badge, systemImage: printActivity ? "printer.fill" : activity.symbol).appFont(size: 12, weight: printActivity ? .semibold : .medium).padding(.horizontal, 7).padding(.vertical, 3).foregroundStyle(printActivity ? .white : badgeColor).background(printActivity ? Palette.printPill : badgeColor.opacity(0.08), in: Capsule())
                    Text((media.originalTimestamp == false ? "Observed " : "") + activity.date.formatted(date: .abbreviated, time: .shortened)).appFont(size: compact ? 11 : 11).foregroundStyle(Palette.secondaryText).help(media.originalTimestamp == false ? "First observed by MakerGlance at this time" : activity.date.formatted(date: .complete, time: .standard))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .padding(.vertical, compact ? 10 : 14).padding(.horizontal, 6)
            .background(printActivity ? Palette.metric(.prints).opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .help(activity.detail).accessibilityElement(children: .combine)
    }
    var badge: String {
        if let metric = media.rewardMetric, let delta = media.rewardDelta { return (delta > 0 ? "+" : "") + DisplayNumber.decimal(delta) + " " + metric.title.lowercased() }
        if let delta = media.delta { return (delta > 0 ? "+" : "") + delta.formatted() + " " + (media.metric?.title.lowercased() ?? "change") }
        return media.kind?.title ?? media.metric?.title ?? "Update"
    }
    @ViewBuilder var artwork: some View {
        if modelCover != nil || activity.modelID != nil {
            RemoteImage(url: modelCover, pixelWidth: 160).frame(width: compact ? 64 : 88, height: compact ? 54 : 70).clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .bottomTrailing) {
                    if media.actorName != nil || media.actorAvatar != nil { RemoteImage(url: media.actorAvatar, symbol: "person.fill", pixelWidth: 96).frame(width: 28, height: 28).clipShape(Circle()).overlay(Circle().stroke(Palette.surface, lineWidth: 2)).offset(x: 4, y: 5) }
                }.padding(.trailing, 4).padding(.bottom, 5)
        } else if media.actorName != nil || media.actorAvatar != nil {
            RemoteImage(url: media.actorAvatar, symbol: "person.fill", pixelWidth: 96).frame(width: compact ? 42 : 50, height: compact ? 42 : 50).clipShape(Circle())
        } else {
            Image(systemName: activity.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(badgeColor).frame(width: compact ? 42 : 50, height: compact ? 42 : 50).background(badgeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
