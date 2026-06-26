import XCTest
import GRDB
@testable import MakeTheChoiceCore

final class InternalTransferDetectorTests: XCTestCase {

    private func tx(_ id: String, account: String, date: String, base: Double,
                    transfer: Bool = false) -> Transaction {
        Transaction(plaidTransactionId: id, accountId: account, date: FixtureLoader.date(date),
                    merchantName: id, isoCurrencyCode: "USD", originalAmount: base, baseAmount: base,
                    categoryId: AppCategory.uncategorized.rawValue, categorySource: .plaid,
                    isInternalTransfer: transfer)
    }

    func testMatchesOppositeSignPairAcrossAccounts() {
        let txns = [
            tx("out", account: "checking", date: "2024-05-25", base: 500),
            tx("in", account: "savings", date: "2024-05-25", base: -500)
        ]
        let pairs = InternalTransferDetector().detect(txns)
        XCTAssertEqual(pairs, [.init(outflowId: "out", inflowId: "in")])
    }

    func testDoesNotMatchSameAccount() {
        let txns = [
            tx("out", account: "checking", date: "2024-05-25", base: 500),
            tx("in", account: "checking", date: "2024-05-25", base: -500)
        ]
        XCTAssertTrue(InternalTransferDetector().detect(txns).isEmpty)
    }

    func testDoesNotMatchOutsideDateWindow() {
        let txns = [
            tx("out", account: "checking", date: "2024-05-01", base: 500),
            tx("in", account: "savings", date: "2024-05-25", base: -500)
        ]
        XCTAssertTrue(InternalTransferDetector().detect(txns).isEmpty)
    }

    func testToleranceAbsorbsSmallFee() {
        let txns = [
            tx("out", account: "checking", date: "2024-05-25", base: 500),
            tx("in", account: "savings", date: "2024-05-26", base: -498)  // 0.4% off
        ]
        let pairs = InternalTransferDetector().detect(txns)
        XCTAssertEqual(pairs.count, 1)
    }

    func testIncomeIsNotFlagged() {
        // A single money-in (payroll) with no matching outflow must not pair.
        let txns = [
            tx("payroll", account: "checking", date: "2024-05-01", base: -3200),
            tx("groceries", account: "checking", date: "2024-05-02", base: 84.20)
        ]
        XCTAssertTrue(InternalTransferDetector().detect(txns).isEmpty)
    }

    func testEachTransactionUsedOnce() {
        // Two outflows, one inflow → only one pair.
        let txns = [
            tx("out1", account: "checking", date: "2024-05-25", base: 500),
            tx("out2", account: "checking", date: "2024-05-25", base: 500),
            tx("in", account: "savings", date: "2024-05-25", base: -500)
        ]
        XCTAssertEqual(InternalTransferDetector().detect(txns).count, 1)
    }

    func testDetectAndFlagIsAuthoritative() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        for item in FixtureLoader.sampleItems() { try ItemAccountRepository(db).save(item) }
        try ItemAccountRepository(db).save(FixtureLoader.sampleAccounts())
        let store = TransactionStore(db)
        // Insert the transfer pair WITHOUT the flag, plus an unrelated spend.
        try store.upsert([
            tx("out", account: "acc_us_checking", date: "2024-05-25", base: 500),
            tx("in", account: "acc_us_savings", date: "2024-05-25", base: -500),
            tx("coffee", account: "acc_us_checking", date: "2024-05-09", base: 6.75)
        ])

        let flagged = try InternalTransferDetector().detectAndFlag(in: db)
        XCTAssertEqual(flagged, 2)
        XCTAssertTrue(try store.find(plaidTransactionId: "out")!.isInternalTransfer)
        XCTAssertTrue(try store.find(plaidTransactionId: "in")!.isInternalTransfer)
        XCTAssertFalse(try store.find(plaidTransactionId: "coffee")!.isInternalTransfer)
    }
}
