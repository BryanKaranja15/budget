import XCTest
import GRDB
@testable import MakeTheChoiceCore

final class ReceiptIngestTests: XCTestCase {

    private func makeDB() throws -> AppDatabase {
        let db = try AppDatabase.makeInMemory(seed: true)
        try FixtureLoader.load(into: db)
        try TransactionStore(db).upsert(FixtureLoader.sampleTargetTransaction())
        return db
    }

    func testIngestCategorizesViaGrokThenSplitsToTransactionTotal() async throws {
        let db = try makeDB()
        let store = ReceiptStore(db)
        let (receipt, rawItems) = FixtureLoader.sampleTargetReceipt()

        // Grok returns item-level categories (order: bread, wine, oven tray, milk, charger).
        let mock = MockRemoteCategorizationClient(.respond(.init(
            categories: ["food", "enjoyment", "housing", "food", "business"])))
        let categorizer = LayeredItemCategorizer(remote: GrokItemCategorizer(client: mock))

        let saved = try await store.ingest(receipt, rawItems: rawItems, using: categorizer)
        let items = try store.items(forReceipt: saved.id!)
        XCTAssertEqual(items.map(\.categoryId), ["food", "enjoyment", "housing", "food", "business"])
        XCTAssertTrue(items.allSatisfy { $0.categorySource == .receipt })
        XCTAssertEqual(mock.lastRequest?.merchant, "Target")

        // Match + split: still scales to the real charged total.
        _ = try store.matchAndSplit(saved)
        let txn = try XCTUnwrap(TransactionStore(db).find(plaidTransactionId: "txn_target"))
        let splits = try store.transactionItems(forTransaction: txn.id!)
        XCTAssertEqual(splits.reduce(0) { $0 + $1.baseAmount }, 87.34, accuracy: 0.001)

        let itemized = try store.itemizedSpendingByCategory(in: MonthKey(year: 2024, month: 5))
        XCTAssertEqual(itemized[AppCategory.business.rawValue] ?? 0, 32.88, accuracy: 0.01)
        XCTAssertEqual(itemized[AppCategory.housing.rawValue] ?? 0, 24.99, accuracy: 0.01)
    }

    func testIngestFallsBackToKeywordWhenGrokOffline() async throws {
        let db = try makeDB()
        let store = ReceiptStore(db)
        let (receipt, rawItems) = FixtureLoader.sampleTargetReceipt()
        let offline = LayeredItemCategorizer(
            remote: GrokItemCategorizer(client: MockRemoteCategorizationClient(.fail(CategorizationError("offline")))))

        let saved = try await store.ingest(receipt, rawItems: rawItems, using: offline)
        let items = try store.items(forReceipt: saved.id!)
        // Keyword still resolves these specific names.
        XCTAssertEqual(items.map(\.categoryId),
                       ["food", "enjoyment", "housing", "food", "business"])
    }

    func testIngestPreservesUserLockedLine() async throws {
        let db = try makeDB()
        let store = ReceiptStore(db)
        let raw = [
            ReceiptItem(receiptId: 0, lineNo: 0, name: "Bread", amount: 5,
                        categoryId: AppCategory.business.rawValue, categorySource: .user),
            ReceiptItem(receiptId: 0, lineNo: 1, name: "Wine", amount: 10, categorySource: .unset)
        ]
        let receipt = Receipt(merchantName: "Target", purchaseDate: FixtureLoader.date("2024-05-12"),
                              totalAmount: 15, currency: "USD", source: .camera)
        // Grok would say food for both, but the user lock on line 0 must survive.
        let mock = MockRemoteCategorizationClient(.respond(.init(categories: ["food", "food"])))
        let categorizer = LayeredItemCategorizer(remote: GrokItemCategorizer(client: mock))

        let saved = try await store.ingest(receipt, rawItems: raw, using: categorizer)
        let items = try store.items(forReceipt: saved.id!)
        XCTAssertEqual(items[0].categoryId, AppCategory.business.rawValue)
        XCTAssertEqual(items[0].categorySource, .user)
        XCTAssertEqual(items[1].categoryId, AppCategory.food.rawValue)
        XCTAssertEqual(items[1].categorySource, .receipt)
    }
}
