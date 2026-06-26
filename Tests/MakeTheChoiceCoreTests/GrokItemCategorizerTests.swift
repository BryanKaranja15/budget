import XCTest
@testable import MakeTheChoiceCore

final class GrokItemCategorizerTests: XCTestCase {

    func testRequestCarriesOnlyMerchantAndItems() async throws {
        let mock = MockRemoteCategorizationClient(.respond(.init(categories: ["food", "enjoyment"])))
        let grok = GrokItemCategorizer(client: mock)
        _ = try await grok.categorize(items: ["GV WHT BRD", "Cabernet"], merchant: "Target")

        let sent = try XCTUnwrap(mock.lastRequest)
        XCTAssertEqual(sent.merchant, "Target")
        XCTAssertEqual(sent.items, ["GV WHT BRD", "Cabernet"])

        // De-identification guarantee: the serialized payload has exactly two keys and
        // no amounts/account/card/identity could be smuggled in.
        let data = try JSONEncoder().encode(sent)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["merchant", "items"])
    }

    func testMerchantCanBeWithheld() async throws {
        let mock = MockRemoteCategorizationClient(.respond(.init(categories: ["food"])))
        let grok = GrokItemCategorizer(client: mock)
        _ = try await grok.categorize(items: ["Bread"], merchant: nil)
        XCTAssertNil(mock.lastRequest?.merchant)
    }

    func testInvalidSlugCoercedToUncategorized() async throws {
        let mock = MockRemoteCategorizationClient(.respond(.init(categories: ["food", "bogus", "housing"])))
        let grok = GrokItemCategorizer(client: mock)
        let result = try await grok.categorize(items: ["a", "b", "c"], merchant: nil)
        XCTAssertEqual(result, [.food, .uncategorized, .housing])
    }

    func testEmptyItemsSkipsNetworkCall() async throws {
        let mock = MockRemoteCategorizationClient(.respond(.init(categories: [])))
        let grok = GrokItemCategorizer(client: mock)
        let result = try await grok.categorize(items: [], merchant: "Target")
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(mock.callCount, 0)
    }

    func testPropagatesClientError() async {
        let mock = MockRemoteCategorizationClient(.fail(CategorizationError("boom")))
        let grok = GrokItemCategorizer(client: mock)
        do {
            _ = try await grok.categorize(items: ["x"], merchant: nil)
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error is CategorizationError)
        }
    }
}
