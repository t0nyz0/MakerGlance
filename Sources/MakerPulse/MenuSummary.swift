import SwiftUI
import AppKit
import MakerPulseCore

struct MenuSummary: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    var balance: RewardBalance? { model.state.account?.balance?.balance }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: AppGlyph.menu).renderingMode(.template).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MakerGlance").appFont(size: 15, weight: .semibold)
                    if model.isDemo { Text("DEMO · Fictional activity").appFont(size: 11, weight: .medium).foregroundStyle(Palette.accent) }
                    Text("@\(model.state.preferences.handle) · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Dev")").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                if model.isRefreshing || model.restoringSession { ProgressView().controlSize(.small).accessibilityLabel("Refreshing analytics or waiting for session access") }
                VStack(alignment: .trailing, spacing: 5) {
                    Button { model.showMain(.activity) } label: {
                        Text(model.menuStatus.badge.map { $0 + " unread" } ?? "All read")
                    }
                    .buttonStyle(.plain).appFont(.caption, weight: .medium).foregroundStyle(Palette.accent)
                    .help("Open activity inbox").accessibilityIdentifier("menu-open-inbox")
                    Button("Mark all read") { model.markAllRead() }
                        .appFont(size: 11).disabled(model.unread == 0)
                        .help("Mark all activity read in MakerGlance on this Mac")
                        .accessibilityIdentifier("menu-mark-all-read")
                }
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    status
                    VStack(alignment: .leading, spacing: 11) {
                        HStack { Text("Today").appFont(.headline); Spacer(); Text("Local day · observed coverage").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                        HStack(spacing: 14) { ForEach([Metric.likes, .downloads, .boosts]) { metric in stat(metric) } }
                        HStack {
                            Button { model.analyticsSection = .community; model.showMain(.creator) } label: { Label("\(model.state.profile?.counts.followers?.formatted() ?? "—") followers", systemImage: "person.2") }
                            Spacer()
                            Button { model.showMain(.models) } label: { Label("\(model.watching) watched", systemImage: "eye") }
                        }.buttonStyle(.plain).appFont(.caption, weight: .medium).foregroundStyle(Palette.accent)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Rewards & wallet").appFont(.headline); Spacer(); Button("Details") { model.showMain(.rewards) }.appFont(size: 12) }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            reward(.exclusivePoints, title: "Exclusive points"); reward(.regularPoints, title: "Regular points")
                            reward(.cashAvailable, title: "Ready to transfer"); reward(.cashEstimate, title: "Cash estimate")
                        }
                        Text(model.restoringSession ? "Saved balances · waiting for Keychain access" : (model.state.account?.balance?.date).map { "Verified \($0.formatted(date: .omitted, time: .shortened)) · cash estimate and wallet funds are separate" } ?? "Connect in Settings for private balances").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    }
                    Divider()
                    HStack { Text("Recent activity").appFont(.headline); Spacer(); Button("Open inbox") { model.showMain(.activity) }.appFont(size: 12) }
                    if model.state.activity.isEmpty { Text("Your initial import stays quiet. New activity will appear here.").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                    ForEach(model.state.activity.prefix(2)) { item in
                        if ActivityLinks.followerProfile(for: item, followers: model.state.followers) != nil {
                            ActivityRow(activity: item, compact: true)
                        } else {
                            Button { model.showMain(item.modelID == nil ? .activity : .models, modelID: item.modelID) } label: { ActivityRow(activity: item, compact: true) }.buttonStyle(.plain).help("Open update details")
                        }
                    }
                }.padding(18)
            }.frame(height: 370)
            Divider()
            VStack(spacing: 12) {
                HStack {
                    Button { Task { await model.refresh() } } label: { Label(model.isRefreshing ? "Refreshing…" : "Refresh now", systemImage: "arrow.clockwise") }.disabled(model.isRefreshing).accessibilityIdentifier("menu-refresh")
                    Spacer()
                    Button("Open dashboard") { model.showMain() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("menu-open-dashboard")
                }
                HStack {
                    Button { model.showMain(.settings) } label: { Label("Settings", systemImage: "slider.horizontal.3") }.buttonStyle(.plain).accessibilityIdentifier("menu-settings")
                    Spacer()
                    AppearanceMenu().fixedSize()
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
                }.appFont(size: 12)
            }.padding(16)
        }.frame(width: 420 * max(1, textScale)).background(Palette.canvas).background(NativeControlTypography(scale: textScale))
    }
    var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.menuStatus.attention {
                Label("Updates need attention", systemImage: "exclamationmark.circle").appFont(.callout, weight: .semibold).foregroundStyle(Palette.orange)
                Text((model.issues + model.privateIssues).first ?? "Open Settings to check the connection.").appFont(size: 12).foregroundStyle(Palette.secondaryText).lineLimit(3)
            } else if model.restoringSession {
                Label("Waiting for saved-session access", systemImage: "key.horizontal").appFont(.caption, weight: .medium).foregroundStyle(Palette.accent)
            } else if model.isRefreshing {
                Label(model.privateSyncing ? "Updating account activity & rewards" : "Updating profile & models", systemImage: "arrow.triangle.2.circlepath").appFont(.caption, weight: .medium).foregroundStyle(Palette.accent)
            } else {
                Label(model.state.lastProfileSync.map { "Public data updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Waiting for first snapshot", systemImage: "clock").appFont(size: 12).foregroundStyle(Palette.secondaryText)
            }
            if let next = model.nextRefreshDate { Text("Next check around \(next.formatted(date: .omitted, time: .shortened)) · while MakerGlance is running").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
        }
    }
    func stat(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.state.profile?.counts[metric].map { $0.formatted() } ?? "—").appFont(size: 24, weight: .semibold).monospacedDigit()
            Text(metric.title).appFont(size: 12).foregroundStyle(Palette.secondaryText)
            GrowthIndicator(growth: model.profileDayGrowth(metric), compact: true, metric: metric)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func reward(_ metric: RewardMetric, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appFont(size: 12).foregroundStyle(Palette.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 4) { Text(balance?[metric].map(DisplayNumber.decimal) ?? "—").appFont(size: 18, weight: .semibold).monospacedDigit(); if metric.isCash, let currency = balance?.currency(for: metric) { Text(currency).appFont(size: 12).foregroundStyle(Palette.secondaryText) } }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}
