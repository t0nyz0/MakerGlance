import AppKit
import SwiftUI
import MakerPulseCore

@MainActor private final class FilterAuditState: ObservableObject {
    @Published var original = "All models"
    @Published var selected: ModelWatchFilter = .all
    @Published var firstWatched = true
    let models = [Design(id: "a", title: "Fixture A", counts: Counts()), Design(id: "b", title: "Fixture B", counts: Counts())]
    var watches: [String: WatchRule] { var first = WatchRule(), second = WatchRule(); first.enabled = firstWatched; second.enabled = false; return ["a": first, "b": second] }
    var counts: [ModelWatchFilter: Int] { Dictionary(uniqueKeysWithValues: ModelWatchFilter.allCases.map { ($0, $0.count(models, watches: watches)) }) }
}
private struct FilterAuditView: View {
    @ObservedObject var state: FilterAuditState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Isolated native control verification · no account settings changed").appFont(.headline)
            Picker("Original implicit String selection", selection: $state.original) { ForEach(["All models", "Watched", "Paused"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 330)
            WatchFilterControl(selection: $state.selected, counts: state.counts).frame(width: 330, height: 28)
            Text("Selected: \(state.selected.title) · \(state.counts[state.selected] ?? 0) matching fixture models").appFont(.callout)
        }.padding(20).frame(width: 700, height: 210).background(Palette.surface)
    }
}

@MainActor enum NativeControlAudit {
    static func run(directory: URL) async throws -> [String: Bool] {
        let fixture = FilterAuditState()
        let host = NSHostingView(rootView: FilterAuditView(state: fixture).preferredColorScheme(.light))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 210)
        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(200))
        func segments(_ view: NSView) -> [NSSegmentedControl] { (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap(segments) }
        let controls = segments(host)
        guard let native = controls.first(where: { $0.identifier?.rawValue == "model-watch-filter" }) else { throw PulseError.incomplete("native watch filter control") }
        let original = controls.first { $0 !== native }
        func select(_ index: Int, on control: NSSegmentedControl?) -> Bool {
            guard let control, let action = control.action else { return false }
            control.selectedSegment = index; return control.sendAction(action, to: control.target)
        }
        let originalDelivered = select(2, on: original)
        try await Task.sleep(for: .milliseconds(100))
        let originalChanged = fixture.original == "Paused"
        let pausedDelivered = select(2, on: native)
        try await Task.sleep(for: .milliseconds(100))
        let pausedCorrect = fixture.selected == .paused && fixture.counts[.paused] == 1
        fixture.firstWatched = false
        try await Task.sleep(for: .milliseconds(100))
        let moved = fixture.counts[.paused] == 2 && fixture.counts[.watched] == 0
        fixture.firstWatched = true
        let watchedDelivered = select(1, on: native)
        try await Task.sleep(for: .milliseconds(100))
        let watchedCorrect = fixture.selected == .watched && fixture.counts[.watched] == 1
        _ = select(0, on: native)
        let allCorrect = fixture.selected == .all && fixture.counts[.all] == 2
        guard pausedDelivered, pausedCorrect, moved, watchedDelivered, watchedCorrect, allCorrect else { throw PulseError.incomplete("watch filter interaction") }
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: rep); try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("watch-controls-fixture.png")) }
        return ["originalControlFound": original != nil, "originalActionDelivered": originalDelivered, "originalSelectionChanged": originalChanged,
            "nativePausedClick": pausedDelivered && pausedCorrect, "fixtureWatchMovement": moved, "nativeWatchedClick": watchedDelivered && watchedCorrect, "nativeAllClick": allCorrect]
    }
}
