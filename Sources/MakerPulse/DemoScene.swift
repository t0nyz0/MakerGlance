import SwiftUI
import AppKit
import MakerPulseCore

private struct DocumentationModelCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let item = model.modelActivityReports[.today]?.first { DashboardModelRow(item: item, window: .today) }
    }
}

private struct DocumentationRoot: View {
    @ObservedObject var model: AppModel
    var body: some View {
        RootView().environmentObject(model).appFont(.body)
            .controlSize(model.state.preferences.textSizePercent > 120 ? .large : .regular)
            .environment(\.appTextScale, model.state.preferences.textScaleFactor).tint(Palette.controlFill)
    }
}

@MainActor private final class DocumentationWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor enum DemoScene {
    static func seedVerificationLibrary(_ store: Storage) async throws {
        let fixture = DemoData()
        let count = fixture.samples.values.map(\.count).max() ?? 0
        for index in 0..<count {
            var samples: [String: Sample] = [:]
            for (entity, values) in fixture.samples where values.indices.contains(index) {
                samples[entity] = values[index]
            }
            try await store.commit(fixture.state, samples: samples)
        }
    }
    static func install(in model: AppModel, store: Storage) async throws {
        let fixture = DemoData()
        try await store.commit(fixture.state)
        model.state = fixture.state; model.histories = fixture.samples; model.latestModelIncreases = fixture.increases
        let models = Dictionary(uniqueKeysWithValues: fixture.state.models.map { ($0.id, fixture.samples["model:\($0.id)"] ?? []) })
        for window in ModelActivityWindow.allCases {
            model.modelActivityReports[window] = ModelActivity.ranked(designs: fixture.state.models, samples: models, events: fixture.state.activity, window: window)
        }
        for entity in ["profile"] + fixture.state.models.map({ "model:\($0.id)" }) {
            var values: [Metric: Sample] = [:]
            for metric in Metric.allCases {
                values[metric] = fixture.samples[entity]?.first { $0.date >= Calendar.autoupdatingCurrent.startOfDay(for: Date()) && $0.counts[metric] != nil }
            }
            model.dailyBaselines[entity] = values
        }
        model.api = MakerWorldAPI(transport: UIReplayTransport(state: fixture.state), minimumInterval: 0)
        model.loaded = true; model.restoringSession = false; model.connection = "Offline demo"
        model.status = "Fictional observations · no network or Keychain access"
        model.authenticationStatus = "Demo does not load or save credentials."
        model.inboxStatus = "Fictional local activity. No account inbox is connected."
        model.rewardsStatus = "No account balances are present in the demo."
        model.walletStatus = "No wallet is connected."
        model.printsStatus = "Fictional offline print history · no cloud account or printer connected."
        model.notificationStatus = "Disabled in demo"
    }
    static func capture(in model: AppModel, directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await Task.sleep(for: .seconds(1))
        // A fresh accessory-only documentation bundle has no restored main
        // window. Host the exact production RootView in an owned native window.
        let window = DocumentationWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 960), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = AppIdentity.displayName; window.isReleasedWhenClosed = false
        let root = NSHostingView(rootView: DocumentationRoot(model: model))
        window.contentView = root; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        for key in ["planter", "tray", "clip", "stand", "organizer", "lamp", "rack", "grid", "vase", "avatar"] { _ = DemoArtwork.image("demo://" + key) }
        try await Task.sleep(for: .milliseconds(500))
        func scrollView(_ node: NSView) -> NSScrollView? {
            func candidates(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(candidates)
            }
            // NavigationSplitView may also create a scroll view for its
            // sidebar. Only the wide detail scroll view is the dashboard.
            return candidates(node).filter { $0.bounds.width > 500 }
                .max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }
        }
        func scroll(_ offset: CGFloat) {
            guard let scroll = scrollView(root), let document = scroll.documentView else { return }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(offset, max(0, document.bounds.height - scroll.contentView.bounds.height))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        func snapshot(_ name: String, view: NSView? = nil) throws {
            let view = view ?? root; view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw PulseError.incomplete("demo render") }
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        for scheme in [ColorScheme.dark, .light] {
            let theme = scheme == .dark ? "dark" : "light"
            model.auditScheme = scheme; model.destination = .overview
            try await Task.sleep(for: .milliseconds(500)); scroll(0); try snapshot("overview-\(theme)")
            model.state.preferences.watchedModelLayout = .cards
            try await Task.sleep(for: .milliseconds(400)); scroll(450); root.displayIfNeeded(); try await Task.sleep(for: .milliseconds(700)); try snapshot("cards-\(theme)")
            model.state.preferences.watchedModelLayout = .compact
            try await Task.sleep(for: .milliseconds(400)); scroll(450); root.displayIfNeeded(); try await Task.sleep(for: .milliseconds(500)); try snapshot("compact-\(theme)")
            model.destination = .creator; model.analyticsSection = .local
            try await Task.sleep(for: .milliseconds(500)); scroll(0); try snapshot("history-\(theme)")
            model.analyticsSection = .community
            try await Task.sleep(for: .milliseconds(500)); try snapshot("followers-\(theme)")
            model.destination = .myPrints
            try await Task.sleep(for: .milliseconds(500)); scroll(0); try snapshot("my-prints-\(theme)")
            model.destination = .activity
            try await Task.sleep(for: .milliseconds(400)); scroll(0); try snapshot("activity-\(theme)")
            let menu = NSHostingView(rootView: MenuSummary().environmentObject(model).appFont(.body).environment(\.appTextScale, 1).preferredColorScheme(scheme))
            menu.frame = NSRect(x: 0, y: 0, width: 420, height: 640)
            try snapshot("menu-\(theme)", view: menu)
        }
        // Capture the complete native Dashboard, including the sections below
        // the original viewport. No stitched or reconstructed UI is used.
        var fullDashboardHeight: CGFloat = 0
        for scheme in [ColorScheme.dark, .light] {
            model.auditScheme = scheme; model.destination = .overview
            model.state.preferences.watchedModelLayout = .compact
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.setContentSize(NSSize(width: 1440, height: 1200))
            for _ in 0..<6 {
                root.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(400))
                guard let view = scrollView(root), let document = view.documentView else { throw PulseError.incomplete("dashboard scroll view") }
                let chrome = root.bounds.height - view.contentView.bounds.height
                let height = ceil(document.bounds.height + chrome + 8)
                guard height.isFinite, height < 8000 else { throw PulseError.incomplete("dashboard content bounds") }
                if document.bounds.height <= view.contentView.bounds.height + 2 { break }
                window.setContentSize(NSSize(width: 1440, height: height))
            }
            root.displayIfNeeded(); try await Task.sleep(for: .milliseconds(500))
            guard root.bounds.height > 1800, let view = scrollView(root), let document = view.documentView,
                document.bounds.height <= view.contentView.bounds.height + 2 else {
                let view = scrollView(root)
                throw PulseError.incomplete("full dashboard capture (host \(Int(root.bounds.height)), content \(Int(view?.documentView?.bounds.height ?? 0)), viewport \(Int(view?.contentView.bounds.height ?? 0)))")
            }
            fullDashboardHeight = max(fullDashboardHeight, root.bounds.height)
            try snapshot("dashboard-full-\(scheme == .dark ? "dark" : "light")")
        }

        // Capture readable native components at their actual display size.
        // These are the same views used by the dashboard, never mock UI.
        model.auditScheme = .dark; window.appearance = NSAppearance(named: .darkAqua)
        let motion = directory.appendingPathComponent("motion")
        try FileManager.default.createDirectory(at: motion, withIntermediateDirectories: true)
        func segments(_ view: NSView) -> [NSSegmentedControl] { (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap(segments) }
        func choose(_ control: NSSegmentedControl?, _ index: Int) throws {
            guard let control, let action = control.action else { throw PulseError.incomplete("demo native control") }
            control.selectedSegment = index
            guard control.sendAction(action, to: control.target) else { throw PulseError.incomplete("demo native action") }
        }
        func host<V: View>(_ content: V, width: CGFloat, height: CGFloat, scale: Double) -> NSHostingView<AnyView> {
            let view = NSHostingView(rootView: AnyView(content.environmentObject(model).appFont(.body).environment(\.appTextScale, scale)
                .frame(width: width).fixedSize(horizontal: false, vertical: true).frame(width: width, height: height, alignment: .topLeading)
                .clipped().background(Palette.canvas).preferredColorScheme(.dark).tint(Palette.controlFill)))
            window.setContentSize(NSSize(width: width, height: height)); window.contentView = view
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            return view
        }
        func frame(_ name: String, _ view: NSView) async throws {
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded(); try await Task.sleep(for: .milliseconds(700))
            try snapshot("motion/" + name, view: view)
        }
        let models = host(WatchedModelsSection(), width: 790, height: 1000, scale: 1.15)
        try await Task.sleep(for: .milliseconds(400))
        let layout = segments(models).first { $0.identifier?.rawValue == "watched-model-layout" }
        try choose(layout, 0); try await frame("layout-0", models)
        guard model.state.preferences.watchedLayout == .cards else { throw PulseError.incomplete("demo Cards selection") }
        try choose(layout, 1); try await frame("layout-1", models)
        guard model.state.preferences.watchedLayout == .compact else { throw PulseError.incomplete("demo Compact selection") }
        try choose(layout, 0); try await frame("layout-2", models)
        var recency = ModelCheckRecency(); recency.recordSuccessful(model.state.models, at: Date())
        model.latestModelIncreases = recency.increases
        let card = host(DocumentationModelCard(), width: 440, height: 760, scale: 1.2)
        try await frame("print-0", card)
        model.state.models[0].counts.prints! += 1; model.state.profile?.counts.prints! += 1
        let check = Date()
        model.histories["model:9000", default: []].append(Sample(date: check, counts: model.state.models[0].counts))
        recency.recordSuccessful(model.state.models, at: check); model.latestModelIncreases = recency.increases
        let histories = Dictionary(uniqueKeysWithValues: model.state.models.map { ($0.id, model.histories["model:\($0.id)"] ?? []) })
        for period in ModelActivityWindow.allCases {
            model.modelActivityReports[period] = ModelActivity.ranked(designs: model.state.models, samples: histories, events: model.state.activity, window: period)
        }
        guard model.latestModelIncreases["9000"]?[.prints]?.delta == 1 else { throw PulseError.incomplete("demo latest-check comparison") }
        try await frame("print-1", card)
        recency.recordSuccessful(model.state.models, at: Date()); model.latestModelIncreases = recency.increases
        guard model.latestModelIncreases["9000"]?[.prints] == nil else { throw PulseError.incomplete("demo unchanged check") }
        try await frame("print-2", card)
        let history = host(HistoryMosaic(samples: model.histories["profile"] ?? []), width: 790, height: 1080, scale: 1.15)
        try await Task.sleep(for: .milliseconds(400))
        let range = segments(history).first { $0.segmentCount == 4 && $0.label(forSegment: 0) == "24H" }
        try choose(range, 0); try await frame("history-0", history)
        try choose(range, 1); try await frame("history-1", history)
        try choose(range, 0); try await frame("history-2", history)
        let coverage: [String: Any] = ["fullDashboard": true, "fullDashboardHeight": fullDashboardHeight, "nativeCardsCompactActions": true,
            "latestPrintIncrease": 1, "unchangedCheckClearsNew": true, "nativeHistoryRangeActions": true,
            "fictionalDataOnly": true, "networkAndKeychainUsed": false]
        try JSONSerialization.data(withJSONObject: coverage, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("CAPTURE-CHECKS.json"))
        try Data("Original fictional fixtures and artwork. Captured by MakerGlance --demo. No live library, credentials, balances or remote images.\n".utf8).write(to: directory.appendingPathComponent("PROVENANCE.txt"))
    }
}
