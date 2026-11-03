import AppKit
import MakerPulseCore

@MainActor enum DashboardSortAudit {
    static func run(model: AppModel, view: NSView, directory: URL) async throws -> [String: Bool] {
        let oldSort = model.state.preferences.watchedModelSort, oldBasis = model.state.preferences.watchedSortBasis
        let oldWindow = model.dashboardActivityWindow, oldLayout = model.state.preferences.watchedModelLayout
        let oldModels = model.state.models, oldWatches = model.state.watches
        defer {
            model.state.preferences.watchedModelSort = oldSort; model.state.preferences.watchedSortBasis = oldBasis
            model.state.preferences.watchedModelLayout = oldLayout; model.dashboardActivityWindow = oldWindow; model.save()
        }
        model.destination = .overview
        try await Task.sleep(for: .milliseconds(350))
        func find<T: NSView>(_ type: T.Type, _ id: String, _ node: NSView) -> T? {
            if let match = node as? T, match.identifier?.rawValue == id { return match }
            return node.subviews.compactMap { find(type, id, $0) }.first
        }
        guard let picker = find(NSPopUpButton.self, "dashboard-model-sort", view), let action = picker.action else { throw PulseError.incomplete("native dashboard sort menu") }
        for (index, sort) in WatchedModelSort.allCases.enumerated() {
            picker.selectItem(at: index)
            guard picker.sendAction(action, to: picker.target) else { throw PulseError.incomplete("native dashboard sort action") }
            try await Task.sleep(for: .milliseconds(100))
            guard model.state.preferences.dashboardSort == sort else { throw PulseError.incomplete("dashboard sort binding") }
        }
        picker.selectItem(at: 1); _ = picker.sendAction(action, to: picker.target)
        try await Task.sleep(for: .milliseconds(150))
        guard let basis = find(NSSegmentedControl.self, "dashboard-sort-basis", view), let basisAction = basis.action else { throw PulseError.incomplete("native dashboard sort basis") }
        basis.selectedSegment = 1; _ = basis.sendAction(basisAction, to: basis.target)
        model.dashboardActivityWindow = .day
        try await Task.sleep(for: .milliseconds(200))
        let stored = try await model.auditStoredDashboardSort()
        guard stored.dashboardSort == .prints, stored.dashboardSortBasis == .growth,
            basis.label(forSegment: 1) == "24 hours gain" else { throw PulseError.incomplete("dashboard sort persistence and range label") }
        model.state.preferences.watchedModelLayout = .compact
        func scrolls(_ node: NSView) -> [NSScrollView] { (node as? NSScrollView).map { [$0] } ?? node.subviews.flatMap(scrolls) }
        if let scroll = scrolls(view).filter({ $0.bounds.width > 500 }).max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 500)); scroll.reflectScrolledClipView(scroll.contentView)
        }
        for total in [true, false] {
            basis.selectedSegment = total ? 0 : 1; _ = basis.sendAction(basisAction, to: basis.target)
            try await Task.sleep(for: .milliseconds(400)); view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("dashboard-sort-prints-\(total ? "total" : "growth").png"))
            }
        }
        guard model.state.models == oldModels, model.state.watches == oldWatches else { throw PulseError.incomplete("sort changed observations or watches") }
        return ["allNativeMenuChoices": true, "nativeBasisSelection": true, "rangeLabelUpdates": true, "choicesPersist": true, "observationsAndWatchesUnchanged": true]
    }
}
