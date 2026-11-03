import XCTest
@testable import MakerPulseCore

final class PrintHistoryTests: XCTestCase {
    let payload = Data(#"{"total":2,"hits":[{"id":123,"designTitle":"Sample model","title":"Sample job","status":2,"cover":"demo://planter","deviceId":"printer-a","deviceName":"Studio printer","plateIndex":1,"plateName":"Small plate","startTime":"2026-10-22T10:00:00Z","endTime":"2026-10-22T10:05:00Z","costTime":3600,"mode":"cloud_file","isPublicProfile":false},{"id":"124","status":4,"startTime":"2026-10-22T10:00:00.123Z","endTime":"2026-10-22T10:00:10.123Z","costTime":3600}]}"#.utf8)
    func testParsesSuppliedContextAndSeparatesElapsedFromEstimate() throws {
        let page=try PrintTaskParser.page(payload);let job=page.items[0]
        XCTAssertEqual(page.total,2);XCTAssertEqual(job.id,"123");XCTAssertEqual(job.displayTitle,"Sample model")
        XCTAssertEqual(job.plateLabel,"Small plate");XCTAssertEqual(job.deviceName,"Studio printer");XCTAssertEqual(job.isPublicProfile,false)
        XCTAssertEqual(job.elapsedSeconds,300);XCTAssertEqual(job.estimatedSeconds,3600)
        XCTAssertEqual(page.items[1].outcome,.stopped);XCTAssertEqual(page.items[1].elapsedSeconds,10)
    }
    func testMissingFieldsAndUnknownStatusesAreNotFabricated() throws {
        let page=try PrintTaskParser.page(Data(#"{"hits":[{"id":"x","status":99},{"id":"y","status":1,"startTime":"2026-10-22T10:00:00Z","endTime":"2026-10-22T10:00:01Z"}]}"#.utf8))
        XCTAssertNil(page.total);XCTAssertEqual(page.items[0].outcome,.unknown);XCTAssertEqual(page.items[0].displayTitle,"Untitled print")
        XCTAssertNil(page.items[0].estimatedSeconds);XCTAssertNil(page.items[0].plateLabel);XCTAssertNil(page.items[1].elapsedSeconds)
        XCTAssertFalse(page.items[1].isTerminal)
    }
    func testRejectsInvalidIdentifiersEnvelopeAndTotals() {
        for json in [#"{}"#,#"{"hits":[{"id":true}]}"#,#"{"hits":[{"id":""}]}"#,#"{"hits":[{"id":1.5}]}"#,#"{"total":-1,"hits":[]}"#,#"{"total":"bad","hits":[]}"#] {
            XCTAssertThrowsError(try PrintTaskParser.page(Data(json.utf8)))
        }
    }
    func testTimeZonesInvalidDurationsAndNegativeEstimates() throws {
        let row=try PrintTaskParser.page(Data(#"{"hits":[{"id":"x","status":2,"startTime":"2026-10-22T10:00:00+02:00","endTime":"2026-10-22T08:01:00Z","costTime":-3},{"id":"y","status":3,"startTime":"2026-10-22T10:00:00Z","endTime":"2026-10-21T10:00:00Z"},{"id":"z","startTime":"yesterday"}]}"#.utf8)).items
        XCTAssertEqual(row[0].elapsedSeconds,60);XCTAssertNil(row[0].estimatedSeconds);XCTAssertNil(row[1].elapsedSeconds);XCTAssertNil(row[2].startTime)
    }
    func testAccountScopedMergeRefreshesStatusWithoutDuplicatingOrErasingHistory() throws {
        var h=PrintHistory(accountID:"sample-account");let date=Date(timeIntervalSince1970:100)
        try h.merge(PrintTaskBatch(jobs:[PrintJob(id:"1",title:"First",status:1),PrintJob(id:"2",title:"Second",status:2)],cloudTotal:2,complete:true),accountID:"sample-account",at:date)
        try h.merge(PrintTaskBatch(jobs:[PrintJob(id:"1",title:"Updated",status:2)],cloudTotal:1,complete:false),accountID:"sample-account",at:date.addingTimeInterval(20))
        XCTAssertEqual(h.jobs.count,2);let updated=h.jobs.first{$0.id=="1"}!
        XCTAssertEqual(updated.firstObservedAt,date);XCTAssertEqual(updated.lastObservedAt,date.addingTimeInterval(20));XCTAssertEqual(updated.outcome,.succeeded)
        XCTAssertEqual(h.lastFullSync,date);XCTAssertThrowsError(try h.merge(PrintTaskBatch(jobs:[],cloudTotal:0,complete:true),accountID:"another-account",at:date))
    }
    func testLegacyStateAndLocalHistorySurviveSQLiteRestart() async throws {
        var state=try JSONDecoder().decode(LibraryState.self,from:JSONEncoder().encode(LibraryState()))
        XCTAssertNil(state.printHistory);state.printHistory=PrintHistory(accountID:"sample")
        try state.printHistory!.merge(PrintTaskBatch(jobs:try PrintTaskParser.page(payload).items,cloudTotal:2,complete:true),accountID:"sample",at:Date())
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("test.sqlite"),store=try Storage(url:url);try await store.commit(state)
        let restored=try await Storage(url:url).load();XCTAssertEqual(restored.printHistory,state.printHistory);XCTAssertTrue(restored.models.isEmpty)
    }
    func testPaginationUsesActualServerCapAndDeduplicatesOverlap() async throws {
        let pager=TaskPager([Page(items:[PrintJob(id:"1"),PrintJob(id:"2")],total:3),Page(items:[PrintJob(id:"2"),PrintJob(id:"3")],total:3)])
        let r=try await PrintTaskPagination.collect(known:nil,forceFull:true){offset,limit in try await pager.fetch(offset,limit)}
        XCTAssertEqual(r.jobs.map(\.id),["1","2","3"]);XCTAssertTrue(r.complete)
        let offsets=await pager.offsets;XCTAssertEqual(offsets,[0,2])
    }
    func testPaginationRejectsRepeatingChangingAndIncompletePages() async {
        let pages:[[Page<PrintJob>]]=[
            [Page(items:[PrintJob(id:"1")],total:2),Page(items:[PrintJob(id:"1")],total:2)],
            [Page(items:[PrintJob(id:"1")],total:2),Page(items:[PrintJob(id:"2")],total:3)],
            [Page(items:[PrintJob(id:"1")],total:2),Page(items:[],total:2)]]
        for input in pages { let p=TaskPager(input);do{_ = try await PrintTaskPagination.collect(known:nil,forceFull:true){a,b in try await p.fetch(a,b)};XCTFail("Incomplete import accepted")}catch{} }
    }
    func testIncrementalCrawlRevisitsOlderUnfinishedJobs() async throws {
        var h=PrintHistory(accountID:"sample");h.jobs=[PrintJob(id:"1",status:2),PrintJob(id:"old",status:1)]
        let p=TaskPager([Page(items:[PrintJob(id:"new",status:2),PrintJob(id:"1",status:2)],total:5),Page(items:[PrintJob(id:"old",status:2)],total:5)])
        let r=try await PrintTaskPagination.collect(known:h,forceFull:false){a,b in try await p.fetch(a,b)}
        XCTAssertEqual(r.jobs.map(\.id),["new","1","old"]);XCTAssertFalse(r.complete)
        let offsets=await p.offsets;XCTAssertEqual(offsets,[0,2])
    }
    func testUnknownTotalContinuesPastShortPagesAndHasBoundedWork() async throws {
        let p=TaskPager([Page(items:[PrintJob(id:"1")],total:nil),Page(items:[PrintJob(id:"2")],total:nil),Page(items:[],total:nil)])
        let r=try await PrintTaskPagination.collect(known:nil,forceFull:true){a,b in try await p.fetch(a,b)};XCTAssertEqual(r.jobs.count,2);XCTAssertTrue(r.complete)
        let q=TaskPager([Page(items:[PrintJob(id:"1")],total:9)])
        do{_ = try await PrintTaskPagination.collect(known:nil,forceFull:true,maxPages:1){a,b in try await q.fetch(a,b)};XCTFail()}catch{}
    }
}
private actor TaskPager {
    var pages:[Page<PrintJob>];var offsets:[Int]=[]
    init(_ pages:[Page<PrintJob>]){self.pages=pages}
    func fetch(_ offset:Int,_ limit:Int)throws->Page<PrintJob>{offsets.append(offset);guard !pages.isEmpty else{throw PulseError.incomplete("test pages")};return pages.removeFirst()}
}

extension PrintHistoryTests {
    func testSearchStatusPrinterDateAndStableDurationSort() throws {
        var rows=try PrintTaskParser.page(payload).items
        rows[0].startTime=Date(timeIntervalSince1970:100);rows[0].endTime=Date(timeIntervalSince1970:400)
        rows[1].startTime=Date(timeIntervalSince1970:1000);rows[1].endTime=Date(timeIntervalSince1970:1010)
        rows.append(PrintJob(id:"missing"))
        XCTAssertEqual(PrintHistoryQuery.select(rows,search:" SMALL ").map(\.id),["123"])
        XCTAssertEqual(PrintHistoryQuery.select(rows,outcome:.stopped).map(\.id),["124"])
        XCTAssertEqual(PrintHistoryQuery.select(rows,printer:"Studio printer").map(\.id),["123"])
        XCTAssertEqual(PrintHistoryQuery.select(rows,order:.elapsed).map(\.id),["123","124","missing"])
        XCTAssertEqual(PrintHistoryQuery.select(rows,order:.oldest).map(\.id),["123","124","missing"])
        XCTAssertTrue(PrintHistoryQuery.select(rows,range:.week,now:Date(timeIntervalSince1970:1_000_000)).isEmpty)
        XCTAssertEqual(PrintHistoryQuery.select(rows).last?.id,"missing")
    }
    func testFullCrawlPreservesMissingLocalJobsAndDoesNotKeepRequeryingThemAsActive() async throws {
        var h=PrintHistory(accountID:"sample");h.jobs=[PrintJob(id:"old",status:1)]
        try h.merge(PrintTaskBatch(jobs:[PrintJob(id:"new",status:2)],cloudTotal:1,complete:true),accountID:"sample",at:Date())
        XCTAssertEqual(h.jobs.count,2);XCTAssertEqual(h.jobs.first{$0.id=="old"}?.inLatestCloudCrawl,false)
        let p=TaskPager([Page(items:[PrintJob(id:"new",status:2)],total:2)])
        let r=try await PrintTaskPagination.collect(known:h,forceFull:false){a,b in try await p.fetch(a,b)}
        XCTAssertFalse(r.complete);XCTAssertEqual(r.jobs.count,1)
    }
    func testConcurrentOldObservationKeepsNewPrintHistoryAndControls() throws {
        var current=LibraryState();current.preferences.userID="sample";current.preferences.textScalePercent=150
        current.printHistory=PrintHistory(accountID:"sample")
        try current.printHistory!.merge(PrintTaskBatch(jobs:[PrintJob(id:"job",status:2)],cloudTotal:1,complete:true),accountID:"sample",at:Date())
        var old=LibraryState();old.preferences.userID="sample"
        XCTAssertTrue(LocalControls.preserve(from:current,in:&old));XCTAssertEqual(old.printHistory,current.printHistory);XCTAssertEqual(old.preferences.textSizePercent,150)
    }
    func testReadOnlyAPIRouteRequiresExistingSessionAndUsesPagedGET() async throws {
        let transport=PrintAPIFake([HTTPResult(data:payload,status:200)])
        let api=MakerWorldAPI(transport:transport,minimumInterval:0)
        do{_ = try await api.printTasks(known:nil,forceFull:true);XCTFail("Unauthenticated history request allowed")}catch{}
        let before=await transport.requests;XCTAssertTrue(before.isEmpty)
        await api.useSession("synthetic-session")
        let batch=try await api.printTasks(known:nil,forceFull:true);XCTAssertEqual(batch.jobs.count,2)
        let request=await transport.requests[0]
        XCTAssertEqual(request.httpMethod,"GET");XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.host,"api.bambulab.com");XCTAssertEqual(request.url?.path,"/v1/user-service/my/tasks")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer synthetic-session")
        XCTAssertNil(request.value(forHTTPHeaderField:"Cookie"))
    }
}
private actor PrintAPIFake:HTTPTransport {
    var responses:[HTTPResult];var requests:[URLRequest]=[]
    init(_ responses:[HTTPResult]){self.responses=responses}
    func send(_ request:URLRequest)throws->HTTPResult{requests.append(request);guard !responses.isEmpty else{throw PulseError.incomplete("test")};return responses.removeFirst()}
}

extension PrintHistoryTests {
    func testPrintCoverPolicyAllowsOnlyVerifiedBucketAndPreservesSignedQuery() {
        let signed="https://or-cloud-model-prod.s3.dualstack.us-west-2.amazonaws.com/sample.png?X-Amz-Signature=synthetic%2Bvalue&X-Amz-Expires=60"
        XCTAssertEqual(ImageURLPolicy.thumbnail(signed)?.absoluteString,signed)
        for raw in ["https://another-bucket.s3.dualstack.us-west-2.amazonaws.com/a.png","https://or-cloud-model-prod.s3.dualstack.us-west-2.amazonaws.com.attacker.invalid/a.png","http://or-cloud-model-prod.s3.dualstack.us-west-2.amazonaws.com/a.png","https://user:pass@or-cloud-model-prod.s3.dualstack.us-west-2.amazonaws.com/a.png"] { XCTAssertNil(ImageURLPolicy.thumbnail(raw)) }
    }
}
