import XCTest
import GRDB
@testable import MakeTheChoiceCore

final class DatabaseSchemaTests: XCTestCase {

    func testMigrationCreatesAllTables() throws {
        let db = try AppDatabase.makeInMemory(seed: false)
        let expected = [
            "categories", "plaid_items", "accounts", "merchants", "transactions",
            "budgets", "subscriptions", "fx_rates", "user_corrections", "training_samples",
            "receipts", "receipt_items", "transaction_items"
        ]
        try db.reader.read { database in
            for table in expected {
                XCTAssertTrue(try database.tableExists(table), "missing table: \(table)")
            }
        }
    }

    func testSchemaVersionIsRecorded() throws {
        let db = try AppDatabase.makeInMemory(seed: false)
        // v1 (core schema) + v2 (receipts).
        XCTAssertEqual(try db.schemaVersion(), 2)
    }

    func testIndexesExist() throws {
        let db = try AppDatabase.makeInMemory(seed: false)
        try db.reader.read { database in
            let indexes = try Row.fetchAll(database, sql:
                "SELECT name FROM sqlite_master WHERE type = 'index'")
                .map { $0["name"] as String }
            for expected in [
                "idx_transactions_date", "idx_transactions_category",
                "idx_transactions_account", "idx_merchants_normalized",
                "idx_subscriptions_merchant"
            ] {
                XCTAssertTrue(indexes.contains(expected), "missing index: \(expected)")
            }
        }
    }

    func testPlaidTransactionIdIsUnique() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let store = TransactionStore(db)
        let tx = Transaction(
            plaidTransactionId: "dup_1", accountId: "acc_us_checking",
            date: Date(), merchantName: "Test", isoCurrencyCode: "USD",
            originalAmount: 10, baseAmount: 10, categoryId: AppCategory.food.rawValue,
            categorySource: .plaid
        )
        // Need a real account due to FK; load fixtures first.
        try FixtureLoader.load(into: db)
        try store.upsert(tx)
        // A second upsert with the same plaid id must update, not duplicate.
        try store.upsert(tx)
        let matches = try db.reader.read { database in
            try Transaction
                .filter(Transaction.Columns.plaidTransactionId == "dup_1")
                .fetchCount(database)
        }
        XCTAssertEqual(matches, 1)
    }

    func testForeignKeyEnforced() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        // Inserting a transaction referencing a non-existent account must fail.
        let store = TransactionStore(db)
        let tx = Transaction(
            plaidTransactionId: "orphan", accountId: "no_such_account",
            date: Date(), merchantName: "X", isoCurrencyCode: "USD",
            originalAmount: 1, baseAmount: 1, categoryId: AppCategory.food.rawValue
        )
        XCTAssertThrowsError(try store.upsert(tx))
    }
}
