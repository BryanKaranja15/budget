import XCTest
@testable import MakeTheChoiceCore

final class SpendingAndBudgetTests: XCTestCase {

    private func makeSeededDB() throws -> AppDatabase {
        let db = try AppDatabase.makeInMemory(seed: true)
        try FixtureLoader.load(into: db)
        return db
    }

    func testSpendingByCategoryExcludesInternalTransfersAndIncome() throws {
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        let may = MonthKey(year: 2024, month: 5)
        let spend = try store.spendingByCategory(in: may)

        // Income (-3200) is excluded → no negative totals.
        XCTAssertTrue(spend.values.allSatisfy { $0 > 0 })
        // Internal transfer to savings (500) is excluded → savings not present.
        XCTAssertNil(spend[AppCategory.savings.rawValue])

        // Food: 84.20 + 6.75 + 12.40 = 103.35
        XCTAssertEqual(spend[AppCategory.food.rawValue] ?? 0, 103.35, accuracy: 0.001)
        // Transport: 23.10 + 48.00 = 71.10
        XCTAssertEqual(spend[AppCategory.transport.rawValue] ?? 0, 71.10, accuracy: 0.001)
        // Subscriptions (May Netflix): 17.99
        XCTAssertEqual(spend[AppCategory.subscriptions.rawValue] ?? 0, 17.99, accuracy: 0.001)
        // Clothing (Zara GBP 59.99 * 1.27): 76.1873
        XCTAssertEqual(spend[AppCategory.clothing.rawValue] ?? 0, 59.99 * 1.27, accuracy: 0.001)
    }

    func testTotalSpendingExcludesTransfersAndIncome() throws {
        let db = try makeSeededDB()
        let store = TransactionStore(db)
        let may = MonthKey(year: 2024, month: 5)
        let expected = 103.35 + 71.10 + 17.99 + (59.99 * 1.27)
        XCTAssertEqual(try store.totalSpending(in: may), expected, accuracy: 0.001)
    }

    func testSetAndReadBudget() throws {
        let db = try makeSeededDB()
        let repo = CategoryRepository(db)
        let may = MonthKey(year: 2024, month: 5)
        try repo.setBudget(AppCategory.food.rawValue, limit: 400, month: may)
        XCTAssertEqual(try repo.find(AppCategory.food.rawValue)?.monthlyBudgetLimit, 400)
        XCTAssertEqual(try repo.budget(AppCategory.food.rawValue, for: may), 400)
    }

    func testBudgetHistoryIsMonthScoped() throws {
        let db = try makeSeededDB()
        let repo = CategoryRepository(db)
        let april = MonthKey(year: 2024, month: 4)
        let may = MonthKey(year: 2024, month: 5)
        try repo.setBudget(AppCategory.food.rawValue, limit: 300, month: april)
        try repo.setBudget(AppCategory.food.rawValue, limit: 400, month: may)
        // Past month keeps its recorded limit even though current limit changed.
        XCTAssertEqual(try repo.budget(AppCategory.food.rawValue, for: april), 300)
        XCTAssertEqual(try repo.budget(AppCategory.food.rawValue, for: may), 400)
    }

    func testClearBudget() throws {
        let db = try makeSeededDB()
        let repo = CategoryRepository(db)
        try repo.setBudget(AppCategory.food.rawValue, limit: 400)
        try repo.setBudget(AppCategory.food.rawValue, limit: nil)
        XCTAssertNil(try repo.find(AppCategory.food.rawValue)?.monthlyBudgetLimit)
    }
}
