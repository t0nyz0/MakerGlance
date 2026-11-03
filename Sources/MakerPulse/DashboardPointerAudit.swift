import AppKit
import Foundation
import SwiftUI
import MakerPulseCore

@MainActor private final class PointerMenuProbe: NSObject, NSMenuDelegate {
    var opened = false
    func menuWillOpen(_ menu: NSMenu) { opened = true; menu.cancelTracking() }
}

@MainActor enum DashboardPointerAudit {
    static func run(model:AppModel,directory:URL) async throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        model.destination = .overview
        try await Task.sleep(for:.milliseconds(700))
        guard let window=NSApp.windows.first(where:{$0.title==AppIdentity.displayName && $0.contentView != nil && !($0 is NSPanel)}),let root=window.contentView else{throw PulseError.incomplete("pointer audit window")}
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--matrix") {
            let results = try await verify(model:model,view:root,directory:directory)
            try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("pointer-matrix.json"));return
        }
        func scrolls(_ v:NSView)->[NSScrollView]{(v as? NSScrollView).map{[$0]} ?? v.subviews.flatMap(scrolls)}
        if let scroll=scrolls(root).filter({$0.bounds.width>500}).max(by:{($0.documentView?.bounds.height ?? 0)<($1.documentView?.bounds.height ?? 0)}) {
            scroll.contentView.scroll(to:NSPoint(x:0,y:500));scroll.reflectScrolledClipView(scroll.contentView)
        }
        try await Task.sleep(for:.milliseconds(350));root.layoutSubtreeIfNeeded()
        func descendants(_ view:NSView)->[NSView]{[view]+view.subviews.flatMap(descendants)}
        func belongs(_ hit:NSView?,to target:NSView)->Bool{var view=hit;while let node=view {if node===target{return true};view=node.superview};return false}
        func info(_ control:NSView)->[String:Any]{
            let point=control.convert(NSPoint(x:control.bounds.midX,y:control.bounds.midY),to:nil)
            let hit=root.hitTest(root.superview?.convert(point,from:nil) ?? point)
            return ["frame":NSStringFromRect(control.convert(control.bounds,to:nil)),"bounds":NSStringFromRect(control.bounds),"hitChildren":hit?.subviews.map{String(describing:type(of:$0))} ?? [],"visibleRect":NSStringFromRect(control.visibleRect),"hidden":control.isHiddenOrHasHiddenAncestor,"hitType":hit.map{String(describing:type(of:$0))} ?? "none","hitBelongsToControl":belongs(hit,to:control)]
        }
        func click(_ control:NSView,fraction:Double) async throws {
            let point=control.convert(NSPoint(x:control.bounds.minX+control.bounds.width*fraction,y:control.bounds.midY),to:nil)
            let time=ProcessInfo.processInfo.systemUptime
            guard let down=NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:time,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1),
                let up=NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:time+0.02,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0) else {throw PulseError.incomplete("native pointer event")}
            NSApp.postEvent(up,atStart:true);window.sendEvent(down)
            try await Task.sleep(for:.milliseconds(220))
        }
        let controls=descendants(root).compactMap{$0 as? NSSegmentedControl}.filter{$0.segmentCount==3 && $0.label(forSegment:0)=="Today"}
        var rangeReports:[[String:Any]]=[]
        for (index,control) in controls.enumerated() {
            var report=info(control);report["index"]=index
            report["before"]=model.dashboardActivityWindow.rawValue
            try await click(control,fraction:0.5);report["afterMiddleClick"]=model.dashboardActivityWindow.rawValue
            try await click(control,fraction:0.85);report["afterLastClick"]=model.dashboardActivityWindow.rawValue
            rangeReports.append(report)
        }
        let sortControls=descendants(root).compactMap{$0 as? NSPopUpButton}.filter{$0.identifier?.rawValue=="dashboard-model-sort"}
        var sorts:[[String:Any]]=[]
        for control in sortControls {
            var record=info(control);record["before"]=model.state.preferences.dashboardSort.rawValue
            // Verify pointer routing; exercise selection through the same native
            // menu action separately so a modal popup cannot strand this audit.
            control.selectItem(at:1)
            if let action=control.action {record["actionDelivered"]=control.sendAction(action,to:control.target)}
            try await Task.sleep(for:.milliseconds(150));record["afterAction"]=model.state.preferences.dashboardSort.rawValue
            sorts.append(record)
        }
        func deltas(_ window:ModelActivityWindow)->[[String:Int]] {
            (model.modelActivityReports[window] ?? []).sorted{$0.id<$1.id}.map { item in Dictionary(uniqueKeysWithValues:item.deltas.map{($0.key.rawValue,$0.value)}) }
        }
        let report:[String:Any]=["rangeControls":rangeReports,"sortControls":sorts,"todayAnd24hDeltasDiffer":deltas(.today) != deltas(.day),"24hAnd7dDeltasDiffer":deltas(.day) != deltas(.week),"windowAfterClicks":model.dashboardActivityWindow.rawValue]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("pointer-report.json"))
        if let rep=root.bitmapImageRepForCachingDisplay(in:root.bounds){root.cacheDisplay(in:root.bounds,to:rep);try rep.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent("pointer-dashboard.png"))}
    }
}

