import SwiftUI
import AppKit
import UserNotifications
import MakerPulseCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var current: AppDelegate?
    var reopenHandler: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        NSApp.setActivationPolicy(CommandLine.arguments.contains("--qa-library") || CommandLine.arguments.contains("--demo-capture") ? .accessory : .regular)
        UNUserNotificationCenter.current().delegate = self
        NSApp.applicationIconImage = AppGlyph.applicationIcon
        NSApp.dockTile.display()
        if let flag = CommandLine.arguments.firstIndex(of: "--icon-audit"), CommandLine.arguments.indices.contains(flag + 1) {
            let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { BrandIconAudit.capture(directory: directory) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { reopenHandler?() }; return true }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .badge] }
}

@main struct MakerGlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("MakerGlance", id: "main") {
            RootView().environmentObject(model).appFont(.body).controlSize(model.state.preferences.textSizePercent > 120 ? .large : .regular).environment(\.appTextScale, model.state.preferences.textScaleFactor).frame(minWidth: 950, minHeight: 660)
                .tint(Palette.controlFill)
                .onAppear { delegate.reopenHandler = { model.showMain() } }
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandMenu("Appearance") {
                Picker("App appearance", selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            CommandGroup(after: .newItem) {
                Button("Refresh Analytics") { Task { await model.refresh() } }.keyboardShortcut("r").disabled(model.isRefreshing)
                Button("Mark All Activity Read") { model.markAllRead() }.keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            MenuSummary().environmentObject(model).preferredColorScheme(model.effectiveColorScheme).tint(Palette.controlFill).appFont(.body).environment(\.appTextScale, model.state.preferences.textScaleFactor)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: AppGlyph.menu)
                if let symbol = model.menuStatus.symbol { Image(systemName: symbol) }
                if let badge = model.menuStatus.badge { Text(badge) }
            }.accessibilityLabel(model.menuStatus.accessibility).help(model.menuStatus.accessibility)
        }
        .menuBarExtraStyle(.window)
    }
}

