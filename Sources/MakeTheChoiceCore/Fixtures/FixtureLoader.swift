import Foundation
import GRDB

/// Loads deterministic sample data (no network) for previews, manual testing, and
/// unit tests. Mirrors the shape of real Plaid sync output: two institutions, several
/// accounts, transactions across categories/months, a monthly subscription, and an
/// internal-transfer pair.
public enum FixtureLoader {

    /// Build the sample items.
    public static func sampleItems() -> [PlaidItem] {
        let created = date("2024-01-01")
        return [
            PlaidItem(id: "item_usbank", institution: "US Bank", status: .active, createdAt: created),
            PlaidItem(id: "item_revolut", institution: "Revolut", status: .active, createdAt: created)
        ]
    }

    /// Build the sample accounts.
    public static func sampleAccounts() -> [Account] {
        [
            Account(id: "acc_us_checking", itemId: "item_usbank", institution: "US Bank",
                    name: "Checking", mask: "1234", type: "depository", currency: "USD",
                    currentBalance: 4200.55, availableBalance: 4100.00),
            Account(id: "acc_us_savings", itemId: "item_usbank", institution: "US Bank",
                    name: "Savings", mask: "5678", type: "depository", currency: "USD",
                    currentBalance: 15000.00, availableBalance: 15000.00),
            Account(id: "acc_rev_gbp", itemId: "item_revolut", institution: "Revolut",
                    name: "GBP Account", mask: "9012", type: "depository", currency: "GBP",
                    currentBalance: 820.30, availableBalance: 820.30)
        ]
    }

    /// Build sample transactions. `baseCurrency` is assumed USD; GBP rows are converted
    /// at a flat fixture rate of 1.27 for simplicity (real FX is Phase 1).
    public static func sampleTransactions() -> [Transaction] {
        var txns: [Transaction] = []
        var counter = 0
        func tx(
            _ plaidId: String? = nil,
            account: String,
            date dateStr: String,
            merchant: String,
            amount: Double,
            currency: String = "USD",
            category: AppCategory,
            source: CategorySource = .merchant,
            subscription: Bool = false,
            internalTransfer: Bool = false
        ) {
            counter += 1
            let base = currency == "GBP" ? amount * 1.27 : amount
            txns.append(Transaction(
                plaidTransactionId: plaidId ?? "txn_\(counter)",
                accountId: account,
                date: date(dateStr),
                merchantName: merchant,
                isoCurrencyCode: currency,
                originalAmount: amount,
                baseAmount: base,
                plaidCategory: nil,
                categoryId: category.rawValue,
                categorySource: source,
                isSubscription: subscription,
                isInternalTransfer: internalTransfer
            ))
        }

        // Monthly Netflix subscription across three months (with a price creep in May).
        tx(account: "acc_us_checking", date: "2024-03-15", merchant: "Netflix", amount: 15.49, category: .subscriptions, subscription: true)
        tx(account: "acc_us_checking", date: "2024-04-15", merchant: "Netflix", amount: 15.49, category: .subscriptions, subscription: true)
        tx(account: "acc_us_checking", date: "2024-05-15", merchant: "Netflix", amount: 17.99, category: .subscriptions, subscription: true)

        // Food in May.
        tx(account: "acc_us_checking", date: "2024-05-02", merchant: "Whole Foods", amount: 84.20, category: .food)
        tx(account: "acc_us_checking", date: "2024-05-09", merchant: "Starbucks", amount: 6.75, category: .food)
        tx(account: "acc_us_checking", date: "2024-05-18", merchant: "Chipotle", amount: 12.40, category: .food)

        // Transport in May.
        tx(account: "acc_us_checking", date: "2024-05-04", merchant: "Uber", amount: 23.10, category: .transport)
        tx(account: "acc_us_checking", date: "2024-05-20", merchant: "Shell", amount: 48.00, category: .transport)

        // Clothing (Revolut, GBP) in May.
        tx(account: "acc_rev_gbp", date: "2024-05-11", merchant: "Zara", amount: 59.99, currency: "GBP", category: .clothing)

        // Income (negative = money in) — should be excluded from spending totals.
        tx(account: "acc_us_checking", date: "2024-05-01", merchant: "Employer Payroll", amount: -3200.00, category: .uncategorized, source: .plaid)

        // Internal transfer pair (checking -> savings) — excluded from spending.
        tx(account: "acc_us_checking", date: "2024-05-25", merchant: "Transfer to Savings", amount: 500.00, category: .savings, source: .plaid, internalTransfer: true)
        tx(account: "acc_us_savings", date: "2024-05-25", merchant: "Transfer from Checking", amount: -500.00, category: .savings, source: .plaid, internalTransfer: true)

        return txns
    }

