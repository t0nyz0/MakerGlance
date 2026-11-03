import SwiftUI
import Charts
import MakerPulseCore

struct CreatorReportView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    @State private var scope: CreatorScope = .models
    @State private var start = CreatorPeriod().start
    @State private var end = CreatorPeriod().end
    @State private var metric: CreatorMetric = .downloads
    @State private var search = ""
    @State private var descending = true
    var report: CreatorReport? { model.state.creatorReport }
    var rows: [CreatorRow] {
        (report?.rows ?? []).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.modelTitle?.localizedCaseInsensitiveContains(search) ?? false) }.sorted {
            let a = $0.metrics[metric], b = $1.metrics[metric]
            if a == b { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            guard let a else { return false }; guard let b else { return true }
            return descending ? a > b : a < b
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Creator reports").appFont(size: 32, weight: .semibold)
                    Text("MakerWorld's authenticated period analytics, saved on your Mac.").foregroundStyle(Palette.secondaryText)
                }
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        (textScale > 1.15 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout())) {
                            Picker("Report scope", selection: $scope) { ForEach(CreatorScope.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 260 * max(1, textScale))
                            if textScale <= 1.15 { Spacer() }
                            HStack { ForEach([7,30,90], id: \.self) { days in Button("\(days) days") { let period = CreatorPeriod(days: days); start = period.start; end = period.end }.fixedSize() } }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 10) { DatePicker("From", selection: $start, in: ...end, displayedComponents: .date); DatePicker("Through", selection: $end, in: start...CreatorPeriod().end, displayedComponents: .date) }
                            HStack { Text("UTC+0").appFont(.caption, weight: .semibold).foregroundStyle(Palette.accent); Spacer(); Button { Task { await load() } } label: { Label("Load report", systemImage: "arrow.clockwise") }.buttonStyle(PrimaryButtonStyle()).disabled(model.creatorLoading || !model.accountSessionAvailable) }
                        }.environment(\.timeZone, CreatorPeriod.calendar.timeZone).environment(\.calendar, CreatorPeriod.calendar)
                        HStack { if model.creatorLoading { ProgressView().controlSize(.small) }; Text(model.creatorStatus).appFont(size: 12).foregroundStyle(Palette.secondaryText).textSelection(.enabled) }
                        Text("Dates are inclusive UTC calendar dates, as on Creator Center. These are period results, separate from lifetime profile totals and local-time Today indicators. The default ends yesterday.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        if model.restoringSession { Text("Complete the macOS Keychain prompt to use your existing saved session.").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                        else if !model.accountSessionAvailable { Button("Connect in Settings") { model.destination = .settings } }
                    }
                }
                if let report {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(report.scope.title) · \(report.period.startText) – \(report.period.endText)").appFont(.title, weight: .semibold)
                            Text("UTC+0 · fetched \(report.fetchedAt.formatted(date: .abbreviated, time: .shortened)) · \(report.rows.count) returned rows").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Text("SAVED REPORT").appFont(.caption, weight: .semibold).foregroundStyle(Palette.accent)
                    }
                    HStack {
                        TextField("Search report", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                        Spacer()
                        Picker("Rank by", selection: $metric) { ForEach(report.availableMetrics) { Text($0.title).tag($0) } }.frame(width: 270)
                        Button { descending.toggle() } label: { Image(systemName: descending ? "arrow.down" : "arrow.up") }.help(descending ? "Largest first" : "Smallest first")
                    }
                    if let history = report.history, !history.isEmpty { CreatorHistoryMosaic(report: report) }
                    if let status = report.historyStatus { Text(status).appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                    if !rows.isEmpty {
                        Surface {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("\(metric.title) · leading returned rows").appFont(.headline)
                                Chart(Array(rows.prefix(8))) { row in
                                    if let value = row.metrics[metric] {
                                        BarMark(x: .value(metric.title, NSDecimalNumber(decimal: value).doubleValue), y: .value("Model", String(row.title.prefix(35)) + " · " + row.id)).foregroundStyle(Palette.accent.gradient).cornerRadius(4)
                                    }
                                }.frame(height: CGFloat(min(8, rows.count) * 34 + 20))
                            }
                        }
                        Surface {
                            LazyVStack(spacing: 0) {
                                HStack { Text(report.scope == .models ? "Model" : "Print profile"); Spacer(); Text(metric.title) }.appFont(.caption, weight: .semibold).foregroundStyle(Palette.secondaryText).padding(.bottom, 10)
                                ForEach(rows) { row in
                                    HStack(spacing: 14) {
                                        RemoteImage(url: row.cover).frame(width: 72, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 5) { Text(row.title).appFont(.callout, weight: .medium).lineLimit(2); if let parent = row.modelTitle { Text(parent).appFont(size: 12).foregroundStyle(Palette.secondaryText).lineLimit(1) } }
                                        Spacer()
                                        Text(row.metrics[metric].map(DisplayNumber.decimal) ?? "Unavailable").appFont(.title3, design: .default, weight: .semibold).monospacedDigit()
                                        Link(destination: URL(string: "https://makerworld.com/en/models/\(row.modelID)\(report.scope == .profiles ? "#profileId-\(row.id)" : "")")!) { Image(systemName: "arrow.up.right") }.help("Open in MakerWorld")
                                    }.padding(.vertical, 12)
                                    Divider().opacity(0.5)
                                }
                            }
                        }
                    } else { Surface { EmptyPanel(title: "No rows in this report", detail: "Try another search or date range. Missing metrics are kept unavailable.", symbol: "chart.bar") } }
                    Text("Global and China point fields remain separate. Earned points in a report are not your current balance. API period tables and server daily histories have UTC dates; neither supplies original individual follower dates.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                } else { Surface { EmptyPanel(title: "Load your first Creator Center report", detail: "Choose models or print profiles and a UTC date range. Your last verified report will remain available offline.", symbol: "chart.bar.xaxis") } }
            }.padding(30)
        }.onChange(of: report?.availableMetrics) { _, metrics in if let metrics, !metrics.contains(metric), let first = metrics.first { metric = first } }
    }
    private func load() async {
        do { await model.loadCreator(scope: scope, period: try CreatorPeriod(start: start, end: end)) }
        catch { model.creatorStatus = error.localizedDescription }
    }
}
