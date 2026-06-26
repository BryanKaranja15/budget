import Foundation
import GRDB

/// A categorized portion of a transaction — the canonical "split". When a transaction
/// has `transaction_items`, itemized spending uses these instead of the transaction's
/// single category. Produced by reconciling `receipt_items` to the transaction total,
/// or created directly for a manual split.
public struct TransactionItem: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// Parent transaction (`transactions.id`).
    public var transactionId: Int64
    /// Source receipt item, if this split came from a scan (`receipt_items.id`).
    public var receiptItemId: Int64?
    /// Item description.
    public var name: String
    /// Portion amount in the transaction's original currency.
    public var amount: Double
    /// Portion amount in the user's base currency (sums to the transaction's base amount).
    public var baseAmount: Double
    /// Category slug for this portion (`categories.id`).
    public var categoryId: String
    /// Where this split's category came from.
    public var categorySource: CategorySource
    /// Confidence (0...1), if applicable.
    public var confidence: Double?

    public init(
        id: Int64? = nil,
        transactionId: Int64,
        receiptItemId: Int64? = nil,
        name: String,
        amount: Double,
        baseAmount: Double,
        categoryId: String,
        categorySource: CategorySource = .receipt,
        confidence: Double? = nil
    ) {
        self.id = id
        self.transactionId = transactionId
        self.receiptItemId = receiptItemId
        self.name = name
        self.amount = amount
        self.baseAmount = baseAmount
        self.categoryId = categoryId
        self.categorySource = categorySource
        self.confidence = confidence
    }
}

extension TransactionItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "transaction_items"

    public enum Columns {
        public static let id = Column("id")
        public static let transactionId = Column("transaction_id")
        public static let receiptItemId = Column("receipt_item_id")
        public static let name = Column("name")
        public static let amount = Column("amount")
        public static let baseAmount = Column("base_amount")
        public static let categoryId = Column("category_id")
        public static let categorySource = Column("category_source")
        public static let confidence = Column("confidence")
    }

    public init(row: Row) {
        id = row["id"]
        transactionId = row["transaction_id"]
        receiptItemId = row["receipt_item_id"]
        name = row["name"]
        amount = row["amount"]
        baseAmount = row["base_amount"]
        categoryId = row["category_id"]
        categorySource = CategorySource(rawValue: row["category_source"]) ?? .receipt
        confidence = row["confidence"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["transaction_id"] = transactionId
        container["receipt_item_id"] = receiptItemId
        container["name"] = name
        container["amount"] = amount
        container["base_amount"] = baseAmount
        container["category_id"] = categoryId
        container["category_source"] = categorySource.rawValue
        container["confidence"] = confidence
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
