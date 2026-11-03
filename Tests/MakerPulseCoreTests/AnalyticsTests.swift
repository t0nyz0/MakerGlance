import XCTest
@testable import MakerPulseCore

final class AnalyticsTests: XCTestCase {
    let date = Date()
    func profile(likes: Int = 9428, downloads: Int = 17473, boosts: Int = 742) -> Profile {
        Profile(id: "1", name: "Maker", handle: "maker", counts: Counts(likes: likes, downloads: downloads, boosts: boosts, followers: 862))
    }
    func design(boosts: Int = 200, likes: Int = 5000, id: String = "10") -> Design {
        Design(id: id, title: "Conveyor", counts: Counts(likes: likes, downloads: 1400, boosts: boosts, collections: 1200))
    }
    func follower(_ id: String) -> Follower { Follower(id: id, name: id, handle: "maker\(id)") }

    func testFirstImportIsSilentAndDatesRemainUnknown() {
        var state = LibraryState()
        XCTAssertTrue(Analytics.ingestProfile(profile(), into: &state, at: date).isEmpty)
        XCTAssertTrue(Analytics.ingestModels([design()], into: &state, at: date).isEmpty)
        XCTAssertTrue(Analytics.ingestFollowers([follower("1"), follower("2")], into: &state, at: date).isEmpty)
        XCTAssertEqual(state.followers.count, 2)
        XCTAssertTrue(state.followers.allSatisfy { $0.baseline && $0.firstObservedAt == nil })
        XCTAssertTrue(state.activity.isEmpty)
    }
    func testNewFollowerGetsObservationDateAndRepeatedCrawlIsQuiet() {
        var state = LibraryState()
        _ = Analytics.ingestFollowers([follower("1")], into: &state, at: date)
        let later = date.addingTimeInterval(100)
        let events = Analytics.ingestFollowers([follower("1"), follower("2"), follower("2")], into: &state, at: later)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(state.followers.count, 2)
        XCTAssertEqual(state.followers.first { $0.id == "2" }?.firstObservedAt, later)
        XCTAssertFalse(state.followers.first { $0.id == "2" }!.baseline)
        XCTAssertTrue(Analytics.ingestFollowers([follower("1"), follower("2")], into: &state, at: later).isEmpty)
    }
    func testReturningFollowersKeepDatesAndDoNotAlertAgain() {
        var state = LibraryState()
        _ = Analytics.ingestFollowers([follower("1")], into: &state, at: date)
        _ = Analytics.ingestFollowers([follower("1"), follower("2")], into: &state, at: date)
        _ = Analytics.ingestFollowers([follower("1")], into: &state, at: date)
        XCTAssertFalse(state.followers.first { $0.id == "2" }!.isFollowing)
        XCTAssertTrue(Analytics.ingestFollowers([follower("2")], into: &state, at: date.addingTimeInterval(200)).isEmpty)
        XCTAssertEqual(state.followers.first { $0.id == "2" }!.firstObservedAt, date)
    }
    func testMilestoneCrossingCoalescesAndDoesNotRepeatAfterCorrection() {
        var state = LibraryState()
        _ = Analytics.ingestProfile(profile(likes: 900), into: &state, at: date)
        let events = Analytics.ingestProfile(profile(likes: 3500), into: &state, at: date)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].id.contains("3000"))
        XCTAssertTrue(Analytics.ingestProfile(profile(likes: 3500), into: &state, at: date).isEmpty)
        XCTAssertTrue(Analytics.ingestProfile(profile(likes: 800), into: &state, at: date).isEmpty)
        XCTAssertTrue(Analytics.ingestProfile(profile(likes: 3500), into: &state, at: date).isEmpty)
    }
    func testDisabledMilestonesAdvanceHighWaterWithoutCatchupStorm() {
        var state = LibraryState()
        _ = Analytics.ingestProfile(profile(likes: 900), into: &state, at: date)
        state.preferences.notifyMilestones = false
        XCTAssertTrue(Analytics.ingestProfile(profile(likes: 3000), into: &state, at: date).isEmpty)
        state.preferences.notifyMilestones = true
        XCTAssertTrue(Analytics.ingestProfile(profile(likes: 3001), into: &state, at: date).isEmpty)
        XCTAssertEqual(Analytics.ingestProfile(profile(likes: 4000), into: &state, at: date).count, 1)
    }
    func testWatchTypesAndPauseDoNotBackfillBoosts() {
        var state = LibraryState()
        _ = Analytics.ingestModels([design()], into: &state, at: date)
        XCTAssertTrue(Analytics.ingestModels([design(likes: 5001)], into: &state, at: date).isEmpty)
        XCTAssertEqual(Analytics.ingestModels([design(boosts: 202)], into: &state, at: date).count, 1)
        state.watches["10"]?.enabled = false
        XCTAssertTrue(Analytics.ingestModels([design(boosts: 205)], into: &state, at: date).isEmpty)
        state.watches["10"]?.enabled = true
        XCTAssertTrue(Analytics.ingestModels([design(boosts: 205)], into: &state, at: date).isEmpty)
        XCTAssertEqual(Analytics.ingestModels([design(boosts: 206)], into: &state, at: date).count, 1)
    }
    func testUnavailableMetricsAreNotZeroAndDoNotAlert() {
        var state = LibraryState()
        _ = Analytics.ingestModels([design()], into: &state, at: date)
        var updated = design(); updated.counts.boosts = nil
        XCTAssertTrue(Analytics.ingestModels([updated], into: &state, at: date).isEmpty)
        XCTAssertEqual(state.highWater["model:10:boosts"], 200)
    }
    func testHistoricalDeltaUsesObservedBaseline() {
        let samples = [Sample(date: date.addingTimeInterval(-90000), counts: Counts(likes: 10)), Sample(date: date, counts: Counts(likes: 15))]
        XCTAssertEqual(Analytics.delta(.likes, samples: samples, current: Counts(likes: 20), since: date.addingTimeInterval(-86400)), 10)
        XCTAssertNil(Analytics.delta(.boosts, samples: samples, current: Counts(likes: 20), since: date))
    }
}
