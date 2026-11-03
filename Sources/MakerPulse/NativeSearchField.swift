import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    @Environment(\.appTextScale) private var textScale
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = ActivatingSearchField(frame: .zero)
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.setAccessibilityIdentifier(identifier)
        field.setAccessibilityLabel(accessibilityLabel)
        let font = NSFont.systemFont(ofSize: AppTypography.pointSize(13, scale: textScale))
        if field.font != font { field.font = font }
        // Do not replace the field editor's contents during normal typing.
        // Keeping the editor intact also preserves selection and IME input.
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        init(_ parent: NativeSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
    }
}

private final class ActivatingSearchField: NSSearchField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // A menu-bar panel can still own keyboard focus when the dashboard
        // comes forward. Give this window the keyboard before starting editing.
        if let window, !window.isKeyWindow || !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
