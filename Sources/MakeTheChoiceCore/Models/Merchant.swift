import Foundation
import GRDB

/// A merchant→category mapping (categorization Layer 2). Keyed by a normalized name
/// so raw merchant strings ("AMZN Mktp US*2X9", "Amazon.com") collapse to one row.
public struct Merchant: Codable, Identifiable, Hashable, Sendable {
    /// Normalized merchant name (lowercased, punctuation/noise stripped). Primary key.
    public var normalizedName: String
    /// Category slug this merchant maps to (`categories.id`).
    public var categoryId: String
    /// Where the mapping came from.
    public var source: MerchantSource
    /// If true, this is a user override and wins over classifier/Plaid (precedence).
    public var locked: Bool
    /// Last time the mapping was updated.
    public var updatedAt: Date

    public var id: String { normalizedName }

    public init(
        normalizedName: String,
        categoryId: String,
        source: MerchantSource = .seed,
        locked: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.normalizedName = normalizedName
        self.categoryId = categoryId
        self.source = source
        self.locked = locked
        self.updatedAt = updatedAt
    }

    /// Convenience using the fixed category enum.
    public init(
        normalizedName: String,
        category: AppCategory,
        source: MerchantSource = .seed,
        locked: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.init(
            normalizedName: normalizedName,
            categoryId: category.rawValue,
            source: source,
            locked: locked,
            updatedAt: updatedAt
        )
    }
}

extension Merchant: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "merchants"

    public enum Columns {
        public static let normalizedName = Column("normalized_name")
        public static let categoryId = Column("category_id")
        public static let source = Column("source")
        public static let locked = Column("locked")
        public static let updatedAt = Column("updated_at")
    }

    public init(row: Row) {
        normalizedName = row["normalized_name"]
        categoryId = row["category_id"]
        source = MerchantSource(rawValue: row["source"]) ?? .seed
        locked = row["locked"]
        updatedAt = row["updated_at"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["normalized_name"] = normalizedName
        container["category_id"] = categoryId
        container["source"] = source.rawValue
        container["locked"] = locked
        container["updated_at"] = updatedAt
    }
}
