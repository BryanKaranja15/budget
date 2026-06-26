import Foundation
import GRDB

/// Stores scanned receipts, matches them to Plaid transactions, splits a transaction
/// into category-level `transaction_items`, and computes item-level ("Layer 0") spending.
public struct ReceiptStore {
    private let writer: DatabaseWriter
    public init(_ db: AppDatabase) { self.writer = db.writer }
    public init(writer: DatabaseWriter) { self.writer = writer }

    /// Tolerances for matching a receipt to a transaction.
    public struct MatchTolerance: Sendable {
        /// Allowed +/- difference between receipt total and transaction amount (absolute).
        public var amount: Double
        /// Allowed +/- difference in calendar days.
        public var days: Int
        public init(amount: Double = 0.02, days: Int = 3) {
            self.amount = amount
            self.days = days
        }
        public static let `default` = MatchTolerance()
    }

    // MARK: - Persistence

    /// Save a receipt and its line items in one transaction. Returns the receipt with id.
    @discardableResult
    public func save(_ receipt: Receipt, items: [ReceiptItem]) throws -> Receipt {
        try writer.write { db in
            var r = receipt
            try r.insert(db)
            let receiptId = r.id!
            for var item in items {
                item.receiptId = receiptId
                try item.insert(db)
            }
            return r
        }
    }

    /// Categorize raw OCR line items with the given categorizer (Grok → keyword
    /// fallback), then persist the receipt + items. User-locked lines are never
    /// overwritten. This is the async entry point the scan/OCR flow calls; matching is
    /// kept separate (`matchAndSplit`) so the network step is isolated.
    @discardableResult
    public func ingest(
        _ receipt: Receipt,
        rawItems: [ReceiptItem],
        using categorizer: any ItemCategorizing
    ) async throws -> Receipt {
        var categorized = rawItems
        if !rawItems.isEmpty {
            let names = rawItems.map(\.name)
            let categories = try await categorizer.categorize(items: names, merchant: receipt.merchantName)
            if categories.count == rawItems.count {
                for i in categorized.indices where categorized[i].categorySource != .user {
                    categorized[i].categoryId = categories[i].rawValue
                    categorized[i].categorySource = .receipt
                }
            }
        }
        return try save(receipt, items: categorized)
    }

    public func items(forReceipt receiptId: Int64) throws -> [ReceiptItem] {
        try writer.read { db in
            try ReceiptItem
                .filter(ReceiptItem.Columns.receiptId == receiptId)
                .order(ReceiptItem.Columns.lineNo)
                .fetchAll(db)
        }
    }

    public func transactionItems(forTransaction transactionId: Int64) throws -> [TransactionItem] {
        try writer.read { db in
            try TransactionItem
                .filter(TransactionItem.Columns.transactionId == transactionId)
                .fetchAll(db)
        }
    }

    // MARK: - Matching

    /// Find the best transaction match for a receipt: same normalized merchant, within
    /// the date window, with the closest amount inside tolerance. Returns nil if none.
    public func findMatch(for receipt: Receipt, tolerance: MatchTolerance = .default) throws -> [Transaction] {
        let lower = receipt.totalAmount - tolerance.amount
        let upper = receipt.totalAmount + tolerance.amount
        let cal = Calendar.utc
        let startDate = cal.date(byAdding: .day, value: -tolerance.days, to: receipt.purchaseDate)!
        let endDate = cal.date(byAdding: .day, value: tolerance.days + 1, to: receipt.purchaseDate)!

        return try writer.read { db in
            let candidates = try Transaction
                .filter(Transaction.Columns.date >= startDate && Transaction.Columns.date < endDate)
                .filter(Transaction.Columns.originalAmount >= lower && Transaction.Columns.originalAmount <= upper)
                .filter(Transaction.Columns.isInternalTransfer == false)
                .fetchAll(db)
            // Only keep those whose merchant normalizes to the same key.
            return candidates.filter {
                MerchantNormalizer.normalize($0.merchantName) == receipt.normalizedMerchant
            }
            .sorted {
                abs($0.originalAmount - receipt.totalAmount) < abs($1.originalAmount - receipt.totalAmount)
            }
        }
    }

