import Foundation
import GRDB

/// Read/write access to the merchant→category table (categorization Layer 2).
public struct MerchantRepository {
    private let writer: DatabaseWriter
    public init(_ db: AppDatabase) { self.writer = db.writer }
    public init(writer: DatabaseWriter) { self.writer = writer }

    /// All merchant mappings.
    public func all() throws -> [Merchant] {
        try writer.read { db in try Merchant.fetchAll(db) }
    }

    /// Count of mappings.
    public func count() throws -> Int {
        try writer.read { db in try Merchant.fetchCount(db) }
    }

    /// Look up a category for a raw merchant string (normalizes internally).
    public func lookup(rawMerchant: String) throws -> Merchant? {
        let normalized = MerchantNormalizer.normalize(rawMerchant)
        guard !normalized.isEmpty else { return nil }
        return try writer.read { db in
            try Merchant.fetchOne(db, key: normalized)
        }
    }

    /// Insert or update a mapping for an already-normalized name.
    @discardableResult
    public func upsert(
        normalizedName: String,
        categoryId: String,
        source: MerchantSource,
        locked: Bool
    ) throws -> Merchant {
        let merchant = Merchant(
            normalizedName: normalizedName,
            categoryId: categoryId,
            source: source,
            locked: locked,
            updatedAt: Date()
        )
        try writer.write { db in try merchant.save(db) }
        return merchant
    }

    /// Record a user override: locks a raw merchant to a category (wins over all
    /// non-user sources). Returns the normalized key used.
    @discardableResult
    public func lockUserOverride(rawMerchant: String, categoryId: String) throws -> String {
        let normalized = MerchantNormalizer.normalize(rawMerchant)
        try upsert(normalizedName: normalized, categoryId: categoryId, source: .user, locked: true)
        return normalized
    }
}
