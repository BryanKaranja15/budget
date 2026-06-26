import Foundation
import GRDB

/// The central transaction repository. Upserts are idempotent on `plaidTransactionId`
/// and never downgrade a stronger existing categorization (precedence-aware).
public struct TransactionStore {
    private let writer: DatabaseWriter
    public init(_ db: AppDatabase) { self.writer = db.writer }
    public init(writer: DatabaseWriter) { self.writer = writer }

    // MARK: - Writes

    /// Idempotent upsert keyed on `plaidTransactionId`.
    ///
    /// If a row already exists, mutable fields are refreshed but the local `id` is kept,
    /// and an existing category assignment is preserved when the incoming source cannot
    /// override it (e.g. a raw sync `.unset`/`.plaid` will not clobber a `.user` lock).
    @discardableResult
    public func upsert(_ incoming: Transaction) throws -> Transaction {
        try writer.write { db in try Self.upsert(incoming, db) }
    }

    /// Batch upsert (added + modified from a sync page). Returns the saved rows.
    @discardableResult
    public func upsert(_ incoming: [Transaction]) throws -> [Transaction] {
        try writer.write { db in
            try incoming.map { try Self.upsert($0, db) }
        }
    }

    static func upsert(_ incoming: Transaction, _ db: Database) throws -> Transaction {
        var row = incoming
        if let existing = try Transaction
            .filter(Transaction.Columns.plaidTransactionId == incoming.plaidTransactionId)
            .fetchOne(db) {
            row.id = existing.id
            // Preserve a stronger existing categorization.
            if !incoming.categorySource.canOverride(existing.categorySource) {
                row.categoryId = existing.categoryId
                row.categorySource = existing.categorySource
                row.confidence = existing.confidence
            }
            try row.update(db)
        } else {
            try row.insert(db)
        }
        return row
    }

    /// Remove transactions by Plaid id (handles `/transactions/sync` `removed`).
    /// Returns the number of rows deleted.
    @discardableResult
    public func remove(plaidTransactionIds ids: [String]) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        return try writer.write { db in
            try Transaction
                .filter(ids.contains(Transaction.Columns.plaidTransactionId))
                .deleteAll(db)
        }
    }

    // MARK: - Reads

    /// Total number of stored transactions.
    public func count() throws -> Int {
        try writer.read { db in try Transaction.fetchCount(db) }
    }

    /// Fetch by Plaid id.
    public func find(plaidTransactionId id: String) throws -> Transaction? {
        try writer.read { db in
            try Transaction
                .filter(Transaction.Columns.plaidTransactionId == id)
                .fetchOne(db)
        }
    }

    /// All transactions in a calendar month, newest first.
    public func transactions(in month: MonthKey) throws -> [Transaction] {
        let start = month.startDate()
        let end = month.endDate()
        return try writer.read { db in
            try Transaction
                .filter(Transaction.Columns.date >= start && Transaction.Columns.date < end)
                .order(Transaction.Columns.date.desc)
                .fetchAll(db)
        }
    }

    /// Transactions for one category within a month, newest first.
    public func transactions(in month: MonthKey, categoryId: String) throws -> [Transaction] {
        let start = month.startDate()
        let end = month.endDate()
        return try writer.read { db in
            try Transaction
                .filter(Transaction.Columns.date >= start && Transaction.Columns.date < end)
                .filter(Transaction.Columns.categoryId == categoryId)
                .order(Transaction.Columns.date.desc)
                .fetchAll(db)
        }
    }

    /// Spending total per category for a month, in base currency. Excludes internal
    /// transfers and counts only money-out (positive base amount).
    public func spendingByCategory(in month: MonthKey) throws -> [String: Double] {
        let start = month.startDate()
        let end = month.endDate()
        return try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT category_id, SUM(base_amount) AS total
                FROM transactions
                WHERE date >= ? AND date < ?
                  AND is_internal_transfer = 0
                  AND base_amount > 0
                GROUP BY category_id
                """, arguments: [start, end])
            var result: [String: Double] = [:]
            for row in rows {
                result[row["category_id"]] = row["total"]
            }
            return result
        }
    }

    /// Total spending for a month (base currency), excluding internal transfers.
    public func totalSpending(in month: MonthKey) throws -> Double {
        try spendingByCategory(in: month).values.reduce(0, +)
    }
}