    /// A sample Target run (one Plaid transaction "Target — $87.34" that should split
    /// into Food + Enjoyment + Housing). Returns the receipt header + its line items
    /// (item categories are left for `ItemCategorizer` to fill, mimicking a fresh scan).
    public static func sampleTargetReceipt() -> (Receipt, [ReceiptItem]) {
        let receipt = Receipt(
            merchantName: "Target",
            purchaseDate: date("2024-05-12"),
            totalAmount: 87.34,
            currency: "USD",
            source: .camera,
            rawText: "TARGET\nBread 4.99\nWine 18.99\nOven Tray 24.99\n...",
            scannedAt: date("2024-05-12")
        )
        let items = [
            ReceiptItem(receiptId: 0, lineNo: 0, name: "Whole Wheat Bread", amount: 4.99, categorySource: .unset),
            ReceiptItem(receiptId: 0, lineNo: 1, name: "Cabernet Wine", amount: 18.99, categorySource: .unset),
            ReceiptItem(receiptId: 0, lineNo: 2, name: "Nonstick Oven Tray", amount: 24.99, categorySource: .unset),
            ReceiptItem(receiptId: 0, lineNo: 3, name: "Organic Milk", amount: 5.49, categorySource: .unset),
            ReceiptItem(receiptId: 0, lineNo: 4, name: "USB-C Charger Cable", amount: 32.88, categorySource: .unset)
        ]
        return (receipt, items)
    }

    /// The matching Plaid transaction for the Target receipt (Food category by Plaid,
    /// before the receipt splits it).
    public static func sampleTargetTransaction() -> Transaction {
        Transaction(
            plaidTransactionId: "txn_target",
            accountId: "acc_us_checking",
            date: date("2024-05-12"),
            merchantName: "Target",
            isoCurrencyCode: "USD",
            originalAmount: 87.34,
            baseAmount: 87.34,
            plaidCategory: "General Merchandise",
            categoryId: AppCategory.uncategorized.rawValue,
            categorySource: .plaid
        )
    }

    /// Install all fixtures into the database (items, accounts, transactions).
    /// Assumes categories/merchants are already seeded.
    public static func load(into db: AppDatabase) throws {
        let items = ItemAccountRepository(db)
        for item in sampleItems() { try items.save(item) }
        try items.save(sampleAccounts())
        let store = TransactionStore(db)
        try store.upsert(sampleTransactions())
    }

    /// Install fixtures plus a Target transaction and a scanned-but-unlinked receipt
    /// (items categorized by `ItemCategorizer`). Call `matchAndSplit` to link them.
    public static func loadWithReceipt(into db: AppDatabase) throws -> Receipt {
        try load(into: db)
        let store = TransactionStore(db)
        try store.upsert(sampleTargetTransaction())
        let (receipt, rawItems) = sampleTargetReceipt()
        let categorized = ItemCategorizer.categorize(items: rawItems)
        return try ReceiptStore(db).save(receipt, items: categorized)
    }

    // MARK: - Helpers

    /// Parse "YYYY-MM-DD" at UTC start-of-day.
    static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = .utc
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }
}
