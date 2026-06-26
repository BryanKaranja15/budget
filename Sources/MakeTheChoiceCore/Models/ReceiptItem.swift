import Foundation
import GRDB

/// A single line item read off a receipt (raw OCR provenance). After a receipt is
/// matched to a transaction, items are reconciled into `transaction_items`.
public struct ReceiptItem: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// Owning receipt (`receipts.id`).
    public var receiptId: Int64
    /// Order on the receipt (0-based).
    public var lineNo: Int
    /// Item description as read.
    public var name: String
    /// Quantity (defaults to 1).
    public var quantity: Double
    /// Line total in the receipt currency.
    public var amount: Double
    /// Categorized slug for this item (`categories.id`).
    public var categoryId: String
    /// Where the item category came from (usually `.receipt`, or `.user` if corrected).
    public var categorySource: CategorySource
    /// Item-classifier confidence (0...1), if applicable.
    public var confidence: Double?

    public init(
        id: Int64? = nil,
        receiptId: Int64,
        lineNo: Int,
        name: String,
        quantity: Double = 1,
        amount: Double,
        categoryId: String = AppCategory.uncategorized.rawValue,
        categorySource: CategorySource = .receipt,
        confidence: Double? = nil
    ) {
        self.id = id
        self.receiptId = receiptId
        self.lineNo = lineNo
        self.name = name
        self.quantity = quantity
        self.amount = amount
        self.categoryId = categoryId
        self.categorySource = categorySource
        self.confidence = confidence
    }
}

extension ReceiptItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "receipt_items"

    public enum Columns {
        public static let id = Column("id")
        public static let receiptId = Column("receipt_id")
        public static let lineNo = Column("line_no")
        public static let name = Column("name")
        public static let quantity = Column("quantity")
        public static let amount = Column("amount")
        public static let categoryId = Column("category_id")
        public static let categorySource = Column("category_source")
        public static let confidence = Column("confidence")
    }

    public init(row: Row) {
        id = row["id"]
        receiptId = row["receipt_id"]
        lineNo = row["line_no"]
        name = row["name"]
        quantity = row["quantity"]
        amount = row["amount"]
        categoryId = row["category_id"]
        categorySource = CategorySource(rawValue: row["category_source"]) ?? .receipt
        confidence = row["confidence"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["receipt_id"] = receiptId
        container["line_no"] = lineNo
        container["name"] = name
        container["quantity"] = quantity
        container["amount"] = amount
        container["category_id"] = categoryId
        container["category_source"] = categorySource.rawValue
        container["confidence"] = confidence
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
