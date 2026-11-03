import SwiftUI
import MakerPulseCore

// Shared by the dashboard and isolated documentation capture. Presentation
// never changes snapshots, watch rules or latest-check comparison state.
struct WatchedModelsSection: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    var body: some View { momentum }
    var momentum: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                StudioSectionHeading(title: "Watched models", subtitle: "\(watched.count) watched · \(watched.filter { $0.lastActivityAt != nil }.count) with activity \(model.dashboardActivityWindow == .today ? "today" : "in this window")")
                Spacer()
                Button { model.destination = .models } label: { Label("All models", systemImage: "arrow.up.right") }.buttonStyle(.plain).appFont(size: 12, weight: .medium).foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { activityWindow; Spacer(); layoutControl }
                    VStack(alignment: .leading, spacing: 10) { activityWindow; layoutControl }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { sortPicker; if model.state.preferences.dashboardSort != .recent { sortBasis }; Spacer(); activityOrder }
                    VStack(alignment: .leading, spacing: 10) { sortPicker; HStack { if model.state.preferences.dashboardSort != .recent { sortBasis }; Spacer(); activityOrder } }
                }
            }
            if watched.isEmpty {
                if model.watching > 0 { Surface { HStack { ProgressView().controlSize(.small); Text("Loading observed model activity…").foregroundStyle(Palette.secondaryText); Spacer() } } }
                else { Surface { EmptyPanel(title: "Choose models to watch", detail: "Selected models and their latest growth will appear here.", symbol: "eye") } }
            } else {
                if model.state.preferences.watchedLayout == .cards {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 285 * CGFloat(max(1, textScale))), spacing: 20)], spacing: 20) {
                        ForEach(selection.visible) { DashboardModelRow(item: $0, window: model.dashboardActivityWindow) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330 * max(1, textScale)), alignment: .top)], alignment: .leading, spacing: 12) {
                        ForEach(selection.visible) { CompactWatchedModelRow(item: $0, window: model.dashboardActivityWindow) }
                    }
                }
                HStack {
                    Text("\(model.dashboardShowsAllModels ? watched.count : min(9, watched.count)) of \(watched.count) watched models").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    Spacer()
                    if watched.count > 9 { Button(model.dashboardShowsAllModels ? "Show fewer" : "Show all \(watched.count)") { model.dashboardShowsAllModels.toggle() }.buttonStyle(.bordered) }
                }
            }
        }
    }
    var activityWindow: some View {
        Picker("Activity window", selection: $model.dashboardActivityWindow) { ForEach(ModelActivityWindow.allCases) { Text($0.title).tag($0) } }
            .pickerStyle(.segmented).labelsHidden().frame(width: 285).accessibilityIdentifier("dashboard-activity-window")
    }
    var layoutControl: some View {
        WatchedLayoutControl(selection: Binding(get: { model.state.preferences.watchedLayout }, set: { model.setWatchedLayout($0) }))
            .frame(width: 175 * max(1, textScale), height: 28 * max(1, textScale))
    }
    var sortPicker: some View {
        HStack(spacing: 8) {
            Text("Sort").appFont(.callout).foregroundStyle(Palette.secondaryText)
            DashboardSortPicker(selection: Binding(get: { model.state.preferences.dashboardSort }, set: { model.setDashboardSort($0) }))
        }.frame(width: 235 * min(1.3, max(1, textScale)))
    }
    var sortBasis: some View {
        DashboardSortBasis(selection: Binding(get: { model.state.preferences.dashboardSortBasis }, set: { model.setDashboardSortBasis($0) }), window: model.dashboardActivityWindow)
            .frame(width: 285 * min(1.3, max(1, textScale)))
    }
    var activityOrder: some View {
        HStack(spacing: 5) {
            Text(model.state.preferences.dashboardSort == .recent ? "Latest change first" : "Highest first").appFont(size: 12).foregroundStyle(Palette.secondaryText)
            ContextInfo("Model activity & growth") {
                Text("Choose recent activity, prints, saves, boosts, downloads or likes. Metric sorts can use lifetime totals or gains in the selected window. Missing values sort below known values, including zero. Both layouts share the same order. Equal values use stable title/ID order.")
                Text("Actual metric changes and model inbox events determine recent-activity order. An unchanged refresh does not make a model newly active. Equal times use stable title/ID order.")
                Text("Today uses local midnight boundaries. The other windows are rolling periods. Each delta compares observations inside the selected window; a card's first observation marks partial coverage.")
                Text("A blue NEW pill means an increase was found in the latest comparable check. Hover for the separate check-to-check increase and both check times. The pill's number remains the selected period total.")
                Text("Violet printer pills emphasize print increases in the selected period. Only the separate blue NEW marker indicates a latest-check increase.")
                Text("Snapshots continue while alerts are paused. Collection saves are aggregate counts; individual collection events are unavailable.")
            }
        }
    }
    var selection: WatchedModelSelection { model.dashboardModelSelection }
    var watched: [ObservedModelActivity] { selection.all }
}
