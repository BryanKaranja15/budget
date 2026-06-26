import Foundation
import GRDB

/// Optional per-month budget history. The "current" budget lives on `categories`;
/// this table records changes over time so past months keep their original limit.
/// `month` is a "YYYY-MM" string (see `MonthKey`).
public struct Budget: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// Category slug (`categories.id`).
    public var categoryId: String
    /// Month key, "YYYY-MM".
    public var month: String
    /// Budget limit for that month in base currency.
    public var limit: Double

    public init(id: Int64? = nil, categoryId: String, month: String, limit: Double) {
        self.id = id
        self.categoryId = categoryId
        self.month = month
        self.limit = limit
    }
}

extension Budget: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "budgets"

    public enum Columns {
        public static let id = Column("id")
        public static let categoryId = Column("category_id")
        public static let month = Column("month")
        public static let limit = Column("limit_amount")
    }

    public init(row: Row) {
        id = row["id"]
        categoryId = row["category_id"]
        month = row["month"]
        limit = row["limit_amount"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["category_id"] = categoryId
        container["month"] = month
        container["limit_amount"] = limit
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
