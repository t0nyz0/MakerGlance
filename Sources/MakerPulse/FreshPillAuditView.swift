import SwiftUI
import MakerPulseCore

// Standalone visual fixture; cannot access or replace an account's state.
struct FreshPillAuditView: View {
    let fresh = LatestMetricIncrease(delta: 1, checkedAt: Date(), previousCheckAt: Date().addingTimeInterval(-600))
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pill recency · synthetic visual fixture").appFont(.headline)
            Text("The period total remains +8. Only the fresh pill reports +1 since the previous check in its tooltip.").appFont(.callout).foregroundStyle(Palette.secondaryText)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Period growth").appFont(size: 12)
                    ModelGrowthBadge(metric: .likes, delta: 8)
                    ModelGrowthBadge(metric: .downloads, delta: 2)
                    ModelGrowthBadge(metric: .prints, delta: 1)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Found in the latest comparable check").appFont(size: 12)
                    ModelGrowthBadge(metric: .likes, delta: 8, fresh: fresh)
                    ModelGrowthBadge(metric: .downloads, delta: 2)
                    ModelGrowthBadge(metric: .prints, delta: 1, fresh: fresh)
                }
            }
            Text(ModelGrowthBadge(metric: .likes, delta: 8, fresh: fresh).tooltip).appFont(size: 12).foregroundStyle(Palette.secondaryText)
            ActivityRow(activity: Activity(id: "visual-fixture-prints", date: Date(), title: "Prints increased", detail: "Synthetic visual fixture only", symbol: "printer", presentation: ActivityPresentation(metric: .prints, delta: 2, originalTimestamp: false)))
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.canvas)
    }
}
