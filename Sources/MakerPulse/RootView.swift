import SwiftUI
import MakerPulseCore

struct RootView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        GeometryReader { bounds in
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: AppGlyph.applicationIcon).resizable().scaledToFit().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) { Text("MakerGlance").appFont(size: 17, weight: .semibold); Text("Creator analytics").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 28)
                Text("Workspace").appFont(size: 12, weight: .medium).foregroundStyle(Palette.secondaryText).padding(.horizontal, 22).padding(.bottom, 10)
                ForEach(Destination.sidebar) { item in
                    Button {
                        model.destination = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).frame(width: 20).foregroundStyle(model.destination.sidebarParent == item ? Palette.accent : Palette.secondaryText)
                            Text(item.rawValue)
                            Spacer()
                            if item == .overview && model.unread > 0 { Text("\(model.unread)").appFont(.caption, weight: .bold).padding(.horizontal, 6).padding(.vertical, 2).background(Palette.accent.opacity(0.15), in: Capsule()) }
                            if item == .models && !model.state.models.isEmpty { Text("\(model.state.models.count)").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                        }.appFont(size: 13, weight: model.destination.sidebarParent == item ? .semibold : .regular).padding(.horizontal, 13).padding(.vertical, 11)
                            .foregroundStyle(model.destination.sidebarParent == item ? Palette.accent : Palette.secondaryText)
                            .background(model.destination.sidebarParent == item ? Palette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 4)
                        .accessibilityLabel(item.rawValue).accessibilityAddTraits(model.destination.sidebarParent == item ? .isSelected : [])
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: model.menuStatus.attention ? "exclamationmark.circle" : "internaldrive").foregroundStyle(model.menuStatus.attention ? Palette.orange : Palette.secondaryText)
                    Text(model.menuStatus.attention ? "Needs attention" : model.isRefreshing ? "Syncing your studio" : "Stored on this Mac").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                }.padding(.horizontal, 20).padding(.bottom, 20)
                HStack(spacing: 10) {
                    RemoteImage(url: model.state.profile?.avatar, symbol: "person.crop.circle").frame(width: 31, height: 31).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) { Text("@\(model.state.preferences.handle)").appFont(.callout, weight: .semibold); Text("MakerWorld creator").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
                }.padding(.horizontal, 20).padding(.bottom, 22)
            }.background(Palette.sidebar).navigationSplitViewColumnWidth(min: 220 * min(1.25, textScale), ideal: 220 * min(1.25, textScale), max: 320)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    if !Destination.sidebar.contains(model.destination) { Button { model.destination = model.destination.sidebarParent } label: { Label(model.destination.sidebarParent.rawValue, systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Palette.secondaryText) }
                    if !Destination.sidebar.contains(model.destination) { Text(model.destination.rawValue).appFont(.callout, weight: .semibold) }
                    Spacer()
                    if model.isRefreshing { ProgressView().controlSize(.small) }
                    Text(model.privateSyncing ? "Updating account activity…" : model.syncing ? model.status : lastSync).appFont(size: 12).foregroundStyle(Palette.secondaryText).lineLimit(1)
                    Button { model.destination = .activity } label: { HStack(spacing: 5) { Image(systemName: model.unread > 0 ? "bell.badge" : "bell"); if model.unread > 0 { Text("\(model.unread)").monospacedDigit() } } }.help("Open activity inbox · \(model.unread) unread").accessibilityLabel("Activity inbox, \(model.unread) unread")
                    AppearanceMenu().fixedSize()
                    Button { Task { await model.refresh() } } label: { if textScale > 1.2 { Image(systemName: "arrow.clockwise") } else { Label("Refresh", systemImage: "arrow.clockwise") } }.disabled(model.isRefreshing || !model.loaded).help("Refresh all analytics (⌘R)")
                }.padding(.horizontal, 30).padding(.vertical, 12)
                Divider().opacity(0.3)
                if model.isDemo {
                    Label("DEMO · Fictional creator, models and activity · No account connected", systemImage: "testtube.2")
                        .appFont(size: 12, weight: .medium).foregroundStyle(Palette.accent).padding(.horizontal, 30).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Palette.accent.opacity(0.06))
                }
                if !model.issues.isEmpty {
                    DisclosureGroup {
                        ForEach(model.issues, id: \.self) { Text($0).appFont(size: 12).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    } label: { Label("Some data could not be updated. Your history is preserved.", systemImage: "exclamationmark.triangle").appFont(size: 12) }
                    .padding(12).background(Palette.orange.opacity(0.1)).foregroundStyle(Palette.orange)
                }
                Group {
                    switch model.destination {
                    case .overview: DashboardView()
                    case .models: ModelsView()
                    case .myPrints: MyPrintsView()
                    case .creator: AnalyticsView()
                    case .followers: FollowersView()
                    case .activity: ActivityView()
                    case .rewards: RewardsView()
                    case .settings: PreferencesView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(Palette.canvas)
        }.frame(width: bounds.size.width, height: bounds.size.height)
        }
        .sheet(item: $model.selectedModel) { design in ModelDetailView(design: model.state.models.first { $0.id == design.id } ?? design).environmentObject(model) }
        .preferredColorScheme(model.effectiveColorScheme)
        .background(NativeControlTypography(scale: textScale, refreshID: model.destination.rawValue + model.analyticsSection.rawValue))
        .onAppear { model.openWindowAction = { openWindow(id: "main") } }
    }
    var lastSync: String {
        guard let date = model.state.lastProfileSync else { return "Waiting for first sync" }
        return "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }
}

struct ActivityView: View {
    @EnvironmentObject var model: AppModel
    @State private var unreadOnly = false
    var activities: [Activity] { model.state.activity.filter { !unreadOnly || !$0.isRead } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) { Text("Activity").appFont(size: 32, weight: .semibold); Text("Milestones, new followers, and changes you chose to watch.").foregroundStyle(Palette.secondaryText) }
                    Spacer()
                    Toggle("Unread only", isOn: $unreadOnly).toggleStyle(.switch).controlSize(.small)
                    Button("Mark all read") { model.markAllRead() }.disabled(model.unread == 0)
                    Button("Clear all") { model.clearActivity() }.disabled(model.state.activity.isEmpty)
                    Button { model.destination = .settings } label: { Image(systemName: "gearshape") }.help("Notification settings")
                }
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Label("MakerWorld account inbox", systemImage: "tray").appFont(.headline); Spacer(); if model.privateSyncing { ProgressView().controlSize(.small) }; Button("Connection settings") { model.destination = .settings }.buttonStyle(.plain).foregroundStyle(Palette.accent) }
                        Text(model.inboxStatus).appFont(size: 12).foregroundStyle(Palette.secondaryText)
                        Text("Comments, replies, mentions and model events are fetched read-only. Mark all read affects only this app. Initial account imports are quiet; event IDs are remembered across restarts.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
                    }
                }
                Surface {
                    if activities.isEmpty { EmptyPanel(title: "You're all caught up", detail: "New activity appears after your baseline when monitored counts grow. No historical alerts are sent on first import.", symbol: "bell.badge") }
                    else { LazyVStack(spacing: 0) { ForEach(activities) { item in
                        HStack(alignment: .top) {
                            ActivityRow(activity: item)
                            Button { model.clearActivity(item.id) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).help("Clear notification").accessibilityLabel("Clear " + item.title)
                        }
                        Divider().opacity(0.5) } } }
                }
            }.padding(30)
        }
    }
}
