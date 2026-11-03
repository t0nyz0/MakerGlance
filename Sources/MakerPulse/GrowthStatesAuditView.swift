import SwiftUI
import MakerPulseCore

// Isolated rendering fixture for the explicit --ui-audit mode. This view does
// not receive AppModel, open a database, or replace any real account state.
struct GrowthStatesAuditView: View {
    let metrics: [Metric] = [.likes, .downloads, .prints, .boosts]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Synthetic visual QA · growth and unavailable states").appFont(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(metrics) { metric in
                    MetricCard(metric: metric, value: current[metric], growth: DayGrowth.evaluate(metric: metric, baseline: Sample(date: Date().addingTimeInterval(-60), counts: Counts(likes: 120, prints: 10, boosts: 7)), current: current), compact: true)
                }
            }
        }.padding(20).background(Palette.canvas)
    }
    var current: Counts { Counts(likes: 110, prints: 10, boosts: 9) }
}
