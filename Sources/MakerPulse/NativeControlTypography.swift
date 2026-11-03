import SwiftUI
import AppKit

// SwiftUI text uses AppFont. Native AppKit input cells need an explicit font
// too; this bridge only visits controls in this app's own hosting window.
struct NativeControlTypography: NSViewRepresentable {
    let scale: Double
    var refreshID = ""
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak view] in
            guard let root = view?.window?.contentView else { return }
            let pointSize = AppTypography.pointSize(13, scale: scale)
            @MainActor func apply(_ node: NSView) {
                let eligible = node is NSSegmentedControl || node is NSDatePicker || ((node as? NSButton)?.title.isEmpty == false) || ((node as? NSTextField)?.isEditable == true)
                if eligible, let control = node as? NSControl, abs((control.font?.pointSize ?? 0) - pointSize) > 0.1 {
                    control.font = NSFont.systemFont(ofSize: pointSize)
                    control.invalidateIntrinsicContentSize()
                }
                for child in node.subviews { apply(child) }
            }
            apply(root)
        }
    }
}
