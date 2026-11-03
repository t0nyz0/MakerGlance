import SwiftUI
import AppKit
import MakerPulseCore

struct DashboardSortPicker: NSViewRepresentable {
    @Environment(\.appTextScale) private var scale
    @Binding var selection: WatchedModelSort
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(); button.addItems(withTitles: WatchedModelSort.allCases.map(\.title))
        button.target = context.coordinator; button.action = #selector(Coordinator.changed(_:))
        button.identifier = NSUserInterfaceItemIdentifier("dashboard-model-sort")
        button.setAccessibilityIdentifier("dashboard-model-sort"); button.setAccessibilityLabel("Sort watched models")
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.selectItem(at: WatchedModelSort.allCases.firstIndex(of: selection) ?? 0)
        button.font = NSFont.systemFont(ofSize: AppTypography.pointSize(13, scale: scale))
        button.controlSize = scale > 1.2 ? .large : .regular
    }
    @MainActor final class Coordinator: NSObject {
        var parent: DashboardSortPicker
        init(_ parent: DashboardSortPicker) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            guard WatchedModelSort.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
            parent.selection = WatchedModelSort.allCases[sender.indexOfSelectedItem]
        }
    }
}
struct DashboardSortBasis: NSViewRepresentable {
    @Environment(\.appTextScale) private var scale
    @Binding var selection: WatchedSortBasis
    let window: ModelActivityWindow
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["Lifetime totals", window.title + " gain"], trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.identifier = NSUserInterfaceItemIdentifier("dashboard-sort-basis")
        control.setAccessibilityIdentifier("dashboard-sort-basis"); control.setAccessibilityLabel("Sort by lifetime totals or selected-window gain")
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.setLabel(window.title + " gain", forSegment: 1)
        control.selectedSegment = selection == .total ? 0 : 1
        control.selectedSegmentBezelColor = NSColor(Palette.controlFill)
        control.font = NSFont.systemFont(ofSize: AppTypography.pointSize(13, scale: scale))
        control.controlSize = scale > 1.2 ? .large : .regular
    }
    @MainActor final class Coordinator: NSObject {
        var parent: DashboardSortBasis
        init(_ parent: DashboardSortBasis) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) { parent.selection = sender.selectedSegment == 0 ? .total : .growth }
    }
}
