import XCTest
@testable import MakeTheChoiceCore

final class LayeredItemCategorizerTests: XCTestCase {

    private func grok(_ behavior: MockRemoteCategorizationClient.Behavior) -> GrokItemCategorizer {
        GrokItemCategorizer(client: MockRemoteCategorizationClient(behavior))
    }

    func testRemoteSuccessWins() async throws {
        let remote = grok(.respond(.init(categories: ["food", "enjoyment", "housing"])))
        let layered = LayeredItemCategorizer(remote: remote)
        let result = try await layered.categorize(
            items: ["GV WHT BRD", "Cabernet", "Nonstick Oven Tray"], merchant: "Target")
        XCTAssertEqual(result, [.food, .enjoyment, .housing])
    }

    func testRemoteThrowsFallsBackToKeyword() async throws {
        let remote = grok(.fail(CategorizationError("offline")))
        let layered = LayeredItemCategorizer(remote: remote)
        // Keyword resolves bread/wine; "Mystery Widget" has no keyword.
        let result = try await layered.categorize(
            items: ["Bread", "Wine", "Mystery Widget"], merchant: "Target")
        XCTAssertEqual(result, [.food, .enjoyment, .uncategorized])
    }

    func testRemoteLengthMismatchFallsBackToKeyword() async throws {
        // Remote returns 2 categories for 3 items → untrustworthy alignment → keyword.
        let remote = grok(.respond(.init(categories: ["business", "business"])))
        let layered = LayeredItemCategorizer(remote: remote)
        let result = try await layered.categorize(
            items: ["Bread", "Wine", "Oven Tray"], merchant: "Target")
        XCTAssertEqual(result, [.food, .enjoyment, .housing])
    }

    func testRemoteUncategorizedIsBackfilledByKeyword() async throws {
        let remote = grok(.respond(.init(categories: ["uncategorized"])))
        let layered = LayeredItemCategorizer(remote: remote)
        let result = try await layered.categorize(items: ["Bread"], merchant: "Target")
        XCTAssertEqual(result, [.food], "keyword should backfill what Grok punted on")
    }

    func testInvalidSlugBecomesUncategorizedWhenKeywordAlsoUnknown() async throws {
        let remote = grok(.respond(.init(categories: ["not_a_real_category"])))
        let layered = LayeredItemCategorizer(remote: remote)
        let result = try await layered.categorize(items: ["Mystery Widget"], merchant: nil)
        XCTAssertEqual(result, [.uncategorized])
    }

    func testNoRemoteUsesKeywordOnly() async throws {
        let layered = LayeredItemCategorizer(remote: nil)
        let result = try await layered.categorize(items: ["Wine", "Zzz"], merchant: nil)
        XCTAssertEqual(result, [.enjoyment, .uncategorized])
    }

    func testEmptyItems() async throws {
        let layered = LayeredItemCategorizer(remote: grok(.respond(.init(categories: []))))
        let result = try await layered.categorize(items: [], merchant: "Target")
        XCTAssertTrue(result.isEmpty)
    }
}
