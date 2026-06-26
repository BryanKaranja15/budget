import XCTest
import GRDB
@testable import MakeTheChoiceCore

final class ReceiptStoreTests: XCTestCase {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.makeInMemory(seed: true)
    }

    func testSaveReceiptWithItems() throws {
        let db = try makeDB()
        try FixtureLoader.load(into: db)
        let store = ReceiptStore(db)
        let (receipt, items) = FixtureLoader.sampleTargetReceipt()
        let saved = try store.save(receipt, items: ItemCategorizer.categorize(items: items))
        XCTAssertNotNil(saved.id)
        XCTAssertEqual(try store.items(forReceipt: saved.id!).count, 5)
    }

    func testFindMatchByMerchantAmountDate() throws {
        let db = try makeDB()
        let receipt = try FixtureLoader.loadWithReceipt(into: db)
        let matches = try ReceiptStore(db).findMatch(for: receipt)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.plaidTransactionId, "txn_target")
    }

    func testMatchAndSplitCreatesItemsSummingToTransaction() throws {
        let db = try makeDB()
        let receipt = try FixtureLoader.loadWithReceipt(into: db)
        let store = ReceiptStore(db)
        let txnId = try store.matchAndSplit(receipt)
        let unwrapped = try XCTUnwrap(txnId)

        let splits = try store.transactionItems(forTransaction: unwrapped)
        XCTAssertEqual(splits.count, 5)
        let baseSum = splits.reduce(0) { $0 + $1.baseAmount }
        XCTAssertEqual(baseSum, 87.34, accuracy: 0.001, "splits must sum to the transaction total")
    }

    func testMatchedReceiptIsLinked() throws {
        let db = try makeDB()
        let receipt = try FixtureLoader.loadWithReceipt(into: db)
        let store = ReceiptStore(db)
        _ = try store.matchAndSplit(receipt)
        let linked = try db.reader.read { try Receipt.fetchOne($0, key: receipt.id!) }
        XCTAssertEqual(linked?.matchStatus, .matched)
        XCTAssertNotNil(linked?.transactionId)
        XCTAssertNotNil(linked?.matchConfidence)
        XCTAssertGreaterThan(linked?.matchConfidence ?? 0, 0.9)
    }

    func testItemizedSpendingUsesSplitsForSplitTransactions() throws {
        let db = try makeDB()
        let receipt = try FixtureLoader.loadWithReceipt(into: db)
        let store = ReceiptStore(db)
        _ = try store.matchAndSplit(receipt)

        let may = MonthKey(year: 2024, month: 5)
        let itemized = try store.itemizedSpendingByCategory(in: may)

        // Target run is now split per item instead of lumped:
        //   bread 4.99 + milk 5.49 = 10.48 → Food (on top of other May food 103.35)
        //   wine 18.99 → Enjoyment ; oven tray 24.99 → Housing ; cable 32.88 → Business
        XCTAssertEqual(itemized[AppCategory.food.rawValue] ?? 0, 103.35 + 10.48, accuracy: 0.01)
        XCTAssertEqual(itemized[AppCategory.enjoyment.rawValue] ?? 0, 18.99, accuracy: 0.01)
        XCTAssertEqual(itemized[AppCategory.housing.rawValue] ?? 0, 24.99, accuracy: 0.01)
        XCTAssertEqual(itemized[AppCategory.business.rawValue] ?? 0, 32.88, accuracy: 0.01)
    }

    func testItemizedSpendingDoesNotDoubleCountSplitTransaction() throws {
        let db = try makeDB()
        let receipt = try FixtureLoader.loadWithReceipt(into: db)
        let store = ReceiptStore(db)
        _ = try store.matchAndSplit(receipt)

        let may = MonthKey(year: 2024, month: 5)
        let itemized = try store.itemizedSpendingByCategory(in: may)
        let total = itemized.values.reduce(0, +)
        // Plain May spend (no Target) + the Target total counted exactly once.
        let plainMay = 103.35 + 71.10 + 17.99 + (59.99 * 1.27)
        XCTAssertEqual(total, plainMay + 87.34, accuracy: 0.01)
    }

    func testScalingReconcilesTaxDifference() throws {
        let db = try makeDB()
        try FixtureLoader.load(into: db)
        let store = ReceiptStore(db)
        // Transaction total 88.00 (incl. tax), receipt items sum to 80.00.
        let txn = Transaction(
            plaidTransactionId: "txn_tax", accountId: "acc_us_checking",
            date: FixtureLoader.date("2024-06-01"), merchantName: "Target",
            isoCurrencyCode: "USD", originalAmount: 88.00, baseAmount: 88.00,
            categoryId: AppCategory.uncategorized.rawValue, categorySource: .plaid)
        try TransactionStore(db).upsert(txn)
        let receipt = Receipt(merchantName: "Target", purchaseDate: FixtureLoader.date("2024-06-01"),
                              totalAmount: 88.00, currency: "USD", source: .camera)
        let items = [
            ReceiptItem(receiptId: 0, lineNo: 0, name: "Bread", amount: 30, categoryId: AppCategory.food.rawValue),
            ReceiptItem(receiptId: 0, lineNo: 1, name: "Wine", amount: 50, categoryId: AppCategory.enjoyment.rawValue)
        ]
        let saved = try store.save(receipt, items: items)
        _ = try store.matchAndSplit(saved)
        let persisted = try XCTUnwrap(TransactionStore(db).find(plaidTransactionId: "txn_tax"))
        let splits = try store.transactionItems(forTransaction: persisted.id!)
        // Even though items summed to 80, splits scale up to the 88 actually charged.
        XCTAssertEqual(splits.reduce(0) { $0 + $1.baseAmount }, 88.00, accuracy: 0.01)
    }

    func testAmbiguousMatchIsNotAutoSplit() throws {
        let db = try makeDB()
        try FixtureLoader.load(into: db)
        let store = ReceiptStore(db)
        let txStore = TransactionStore(db)
        // Two identical Target transactions on the same day → ambiguous.
        for i in 0..<2 {
            try txStore.upsert(Transaction(
                plaidTransactionId: "txn_amb_\(i)", accountId: "acc_us_checking",
                date: FixtureLoader.date("2024-07-01"), merchantName: "Target",
                isoCurrencyCode: "USD", originalAmount: 40.00, baseAmount: 40.00,
                categoryId: AppCategory.uncategorized.rawValue, categorySource: .plaid))
        }
        let receipt = Receipt(merchantName: "Target", purchaseDate: FixtureLoader.date("2024-07-01"),
                              totalAmount: 40.00, currency: "USD", source: .camera)
        let saved = try store.save(receipt, items: [
            ReceiptItem(receiptId: 0, lineNo: 0, name: "Bread", amount: 40, categoryId: AppCategory.food.rawValue)
        ])
        let result = try store.matchAndSplit(saved)
        XCTAssertNil(result)
        let reloaded = try db.reader.read { try Receipt.fetchOne($0, key: saved.id!) }
        XCTAssertEqual(reloaded?.matchStatus, .ambiguous)
    }

    func testUnmatchedReceiptWhenNoCandidate() throws {
        let db = try makeDB()
        try FixtureLoader.load(into: db)
        let store = ReceiptStore(db)
        let receipt = Receipt(merchantName: "Nonexistent Store",
                              purchaseDate: FixtureLoader.date("2024-05-12"),
                              totalAmount: 999.99, currency: "USD", source: .camera)
        let saved = try store.save(receipt, items: [])
        XCTAssertNil(try store.matchAndSplit(saved))
        XCTAssertEqual(try store.unmatchedReceipts().first?.matchStatus, .unmatched)
    }

    func testTransactionsNeedingReceiptDrivesNudge() throws {
        let db = try makeDB()
        try FixtureLoader.load(into: db)
        let store = ReceiptStore(db)
        try TransactionStore(db).upsert(FixtureLoader.sampleTargetTransaction())
        let may = MonthKey(year: 2024, month: 5)
        let targets: Set<String> = ["target"]

        // Before scanning: the Target transaction needs a receipt.
        let before = try store.transactionsNeedingReceipt(in: may, merchants: targets)
        XCTAssertEqual(before.map(\.plaidTransactionId), ["txn_target"])

        // After scanning + matching: it drops out of the nudge queue.
        let (receipt, items) = FixtureLoader.sampleTargetReceipt()
        let saved = try store.save(receipt, items: ItemCategorizer.categorize(items: items))
        _ = try store.matchAndSplit(saved)
        let after = try store.transactionsNeedingReceipt(in: may, merchants: targets)
        XCTAssertTrue(after.isEmpty)
    }
}
