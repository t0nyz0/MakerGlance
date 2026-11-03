import AppKit
import SwiftUI
import MakerPulseCore

@MainActor enum MyPrintsAudit {
    static func run(model: AppModel, view: NSView, directory: URL) async throws -> [String: Bool] {
        let originalHistory=model.state.printHistory,originalStatus=model.printsStatus,originalDestination=model.destination
        let originalScale=model.state.preferences.textScalePercent,originalScheme=model.auditScheme
        let search=model.printSearch,outcome=model.printOutcome,printer=model.printPrinter,range=model.printRange,order=model.printOrder
        defer {
            model.state.printHistory=originalHistory;model.printsStatus=originalStatus;model.destination=originalDestination
            model.state.preferences.textScalePercent=originalScale;model.auditScheme=originalScheme
            model.printSearch=search;model.printOutcome=outcome;model.printPrinter=printer;model.printRange=range;model.printOrder=order
        }
        var fixture=DemoData().state.printHistory!;fixture.accountID=model.state.preferences.userID
        model.state.printHistory=fixture;model.printsStatus="Isolated native QA · fictional print jobs · no cloud account access"
        model.printSearch="";model.printOutcome = .all;model.printPrinter="";model.printRange = .all;model.printOrder = .newest
        model.destination = .myPrints;try await Task.sleep(for:.milliseconds(500))
        func find<T:NSView>(_ type:T.Type,_ id:String,_ node:NSView)->T? {
            if let match=node as? T,match.identifier?.rawValue==id{return match}
            return node.subviews.compactMap{find(type,id,$0)}.first
        }
        func choose(_ id:String,_ title:String) async throws {
            guard let control=find(NSPopUpButton.self,id,view),let action=control.action,control.itemTitles.contains(title) else{throw PulseError.incomplete("native My Prints menu")}
            control.selectItem(withTitle:title);guard control.sendAction(action,to:control.target) else{throw PulseError.incomplete("My Prints native action")}
            try await Task.sleep(for:.milliseconds(100))
        }
        try await choose("my-prints-status",PrintOutcome.stopped.title)
        guard model.printOutcome == .stopped, model.visiblePrintJobs.count==2 else{throw PulseError.incomplete("My Prints status binding")}
        let device=model.visiblePrintJobs.first!.deviceName!
        try await choose("my-prints-printer",device)
        guard model.printPrinter==device,model.visiblePrintJobs.count==1 else{throw PulseError.incomplete("My Prints printer binding")}
        guard let field=find(NSSearchField.self,"my-prints-search",view) else{throw PulseError.incomplete("My Prints search field")}
        field.stringValue="no such fictional print";field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field))
        try await Task.sleep(for:.milliseconds(100))
        guard model.visiblePrintJobs.isEmpty,model.printSearch==field.stringValue else{throw PulseError.incomplete("My Prints search binding")}
        field.stringValue="";field.delegate?.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:field))
        try await choose("my-prints-status",PrintOutcome.all.title);try await choose("my-prints-printer","All printers")
        try await choose("my-prints-date",PrintHistoryRange.month.title);try await choose("my-prints-sort",PrintHistoryOrder.elapsed.title)
        guard model.printRange == .month,model.printOrder == .elapsed,model.visiblePrintJobs.first?.id=="sample-print-8" else{throw PulseError.incomplete("My Prints date or sort binding")}
        try await choose("my-prints-date",PrintHistoryRange.all.title);try await choose("my-prints-sort",PrintHistoryOrder.newest.title)
        func save(_ node:NSView,_ name:String)throws{
            node.layoutSubtreeIfNeeded();node.displayIfNeeded();guard let rep=node.bitmapImageRepForCachingDisplay(in:node.bounds) else{throw PulseError.incomplete("My Prints render")}
            node.cacheDisplay(in:node.bounds,to:rep);try rep.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent(name+".png"))
        }
        for scheme in [ColorScheme.dark,.light] {
            model.auditScheme=scheme
            for percent in [100,150] {
                model.state.preferences.textScalePercent=percent
                try await Task.sleep(for:.milliseconds(450));try save(view,"my-prints-\(percent)-\(scheme == .dark ? "dark":"light")")
            }
            let detail=NSHostingView(rootView:PrintJobDetail(job:PrintJob(id:"sample-missing",status:99)).environment(\.appTextScale,1.5).appFont(.body).preferredColorScheme(scheme))
            detail.frame=NSRect(x:0,y:0,width:820,height:760);try save(detail,"my-prints-missing-detail-\(scheme == .dark ? "dark":"light")")
        }
        guard model.state.printHistory==fixture else{throw PulseError.incomplete("My Prints filters mutated history")}
        return ["nativeStatusSelection":true,"nativePrinterSelection":true,"nativeSearchAndReset":true,"nativeDateAndSort":true,"filtersKeepHistory":true,"missingDataDetailRendered":true]
    }
}
