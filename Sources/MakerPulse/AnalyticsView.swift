import SwiftUI
import MakerPulseCore

struct AnalyticsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Analytics section", selection: $model.analyticsSection) { ForEach(AnalyticsSection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 620)
                Spacer()
            }.padding(.horizontal, 26).padding(.vertical, 16)
            Divider().opacity(0.5)
            Group {
                switch model.analyticsSection {
                case .local: localTrends
                case .creator: CreatorReportView()
                case .community: FollowersView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    var localTrends: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) { Text("Local trends").appFont(size: 32, weight: .semibold); Text("Your observations, preserved on this Mac.").foregroundStyle(Palette.secondaryText) }
                HistoryMosaic(samples: model.histories["profile"] ?? [])
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Two useful timelines", systemImage: "clock.arrow.circlepath").appFont(.headline)
                        Text("Local trends start when MakerGlance first observes your account. Today indicators use local midnight boundaries, with partial coverage labeled. Creator Center contains MakerWorld's own historical reports in UTC+0; those server-day values remain separate.").appFont(.callout).foregroundStyle(Palette.secondaryText)
                        HStack { Button("Open Creator Center history") { model.analyticsSection = .creator }; Button("Browse individual model charts") { model.destination = .models } }
                    }
                }
            }.padding(26)
        }
    }
}
