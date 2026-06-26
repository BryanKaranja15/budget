import XCTest
import GRDB
@testable import MakeTheChoiceCore

final class AppPresenterTests: XCTestCase {

    private let may = MonthKey(year: 2024, month: 5)

    private func loadedDB() throws -> AppDatabase {
        let db = try AppDatabase.makeInMemory(seed: true)
        try FixtureLoader.load(into: db)
        return db
    }

    func testDashboardComputesSpendBudgetAndMonths() throws {
        let db = try loadedDB()
        try CategoryRepository(db).setBudget("food", limit: 400, month: may)
        try CategoryRepository(db).setBudget("transport", limit: 60, month: may)

        let vm = try AppPresenter(db, baseCurrency: "USD").dashboard(for: may)

        XCTAssertEqual(vm.month, "2024-05")
        XCTAssertEqual(vm.totalSpent.amount, 268.6273, accuracy: 0.01)
        XCTAssertEqual(vm.availableMonths, ["2024-05", "2024-04", "2024-03"])

        let food = try XCTUnwrap(vm.categories.first { $0.id == "food" })
        XCTAssertEqual(food.spent.amount, 103.35, accuracy: 0.001)
        XCTAssertEqual(food.remaining?.amount ?? 0, 296.65, accuracy: 0.001)
        XCTAssertEqual(food.status, .ok)

        // Transport is over its $60 budget (71.10).
        let transport = try XCTUnwrap(vm.categories.first { $0.id == "transport" })
        XCTAssertEqual(transport.status, .over)

        // Clothing has spend but no budget → status none, still shown.
        let clothing = try XCTUnwrap(vm.categories.first { $0.id == "clothing" })
        XCTAssertEqual(clothing.status, .none)
        XCTAssertNil(clothing.budget)

        // Internal transfer + payroll never appear as spend.
        XCTAssertNil(vm.categories.first { $0.id == "savings" })
        let fractions = vm.categories.map(\.fractionOfTotal).reduce(0, +)
        XCTAssertEqual(fractions, 1.0, accuracy: 0.001)
    }

    func testCategoryDetailListsTransactions() throws {
        let db = try loadedDB()
        let vm = try AppPresenter(db, baseCurrency: "USD").categoryDetail(categoryId: "food", month: may)
        XCTAssertEqual(vm.categoryName, "Food")
        XCTAssertEqual(vm.transactions.count, 3)
        XCTAssertEqual(vm.total.amount, 103.35, accuracy: 0.001)
        XCTAssertEqual(Set(vm.transactions.map(\.merchant)),
                       ["Whole Foods", "Starbucks", "Chipotle"])
    }

    func testCategoryDetailMarksForeignCurrency() throws {
        let db = try loadedDB()
        let vm = try AppPresenter(db, baseCurrency: "USD").categoryDetail(categoryId: "clothing", month: may)
        let zara = try XCTUnwrap(vm.transactions.first { $0.merchant == "Zara" })
        XCTAssertTrue(zara.isForeignCurrency)
        XCTAssertEqual(zara.originalAmount.currencyCode, "GBP")
        XCTAssertEqual(zara.originalAmount.amount, 59.99, accuracy: 0.001)
        XCTAssertEqual(zara.baseAmount.currencyCode, "USD")
    }

    func testSubscriptionsBoardReflectsDetector() throws {
        let db = try loadedDB()
        try SubscriptionDetector().detectAndStore(in: db, baseCurrency: "USD")
        let vm = try AppPresenter(db, baseCurrency: "USD").subscriptionsBoard()

        XCTAssertEqual(vm.rows.count, 1)
        let netflix = vm.rows[0]
        XCTAssertEqual(netflix.merchant, "Netflix")
        XCTAssertEqual(netflix.cadenceLabel, "Monthly")
        XCTAssertTrue(netflix.priceCreep)
        XCTAssertEqual(vm.totalAnnual.amount, 17.99 * 365.0 / 30.0, accuracy: 0.01)
        XCTAssertEqual(vm.totalMonthly.amount, vm.totalAnnual.amount / 12, accuracy: 0.01)
    }

    func testReceiptSplitShowsItemsAndSplits() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let receipt = try FixtureLoader.loadWithReceipt(into: db)
        _ = try ReceiptStore(db).matchAndSplit(receipt)

        let vm = try XCTUnwrap(try AppPresenter(db, baseCurrency: "USD").receiptSplit(receiptId: receipt.id!))
        XCTAssertEqual(vm.merchant, "Target")
        XCTAssertEqual(vm.matchStatus, .matched)
        XCTAssertEqual(vm.items.count, 5)
        XCTAssertFalse(vm.splits.isEmpty)
        // Splits scale to the real charged total.
        XCTAssertEqual(vm.splits.reduce(0) { $0 + $1.amount.amount }, 87.34, accuracy: 0.01)
    }

    func testMoneyFormatsLocalizedCurrency() {
        XCTAssertTrue(Money(17.99, "USD").formatted.contains("17.99"))
        XCTAssertTrue(Money(59.99, "GBP").formatted.contains("59.99"))
    }
}
