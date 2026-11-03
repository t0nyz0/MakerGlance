import SwiftUI
import MakerPulseCore

struct MyPrintsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.appTextScale) private var scale
    @State private var selected: PrintJob?
    var jobs: [PrintJob] { model.myPrints?.jobs ?? [] }
    var shown: [PrintJob] { model.visiblePrintJobs }
    var printers: [String] { Array(Set(jobs.compactMap(\.deviceName))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) { heading; Spacer(); refresh }
                    VStack(alignment: .leading, spacing: 12) { heading; refresh }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Label(model.printsLoading ? "Updating cloud history…" : "Cloud history, kept on your Mac", systemImage: "lock.shield").appFont(.headline); Spacer(); if model.printsLoading { ProgressView().controlSize(.small) } }
                        Text(model.printsStatus).appFont(.callout).foregroundStyle(Palette.secondaryText).textSelection(.enabled)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { summary; Spacer(); historyDetails }
                            VStack(alignment: .leading, spacing: 10) { summary; historyDetails }
                        }
                        if !model.accountSessionAvailable && !model.isDemo { Button("Connect in Settings") { model.destination = .settings }.buttonStyle(.bordered) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { searchField; outcomePicker }
                        VStack(alignment: .leading, spacing: 12) { searchField; outcomePicker }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { printerPicker; datePicker; sortPicker; Spacer() }
                        VStack(alignment: .leading, spacing: 12) { printerPicker; HStack { datePicker; sortPicker } }
                    }
                }
                if shown.isEmpty {
                    Surface { EmptyPanel(title: jobs.isEmpty ? "Your cloud print history belongs here" : "No matching prints", detail: jobs.isEmpty ? "Connect your existing Bambu account and refresh. Only jobs returned by the cloud can be imported; older offline or LAN-only prints may not appear." : "Try another status, printer, date range or search. Saved records are preserved.", symbol: "printer") }
                } else {
                    Text("\(shown.count.formatted()) of \(jobs.count.formatted()) saved prints").appFont(.callout).foregroundStyle(Palette.secondaryText)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 310 * max(1,scale)),spacing: 18,alignment: .top)], spacing: 18) {
                        ForEach(shown) { job in Button { selected = job } label: { PrintHistoryCard(job: job) }.buttonStyle(.plain).help("Open print details").accessibilityLabel("\(job.displayTitle), \(job.outcome.title). Open print details.") }
                    }
                }
            }.padding(30)
        }.sheet(item: $selected) { PrintJobDetail(job: $0) }
        .onChange(of: printers) { _, names in if !model.printPrinter.isEmpty && !names.contains(model.printPrinter) { model.printPrinter = "" } }
        .task { if model.myPrints == nil && model.accountSessionAvailable && !model.isRefreshing { await model.refreshPrintHistory(forceFull: true) } }
    }
    var heading: some View { VStack(alignment: .leading, spacing: 8) { Text("My Prints").appFont(size: 32, weight: .semibold); Text("Your own cloud print jobs—not your models’ public print counts.").foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true) } }
    var refresh: some View { Button { Task { await model.refreshPrintHistory(forceFull: true) } } label: { Label("Refresh history",systemImage: "arrow.clockwise") }.buttonStyle(.bordered).disabled(model.isRefreshing || !model.accountSessionAvailable || model.isDemo).accessibilityIdentifier("my-prints-refresh") }
    var summary: some View { HStack(spacing: 14) { Label("\(jobs.count.formatted()) saved",systemImage: "internaldrive"); if let total=model.myPrints?.cloudTotal { Text("\(total.formatted()) currently in cloud") } }.appFont(size: 12).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true) }
    var historyDetails: some View { ContextInfo("Print-history coverage and status") {
        Text("Read-only Bambu cloud task history, scoped to the connected creator account. Saved records remain local if a job disappears from the cloud. Failed or incomplete imports keep the last successful history.")
        Text("Recent checks revisit the newest pages and previously unfinished jobs; a full crawl runs hourly and when you click Refresh history. This is periodic history, not live printer telemetry.")
        Text("The cloud’s stopped codes do not reliably distinguish user cancellation from failure, so they are grouped as Canceled / failed. Unknown status codes remain explicit.")
        Text("Recorded elapsed time uses completed start/end timestamps. Slice estimates are labeled separately; neither proves material actually consumed. No filament-usage estimates or printer controls are provided.")
        Text("Offline/LAN-only jobs and old jobs missing from the service cannot be reconstructed. These private jobs do not change public-model metrics or create initial-import notifications.")
    } }
    var searchField: some View { PrintSearchField(text: $model.printSearch).frame(minWidth: 210, minHeight: 28 * max(1,scale)) }
    var outcomePicker: some View { PrintFilterMenu(label:"Status", identifier:"my-prints-status", options:PrintOutcome.allCases.map{($0.title,$0)}, selection:$model.printOutcome).frame(width: 240 * min(1.3,max(1,scale))).accessibilityIdentifier("my-prints-status") }
    var printerPicker: some View { PrintFilterMenu(label:"Printer name", identifier:"my-prints-printer", options:[("All printers","")]+printers.map{($0,$0)}, selection:$model.printPrinter).frame(maxWidth: 340).accessibilityIdentifier("my-prints-printer") }
    var datePicker: some View { PrintFilterMenu(label:"Started", identifier:"my-prints-date", options:PrintHistoryRange.allCases.map{($0.title,$0)}, selection:$model.printRange).frame(maxWidth: 250).accessibilityIdentifier("my-prints-date") }
    var sortPicker: some View { PrintFilterMenu(label:"Sort", identifier:"my-prints-sort", options:PrintHistoryOrder.allCases.map{($0.title,$0)}, selection:$model.printOrder).frame(maxWidth: 250).accessibilityIdentifier("my-prints-sort") }
}

