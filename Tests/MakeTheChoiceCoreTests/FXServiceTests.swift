import XCTest
import GRDB
@testable import MakeTheChoiceCore

final class FXServiceTests: XCTestCase {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.makeInMemory(seed: true)
    }

    func testSameCurrencyIsIdentity() throws {
        let db = try makeDB()
        let fx = FXService(db, baseCurrency: "USD")
        XCTAssertEqual(try fx.toBase(42.0, currency: "USD", on: FixtureLoader.date("2024-05-10")), 42.0)
    }

    func testConvertsAtStoredRate() throws {
        let db = try makeDB()
        try FXRateStore(db).save([
            FXRate(day: "2024-05-10", base: "GBP", quote: "USD", rate: 1.25)
        ])
        let fx = FXService(db, baseCurrency: "USD")
        XCTAssertEqual(try fx.toBase(100, currency: "GBP", on: FixtureLoader.date("2024-05-10")),
                       125, accuracy: 0.0001)
    }

    func testFallsBackToClosestEarlierDay() throws {
        let db = try makeDB()
        try FXRateStore(db).save([
            FXRate(day: "2024-05-01", base: "GBP", quote: "USD", rate: 1.20),
            FXRate(day: "2024-05-08", base: "GBP", quote: "USD", rate: 1.30)
        ])
        let fx = FXService(db, baseCurrency: "USD")
        // No rate on the 10th → use the 8th.
        XCTAssertEqual(try fx.toBase(100, currency: "GBP", on: FixtureLoader.date("2024-05-10")),
                       130, accuracy: 0.0001)
    }

    func testFallsBackToEarliestLaterDayWhenNoPriorRate() throws {
        let db = try makeDB()
        try FXRateStore(db).save([
            FXRate(day: "2024-05-15", base: "GBP", quote: "USD", rate: 1.40)
        ])
        let fx = FXService(db, baseCurrency: "USD")
        XCTAssertEqual(try fx.toBase(100, currency: "GBP", on: FixtureLoader.date("2024-05-10")),
                       140, accuracy: 0.0001)
    }

    func testUsesInverseRateWhenOnlyOppositePairStored() throws {
        let db = try makeDB()
        try FXRateStore(db).save([
            FXRate(day: "2024-05-10", base: "USD", quote: "GBP", rate: 0.80)
        ])
        let fx = FXService(db, baseCurrency: "USD")
        // Only USD→GBP stored; converting GBP→USD must invert (1/0.8 = 1.25).
        XCTAssertEqual(try fx.toBase(100, currency: "GBP", on: FixtureLoader.date("2024-05-10")),
                       125, accuracy: 0.0001)
    }

    func testMissingRateThrows() throws {
        let db = try makeDB()
        let fx = FXService(db, baseCurrency: "USD")
        XCTAssertThrowsError(try fx.toBase(100, currency: "KES", on: FixtureLoader.date("2024-05-10"))) {
            guard case FXError.missingRate(let from, let to, _) = $0 else {
                return XCTFail("expected missingRate, got \($0)")
            }
            XCTAssertEqual(from, "KES")
            XCTAssertEqual(to, "USD")
        }
    }

    func testNormalizingTransactionSetsBaseAmount() throws {
        let db = try makeDB()
        try FXRateStore(db).save([
            FXRate(day: "2024-05-10", base: "GBP", quote: "USD", rate: 1.25)
        ])
        let fx = FXService(db, baseCurrency: "USD")
        let txn = Transaction(plaidTransactionId: "t1", accountId: "a1",
                              date: FixtureLoader.date("2024-05-10"), merchantName: "Zara",
                              isoCurrencyCode: "GBP", originalAmount: 40, baseAmount: 0)
        let normalized = try fx.normalizing(txn)
        XCTAssertEqual(normalized.baseAmount, 50, accuracy: 0.0001)
        XCTAssertEqual(normalized.originalAmount, 40, "original is preserved")
    }

    func testMockProviderFillsDateRange() async throws {
        let provider = MockFXRateProvider(["GBP>USD": 1.27])
        let rates = try await provider.rates(base: "GBP", quote: "USD",
                                             from: FixtureLoader.date("2024-05-01"),
                                             to: FixtureLoader.date("2024-05-05"))
        XCTAssertEqual(rates.count, 5)
        XCTAssertEqual(rates.first?.day, "2024-05-01")
        XCTAssertEqual(rates.last?.day, "2024-05-05")
        XCTAssertTrue(rates.allSatisfy { $0.rate == 1.27 })
    }
}
