import SwiftUI
import AppKit
import MakerPulseCore

struct WatchedLayoutControl: NSViewRepresentable {
    @Environment(\.appTextScale) private var textScale
    @Binding var selection: WatchedModelLayout
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: WatchedModelLayout.allCases.map(\.title), trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded
        control.identifier = NSUserInterfaceItemIdentifier("watched-model-layout")
        control.setAccessibilityLabel("Watched model presentation")
        control.setAccessibilityIdentifier("watched-model-layout")
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = WatchedModelLayout.allCases.firstIndex(of: selection) ?? 0
        control.selectedSegmentBezelColor = NSColor(Palette.controlFill)
        control.font = NSFont.systemFont(ofSize: AppTypography.pointSize(13, scale: textScale))
        control.controlSize = textScale > 1.2 ? .large : .regular
        control.toolTip = "Choose large image cards or compact rows. Both show the same watched models and observations."
    }
    @MainActor final class Coordinator: NSObject {
        var parent: WatchedLayoutControl
        init(_ parent: WatchedLayoutControl) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard WatchedModelLayout.allCases.indices.contains(sender.selectedSegment) else { return }
            parent.selection = WatchedModelLayout.allCases[sender.selectedSegment]
        }
    }
}
