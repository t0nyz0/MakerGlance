import SwiftUI
import Charts
import MakerPulseCore

struct HistoryMosaic: View {
    @Environment(\.appTextScale) private var textScale
    let samples: [Sample]
    var metrics: [Metric] = Metric.allCases
    var compact = false
    @State private var range: HistoryRange = .week
    @State private var now = Date()
    var interval: DateInterval { DateInterval(start: now.addingTimeInterval(-Double(range.rawValue) * 86400), end: now) }
    var axis: DateInterval {
        let first = samples.filter { $0.date >= interval.start }.map(\.date).min() ?? interval.start
        return DateInterval(start: min(first, now.addingTimeInterval(-60)), end: now)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StudioSectionHeading(title: compact ? "History at a glance" : "Profile history", subtitle: "All metrics · one observed timeline")
                Spacer(minLength: 12)
                Picker("History date range", selection: $range) { ForEach(HistoryRange.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300 * CGFloat(max(1, textScale))), spacing: 18)], spacing: 18) {
                ForEach(metrics) { metric in
                    MiniHistoryChart(title: metric.title, symbol: metric.symbol, color: Palette.metric(metric), points: HistorySeries.snapshots(samples, metric: metric, interval: interval), interval: axis, daily: false, compact: compact)
                }
            }
            HStack {
                Text("\(axis.start.formatted(date: .abbreviated, time: .shortened)) – \(axis.end.formatted(date: .abbreviated, time: .shortened))").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                ContextInfo("Reading local history") { Text("Every chart uses its own scale and the same observed time span. Change compares the first and last available observation. Gaps and missing fields are never filled with zero. Local observations remain separate from Creator Center's UTC daily reports.") }
            }
        }.onChange(of: samples.last?.date) { _, _ in now = Date() }.onChange(of: range) { _, _ in now = Date() }
    }
}

struct CreatorHistoryMosaic: View {
    @Environment(\.appTextScale) private var textScale
    let report: CreatorReport
    var interval: DateInterval { DateInterval(start: report.period.start, end: CreatorPeriod.calendar.date(byAdding: .day, value: 1, to: report.period.end)!) }
    var metrics: [CreatorMetric] { CreatorMetric.allCases.filter { key in report.history?.contains { $0.metrics[key] != nil } == true } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Daily history · all exposed metrics").appFont(.title, weight: .semibold); Spacer(); Text("UTC+0").appFont(.caption, weight: .semibold).foregroundStyle(Palette.accent) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290 * CGFloat(max(1, textScale))), spacing: 12)], spacing: 12) {
                ForEach(metrics) { metric in
                    MiniHistoryChart(title: metric.title, symbol: symbol(metric), color: color(metric), points: HistorySeries.daily(report.history ?? [], metric: metric, interval: interval), interval: interval, daily: true)
                }
            }
            Text("Server daily values · shared selected UTC date range · independent scales. Follower activity is the API field; its gross-versus-net meaning is unverified. These are not individual follow dates. Missing days are not invented.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
        }
    }
    func symbol(_ metric: CreatorMetric) -> String {
        switch metric { case .likes: "heart"; case .downloads: "arrow.down.circle"; case .prints: "printer"; case .followers: "person.2"; case .saves: "square.stack"; case .views, .impressions: "eye"; case .boosts: "bolt"; default: "sparkles" }
    }
    func color(_ metric: CreatorMetric) -> Color {
        switch metric { case .likes: Palette.metric(.likes); case .downloads, .views: Palette.metric(.downloads); case .prints, .impressions: Palette.metric(.prints); case .saves: Palette.metric(.collections); case .boosts, .exclusivePoints, .exclusivePointsCN: Palette.orange; default: Palette.accent }
    }
}

