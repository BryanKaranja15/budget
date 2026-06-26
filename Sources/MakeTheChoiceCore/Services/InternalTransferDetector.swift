import Foundation
import GRDB

/// Detects transfers between the user's *own* accounts (e.g. checking → savings,
/// credit-card payments) so they can be excluded from spending totals. See plan.md
/// "Internal Transfers". The robust signal is an opposite-sign amount match across two
/// different accounts within a short date window; balances are compared in base currency.
public struct InternalTransferDetector {

    public struct Config: Sendable {
        /// Max number of days between the two legs of a transfer.
        public var dateWindowDays: Int
        /// Allowed relative difference between the two leg magnitudes (e.g. 0.01 = 1%),
        /// absorbing fees/rounding/FX drift.
        public var relativeTolerance: Double
        public init(dateWindowDays: Int = 3, relativeTolerance: Double = 0.01) {
            self.dateWindowDays = dateWindowDays
            self.relativeTolerance = relativeTolerance
        }
    }

    /// A matched transfer: the money-out leg and the money-in leg (by Plaid id).
    public struct Pair: Equatable, Sendable {
        public let outflowId: String
        public let inflowId: String
        public init(outflowId: String, inflowId: String) {
            self.outflowId = outflowId
            self.inflowId = inflowId
        }
    }

    public let config: Config
    public init(config: Config = .init()) { self.config = config }

    /// Pure detection over a transaction set. Each transaction is used in at most one
    /// pair. Outflows (base > 0) are matched to the closest eligible inflow (base < 0).
    public func detect(_ transactions: [Transaction]) -> [Pair] {
        let outflows = transactions.filter { $0.baseAmount > 0 }.sorted { $0.date < $1.date }
        let inflows  = transactions.filter { $0.baseAmount < 0 }.sorted { $0.date < $1.date }
        var usedInflowIds = Set<String>()
        var pairs: [Pair] = []

        for out in outflows {
            var best: Transaction?
            var bestScore = Double.greatestFiniteMagnitude
            for inn in inflows where !usedInflowIds.contains(inn.plaidTransactionId) {
                guard inn.accountId != out.accountId else { continue }
                let dayGap = abs(out.date.timeIntervalSince(inn.date)) / 86_400
                guard dayGap <= Double(config.dateWindowDays) else { continue }
                let a = abs(out.baseAmount), b = abs(inn.baseAmount)
                let diff = abs(a - b)
                guard diff <= config.relativeTolerance * max(a, b) else { continue }
                // Prefer the closest date, then the closest amount.
                let score = dayGap + diff
                if score < bestScore {
                    bestScore = score
                    best = inn
                }
            }
            if let match = best {
                usedInflowIds.insert(match.plaidTransactionId)
                pairs.append(Pair(outflowId: out.plaidTransactionId, inflowId: match.plaidTransactionId))
            }
        }
        return pairs
    }

    /// Run detection over all stored transactions and write `is_internal_transfer`.
    /// Authoritative + idempotent: every transaction's flag is set to whether it
    /// participates in a detected pair. Returns the number of transactions flagged true.
    @discardableResult
    public func detectAndFlag(in db: AppDatabase) throws -> Int {
        try db.writer.write { database in
            let all = try Transaction.fetchAll(database)
            let pairs = detect(all)
            var flagged = Set<String>()
            for pair in pairs {
                flagged.insert(pair.outflowId)
                flagged.insert(pair.inflowId)
            }
            for var txn in all {
                let shouldFlag = flagged.contains(txn.plaidTransactionId)
                if txn.isInternalTransfer != shouldFlag {
                    txn.isInternalTransfer = shouldFlag
                    try txn.update(database)
                }
            }
            return flagged.count
        }
    }
}
