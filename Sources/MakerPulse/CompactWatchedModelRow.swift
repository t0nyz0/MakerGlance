import SwiftUI
import MakerPulseCore

struct CompactWatchedModelRow: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    let item: ObservedModelActivity
    let window: ModelActivityWindow
    var design: Design { item.design }
    var watched: Bool { model.state.watches[design.id]?.enabled ?? true }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identity
            HStack(alignment: .top, spacing: 12) {
                artwork
                metrics.frame(maxWidth: .infinity)
            }
            if let event = item.latestEvent, event.date >= (item.lastMetricChangeAt ?? .distantPast) {
                Label(event.title, systemImage: event.symbol).appFont(size: 11).foregroundStyle(Palette.secondaryText).lineLimit(2).help(event.detail)
            }
            Divider().opacity(0.25)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { activity; Spacer(minLength: 4); coverage }
                VStack(alignment: .leading, spacing: 4) { activity; coverage }
            }.appFont(size: 11).foregroundStyle(Palette.secondaryText)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.35), lineWidth: 0.7))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(design.title), compact model summary")
    }
    var identity: some View {
        HStack(alignment: .top, spacing: 8) {
                Button { model.selectedModel = design } label: {
                    Text(design.title).appFont(size: 15, weight: .semibold).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help("Open \(design.title) insights and notification controls")
            Button { model.updateWatch(design.id) { $0.enabled.toggle() } } label: {
                Image(systemName: watched ? "eye.fill" : "eye.slash").font(.system(size: 12)).foregroundStyle(Palette.accent).frame(width: 28, height: 28).background(Palette.accent.opacity(watched ? 0.11 : 0.04), in: Circle())
            }.buttonStyle(.plain).help(watched ? "Pause metric alerts for this model; snapshots continue" : "Watch this model")
                .accessibilityLabel("\(watched ? "Pause alerts for" : "Watch") \(design.title)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var artwork: some View {
        Button { model.selectedModel = design } label: {
            RemoteImage(url: design.cover, pixelWidth: 256).frame(width: 116, height: 116).contentShape(Rectangle()).clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel("Open \(design.title) insights")
    }
    var metrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text("Lifetime").frame(width: 54 * max(1, textScale), alignment: .trailing)
                Text(window.title).frame(minWidth: 46 * max(1, textScale), alignment: .trailing)
            }.appFont(size: 11).foregroundStyle(Palette.secondaryText)
            Divider().opacity(0.2)
            ForEach(ModelActivity.metrics) { metric in metricCell(metric) }
        }
    }
    func metricCell(_ metric: Metric) -> some View {
        let delta = item.deltas[metric]
        let fresh = model.latestModelIncreases[design.id]?[metric]
        let printIncrease = metric == .prints && (delta ?? 0) > 0
        let color = printIncrease ? Palette.metric(.prints) : (delta ?? 0) > 0 ? Palette.positive : (delta ?? 0) < 0 ? Palette.negative : Palette.secondaryText
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Label(metric == .collections ? "Saves" : metric.title, systemImage: printIncrease ? "printer.fill" : metric.symbol)
                .appFont(size: 12, weight: printIncrease ? .semibold : .medium).foregroundStyle(printIncrease ? Palette.metric(.prints) : Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(design.counts[metric].map { $0.formatted(.number.notation(.compactName)) } ?? "—")
                .appFont(size: 15, weight: .semibold).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                .frame(width: 54 * max(1, textScale), alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                if let delta {
                    Image(systemName: printIncrease ? "printer.fill" : delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "minus").font(.system(size: 9))
                    Text(delta > 0 ? "+\(delta.formatted())" : delta.formatted()).foregroundStyle(color)
                } else { Text("—").foregroundStyle(Palette.secondaryText) }
                }
                if fresh != nil { Text("NEW").appFont(size: 9, weight: .bold).padding(.horizontal, 4).padding(.vertical, 1).foregroundStyle(.white).background(Palette.freshPill, in: Capsule()) }
            }.appFont(size: 11, weight: .medium).monospacedDigit().foregroundStyle(color)
                .frame(minWidth: 46 * max(1, textScale), alignment: .trailing)
        }.padding(.horizontal, 3).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading)
            .background(printIncrease ? Palette.metric(.prints).opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .help(metricDescription(metric, delta: delta, fresh: fresh))
            .accessibilityElement(children: .ignore).accessibilityLabel(metricDescription(metric, delta: delta, fresh: fresh))
    }
    func metricDescription(_ metric: Metric, delta: Int?, fresh: LatestMetricIncrease?) -> String {
        let total = "\(metric.title). Lifetime \(design.counts[metric].map { $0.formatted() } ?? "unavailable"). "
        guard let delta else { return total + "\(window.title) comparison unavailable." }
        return total + ModelGrowthBadge(metric: metric, delta: delta, fresh: fresh, period: window.title).tooltip
    }
    var activity: some View {
        Label(activityText, systemImage: item.lastActivityAt == nil ? "clock" : "waveform.path")
            .fixedSize(horizontal: false, vertical: true)
            .help(item.lastActivityAt.map { "Last actual activity: " + $0.formatted(date: .complete, time: .standard) } ?? "A refresh alone does not count as model activity.")
    }
    var coverage: some View {
        Group {
            if let baseline = item.baselineDate {
                Label("From \(baseline.formatted(window == .today ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day().hour().minute())) · \(baseline > window.interval(now: Date()).start.addingTimeInterval(1) ? "Partial coverage" : "Full coverage")", systemImage: "clock")
            } else { Text("No observations in this window") }
        }.fixedSize(horizontal: false, vertical: true).help(item.baselineDate.map { "First actual observation: " + $0.formatted(date: .complete, time: .standard) + ". No earlier values are estimated." } ?? "This window has no observation baseline.")
    }
    var activityText: String {
        if let date = item.lastActivityAt { return "Activity " + date.formatted(window == .today ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day().hour().minute()) }
        return item.hasComparison ? "No change in this window" : "Awaiting comparison"
    }
}