struct MiniHistoryChart: View {
    @Environment(\.appTextScale) private var textScale
    let title: String
    let symbol: String
    let color: Color
    let points: [HistoryPoint]
    let interval: DateInterval
    let daily: Bool
    var compact = false
    @State private var hovered: Date?
    @State private var expanded = false
    var selected: HistoryPoint? { hovered.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } } }
    var value: Decimal? { daily ? HistorySeries.total(points) : points.last?.value }
    var delta: Decimal? { HistorySeries.delta(points) }
    var bounds: ClosedRange<Double> {
        let values = points.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        let low = values.min() ?? 0, high = values.max() ?? 0
        if daily { return floor(min(0, low))...max(1, ceil(high * 1.08)) }
        let padding = max(1, (high - low) * 0.15)
        let lower = low >= 0 ? max(0, floor(low - padding)) : floor(low - padding)
        return lower...max(lower + 1, ceil(high + padding))
    }
    var ticks: [Double] { Array(Set([bounds.lowerBound, ((bounds.lowerBound + bounds.upperBound) / 2).rounded(), bounds.upperBound])).sorted() }
    var axisFormat: Date.FormatStyle {
        var format = daily || interval.duration > 48 * 3600 ? Date.FormatStyle.dateTime.month(.abbreviated).day() : Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = daily ? CreatorPeriod.calendar.timeZone : .autoupdatingCurrent
        return format
    }
    var body: some View {
        Surface(inset: 20) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 7) { Image(systemName: symbol).foregroundStyle(color); Text(title).fontWeight(.medium); Spacer(); Button { expanded = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.buttonStyle(.plain).foregroundStyle(Palette.secondaryText).help("Expand \(title) history").accessibilityLabel("Expand \(title) history") }.appFont(size: 12)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value.map(DisplayNumber.decimal) ?? "—").appFont(size: 28, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(daily ? "period total" : "latest").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    Spacer(minLength: 0)
                    if !daily, let delta { Text((delta > 0 ? "+" : "") + DisplayNumber.decimal(delta)).appFont(.caption, weight: .medium).foregroundStyle(delta > 0 ? Palette.positive : delta < 0 ? Palette.negative : Palette.secondaryText).monospacedDigit().help("Change between available observations in the selected range") }
                }
                if points.count >= (daily ? 1 : 2) { plot(height: compact ? 110 : 155) }
                else { Text(points.isEmpty ? "No observations in this range" : "One observation · awaiting the next snapshot").appFont(size: 12).foregroundStyle(Palette.secondaryText).frame(maxWidth: .infinity).frame(height: compact ? 100 : 140) }
                Text("\(points.count) \(daily ? "days returned" : "observations")").appFont(size: 11).foregroundStyle(Palette.secondaryText)
            }
        }.sheet(isPresented: $expanded) {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text(title).appFont(.title, weight: .semibold); Spacer(); Text(daily ? "UTC daily values" : "Local observations").foregroundStyle(Palette.secondaryText); Button("Done") { expanded = false }.keyboardShortcut(.defaultAction) }
                plot(height: 280)
                Text("\(points.count) available \(daily ? "days" : "observations"). \(daily ? "Total is the sum of returned daily values." : "Change uses the first and last available observations, not an invented midnight baseline.")").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                List(points.reversed()) { point in HStack { Text(dateText(point.date)); Spacer(); Text(DisplayNumber.decimal(point.value)).monospacedDigit() } }
            }.padding(24).frame(width: 720, height: 650)
        }
    }
    func plot(height: CGFloat) -> some View {
        Chart {
            ForEach(points) { point in
                if daily { BarMark(x: .value("UTC day", point.date, unit: .day, calendar: CreatorPeriod.calendar), y: .value(title, NSDecimalNumber(decimal: point.value).doubleValue)).foregroundStyle(color.gradient) }
                else {
                    AreaMark(x: .value("Observed", point.date), yStart: .value("Scale baseline", bounds.lowerBound), yEnd: .value(title, NSDecimalNumber(decimal: point.value).doubleValue))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.13), color.opacity(0.015)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.linear)
                    LineMark(x: .value("Observed", point.date), y: .value(title, NSDecimalNumber(decimal: point.value).doubleValue)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.25)).interpolationMethod(.linear)
                }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date)).foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, alignment: .leading) { VStack(alignment: .leading, spacing: 3) { Text(DisplayNumber.decimal(selected.value)).fontWeight(.semibold); Text(dateText(selected.date)).foregroundStyle(Palette.secondaryText) }.appFont(size: 12).padding(7).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6)) }
            }
        }.chartXScale(domain: interval.start...interval.end).chartYScale(domain: bounds)
            .chartYAxis { AxisMarks(position: .leading, values: ticks) { _ in AxisGridLine().foregroundStyle(Palette.line.opacity(0.6)); AxisValueLabel().foregroundStyle(Palette.secondaryText).font(AppTypography.font(size: 12, scale: textScale)) } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: axisFormat).foregroundStyle(Palette.secondaryText).font(AppTypography.font(size: 12, scale: textScale)) } }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                        guard !CommandLine.arguments.contains("--demo-capture") else { return }
                        switch phase { case .active(let location): if let frame = proxy.plotFrame { hovered = proxy.value(atX: location.x - geometry[frame].origin.x, as: Date.self) }; case .ended: hovered = nil }
                    }
                }
            }
            .environment(\.timeZone, daily ? CreatorPeriod.calendar.timeZone : .autoupdatingCurrent)
            .frame(height: height).accessibilityLabel("\(title) \(daily ? "daily UTC" : "snapshot") chart").accessibilityValue("\(points.count) values. \(daily ? "Period total" : "Latest") \(value.map(DisplayNumber.decimal) ?? "unavailable"). Expand for an accessible list.")
    }
    func dateText(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.timeZone = daily ? CreatorPeriod.calendar.timeZone : .autoupdatingCurrent; formatter.dateStyle = .medium; formatter.timeStyle = daily ? .none : .short
        return formatter.string(from: date) + (daily ? " UTC" : "")
    }
}
