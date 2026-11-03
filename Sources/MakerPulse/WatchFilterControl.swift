import SwiftUI
import AppKit
import MakerPulseCore

// Native segments with an explicit typed selection and target/action. No
// implicit Picker tags or overlays participate in filter hit testing.
struct WatchFilterControl: NSViewRepresentable {
    @Environment(\.appTextScale) private var textScale
    @Binding var selection: ModelWatchFilter
    var counts: [ModelWatchFilter: Int]
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ModelWatchFilter.allCases.map(\.title), trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded; control.controlSize = .regular
        control.setAccessibilityLabel("Model watch filter"); control.setAccessibilityIdentifier("model-watch-filter")
        control.identifier = NSUserInterfaceItemIdentifier("model-watch-filter")
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        for (index, filter) in ModelWatchFilter.allCases.enumerated() { control.setLabel("\(filter.title) (\(counts[filter] ?? 0))", forSegment: index) }
        control.selectedSegment = ModelWatchFilter.allCases.firstIndex(of: selection) ?? 0
        control.selectedSegmentBezelColor = NSColor(Palette.controlFill)
        control.controlSize = textScale > 1.2 ? .large : .regular
        control.font = NSFont.systemFont(ofSize: AppTypography.pointSize(13, scale: textScale))
        control.isEnabled = true
    }
    @MainActor final class Coordinator: NSObject {
        var parent: WatchFilterControl
        init(_ parent: WatchFilterControl) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard ModelWatchFilter.allCases.indices.contains(sender.selectedSegment) else { return }
            parent.selection = ModelWatchFilter.allCases[sender.selectedSegment]
        }
    }
}