    /// Match a receipt to a transaction and split that transaction into
    /// `transaction_items` from the receipt's line items (amounts scaled so the splits
    /// sum exactly to the transaction's amounts). Returns the linked transaction id.
    ///
    /// If there are zero candidates the receipt is left `.unmatched`; if more than one,
    /// it is marked `.ambiguous` and not auto-split.
    @discardableResult
    public func matchAndSplit(_ receipt: Receipt, tolerance: MatchTolerance = .default) throws -> Int64? {
        let candidates = try findMatch(for: receipt, tolerance: tolerance)

        if candidates.isEmpty {
            try updateMatch(receiptId: receipt.id!, status: .unmatched, transactionId: nil, confidence: nil)
            return nil
        }
        if candidates.count > 1 {
            try updateMatch(receiptId: receipt.id!, status: .ambiguous, transactionId: nil, confidence: nil)
            return nil
        }

        let txn = candidates[0]
        let txnId = txn.id!
        let confidence = matchConfidence(receipt: receipt, transaction: txn, tolerance: tolerance)
        let receiptItems = try items(forReceipt: receipt.id!)

        try writer.write { db in
            // Link receipt → transaction.
            try Self.updateMatch(db, receiptId: receipt.id!, status: .matched,
                                 transactionId: txnId, confidence: confidence)
            // Replace any prior splits for this transaction.
            try TransactionItem
                .filter(TransactionItem.Columns.transactionId == txnId)
                .deleteAll(db)
            // Scale receipt item amounts to the transaction totals (handles tax/rounding
            // and FX: the transaction is the source of truth for money actually moved).
            let itemTotal = receiptItems.reduce(0) { $0 + $1.amount }
            let amountScale = itemTotal != 0 ? (txn.originalAmount / itemTotal) : 1
            let baseScale = itemTotal != 0 ? (txn.baseAmount / itemTotal) : 1
            for item in receiptItems {
                var split = TransactionItem(
                    transactionId: txnId,
                    receiptItemId: item.id,
                    name: item.name,
                    amount: item.amount * amountScale,
                    baseAmount: item.amount * baseScale,
                    categoryId: item.categoryId,
                    categorySource: item.categorySource == .user ? .user : .receipt,
                    confidence: item.confidence
                )
                try split.insert(db)
            }
            // Reflect item-level truth on the transaction header: dominant category +
            // receipt source (without clobbering a user lock).
            if var t = try Transaction.fetchOne(db, key: txnId),
               CategorySource.receipt.canOverride(t.categorySource) {
                t.categoryId = Self.dominantCategory(receiptItems) ?? t.categoryId
                t.categorySource = .receipt
                try t.update(db)
            }
        }
        return txnId
    }

    /// Compute a 0...1 match confidence from how close the amount and date are.
    func matchConfidence(receipt: Receipt, transaction: Transaction, tolerance: MatchTolerance) -> Double {
        let amountErr = abs(transaction.originalAmount - receipt.totalAmount)
        let amountScore = tolerance.amount > 0 ? max(0, 1 - amountErr / tolerance.amount) : (amountErr == 0 ? 1 : 0)
        let dayErr = abs(Calendar.utc.dateComponents([.day], from: receipt.purchaseDate, to: transaction.date).day ?? 0)
        let dayScore = tolerance.days > 0 ? max(0, 1 - Double(dayErr) / Double(tolerance.days)) : (dayErr == 0 ? 1 : 0)
        return 0.6 * amountScore + 0.4 * dayScore
    }

