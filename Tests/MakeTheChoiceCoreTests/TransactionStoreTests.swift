import XCTest
import GRDB
@testable import MakeTheChoiceCore

final class TransactionStoreTests: XCTestCase {

    private func makeSeededDB() throws -> AppDatabase {
        let db = try AppDatabase.makeInMemory(seed: true)
        try FixtureLoader.load(into: db)
        return db
    }

    func testUpsertIsIdempotent() throws {
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        let before = try store.count()
        // Re-upsert the same fixtures — count must not change.
        try store.upsert(FixtureLoader.sampleTransactions())
        XCTAssertEqual(try store.count(), before)
    }

    func testUpsertUpdatesMutableFields() throws {
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        var tx = try XCTUnwrap(store.find(plaidTransactionId: "txn_1"))
        let originalId = tx.id
        tx.pending = true
        tx.originalAmount = 99.99
        let saved = try store.upsert(tx)
        XCTAssertEqual(saved.id, originalId, "local id must be preserved")
        let reloaded = try XCTUnwrap(store.find(plaidTransactionId: "txn_1"))
        XCTAssertTrue(reloaded.pending)
        XCTAssertEqual(reloaded.originalAmount, 99.99, accuracy: 0.0001)
    }

    func testUpsertDoesNotDowngradeUserCategory() throws {
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        // User locks txn_1 to Business.
        var tx = try XCTUnwrap(store.find(plaidTransactionId: "txn_1"))
        tx.categoryId = AppCategory.business.rawValue
        tx.categorySource = .user
        try store.upsert(tx)
        // A subsequent raw sync (plaid source) must NOT overwrite the user choice.
        var sync = try XCTUnwrap(store.find(plaidTransactionId: "txn_1"))
        sync.categoryId = AppCategory.subscriptions.rawValue
        sync.categorySource = .plaid
        try store.upsert(sync)
        let result = try XCTUnwrap(store.find(plaidTransactionId: "txn_1"))
        XCTAssertEqual(result.categoryId, AppCategory.business.rawValue)
        XCTAssertEqual(result.categorySource, .user)
    }

    func testSubscriptionCanBeRecategorizedToBusinessKeepingFlag() throws {
        // User requirement: a subscription used for personal tinkering should be movable
        // to Business while remaining flagged as a subscription.
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        var netflix = try XCTUnwrap(store.find(plaidTransactionId: "txn_1"))
        XCTAssertTrue(netflix.isSubscription)
        netflix.categoryId = AppCategory.business.rawValue
        netflix.categorySource = .user
        try store.upsert(netflix)
        let result = try XCTUnwrap(store.find(plaidTransactionId: "txn_1"))
        XCTAssertEqual(result.categoryId, AppCategory.business.rawValue)
        XCTAssertTrue(result.isSubscription, "subscription flag is orthogonal to category")
    }

    func testRemoveByPlaidIds() throws {
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        let before = try store.count()
        let removed = try store.remove(plaidTransactionIds: ["txn_4", "txn_5"])
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(try store.count(), before - 2)
        XCTAssertNil(try store.find(plaidTransactionId: "txn_4"))
    }

    func testTransactionsInMonth() throws {
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        let may = try store.transactions(in: MonthKey(year: 2024, month: 5))
        // April Netflix and March Netflix excluded; everything else is in May.
        XCTAssertTrue(may.allSatisfy { MonthKey(date: $0.date) == MonthKey(year: 2024, month: 5) })
        let april = try store.transactions(in: MonthKey(year: 2024, month: 4))
        XCTAssertEqual(april.count, 1)
        XCTAssertEqual(april.first?.merchantName, "Netflix")
    }

    func testTransactionsInMonthByCategory() throws {
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        let food = try store.transactions(in: MonthKey(year: 2024, month: 5),
                                          categoryId: AppCategory.food.rawValue)
        XCTAssertEqual(Set(food.map(\.merchantName)),
                       ["Whole Foods", "Starbucks", "Chipotle"])
    }
}
