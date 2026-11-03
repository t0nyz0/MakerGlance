import AppKit
import MakerPulseCore

@MainActor enum MenuActionsAudit {
    static func run(model: AppModel) async throws -> [String: Bool] {
        guard model.isolatedQA else { throw PulseError.incomplete("isolated menu verification") }
        model.showMain(.settings); try await Task.sleep(for: .milliseconds(250))
        let settings = model.destination == .settings
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
        window.performClose(nil); try await Task.sleep(for: .milliseconds(200))
        let keepsRunning = NSApp.isRunning && !window.isVisible
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
        let report = ["settingsAction": settings, "inboxAction": inbox, "modelDeepLink": modelLink, "openReusesWindow": reused,
            "appRemainsRunningAfterWindowClose": keepsRunning, "refreshLoadingFeedback": loading, "reopenWhileRefreshResponsive": reopened,
            "refreshCompletes": completed, "dockReopenHandler": dockReopen, "pauseDuringRefreshPersists": pauseSurvives, "pollIntervalReschedulesImmediately": rescheduled,
            "unchangedRefreshPreservesActivityTime": unchangedActivity, "unchangedRefreshDoesNotCreateFreshPills": noFalseFreshness]
        guard report.values.allSatisfy({ $0 }) else { throw PulseError.incomplete("menu action \(report.filter { !$0.value }.keys.sorted().joined(separator: ", "))") }
        return report
    }
}
