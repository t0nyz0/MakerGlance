import SwiftUI
import MakerPulseCore

struct FollowersView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var sort = "First observed"
    @State private var includeDeparted = false
    var followers: [Follower] {
        model.state.followers.filter { follower in
            (includeDeparted || follower.isFollowing) && (search.isEmpty || follower.name.localizedCaseInsensitiveContains(search) || follower.handle.localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            if sort == "Name" { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            if sort == "Handle" { return a.handle.localizedStandardCompare(b.handle) == .orderedAscending }
            let left = a.firstObservedAt ?? .distantPast; let right = b.firstObservedAt ?? .distantPast
            return left == right ? a.handle.localizedStandardCompare(b.handle) == .orderedAscending : left > right
        }
    }
    var body: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) { Text("Your community").appFont(size: 32, weight: .semibold); Text("\(model.activeFollowers.count.formatted()) followers in your local library").appFont(.callout).foregroundStyle(Palette.secondaryText) }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) { Text("\(model.state.followers.filter { !$0.baseline }.count)").appFont(size: 24, weight: .semibold, design: .default).foregroundStyle(Palette.accent); Text("first seen since baseline").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.badge.questionmark").font(.title3).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("An honest timeline").appFont(.callout, weight: .semibold)
                    Text("MakerWorld does not provide follow dates. Existing followers are dated unknown. New followers get the time MakerGlance first observes them, not their original follow date.").appFont(size: 12).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
            if textScale > 1.15 { VStack(alignment: .leading, spacing: 14) { followerSearch; HStack { followerFilters; Spacer() } } }
            else { HStack(spacing: 15) { followerSearch; Spacer(); followerFilters } }
            Table(followers) {
                TableColumn("Follower") { follower in
                    if let url = ActivityLinks.makerProfile(handle: follower.handle) {
                        Link(destination: url) { followerIdentity(follower) }
                            .buttonStyle(.plain).disabled(model.isDemo)
                            .help("Open \(follower.handle) on MakerWorld")
                            .accessibilityIdentifier("follower-profile-" + follower.id)
                    } else { followerIdentity(follower) }
                }.width(max(160, (geometry.size.width - 285) * 0.58))
                TableColumn("First observed") { follower in
                    if let date = follower.firstObservedAt { Text(date.formatted(date: .abbreviated, time: .shortened)).appFont(size: 12).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
                    else { Text("Unknown · baseline follower").appFont(size: 12).foregroundStyle(Palette.secondaryText).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
                }.width(max(140, (geometry.size.width - 285) * 0.42))
                TableColumn("Status") { follower in
                    Label(follower.isFollowing ? "Following" : "No longer observed", systemImage: follower.isFollowing ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.minus")
                        .appFont(size: 12).foregroundStyle(follower.isFollowing ? Palette.accent : .secondary).lineLimit(2)
                }.width(120 * min(1.25, textScale))
                TableColumn("") { follower in
                    if let url = ActivityLinks.makerProfile(handle: follower.handle) {
                        Link(destination: url) { Image(systemName: "arrow.up.right").foregroundStyle(Palette.secondaryText) }.help("Open \(follower.handle) on MakerWorld").disabled(model.isDemo)
                    }
                }.width(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay { if followers.isEmpty { EmptyPanel(title: model.syncing ? "Importing your followers" : "No followers to show", detail: search.isEmpty ? "A complete paginated sync will establish your baseline." : "Try another name or handle.", symbol: "person.2") } }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack { Text("\(followers.count.formatted()) shown · deduplicated by account ID"); Spacer(); if let date = model.state.lastFollowerSync { Text("Last complete sync \(date.formatted(date: .abbreviated, time: .shortened))") } }.appFont(size: 12).foregroundStyle(Palette.secondaryText)
        }.padding(30)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
    }
    func followerIdentity(_ follower: Follower) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: follower.avatar, symbol: "person.fill").frame(width: 32, height: 32).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) { Text(follower.name).appFont(.callout, weight: .medium); Text("@\(follower.handle)").appFont(size: 12).foregroundStyle(Palette.secondaryText) }
        }.frame(maxWidth: .infinity, minHeight: 42 * max(1, textScale), alignment: .leading)
            .padding(.vertical, 5).contentShape(Rectangle())
    }
    var followerSearch: some View {
        NativeSearchField(text: $search, placeholder: "Search name or handle", accessibilityLabel: "Search followers", identifier: "followers-search")
            .frame(maxWidth: 300)
    }
    var followerFilters: some View {
        HStack(spacing: 15) {
            Toggle("Include departed", isOn: $includeDeparted).toggleStyle(.checkbox).appFont(size: 12).fixedSize()
            Picker("Sort followers", selection: $sort) { Text("First observed").tag("First observed"); Text("Name").tag("Name"); Text("Handle").tag("Handle") }.labelsHidden().frame(width: 160 * max(1, textScale))
        }
    }

}
