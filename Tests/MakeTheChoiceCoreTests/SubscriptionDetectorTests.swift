import XCTest
import GRDB
@testable import MakeTheChoiceCore

final class SubscriptionDetectorTests: XCTestCase {

    private func charge(_ merchant: String, _ date: String, _ amount: Double,
                        account: String = "acc_us_checking") -> Transaction {
        Transaction(plaidTransactionId: "\(merchant)-\(date)", accountId: account,
                    date: FixtureLoader.date(date), merchantName: merchant,
                    isoCurrencyCode: "USD", originalAmount: amount, baseAmount: amount,
                    categoryId: AppCategory.subscriptions.rawValue, categorySource: .merchant)
    }

    func testDetectsMonthlySubscriptionWithPriceCreep() {
        let txns = [
            charge("Netflix", "2024-03-15", 15.49),
            charge("Netflix", "2024-04-15", 15.49),
            charge("Netflix", "2024-05-15", 17.99)
        ]
        let subs = SubscriptionDetector().detect(txns, baseCurrency: "USD")
        XCTAssertEqual(subs.count, 1)
        let netflix = subs[0]
        XCTAssertEqual(netflix.merchant, "Netflix")
        XCTAssertEqual(netflix.cadenceDays, 30)
        XCTAssertEqual(netflix.amount, 17.99, accuracy: 0.001)
        XCTAssertTrue(netflix.priceCreep)
        XCTAssertEqual(netflix.annualCost, 17.99 * 365.0 / 30.0, accuracy: 0.01)
        XCTAssertEqual(netflix.nextExpectedDate, FixtureLoader.date("2024-06-14"))
    }

    func testRejectsNoisyAmountsAtSameMerchant() {
        // Regular-ish dates but wildly varying amounts (groceries) → not a subscription.
        let txns = [
            charge("Whole Foods", "2024-03-01", 84.20),
            charge("Whole Foods", "2024-04-01", 6.75),
            charge("Whole Foods", "2024-05-01", 152.40)
        ]
        XCTAssertTrue(SubscriptionDetector().detect(txns, baseCurrency: "USD").isEmpty)
    }

    func testRejectsIrregularCadence() {
        let txns = [
            charge("Gym", "2024-01-01", 40),
            charge("Gym", "2024-01-05", 40),   // 4-day gap, not canonical
            charge("Gym", "2024-03-15", 40)
        ]
        XCTAssertTrue(SubscriptionDetector().detect(txns, baseCurrency: "USD").isEmpty)
    }

    func testWeeklyCadenceDetected() {
        let txns = [
            charge("Cloud Backup", "2024-05-01", 4.99),
            charge("Cloud Backup", "2024-05-08", 4.99),
            charge("Cloud Backup", "2024-05-15", 4.99)
        ]
        let subs = SubscriptionDetector().detect(txns, baseCurrency: "USD")
        XCTAssertEqual(subs.first?.cadenceDays, 7)
        XCTAssertFalse(subs.first?.priceCreep ?? true)
    }

    func testLapsedWhenStale() {
        let txns = [
            charge("OldSub", "2024-01-15", 9.99),
            charge("OldSub", "2024-02-15", 9.99)
        ]
        // asOf is ~4 months after the last charge → > 2 cycles → lapsed.
        let subs = SubscriptionDetector().detect(txns, baseCurrency: "USD",
                                                 asOf: FixtureLoader.date("2024-06-15"))
        XCTAssertEqual(subs.first?.status, .lapsed)
    }

    func testSortedByAnnualCostDescending() {
        let txns = [
            charge("Cheap", "2024-04-01", 2.99), charge("Cheap", "2024-05-01", 2.99),
            charge("Pricey", "2024-04-01", 49.99), charge("Pricey", "2024-05-01", 49.99)
        ]
        let subs = SubscriptionDetector().detect(txns, baseCurrency: "USD")
        XCTAssertEqual(subs.map(\.merchant), ["Pricey", "Cheap"])
    }

    func testDetectAndStorePersistsAndFlagsTransactions() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        for item in FixtureLoader.sampleItems() { try ItemAccountRepository(db).save(item) }
        try ItemAccountRepository(db).save(FixtureLoader.sampleAccounts())
        try TransactionStore(db).upsert(FixtureLoader.sampleTransactions())

        let saved = try SubscriptionDetector().detectAndStore(in: db, baseCurrency: "USD")
        XCTAssertEqual(saved.count, 1)  // only Netflix recurs in the fixtures
        XCTAssertEqual(saved.first?.merchant, "Netflix")

        // Netflix transactions are now flagged; one-off spends are not.
        let netflixMay = try TransactionStore(db).find(plaidTransactionId: "txn_3")
        XCTAssertEqual(netflixMay?.isSubscription, true)
        let coffee = try TransactionStore(db).find(plaidTransactionId: "txn_5")
        XCTAssertEqual(coffee?.isSubscription, false)
    }
}
