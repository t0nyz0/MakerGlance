import SwiftUI
import MakerPulseCore

enum ModelSort: String, CaseIterable, Identifiable {
    case growth = "Recent activity", likes = "Most liked", downloads = "Most downloaded", boosts = "Most boosted", newest = "Newest published", name = "Name"
    var id: String { rawValue }
}

struct ModelsView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var sort: ModelSort = .growth
    var filter: ModelWatchFilter { model.auditWatchFilter ?? model.state.preferences.modelFilter ?? .all }
    var designs: [Design] {
        let ranks = Dictionary(uniqueKeysWithValues: (model.modelActivityReports[.today] ?? []).enumerated().map { ($0.element.id, $0.offset) })
        return model.state.models.filter { design in
            return (search.isEmpty || design.title.localizedCaseInsensitiveContains(search)) && filter.includes(design, watches: model.state.watches)
        }.sorted { a, b in
            switch sort {
            case .growth:
                return (ranks[a.id] ?? Int.max) == (ranks[b.id] ?? Int.max) ? a.id < b.id : (ranks[a.id] ?? Int.max) < (ranks[b.id] ?? Int.max)
            case .likes: return (a.counts.likes ?? -1) > (b.counts.likes ?? -1)
            case .downloads: return (a.counts.downloads ?? -1) > (b.counts.downloads ?? -1)
            case .boosts: return (a.counts.boosts ?? -1) > (b.counts.boosts ?? -1)
            case .newest: return (a.publishedAt ?? .distantPast) > (b.publishedAt ?? .distantPast)
            case .name: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Models").appFont(size: 32, weight: .semibold)
                        Text("\(model.state.models.count) public designs · \(model.watching) watched").appFont(.callout).foregroundStyle(Palette.secondaryText)
                    }; Spacer()
                    ContextInfo("Watching and model alerts") { Text("All models begin watched, including newly discovered models. Pausing disables metric alerts while snapshots continue. Boost alerts start enabled; choose each model’s alert types in its details. Account comments and mentions have separate preferences in Settings.") }
                }
                (textScale > 1.15 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(spacing: 14))) {
                    WatchFilterControl(selection: Binding(get: { filter }, set: { if model.auditWatchFilter != nil { model.auditWatchFilter = $0 } else { model.state.preferences.modelFilter = $0; model.save() } }), counts: Dictionary(uniqueKeysWithValues: ModelWatchFilter.allCases.map { ($0, $0.count(model.state.models, watches: model.state.watches)) })).frame(width: 330 * min(1.2, textScale), height: 28 * max(1, textScale))
                    if textScale <= 1.15 { Spacer() }
                    Picker("Sort models", selection: $sort) { ForEach(ModelSort.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 160 * max(1, textScale))
                }
                HStack {
                    TextField("Search models", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320).accessibilityLabel("Search models")
                    Text("\(designs.count) shown").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    Spacer()
                    Menu("Watch actions") { Button("Watch all models") { model.setAllWatches(enabled: true) }; Button("Pause all metric alerts") { model.setAllWatches(enabled: false) } }
                }
                if designs.isEmpty { EmptyPanel(title: filter == .paused && search.isEmpty ? "No paused models" : "No models found", detail: search.isEmpty ? "All models initially start watched. Use a model's eye button to pause its alerts. History continues while paused." : "Try a different model name.", symbol: "cube.transparent") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 285 * CGFloat(max(1, textScale))), spacing: 20)], spacing: 20) {
                    ForEach(designs) { ModelCard(design: $0) }
                }
                Text("Today uses local midnight. Hover a value for the exact count; open a model for its charts and alert controls.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
            }.padding(30)
        }
    }
}

