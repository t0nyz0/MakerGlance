import AppKit
import MakerPulseCore
import SwiftUI

@MainActor enum MenuActionsAudit {
    static func run(model: AppModel) async throws -> [String: Bool] {
        guard model.isolatedQA else { throw PulseError.incomplete("isolated menu verification") }
        model.showMain(.settings); try await Task.sleep(for: .milliseconds(250))
        let settings = model.destination == .settings
        let savedDirectMessagePreference = model.state.account?.preferences.directMessageNotifications
        model.setDirectMessageNotifications(false); try await Task.sleep(for: .milliseconds(150))
        let directMessagesOff = try await model.auditStoredDirectMessagePreference() == false
        model.setDirectMessageNotifications(true); try await Task.sleep(for: .milliseconds(150))
        let directMessagesOn = try await model.auditStoredDirectMessagePreference() == true
        model.state.account?.preferences.directMessageNotifications = savedDirectMessagePreference
        model.save(); try await Task.sleep(for: .milliseconds(150))
        model.showMain(.activity); try await Task.sleep(for: .milliseconds(250))
        let inbox = model.destination == .activity
        let firstID = model.state.models.first?.id
        if let firstID { model.showMain(.models, modelID: firstID) }
        try await Task.sleep(for: .milliseconds(250))
        let modelLink = firstID == nil || model.selectedModel?.id == firstID
        model.selectedModel = nil
        try await Task.sleep(for: .milliseconds(250))
        model.showMain(); model.showMain()
        let before = NSApp.windows.filter { $0.title == AppIdentity.displayName && $0.isVisible && !($0 is NSPanel) }
        guard let window = before.first else { throw PulseError.incomplete("main window routing") }
        let reused = before.count == 1
        let incoming = Activity(id: "qa-read-on-open", date: Date(), title: "Sample update", detail: "Window reopen fixture", symbol: "bell")
        model.state.activity.insert(incoming, at: 0)
        model.save()
        try await Task.sleep(for: .milliseconds(150))
        let unreadWhileOpen = model.unread == 1
        window.performClose(nil); try await Task.sleep(for: .milliseconds(200))
        let keepsRunning = NSApp.isRunning && !window.isVisible
        let unreadWhileClosed = model.unread == 1
        let activityBefore = Dictionary(uniqueKeysWithValues: (model.modelActivityReports[.today] ?? []).map { ($0.id, $0.lastMetricChangeAt) })
        let cleanLaunchFreshness = model.latestModelIncreases.isEmpty
        let refresh = Task { await model.refresh(forceFollowers: false) }
        try await Task.sleep(for: .milliseconds(80))
        let loading = model.isRefreshing
        let savedRule = firstID.map { model.state.watches[$0] ?? WatchRule() }
        if let firstID { model.updateWatch(firstID) { $0.enabled = false } }
        model.showMain()
        try await Task.sleep(for: .milliseconds(250))
        let reopened = NSApp.windows.contains { $0.title == AppIdentity.displayName && $0.isVisible && !($0 is NSPanel) }
        let markedReadOnReopen = model.unread == 0 && model.state.activity.first(where: { $0.id == incoming.id })?.isRead == true
        let readPersisted = try await model.auditStoredActivity().first(where: { $0.id == incoming.id })?.isRead == true
        await refresh.value
        try await Task.sleep(for: .milliseconds(100))
        let activityAfter = Dictionary(uniqueKeysWithValues: (model.modelActivityReports[.today] ?? []).map { ($0.id, $0.lastMetricChangeAt) })
        let unchangedActivity = activityBefore == activityAfter && !activityAfter.isEmpty
        let noFalseFreshness = cleanLaunchFreshness && model.latestModelIncreases.values.allSatisfy(\.isEmpty)
        let completed = !model.isRefreshing
        if let reopenedWindow = NSApp.windows.first(where: { $0.title == AppIdentity.displayName && $0.isVisible && !($0 is NSPanel) }) { reopenedWindow.performClose(nil) }
        try await Task.sleep(for: .milliseconds(150))
        _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
        try await Task.sleep(for: .milliseconds(300))
        let dockReopen = NSApp.windows.contains { $0.title == AppIdentity.displayName && $0.isVisible && !($0 is NSPanel) }
        try await Task.sleep(for: .milliseconds(150))
        let stored = try await model.auditStoredWatches()
        let pauseSurvives = firstID.map { model.state.watches[$0]?.enabled == false && stored[$0]?.enabled == false } ?? true
        if let firstID, let savedRule { model.updateWatch(firstID) { $0 = savedRule } }
        let savedMinutes = model.state.preferences.pollingMinutes
        model.setPollingMinutes(30); let long = model.nextRefreshDate
        model.setPollingMinutes(10); let short = model.nextRefreshDate
        let rescheduled = long != nil && short != nil && short! < long! && (590...620).contains(short!.timeIntervalSinceNow)
        model.setPollingMinutes(savedMinutes)
        var report = ["settingsAction": settings, "directMessageAlertsOffPersist": directMessagesOff, "directMessageAlertsOnPersist": directMessagesOn,
            "inboxAction": inbox, "modelDeepLink": modelLink, "openReusesWindow": reused,
            "appRemainsRunningAfterWindowClose": keepsRunning, "refreshLoadingFeedback": loading, "reopenWhileRefreshResponsive": reopened,
            "activityRemainsUnreadWhileWindowStaysOpen": unreadWhileOpen, "activityRemainsUnreadWhenWindowCloses": unreadWhileClosed,
            "reopeningMarksActivityRead": markedReadOnReopen, "reopenReadStatePersists": readPersisted,
            "refreshCompletes": completed, "dockReopenHandler": dockReopen, "pauseDuringRefreshPersists": pauseSurvives, "pollIntervalReschedulesImmediately": rescheduled,
            "unchangedRefreshPreservesActivityTime": unchangedActivity, "unchangedRefreshDoesNotCreateFreshPills": noFalseFreshness]
        report.merge(try await verifyTray(model)) { _, value in value }
        guard report.values.allSatisfy({ $0 }) else { throw PulseError.incomplete("menu action \(report.filter { !$0.value }.keys.sorted().joined(separator: ", "))") }
        return report
    }