struct PrintHistoryCard: View {
    let job: PrintJob
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            GeometryReader { box in RemoteImage(url:job.cover,symbol:"printer",pixelWidth:700,contentMode:.fit).frame(width:box.size.width,height:190).clipped() }.frame(height:190).clipShape(RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:12) {
                PrintStatusBadge(job:job)
                Text(job.displayTitle).appFont(size:17,weight:.semibold).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(3)
                Label(job.deviceName ?? "Printer name unavailable",systemImage:"printer").appFont(.callout).foregroundStyle(Palette.secondaryText).multilineTextAlignment(.leading)
                if job.inLatestCloudCrawl == false { Text("Saved copy · absent from last full cloud crawl").appFont(size:12).foregroundStyle(Palette.orange) }
                if let plate=job.plateLabel { Label(plate,systemImage:"square.stack.3d.up").appFont(.callout).foregroundStyle(Palette.secondaryText).lineLimit(2) }
                Divider().opacity(0.3)
                VStack(alignment:.leading,spacing:6) {
                    Label(job.startTime.map{$0.formatted(date:.abbreviated,time:.shortened)} ?? "Start date unavailable",systemImage:"calendar")
                    if let elapsed=job.elapsedSeconds { Label(PrintJobPresentation.duration(elapsed)+" elapsed",systemImage:"timer") }
                    else if let estimate=job.estimatedSeconds { Label(PrintJobPresentation.duration(estimate)+" slice estimate",systemImage:"clock") }
                    else { Label("Duration unavailable",systemImage:"clock") }
                }.appFont(size:12).foregroundStyle(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Palette.surface,in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(Palette.line.opacity(0.35),lineWidth:0.7))
    }
}
struct PrintStatusBadge: View {
    let job:PrintJob
    var symbol:String { switch job.outcome {case .succeeded:"checkmark.circle.fill";case .stopped:"stop.circle";case .unfinished:"clock.arrow.circlepath";default:"questionmark.circle"} }
    var color:Color { switch job.outcome {case .succeeded:Palette.positive;case .stopped:Palette.orange;case .unfinished:Palette.accent;default:Palette.secondaryText} }
    var body:some View { Label(job.outcome == .unknown ? "Unknown status\(job.status.map{" · \($0)"} ?? "")" : job.outcome.title,systemImage:symbol).appFont(size:12,weight:.semibold).foregroundStyle(color).padding(.horizontal,9).padding(.vertical,5).background(color.opacity(0.1),in:Capsule()).help("Cloud task status: \(job.status.map(String.init) ?? "not supplied"). Last observed: \(job.lastObservedAt?.formatted() ?? "not yet saved").") }
}
struct PrintJobDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTextScale) private var scale
    let job:PrintJob
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            HStack { Text("Print details").appFont(.title,weight:.semibold);Spacer();Button("Done"){dismiss()}.keyboardShortcut(.cancelAction) }
            GeometryReader { box in RemoteImage(url:job.cover,symbol:"printer",pixelWidth:1000,contentMode:.fit).frame(width:box.size.width,height:220).clipped() }.frame(height:220).clipShape(RoundedRectangle(cornerRadius:14))
            Text(job.displayTitle).appFont(.title2,weight:.semibold);PrintStatusBadge(job:job)
            Grid(alignment:.leading,horizontalSpacing:20,verticalSpacing:12) {
                field("Printer",job.deviceName);field("Plate",job.plateLabel)
                if job.title != job.displayTitle { field("Job title",job.title) }
                field("Started",job.startTime?.formatted(date:.complete,time:.standard));field("Ended",job.endTime?.formatted(date:.complete,time:.standard))
                field("Recorded elapsed",job.elapsedSeconds.map(PrintJobPresentation.duration));field("Slice estimate",job.estimatedSeconds.map(PrintJobPresentation.duration))
                field("Cloud mode",job.mode);field("Task ID",job.id)
                field("Last observed",job.lastObservedAt?.formatted(date:.abbreviated,time:.standard))
            }.appFont(.callout).textSelection(.enabled)
            Text("This is a saved cloud record. The elapsed value comes from completed timestamps; the slice estimate is not actual runtime or measured material usage. Stopped records may represent cancellation or failure. No printer commands are sent.").appFont(.callout).foregroundStyle(Palette.secondaryText).fixedSize(horizontal:false,vertical:true)
        }.padding(28) }.frame(width:min(820,620*max(1,scale)),height:760).background(Palette.canvas)
    }
    func field(_ name:String,_ value:String?)->some View { GridRow { Text(name).foregroundStyle(Palette.secondaryText);Text(value ?? "Not supplied").frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true) } }
}
enum PrintJobPresentation {
    static func duration(_ seconds:Double)->String {
        guard seconds.isFinite,seconds>=0,seconds<Double(Int.max) else{return "Unavailable"}
        let total=Int(seconds),hours=total/3600,minutes=(total%3600)/60
        if hours>0{return "\(hours)h \(minutes)m"};if minutes>0{return "\(minutes)m \(total%60)s"};return "\(total)s"
    }
}
