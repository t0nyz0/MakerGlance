import SwiftUI
import MakerPulseCore

struct ContextInfo<Content: View>: View {
    @Environment(\.appTextScale) private var textScale
    let title: String
    let content: Content
    @State private var expanded = false
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        Button { expanded.toggle() } label: { Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Palette.secondaryText).frame(width: 24, height: 24) }
            .buttonStyle(.plain).help(title).accessibilityLabel("Details: \(title)")
            .popover(isPresented: $expanded) {
                VStack(alignment: .leading, spacing: 14) { Text(title).appFont(.headline); content.appFont(.callout).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true) }
                    .padding(22).frame(width: min(570, 370 * max(1, textScale)), alignment: .leading)
            }
    }
}

struct StudioSectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).appFont(size: 20, weight: .semibold)
            if !subtitle.isEmpty { Text(subtitle).appFont(size: 13).foregroundStyle(Palette.secondaryText) }
        }
    }
}

struct ModelMetricRows: View {
    @Environment(\.appTextScale) private var textScale
    let design: Design
    let deltas: [Metric: Int]
    let period: String
    var body: some View {
        VStack(spacing: 10) {
            HStack { Text("Performance"); Spacer(); Text("Lifetime").frame(width: 66 * max(1, textScale), alignment: .trailing); Text(period).frame(width: 50 * max(1, textScale), alignment: .trailing) }
                .appFont(size: 11, weight: .medium).foregroundStyle(Palette.secondaryText)
            ForEach(ModelActivity.metrics) { metric in
                let printIncrease = metric == .prints && (deltas[metric] ?? 0) > 0
                HStack(spacing: 8) {
                    Image(systemName: printIncrease ? "printer.fill" : metric.symbol).font(.system(size: 12)).foregroundStyle(printIncrease ? Palette.metric(.prints) : Palette.secondaryText).frame(width: 15)
                    Text(metric == .collections ? "Saves" : metric.title).appFont(size: 12, weight: printIncrease ? .semibold : .regular).foregroundStyle(printIncrease ? Palette.metric(.prints) : Palette.secondaryText)
                    Spacer(minLength: 4)
                    Text(design.counts[metric].map { $0.formatted(.number.notation(.compactName)) } ?? "—")
                        .appFont(size: 14, weight: .medium).monospacedDigit().frame(width: 66 * max(1, textScale), alignment: .trailing)
                    HStack(spacing: 2) {
                        if let change = deltas[metric] {
                            if change != 0 { Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .semibold)) }
                            Text(change > 0 ? "+\(change.formatted())" : change.formatted())
                        } else { Text("—") }
                    }.appFont(size: 12, weight: printIncrease ? .semibold : .medium).monospacedDigit().foregroundStyle(printIncrease ? Palette.metric(.prints) : color(deltas[metric])).frame(width: 50 * max(1, textScale), alignment: .trailing)
                }.padding(.horizontal, 5).padding(.vertical, 4)
                .background(printIncrease ? Palette.metric(.prints).opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.title). Lifetime \(design.counts[metric].map { $0.formatted() } ?? "unavailable"). \(period) change \(deltas[metric].map { String($0) } ?? "unavailable").")
                .help("\(metric.title): \(design.counts[metric].map { $0.formatted() } ?? "Not exposed"). \(period) change: \(deltas[metric].map { String($0) } ?? "Comparison unavailable").")
            }
        }
    }
    private func color(_ value: Int?) -> Color { guard let value else { return Palette.secondaryText }; return value > 0 ? Palette.positive : value < 0 ? Palette.negative : Palette.secondaryText }
}