struct ModelCard: View {
    @EnvironmentObject var model: AppModel
    let design: Design
    var watched: Bool { model.state.watches[design.id]?.enabled ?? true }
    var deltas: [Metric: Int] { Dictionary(uniqueKeysWithValues: ModelActivity.metrics.compactMap { metric in model.dayGrowth(for: design, metric: metric).value.map { (metric, $0) } }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.selectedModel = design } label: {
                RemoteImage(url: design.cover, pixelWidth: 640).frame(height: 200).frame(maxWidth: .infinity).clipped()
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach([Metric.prints, .likes]) { metric in
                                if let growth = deltas[metric], growth > 0 {
                                    ModelGrowthBadge(metric: metric, delta: growth, fresh: model.latestModelIncreases[design.id]?[metric])
                                }
                            }
                        }.padding(12)
                    }
            }.buttonStyle(.plain).accessibilityLabel("View \(design.title)")
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Button { model.selectedModel = design } label: { Text(design.title).appFont(size: 15, weight: .semibold).foregroundStyle(.primary).lineLimit(2).frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading) }.buttonStyle(.plain)
                    Button { model.updateWatch(design.id) { $0.enabled.toggle() } } label: {
                        Image(systemName: watched ? "eye.fill" : "eye.slash").font(.system(size: 13)).foregroundStyle(watched ? Palette.accent : Palette.secondaryText).frame(width: 32, height: 32).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).help(watched ? "Pause alerts for this model" : "Watch this model").accessibilityLabel("\(watched ? "Pause" : "Watch") \(design.title)")
                }
                ModelMetricRows(design: design, deltas: deltas, period: "Today")
                HStack {
                    Label(watched ? "Watching" : "Alerts paused", systemImage: watched ? "eye" : "eye.slash")
                    Spacer()
                    if let date = model.dayGrowth(for: design, metric: .downloads).baselineDate { Text("From \(date.formatted(date: .omitted, time: .shortened))").help("Today's first download observation. Other metrics have their own first available observation. No midnight values are estimated.") }
                    else { Text("Awaiting baseline") }
                }.appFont(size: 11).foregroundStyle(Palette.secondaryText).padding(.top, 2)
            }.padding(18)
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct ModelDetailView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let design: Design
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Model insights").appFont(.headline); Spacer(); Link("Open in MakerWorld ↗", destination: URL(string: "https://makerworld.com/en/models/\(design.id)")!).appFont(size: 12).disabled(model.isDemo); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.secondaryText) }.buttonStyle(.plain).accessibilityLabel("Close model insights") }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 22) {
                        RemoteImage(url: design.cover).frame(width: 250, height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 14) {
                            Text(design.title).appFont(size: 24, weight: .bold, design: .default)
                            if let date = design.publishedAt { Text("Published \(date.formatted(date: .abbreviated, time: .omitted))").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                            Toggle("Watch this model", isOn: rule(\.enabled)).toggleStyle(.switch)
                            Text("History continues while alerts are paused.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150 * max(1, textScale)))], spacing: 12) { ForEach([Metric.likes, .downloads, .prints, .boosts, .collections]) { MetricCard(metric: $0, value: design.counts[$0], growth: model.dayGrowth(for: design, metric: $0)) } }
                    HistoryMosaic(samples: model.histories["model:\(design.id)"] ?? [], metrics: [.likes, .downloads, .prints, .boosts, .collections])
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Alert preferences").appFont(.headline)
                            Text("Choose which observed increases appear in Activity and local notifications.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                            HStack(spacing: 25) {
                                Toggle("Boosts", isOn: rule(\.boosts))
                                Toggle("Likes", isOn: rule(\.likes))
                                Toggle("Downloads", isOn: rule(\.downloads))
                                Toggle("Collections", isOn: rule(\.collections))
                            }.toggleStyle(.checkbox).disabled(!(model.state.watches[design.id]?.enabled ?? true))
                            Text("Collections are aggregate counts; individual collection events and identities are unavailable.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        }
                    }
                }.padding(24)
            }
        }.frame(width: 850, height: 760).background(Palette.canvas)
    }
    func rule(_ key: WritableKeyPath<WatchRule, Bool>) -> Binding<Bool> {
        Binding(get: { (model.state.watches[design.id] ?? WatchRule())[keyPath: key] }, set: { value in model.updateWatch(design.id) { $0[keyPath: key] = value } })
    }
}
