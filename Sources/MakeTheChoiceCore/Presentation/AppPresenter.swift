import Foundation
import GRDB

/// The single entry point the UI calls to build screen view-models from the database.
/// "Work backwards from the UI": each method returns exactly one screen's contract, in
/// base currency, with all computation already done. SwiftUI views (designed in Codex)
/// bind to the returned structs and never touch GRDB directly.
public struct AppPresenter {
    private let db: AppDatabase
    private let baseCurrency: String

    private var transactions: TransactionStore { TransactionStore(db) }
    private var categories: CategoryRepository { CategoryRepository(db) }
    private var receipts: ReceiptStore { ReceiptStore(db) }

    public init(_ db: AppDatabase, baseCurrency: String) {
        self.db = db
        self.baseCurrency = baseCurrency
    }

    // MARK: - Screen 1: Dashboard

    public func dashboard(for month: MonthKey) throws -> DashboardViewModel {
        let spend = try receipts.itemizedSpendingByCategory(in: month)  // Layer 0 aware
        let total = spend.values.reduce(0, +)
        let allCategories = try categories.all()

        var rows: [DashboardViewModel.CategoryRow] = []
        for category in allCategories {
            let spent = spend[category.id] ?? 0
            let budgetLimit = try categories.budget(category.id, for: month)
            // Show a row only if it has spending or a budget worth tracking.
            guard spent > 0 || budgetLimit != nil else { continue }
            let remaining = budgetLimit.map { $0 - spent }
            rows.append(.init(
                id: category.id,
                name: category.name,
                spent: Money(spent, baseCurrency),
                budget: budgetLimit.map { Money($0, baseCurrency) },
                remaining: remaining.map { Money($0, baseCurrency) },
                fractionOfTotal: total > 0 ? spent / total : 0,
                status: BudgetStatus.classify(spent: spent, limit: budgetLimit)
            ))
        }

        return DashboardViewModel(
            month: month.description,
            totalSpent: Money(total, baseCurrency),
            categories: rows,
            availableMonths: try availableMonths()
        )
    }

    // MARK: - Screen 2: Category Drilldown

    public func categoryDetail(categoryId: String, month: MonthKey) throws -> CategoryDetailViewModel {
        let txns = try transactions.transactions(in: month, categoryId: categoryId)
        let splitTxnIds = try transactionIdsWithSplits()

        let rows: [CategoryDetailViewModel.TransactionRow] = txns.compactMap { txn in
            guard let id = txn.id else { return nil }
            return .init(
                id: id,
                merchant: txn.merchantName,
                date: txn.date,
                baseAmount: Money(txn.baseAmount, baseCurrency),
                originalAmount: Money(txn.originalAmount, txn.isoCurrencyCode),
                isForeignCurrency: txn.isoCurrencyCode != baseCurrency,
                hasItemSplits: splitTxnIds.contains(id),
                categorySource: txn.categorySource
            )
        }
        let total = txns.filter { !$0.isInternalTransfer && $0.baseAmount > 0 }
            .reduce(0) { $0 + $1.baseAmount }

        return CategoryDetailViewModel(
            categoryId: categoryId,
            categoryName: Self.categoryName(categoryId),
            month: month.description,
            total: Money(total, baseCurrency),
            transactions: rows
        )
    }

    // MARK: - Screen 3: Subscriptions Board

    public func subscriptionsBoard() throws -> SubscriptionsBoardViewModel {
        let subs = try db.reader.read { database in
            try Subscription
                .order(Subscription.Columns.annualCost.desc)
                .fetchAll(database)
        }
        let rows: [SubscriptionsBoardViewModel.Row] = subs.compactMap { sub in
            guard let id = sub.id else { return nil }
            return .init(
                id: id,
                merchant: sub.merchant,
                amount: Money(sub.amount, sub.currency),
                cadenceDays: sub.cadenceDays,
                cadenceLabel: SubscriptionsBoardViewModel.cadenceLabel(sub.cadenceDays),
                nextExpectedDate: sub.nextExpectedDate,
                annualCost: Money(sub.annualCost, sub.currency),
                status: sub.status,
                priceCreep: sub.priceCreep
            )
        }
        let annual = subs.filter { $0.status == .active }.reduce(0) { $0 + $1.annualCost }
        return SubscriptionsBoardViewModel(
            rows: rows,
            totalAnnual: Money(annual, baseCurrency),
            totalMonthly: Money(annual / 12, baseCurrency)
        )
    }

    // MARK: - Screen 5: Receipt Split

    public func receiptSplit(receiptId: Int64) throws -> ReceiptSplitViewModel? {
        guard let receipt = try db.reader.read({ try Receipt.fetchOne($0, key: receiptId) }) else {
            return nil
        }
        let items = try receipts.items(forReceipt: receiptId).map { item in
            ReceiptSplitViewModel.ItemRow(
                id: item.id ?? 0,
                name: item.name,
                amount: Money(item.amount, receipt.currency),
                categoryId: item.categoryId,
                categoryName: Self.categoryName(item.categoryId),
                categorySource: item.categorySource
            )
        }

        var splits: [ReceiptSplitViewModel.SplitRow] = []
        if let txnId = receipt.transactionId {
            var totals: [String: Double] = [:]
            for ti in try receipts.transactionItems(forTransaction: txnId) {
                totals[ti.categoryId, default: 0] += ti.baseAmount
            }
            splits = totals
                .map { ReceiptSplitViewModel.SplitRow(categoryId: $0.key,
                                                      categoryName: Self.categoryName($0.key),
                                                      amount: Money($0.value, baseCurrency)) }
                .sorted { $0.amount.amount > $1.amount.amount }
        }

        return ReceiptSplitViewModel(
            receiptId: receiptId,
            merchant: receipt.merchantName,
            purchaseDate: receipt.purchaseDate,
            total: Money(receipt.totalAmount, receipt.currency),
            matchStatus: receipt.matchStatus,
            matchConfidence: receipt.matchConfidence,
            items: items,
            splits: splits
        )
    }

    // MARK: - Helpers

    /// Distinct months that have transactions, newest first ("YYYY-MM").
    public func availableMonths() throws -> [String] {
        try db.reader.read { database in
            try String.fetchAll(database, sql: """
                SELECT DISTINCT substr(date, 1, 7) AS m
                FROM transactions
                ORDER BY m DESC
                """)
        }
    }

    private func transactionIdsWithSplits() throws -> Set<Int64> {
        try db.reader.read { database in
            try Set(Int64.fetchAll(database, sql:
                "SELECT DISTINCT transaction_id FROM transaction_items"))
        }
    }

    static func categoryName(_ slug: String) -> String {
        AppCategory(rawValue: slug)?.displayName ?? slug.capitalized
    }
}
