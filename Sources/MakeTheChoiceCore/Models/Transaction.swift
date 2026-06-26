import Foundation
import GRDB

/// A single transaction stored locally. Upserts are idempotent on `plaidTransactionId`.
///
/// Amounts follow Plaid's sign convention as stored: positive = money out (spending),
/// negative = money in (income/refund). `originalAmount` is in `isoCurrencyCode`;
/// `baseAmount` is the same value converted to the user's base currency.
public struct Transaction: Codable, Identifiable, Hashable, Sendable {
    /// Local autoincrement id (nil until inserted).
    public var id: Int64?
    /// Plaid `transaction_id` — unique; the idempotency key for upserts.
    public var plaidTransactionId: String
    /// Owning account (`accounts.id`).
    public var accountId: String
    /// Transaction date (calendar day; time component normalized to start-of-day UTC).
    public var date: Date
    /// Merchant / counterparty display name.
    public var merchantName: String
    /// Whether the transaction is still pending (id changes once posted).
    public var pending: Bool
    /// If this posted transaction supersedes a pending one, the prior pending id.
    public var pendingTransactionId: String?
    /// ISO currency of `originalAmount`.
    public var isoCurrencyCode: String
    /// Amount in `isoCurrencyCode` (Plaid sign convention).
    public var originalAmount: Double
    /// Amount converted to the user's base currency.
    public var baseAmount: Double
    /// Raw Plaid category label, if any.
    public var plaidCategory: String?
    /// Resolved category slug (`categories.id`).
    public var categoryId: String
    /// Where `categoryId` came from (drives precedence).
    public var categorySource: CategorySource
    /// Classifier confidence (0...1) when `categorySource == .model`.
    public var confidence: Double?
    /// True if part of a detected subscription.
    public var isSubscription: Bool
    /// True if a transfer between the user's own accounts (excluded from spend totals).
    public var isInternalTransfer: Bool

    public init(
        id: Int64? = nil,
        plaidTransactionId: String,
        accountId: String,
        date: Date,
        merchantName: String,
        pending: Bool = false,
        pendingTransactionId: String? = nil,
        isoCurrencyCode: String,
        originalAmount: Double,
        baseAmount: Double,
        plaidCategory: String? = nil,
        categoryId: String = AppCategory.uncategorized.rawValue,
        categorySource: CategorySource = .unset,
        confidence: Double? = nil,
        isSubscription: Bool = false,
        isInternalTransfer: Bool = false
    ) {
        self.id = id
        self.plaidTransactionId = plaidTransactionId
        self.accountId = accountId
        self.date = date
        self.merchantName = merchantName
        self.pending = pending
        self.pendingTransactionId = pendingTransactionId
        self.isoCurrencyCode = isoCurrencyCode
        self.originalAmount = originalAmount
        self.baseAmount = baseAmount
        self.plaidCategory = plaidCategory
        self.categoryId = categoryId
        self.categorySource = categorySource
        self.confidence = confidence
        self.isSubscription = isSubscription
        self.isInternalTransfer = isInternalTransfer
    }

    /// True if this row represents money leaving an account (spending).
    public var isSpending: Bool { baseAmount > 0 }
}

extension Transaction: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "transactions"

    public enum Columns {
        public static let id = Column("id")
        public static let plaidTransactionId = Column("plaid_transaction_id")
        public static let accountId = Column("account_id")
        public static let date = Column("date")
        public static let merchantName = Column("merchant_name")
        public static let pending = Column("pending")
        public static let pendingTransactionId = Column("pending_transaction_id")
        public static let isoCurrencyCode = Column("iso_currency_code")
        public static let originalAmount = Column("original_amount")
        public static let baseAmount = Column("base_amount")
        public static let plaidCategory = Column("plaid_category")
        public static let categoryId = Column("category_id")
        public static let categorySource = Column("category_source")
        public static let confidence = Column("confidence")
        public static let isSubscription = Column("is_subscription")
        public static let isInternalTransfer = Column("is_internal_transfer")
    }

    public init(row: Row) {
        id = row["id"]
        plaidTransactionId = row["plaid_transaction_id"]
        accountId = row["account_id"]
        date = row["date"]
        merchantName = row["merchant_name"]
        pending = row["pending"]
        pendingTransactionId = row["pending_transaction_id"]
        isoCurrencyCode = row["iso_currency_code"]
        originalAmount = row["original_amount"]
        baseAmount = row["base_amount"]
        plaidCategory = row["plaid_category"]
        categoryId = row["category_id"]
        categorySource = CategorySource(rawValue: row["category_source"]) ?? .unset
        confidence = row["confidence"]
        isSubscription = row["is_subscription"]
        isInternalTransfer = row["is_internal_transfer"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["plaid_transaction_id"] = plaidTransactionId
        container["account_id"] = accountId
        container["date"] = date
        container["merchant_name"] = merchantName
        container["pending"] = pending
        container["pending_transaction_id"] = pendingTransactionId
        container["iso_currency_code"] = isoCurrencyCode
        container["original_amount"] = originalAmount
        container["base_amount"] = baseAmount
        container["plaid_category"] = plaidCategory
        container["category_id"] = categoryId
        container["category_source"] = categorySource.rawValue
        container["confidence"] = confidence
        container["is_subscription"] = isSubscription
        container["is_internal_transfer"] = isInternalTransfer
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
