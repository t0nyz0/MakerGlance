import XCTest
@testable import MakerPulseCore

final class WatchedModelSortTests: XCTestCase {
    func item(_ id: String, total: Int?, gain: Int?, time: TimeInterval? = nil, title: String? = nil) -> ObservedModelActivity {
        let counts = Counts(likes: total, downloads: total, prints: total, boosts: total, collections: total)
        var deltas: [Metric: Int] = [:]
        for metric in ModelActivity.metrics { deltas[metric] = gain }
        return ObservedModelActivity(design: Design(id: id, title: title ?? id, counts: counts), deltas: deltas, baselineDate: nil, lastObservedAt: nil, lastMetricChangeAt: time.map(Date.init(timeIntervalSince1970:)), latestEvent: nil)
    }
    func testAllMetricSortsKeepMissingBelowZeroAndUseDescendingKnownValues() {
        let rows = [item("missing", total: nil, gain: nil), item("zero", total: 0, gain: 0), item("high", total: 100, gain: 4), item("negative", total: 1, gain: -2)]
        for sort in WatchedModelSort.allCases where sort.metric != nil {
            XCTAssertEqual(WatchedModelSorting.ordered(rows, by: sort, basis: .total).map(\.id), ["high", "negative", "zero", "missing"])
            XCTAssertEqual(WatchedModelSorting.ordered(rows, by: sort, basis: .growth).map(\.id), ["high", "zero", "negative", "missing"])
        }
    }
    func testLifetimeAndSelectedWindowGainsAreIndependent() {
        let now = Date(timeIntervalSince1970: 200000)
        let designs = [Design(id: "popular", title: "Popular", counts: Counts(prints: 1000)), Design(id: "growing", title: "Growing", counts: Counts(prints: 20))]
        let samples = ["popular": [Sample(date: now.addingTimeInterval(-2*86400), counts: Counts(prints: 900)), Sample(date: now.addingTimeInterval(-3600), counts: Counts(prints: 1000)), Sample(date: now, counts: Counts(prints: 1000))], "growing": [Sample(date: now.addingTimeInterval(-2*86400), counts: Counts(prints: 15)), Sample(date: now.addingTimeInterval(-3600), counts: Counts(prints: 15)), Sample(date: now, counts: Counts(prints: 20))]]
        let day = ModelActivity.ranked(designs: designs, samples: samples, events: [], window: .day, now: now)
        let week = ModelActivity.ranked(designs: designs, samples: samples, events: [], window: .week, now: now)
        XCTAssertEqual(WatchedModelSorting.ordered(day, by: .prints, basis: .total).first?.id, "popular")
        XCTAssertEqual(WatchedModelSorting.ordered(day, by: .prints, basis: .growth).first?.id, "growing")
        XCTAssertEqual(WatchedModelSorting.ordered(week, by: .prints, basis: .growth).first?.id, "popular")
    }
    func testRecentDefaultAndStableTiesDoNotUseFetchTime() {
        let rows = [item("2", total: 5, gain: 1, time: 10, title: "Same"), item("1", total: 5, gain: 1, time: 10, title: "Same"), item("3", total: 100, gain: 5, time: nil, title: "Absent")]
        XCTAssertEqual(WatchedModelSorting.ordered(rows, by: .recent, basis: .total).map(\.id), ["1", "2", "3"])
        XCTAssertEqual(WatchedModelSorting.ordered(Array(rows.reversed()), by: .recent, basis: .growth).map(\.id), ["1", "2", "3"])
        XCTAssertEqual(WatchedModelSorting.ordered(rows, by: .prints, basis: .growth).map(\.id), ["3", "1", "2"])
    }
    func testDefaultsAndPreferencesPersistWithoutResettingControls() throws {
        let original = Preferences()
        let old = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(old.dashboardSort, .recent); XCTAssertEqual(old.dashboardSortBasis, .total)
        var saved = old; saved.watchedModelSort = .saves; saved.watchedSortBasis = .growth; saved.watchedModelLayout = .compact; saved.textScalePercent = 150
        let loaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(loaded.dashboardSort, .saves); XCTAssertEqual(loaded.dashboardSortBasis, .growth)
        XCTAssertEqual(loaded.watchedLayout, .compact); XCTAssertEqual(loaded.textSizePercent, 150)
    }
    func testSortBeforeLimitPreservesWatchesAndAllMetricsInBothLayouts() {
        let rows = (0..<14).map { item(String($0), total: $0, gain: $0) }
        var paused = WatchRule(); paused.enabled = false
        let ranked = WatchedModelSorting.ordered(rows, by: .downloads, basis: .total)
        let selection = WatchedModelSelection(ranked: ranked, watches: ["13": paused], expanded: false)
        XCTAssertEqual(selection.visible.first?.id, "12"); XCTAssertEqual(selection.visible.count, 9)
        XCTAssertEqual(selection.visible[0].deltas[.prints], 12)
        XCTAssertEqual(selection.visible[0].design.counts.collections, 12)
        XCTAssertFalse(selection.all.contains { $0.id == "13" })
    }
}