    private static func verifyTray(_ model: AppModel) async throws -> [String: Bool] {
        let saved = model.state.activity
        let now = Date()
        let updates = (1...10).map { number in
            Activity(id: "qa-tray-\(number)", date: now.addingTimeInterval(-Double(number)),
                     title: "Sample update \(number)", detail: "Menu tray fixture", symbol: "bell")
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 590),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        model.state.activity = Array(updates.prefix(2))
        let host = NSHostingView(rootView: MenuSummary().environmentObject(model))
        panel.contentView = host
        defer {
            panel.close()
            model.state.activity = saved
            model.save()
        }

        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        panel.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(250))
        guard let smallDocument = scrollView(in: host)?.documentView else {
            throw PulseError.incomplete("menu activity scroll view")
        }
        let twoRowHeight = smallDocument.bounds.height
        let firstOpenClearsBadge = model.menuStatus.badge == nil

        panel.orderOut(nil)
        try await Task.sleep(for: .milliseconds(150))
        model.state.activity = updates
        let badgeShowsTen = model.menuStatus.badge == "10"
        panel.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        guard let scroll = scrollView(in: host), let document = scroll.documentView else {
            throw PulseError.incomplete("reopened menu activity scroll view")
        }
        let hasMoreThanTwoRows = document.bounds.height > twoRowHeight + 100
        let clip = scroll.contentView
        let origin = clip.bounds.origin
        clip.scroll(to: NSPoint(x: origin.x, y: document.bounds.maxY - clip.bounds.height))
        scroll.reflectScrolledClipView(clip)
        let scrollsThroughUpdates = clip.bounds.origin.y > origin.y
        let stored = try await model.auditStoredActivity()
        let allTenRetainedAndRead = model.state.activity.map(\.id) == updates.map(\.id)
            && model.menuStatus.badge == nil && stored.filter { $0.id.hasPrefix("qa-tray-") && $0.isRead }.count == 10

        model.state.activity.insert(Activity(id: "qa-tray-new", date: Date(), title: "New sample update",
                                             detail: "Arrived while tray was open", symbol: "bell"), at: 0)
        try await Task.sleep(for: .milliseconds(150))
        return ["trayFirstOpenClearsBadge": firstOpenClearsBadge, "closedTrayShowsTenUnread": badgeShowsTen,
                "trayReopenKeepsTenUpdatesAndMarksThemRead": allTenRetainedAndRead,
                "trayScrollShowsMoreThanTwoRows": hasMoreThanTwoRows && scrollsThroughUpdates,
                "newUpdateRemainsUnreadWhileTrayStaysOpen": model.menuStatus.badge == "1"]
    }
}
