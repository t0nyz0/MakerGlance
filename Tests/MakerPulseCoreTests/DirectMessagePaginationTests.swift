import XCTest
@testable import MakerPulseCore

private actor DirectMessagePages {
    var calls: [(Int, Int)] = []
    let pages: [DirectMessagePage]
    init(_ pages: [DirectMessagePage]) { self.pages = pages }
    func fetch(_ number: Int, _ limit: Int) throws -> DirectMessagePage {
        calls.append((number, limit))
        guard number <= pages.count else { throw PulseError.http(503) }
        return pages[number - 1]
    }
}

final class DirectMessagePaginationTests: XCTestCase {
    private func row(_ id: String) -> DirectMessageConversation {
        DirectMessageConversation(conversationID: id, unreadCount: 0, receiveOption: .normal, latestMessage: nil)
    }
    private func page(_ ids: [String], total: Int, unread: Int = 0) -> DirectMessagePage {
        DirectMessagePage(conversationTotal: total, unreadTotal: unread, conversations: ids.map(row))
    }
    private func collect(_ pages: [DirectMessagePage], limit: Int = 2, maxPages: Int = 500) async throws -> DirectMessageBatch {
        let transport = DirectMessagePages(pages)
        return try await DirectMessagePagination.collect(limit: limit, maxPages: maxPages) { number, size in
            try await transport.fetch(number, size)
        }
    }
    func testCompleteCrawlIncludesReadAndEmptyConversationsBeforeFiltering() async throws {
        let transport = DirectMessagePages([page(["a", "b"], total: 3), page(["c"], total: 3)])
        let batch = try await DirectMessagePagination.collect(limit: 2) { number, size in try await transport.fetch(number, size) }
        XCTAssertEqual(batch.conversations.map(\.conversationID), ["a", "b", "c"])
        let calls = await transport.calls
        XCTAssertEqual(calls.map(\.0), [1, 2]); XCTAssertEqual(calls.map(\.1), [2, 2])
        let empty = try await collect([page([], total: 0)])
        XCTAssertEqual(empty.conversationTotal, 0)
    }
    func testChangingTotalOrUnreadCountIsNotComplete() async {
        for pages in [[page(["a", "b"], total: 3), page(["c"], total: 2)],
                      [page(["a", "b"], total: 3), page(["c"], total: 3, unread: 1)]] {
            do { _ = try await collect(pages); XCTFail("Changing snapshot must fail") } catch {}
        }
    }
    func testDuplicateEmptyShortAndOverfullPagesAreRejected() async {
        let cases = [[page(["a", "b"], total: 3), page(["b"], total: 3)],
                     [page(["a", "b"], total: 3), page([], total: 3)],
                     [page(["a"], total: 3)], [page(["a", "b", "c"], total: 3)],
                     [page(["a", "b"], total: 1)]]
        for pages in cases {
            do { _ = try await collect(pages); XCTFail("Partial or inconsistent crawl must fail") } catch {}
        }
    }
    func testTransportFailureAndPageLimitNeverYieldBatch() async {
        do { _ = try await collect([page(["a", "b"], total: 3)]); XCTFail("Missing page must fail") } catch {}
        do { _ = try await collect([page(["a", "b"], total: 3)], maxPages: 1); XCTFail("Page limit must fail") } catch {}
    }
    func testCancellationNeverStartsFetch() async {
        let transport = DirectMessagePages([page([], total: 0)])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DirectMessagePagination.collect { number, size in try await transport.fetch(number, size) }
        }
        do { _ = try await task.value; XCTFail("Cancellation must propagate") } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await transport.calls; XCTAssertTrue(calls.isEmpty)
    }
    func testCancellationInsideFinalFetchCannotEstablishBaseline() async {
        let empty = page([], total: 0)
        let task = Task {
            try await DirectMessagePagination.collect { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return empty
            }
        }
        do { _ = try await task.value; XCTFail("Cancellation after fetch must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testBatchCannotClaimIncompleteOrDuplicateSnapshot() {
        XCTAssertThrowsError(try DirectMessageBatch(conversations: [row("a")], conversationTotal: 2, unreadTotal: 0))
        XCTAssertThrowsError(try DirectMessageBatch(conversations: [row("a"), row("a")], conversationTotal: 2, unreadTotal: 0))
        XCTAssertThrowsError(try DirectMessageBatch(conversations: [row("a")], conversationTotal: 1, unreadTotal: 1))
    }
}
