import SwiftUI
import MakerPulseCore

struct RewardHistoryMosaic: View {
    @Environment(\.appTextScale) private var textScale
    let samples: [BalanceSample]
    let balance: RewardBalance?
    @State private var range: HistoryRange = .week
    @State private var now = Date()
    var interval: DateInterval { DateInterval(start: now.addingTimeInterval(-Double(range.rawValue) * 86400), end: now) }
    var axis: DateInterval {
        DateInterval(start: min(samples.first(where: { $0.date >= interval.start })?.date ?? interval.start, now.addingTimeInterval(-60)), end: now)
    }
    var available: [RewardMetric] { RewardMetric.allCases.filter { key in samples.contains { $0.balance[key] != nil } || balance?[key] != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("All balance histories").appFont(.title, weight: .semibold); Spacer(); Picker("Balance history range", selection: $range) { ForEach(HistoryRange.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 210) }
            if available.isEmpty { Surface { EmptyPanel(title: "Balance history starts after connection", detail: "Only verified observations are shown. Points and cash keep separate scales and currencies.", symbol: "chart.xyaxis.line") } }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290 * CGFloat(max(1, textScale))), spacing: 12)], spacing: 12) {
                    ForEach(available) { metric in
                        MiniHistoryChart(title: metric.title + (metric.isCash ? " · \(balance?.currency(for: metric) ?? "currency unavailable")" : ""), symbol: metric.isCash ? "banknote" : "sparkles", color: metric == .exclusivePoints ? Palette.orange : Palette.accent,
                            points: points(metric), interval: axis, daily: false)
                    }
                }
            }
            Text("Shared observation span · each balance has its own scale. Cash charts use a single matching currency; missing balances are never substituted or converted.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
        }.onChange(of: samples.last?.date) { _, _ in now = Date() }
    }
    func points(_ metric: RewardMetric) -> [HistoryPoint] {
        samples.filter { $0.date >= interval.start && $0.date <= interval.end && (!metric.isCash || $0.balance.currency(for: metric) == balance?.currency(for: metric)) }.compactMap { sample in
            sample.balance[metric].map { HistoryPoint(date: sample.date, value: $0) }
        }
    }
}
