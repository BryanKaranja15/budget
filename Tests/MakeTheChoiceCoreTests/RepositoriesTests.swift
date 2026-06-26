import XCTest
@testable import MakeTheChoiceCore

final class RepositoriesTests: XCTestCase {

    func testMerchantLookupUserOverrideLocks() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let repo = MerchantRepository(db)
        // Move a noisy merchant string to Business and lock it.
        let key = try repo.lockUserOverride(rawMerchant: "GITHUB *COPILOT", categoryId: AppCategory.business.rawValue)
        let merchant = try XCTUnwrap(repo.lookup(rawMerchant: "github *copilot"))
        XCTAssertEqual(merchant.normalizedName, key)
        XCTAssertEqual(merchant.categoryId, AppCategory.business.rawValue)
        XCTAssertEqual(merchant.source, .user)
        XCTAssertTrue(merchant.locked)
    }

    func testMerchantLookupMissReturnsNil() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let repo = MerchantRepository(db)
        XCTAssertNil(try repo.lookup(rawMerchant: "Totally Unknown Merchant 9XZ"))
    }

    func testItemAndAccountPersistence() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let repo = ItemAccountRepository(db)
        try repo.save(PlaidItem(id: "item_1", institution: "Test Bank"))
        try repo.save(Account(id: "acc_1", itemId: "item_1", institution: "Test Bank",
                              name: "Checking", currency: "USD"))
        XCTAssertEqual(try repo.allItems().count, 1)
        XCTAssertEqual(try repo.accounts(forItem: "item_1").count, 1)
    }

    func testItemReauthQuery() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let repo = ItemAccountRepository(db)
        try repo.save(PlaidItem(id: "item_ok", institution: "A", status: .active))
        try repo.save(PlaidItem(id: "item_bad", institution: "B", status: .active))
        try repo.setStatus(itemId: "item_bad", status: .loginRequired)
        let needing = try repo.itemsNeedingReauth()
        XCTAssertEqual(needing.map(\.id), ["item_bad"])
    }

    func testDeletingItemCascadesAccountsAndTransactions() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        try FixtureLoader.load(into: db)
        let store = TransactionStore(db)
        XCTAssertGreaterThan(try store.count(), 0)
        // Delete the US Bank item; its accounts + their transactions should cascade out.
        try db.writer.write { database in
            _ = try PlaidItem.deleteOne(database, key: "item_usbank")
        }
        let remaining = try ItemAccountRepository(db).accounts(forItem: "item_usbank")
        XCTAssertTrue(remaining.isEmpty)
        // Revolut (Zara) transaction should survive.
        XCTAssertNotNil(try store.find(plaidTransactionId: "txn_9"))
    }
}
