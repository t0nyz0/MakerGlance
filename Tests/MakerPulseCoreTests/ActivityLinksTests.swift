import XCTest
@testable import MakerPulseCore

final class ActivityLinksTests: XCTestCase {
    func testNewFollowerNotificationOpensThatFollowerRatherThanTheMonitoredAccount() throws {
        var state = LibraryState()
        state.profile = Profile(id: "1", name: "Sample Studio", handle: "samplecreator", counts: Counts())
        _ = Analytics.ingestFollowers([], into: &state, at: Date())
        let follower = Follower(id: "42", name: "samplemaker", handle: "samplemaker")
        let event = try XCTUnwrap(Analytics.ingestFollowers([follower], into: &state, at: Date()).first)
        XCTAssertEqual(event.presentation?.actorID, follower.id)
        XCTAssertEqual(ActivityLinks.followerProfile(for: event, followers: state.followers)?.absoluteString, "https://makerworld.com/en/@samplemaker")
    }

    func testSavedNotificationWithoutPresentationResolvesFromItsStableFollowerID() throws {
        let data = Data(#"{"id":"followers:42","date":0,"title":"New follower","detail":"@oldHandle","symbol":"person.badge.plus","isRead":true}"#.utf8)
        let saved = try JSONDecoder().decode(Activity.self, from: data)
        let follower = Follower(id: "42", name: "Display name", handle: "currentHandle")
        XCTAssertEqual(ActivityLinks.followerProfile(for: saved, followers: [follower])?.absoluteString, "https://makerworld.com/en/@currentHandle")
        XCTAssertTrue(saved.isRead)
    }

    func testStoredHandleStillWorksWhenFollowerIsNotInTheCurrentLibrary() {
        let event = Activity(id: "followers:42", date: Date(), title: "New follower", detail: "@samplemaker", symbol: "person.badge.plus", presentation: ActivityPresentation(actorHandle: "samplemaker"))
        XCTAssertEqual(ActivityLinks.followerProfile(for: event, followers: [])?.absoluteString, "https://makerworld.com/en/@samplemaker")
    }

    func testGroupedUpdatesMilestonesAndUnknownIdentitiesDoNotChooseAnUnrelatedProfile() {
        let follower = Follower(id: "42", name: "Maker", handle: "maker")
        for id in ["followers:42,43", "followers:", "profile:1:followers:milestone:1000"] {
            let event = Activity(id: id, date: Date(), title: "Update", detail: "", symbol: "person", presentation: ActivityPresentation(actorHandle: "someone"))
            XCTAssertNil(ActivityLinks.followerProfile(for: event, followers: [follower]))
        }
        let unknown = Activity(id: "followers:43", date: Date(), title: "New follower", detail: "@unverified", symbol: "person")
        XCTAssertNil(ActivityLinks.followerProfile(for: unknown, followers: [follower]))
        let mismatch = Activity(id: "followers:43", date: Date(), title: "New follower", detail: "", symbol: "person", presentation: ActivityPresentation(actorID: "42", actorHandle: "maker"))
        XCTAssertNil(ActivityLinks.followerProfile(for: mismatch, followers: []))
    }

    func testHandleIsEncodedAsOnePathSegmentOnMakerWorld() throws {
        let event = Activity(id: "followers:42", date: Date(), title: "New follower", detail: "", symbol: "person", presentation: ActivityPresentation(actorHandle: "@maker/one?x=1#fragment"))
        let url = try XCTUnwrap(ActivityLinks.followerProfile(for: event, followers: []))
        XCTAssertEqual(url.absoluteString, "https://makerworld.com/en/@maker%2Fone%3Fx%3D1%23fragment")
        XCTAssertEqual(url.host, "makerworld.com")
        XCTAssertNil(url.query); XCTAssertNil(url.fragment)
    }
}