extension DashboardPointerAudit {
    static func verify(model:AppModel,view root:NSView,directory:URL) async throws -> [String:Bool] {
        guard let window=root.window else{throw PulseError.incomplete("dashboard pointer window")}
        let savedState=model.state,savedReports=model.modelActivityReports,savedWindow=model.dashboardActivityWindow
        let savedScale=model.state.preferences.textScalePercent,savedLayout=model.state.preferences.watchedModelLayout,savedScheme=model.auditScheme
        let savedDestination=model.destination,savedIncreases=model.latestModelIncreases
        let savedSize=window.contentLayoutRect.size
        defer {
            model.state=savedState;model.modelActivityReports=savedReports;model.dashboardActivityWindow=savedWindow
            model.state.preferences.textScalePercent=savedScale;model.state.preferences.watchedModelLayout=savedLayout
            model.destination=savedDestination;model.auditScheme=savedScheme;model.latestModelIncreases=savedIncreases
            window.setContentSize(savedSize);model.save()
        }
        func all(_ node:NSView)->[NSView]{[node]+node.subviews.flatMap(all)}
        func rangeControl()->NSSegmentedControl?{all(root).compactMap{$0 as? NSSegmentedControl}.first{$0.segmentCount==3 && $0.label(forSegment:0)=="Today" && !$0.isHiddenOrHasHiddenAncestor}}
        func sortControl()->NSPopUpButton?{all(root).compactMap{$0 as? NSPopUpButton}.first{$0.identifier?.rawValue=="dashboard-model-sort" && !$0.isHiddenOrHasHiddenAncestor}}
        func reveal(_ control:NSView) async throws {
            let scrolls=all(root).compactMap{$0 as? NSScrollView}.filter{$0.bounds.width>450}
            guard let scroll=scrolls.max(by:{($0.documentView?.bounds.height ?? 0)<($1.documentView?.bounds.height ?? 0)}),let document=scroll.documentView else{throw PulseError.incomplete("dashboard pointer scroll")}
            document.scrollToVisible(control.convert(control.bounds,to:document).insetBy(dx:0,dy:-60));scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for:.milliseconds(100));root.layoutSubtreeIfNeeded()
        }
        func point(_ control:NSView,_ fraction:Double)->NSPoint{control.convert(NSPoint(x:control.bounds.minX+control.bounds.width*fraction,y:control.bounds.midY),to:nil)}
        func hits(_ control:NSView,_ fraction:Double)->Bool{
            let p=point(control,fraction);var target=root.hitTest(root.superview?.convert(p,from:nil) ?? p)
            while let node=target{if node===control{return true};target=node.superview};return false
        }
        func click(_ control:NSView,_ fraction:Double) async throws {
            try await reveal(control)
            guard hits(control,fraction) else{throw PulseError.incomplete("dashboard control obscured by another hit region")}
            let p=point(control,fraction),t=ProcessInfo.processInfo.systemUptime
            guard let down=NSEvent.mouseEvent(with:.leftMouseDown,location:p,modifierFlags:[],timestamp:t,windowNumber:window.windowNumber,context:nil,eventNumber:10,clickCount:1,pressure:1),let up=NSEvent.mouseEvent(with:.leftMouseUp,location:p,modifierFlags:[],timestamp:t+0.02,windowNumber:window.windowNumber,context:nil,eventNumber:11,clickCount:1,pressure:0) else{throw PulseError.incomplete("dashboard mouse events")}
            NSApp.postEvent(up,atStart:true);window.sendEvent(down)
            try await Task.sleep(for:.milliseconds(120))
        }
        func chooseNextSort(_ control:NSPopUpButton) async throws {
            guard let menu=control.menu else {throw PulseError.incomplete("native sort popup menu")}
            let previous=menu.delegate,probe=PointerMenuProbe();menu.delegate=probe
            defer {menu.delegate=previous}
            // Native menu tracking runs outside the normal event queue on this
            // macOS version. Verify pointer opening, cancel only this QA popup,
            // then dispatch the real NSMenuItem action, rather than assigning
            // the selected model value or calling the button's sendAction.
            try await click(control,0.5)
            guard probe.opened else {throw PulseError.incomplete("sort popup did not open from pointer")}
            menu.performActionForItem(at:1)
            try await Task.sleep(for:.milliseconds(150))
        }
        // Deliberately different totals and window gains. Tall/ultrawide
        // original artwork makes the old visually-clipped hit overflow fail.
        let now=Date(),today=Calendar.autoupdatingCurrent.startOfDay(for:now)
        let early=today.addingTimeInterval(min(60,max(0,now.timeIntervalSince(today)/3)))
        let a=Design(id:"pointer-a",title:"Recent fixture",cover:"demo://hit-portrait",counts:Counts(likes:110,prints:80))
        let b=Design(id:"pointer-b",title:"Lifetime fixture",cover:"demo://hit-landscape",counts:Counts(likes:1000,prints:500))
        let c=Design(id:"pointer-c",title:"Third fixture",cover:"demo://hit-portrait",counts:Counts(likes:300,prints:10))
        let models=[a,b,c]
        let history:[String:[Sample]]=[
            a.id:[Sample(date:now.addingTimeInterval(-6*86400),counts:Counts(likes:50,prints:40)),Sample(date:today.addingTimeInterval(-60),counts:Counts(likes:70,prints:60)),Sample(date:early,counts:Counts(likes:100,prints:70)),Sample(date:now,counts:a.counts)],
            b.id:[Sample(date:now.addingTimeInterval(-6*86400),counts:Counts(likes:950,prints:480)),Sample(date:today.addingTimeInterval(-60),counts:Counts(likes:980,prints:490)),Sample(date:early,counts:Counts(likes:999,prints:499)),Sample(date:now.addingTimeInterval(-0.1),counts:b.counts)],
            c.id:[Sample(date:now.addingTimeInterval(-6*86400),counts:Counts(likes:280,prints:0)),Sample(date:today.addingTimeInterval(-60),counts:Counts(likes:290,prints:2)),Sample(date:early,counts:Counts(likes:299,prints:9)),Sample(date:now.addingTimeInterval(-0.2),counts:c.counts)]]
        model.state.models=models;model.latestModelIncreases=[:];model.state.preferences.watchedModelSort = .recent;model.state.preferences.watchedSortBasis = .total
        model.modelActivityReports=Dictionary(uniqueKeysWithValues:ModelActivityWindow.allCases.map{($0,ModelActivity.ranked(designs:models,samples:history,events:[],window:$0,now:now))})
        model.destination = .overview;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        var passed=0
        for layout in WatchedModelLayout.allCases {
            model.state.preferences.watchedModelLayout=layout
            for scale in [100,150] {
                model.state.preferences.textScalePercent=scale
                for theme in [ColorScheme.dark,.light] {
                    model.auditScheme=theme;window.setContentSize(NSSize(width:scale==150 ? 950:1280,height:860))
                    model.dashboardActivityWindow = .today;model.state.preferences.watchedModelSort = .recent;model.state.preferences.watchedSortBasis = .total
                    try await Task.sleep(for:.milliseconds(350))
                    guard let range=rangeControl() else{throw PulseError.incomplete("visible range control")}
                    let before=model.dashboardModelSelection.visible
                    try await click(range,0.5)
                    guard model.dashboardActivityWindow == .day,model.dashboardModelSelection.visible != before else{throw PulseError.incomplete("range pointer did not update card data")}
                    try await click(range,0.85)
                    guard model.dashboardActivityWindow == .week else{throw PulseError.incomplete("week pointer binding")}
                    try await click(range,0.1)
                    guard model.dashboardActivityWindow == .today else{throw PulseError.incomplete("today pointer binding")}
                    guard let sort=sortControl() else{throw PulseError.incomplete("visible sort control")}
                    try await chooseNextSort(sort)
                    guard model.state.preferences.dashboardSort == .prints,model.dashboardModelSelection.visible.first?.id==b.id else{throw PulseError.incomplete("sort pointer/menu did not update ordered cards")}
                    if let basis=all(root).compactMap({$0 as? NSSegmentedControl}).first(where:{$0.identifier?.rawValue=="dashboard-sort-basis"}) {
                        try await click(basis,0.8)
                        guard model.state.preferences.dashboardSortBasis == .growth,model.dashboardModelSelection.visible.first?.id==a.id else{throw PulseError.incomplete("sort basis pointer did not reorder cards")}
                    } else {throw PulseError.incomplete("visible sort basis")}
                    passed+=1
                }
            }
        }
        guard passed==8 else{throw PulseError.incomplete("dashboard pointer matrix")}
        return ["actualRangeMouseEvents":true,"rangeChangesRenderedSelectionData":true,"actualSortPopupAndNativeItemSelection":true,"sortChangesCardOrder":true,"actualBasisMouseEvents":true,"tallAndWideImageHitRegionsContained":true,"cardsAndCompact":true,"lightAndDark":true,"standardAnd150PercentText":true]
    }
}
