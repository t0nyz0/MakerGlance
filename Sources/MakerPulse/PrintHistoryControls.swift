import AppKit
import SwiftUI

struct PrintFilterMenu<Value: Equatable>: NSViewRepresentable {
    @Environment(\.appTextScale) private var scale
    let label: String
    let identifier: String
    let options: [(String,Value)]
    @Binding var selection: Value
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeNSView(context:Context)->NSPopUpButton {
        let control=NSPopUpButton();control.target=context.coordinator;control.action=#selector(Coordinator.changed(_:))
        control.identifier=NSUserInterfaceItemIdentifier(identifier);control.setAccessibilityIdentifier(identifier);control.setAccessibilityLabel(label)
        return control
    }
    func updateNSView(_ control:NSPopUpButton,context:Context) {
        context.coordinator.parent=self
        if control.itemTitles != options.map(\.0) { control.removeAllItems();control.addItems(withTitles:options.map(\.0)) }
        control.selectItem(at:options.firstIndex{$0.1==selection} ?? 0)
        control.font=NSFont.systemFont(ofSize:AppTypography.pointSize(13,scale:scale));control.controlSize=scale>1.2 ? .large:.regular
        control.toolTip=label
    }
    @MainActor final class Coordinator:NSObject {
        var parent:PrintFilterMenu
        init(_ parent:PrintFilterMenu){self.parent=parent}
        @objc func changed(_ sender:NSPopUpButton) { guard parent.options.indices.contains(sender.indexOfSelectedItem) else{return};parent.selection=parent.options[sender.indexOfSelectedItem].1 }
    }
}
struct PrintSearchField:NSViewRepresentable {
    @Environment(\.appTextScale) private var scale
    @Binding var text:String
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeNSView(context:Context)->NSSearchField {
        let field=NSSearchField();field.placeholderString="Search print, model, printer or plate";field.delegate=context.coordinator
        field.identifier=NSUserInterfaceItemIdentifier("my-prints-search");field.setAccessibilityIdentifier("my-prints-search");field.setAccessibilityLabel("Search print history")
        return field
    }
    func updateNSView(_ field:NSSearchField,context:Context) {
        context.coordinator.parent=self;if field.stringValue != text {field.stringValue=text}
        field.font=NSFont.systemFont(ofSize:AppTypography.pointSize(13,scale:scale));field.controlSize=scale>1.2 ? .large:.regular
    }
    @MainActor final class Coordinator:NSObject,NSSearchFieldDelegate {
        var parent:PrintSearchField
        init(_ parent:PrintSearchField){self.parent=parent}
        func controlTextDidChange(_ obj:Notification){guard let field=obj.object as? NSSearchField else{return};parent.text=field.stringValue}
    }
}
