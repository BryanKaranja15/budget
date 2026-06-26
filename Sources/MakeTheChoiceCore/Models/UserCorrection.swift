import Foundation
import GRDB

/// A record of a user re-categorizing a transaction. Feeds the merchant table (locked)
/// and the training set (see plan.md "Categorization Engine — Feedback loop").
public struct UserCorrection: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// The transaction that was corrected (`transactions.id`).
    public var transactionId: Int64
    /// Normalized merchant name at correction time.
    public var normalizedMerchant: String
    /// Category before the correction.
    public var fromCategoryId: String?
    /// Category the user chose.
    public var toCategoryId: String
    /// When the correction was made.
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        transactionId: Int64,
        normalizedMerchant: String,
        fromCategoryId: String?,
        toCategoryId: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.normalizedMerchant = normalizedMerchant
        self.fromCategoryId = fromCategoryId
        self.toCategoryId = toCategoryId
        self.createdAt = createdAt
    }
}

extension UserCorrection: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "user_corrections"

    public enum Columns {
        public static let id = Column("id")
        public static let transactionId = Column("transaction_id")
        public static let normalizedMerchant = Column("normalized_merchant")
        public static let fromCategoryId = Column("from_category_id")
        public static let toCategoryId = Column("to_category_id")
        public static let createdAt = Column("created_at")
    }

    public init(row: Row) {
        id = row["id"]
        transactionId = row["transaction_id"]
        normalizedMerchant = row["normalized_merchant"]
        fromCategoryId = row["from_category_id"]
        toCategoryId = row["to_category_id"]
        createdAt = row["created_at"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["transaction_id"] = transactionId
        container["normalized_merchant"] = normalizedMerchant
        container["from_category_id"] = fromCategoryId
        container["to_category_id"] = toCategoryId
        container["created_at"] = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