extension WatchedModelSortTests {
    func testDashboardRangeSwitchesChangeGainsAndGrowthOrderWhileKeepingTotalsAndWatches() throws {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let now=ISO8601DateFormatter().date(from:"2026-10-23T18:00:00Z")!
        let today=calendar.startOfDay(for:now)
        let a=Design(id:"recent",title:"Recent",counts:Counts(prints:80)),b=Design(id:"popular",title:"Popular",counts:Counts(prints:500)),c=Design(id:"paused",title:"Paused",counts:Counts(prints:2000))
        let samples=[a.id:[Sample(date:now.addingTimeInterval(-6*86400),counts:Counts(prints:40)),Sample(date:today.addingTimeInterval(-60),counts:Counts(prints:60)),Sample(date:today.addingTimeInterval(60),counts:Counts(prints:70)),Sample(date:now,counts:a.counts)],b.id:[Sample(date:now.addingTimeInterval(-6*86400),counts:Counts(prints:450)),Sample(date:today.addingTimeInterval(-60),counts:Counts(prints:490)),Sample(date:today.addingTimeInterval(60),counts:Counts(prints:499)),Sample(date:now.addingTimeInterval(-1),counts:b.counts)]]
        var paused=WatchRule();paused.enabled=false
        let watches=[c.id:paused]
        let expected:[ModelActivityWindow:(Int,String)]=[.today:(10,a.id),.day:(20,a.id),.week:(40,b.id)]
        for window in [ModelActivityWindow.today,.day,.week,.today,.week,.day,.today] {
            let report=ModelActivity.ranked(designs:[a,b,c],samples:samples,events:[],window:window,now:now,calendar:calendar)
            let growth=WatchedModelSelection(ranked:WatchedModelSorting.ordered(report,by:.prints,basis:.growth),watches:watches,expanded:true)
            XCTAssertEqual(growth.visible.first?.id,expected[window]!.1)
            XCTAssertEqual(growth.all.first{$0.id==a.id}?.deltas[.prints],expected[window]!.0)
            XCTAssertFalse(growth.all.contains{$0.id==c.id});XCTAssertEqual(growth.all.count,2)
            let totals=WatchedModelSelection(ranked:WatchedModelSorting.ordered(report,by:.prints,basis:.total),watches:watches,expanded:false)
            XCTAssertEqual(totals.visible.first?.id,b.id);XCTAssertEqual(totals.visible.first?.design.counts.prints,500)
        }
        XCTAssertFalse(watches[c.id]!.enabled)
    }
    func testDifferentRangesCanHonestlyHaveIdenticalGainsWhenOnlyTodayWasObserved() {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let now=ISO8601DateFormatter().date(from:"2026-10-23T18:00:00Z")!
        let design=Design(id:"sample",title:"Sample",counts:Counts(likes:15))
        let samples=[design.id:[Sample(date:now.addingTimeInterval(-3600),counts:Counts(likes:10)),Sample(date:now,counts:design.counts)]]
        let reports=ModelActivityWindow.allCases.map{ModelActivity.ranked(designs:[design],samples:samples,events:[],window:$0,now:now,calendar:calendar)}
        XCTAssertTrue(reports.allSatisfy{$0.first?.deltas[.likes]==5})
        XCTAssertEqual(Set(ModelActivityWindow.allCases.map(\.title)).count,3)
    }
}