    static func dominantCategory(_ items: [ReceiptItem]) -> String? {
        var totals: [String: Double] = [:]
        for item in items { totals[item.categoryId, default: 0] += item.amount }
        return totals.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Match updates

    private func updateMatch(receiptId: Int64, status: ReceiptMatchStatus,
                             transactionId: Int64?, confidence: Double?) throws {
        try writer.write { db in
            try Self.updateMatch(db, receiptId: receiptId, status: status,
                                 transactionId: transactionId, confidence: confidence)
        }
    }

    private static func updateMatch(_ db: Database, receiptId: Int64, status: ReceiptMatchStatus,
                                    transactionId: Int64?, confidence: Double?) throws {
        guard var receipt = try Receipt.fetchOne(db, key: receiptId) else { return }
        receipt.matchStatus = status
        receipt.transactionId = transactionId
        receipt.matchConfidence = confidence
        try receipt.update(db)
    }

    // MARK: - Queries

    public func unmatchedReceipts() throws -> [Receipt] {
        try writer.read { db in
            try Receipt
                .filter(Receipt.Columns.matchStatus != ReceiptMatchStatus.matched.rawValue)
                .order(Receipt.Columns.scannedAt.desc)
                .fetchAll(db)
        }
    }

    /// Posted transactions in a month at receipt-worthy merchants that have no linked
    /// receipt yet — the queue that drives the daily "scan your receipts" nudge.
    public func transactionsNeedingReceipt(
        in month: MonthKey,
        merchants normalizedMerchants: Set<String>
    ) throws -> [Transaction] {
        let start = month.startDate()
        let end = month.endDate()
        return try writer.read { db in
            let txns = try Transaction
                .filter(Transaction.Columns.date >= start && Transaction.Columns.date < end)
                .filter(Transaction.Columns.pending == false)
                .filter(Transaction.Columns.isInternalTransfer == false)
                .filter(Transaction.Columns.originalAmount > 0)
                .fetchAll(db)
            let linkedIds = try Set(Receipt
                .filter(Receipt.Columns.matchStatus == ReceiptMatchStatus.matched.rawValue)
                .fetchAll(db)
                .compactMap(\.transactionId))
            return txns.filter { txn in
                guard let id = txn.id, !linkedIds.contains(id) else { return false }
                return normalizedMerchants.contains(MerchantNormalizer.normalize(txn.merchantName))
            }
        }
    }

    /// Item-level ("Layer 0") spending by category for a month, in base currency.
    /// Transactions that have splits contribute per item; the rest contribute their own
    /// category. Excludes internal transfers and money-in.
    public func itemizedSpendingByCategory(in month: MonthKey) throws -> [String: Double] {
        let start = month.startDate()
        let end = month.endDate()
        return try writer.read { db in
            var result: [String: Double] = [:]

            // Split transactions: sum transaction_items per category.
            let splitRows = try Row.fetchAll(db, sql: """
                SELECT ti.category_id AS category_id, SUM(ti.base_amount) AS total
                FROM transaction_items ti
                JOIN transactions t ON t.id = ti.transaction_id
                WHERE t.date >= ? AND t.date < ?
                  AND t.is_internal_transfer = 0
                  AND t.base_amount > 0
                GROUP BY ti.category_id
                """, arguments: [start, end])
            for row in splitRows {
                result[row["category_id"], default: 0] += row["total"]
            }

            // Unsplit transactions: use their own category.
            let wholeRows = try Row.fetchAll(db, sql: """
                SELECT t.category_id AS category_id, SUM(t.base_amount) AS total
                FROM transactions t
                WHERE t.date >= ? AND t.date < ?
                  AND t.is_internal_transfer = 0
                  AND t.base_amount > 0
                  AND NOT EXISTS (SELECT 1 FROM transaction_items ti WHERE ti.transaction_id = t.id)
                GROUP BY t.category_id
                """, arguments: [start, end])
            for row in wholeRows {
                result[row["category_id"], default: 0] += row["total"]
            }

            return result
        }
    }
}
