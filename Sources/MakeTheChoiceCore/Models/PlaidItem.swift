import Foundation
import GRDB

/// One linked institution (a Plaid Item). The device keeps status/metadata only;
/// the access_token ciphertext and sync cursor live server-side (see plan.md).
public struct PlaidItem: Codable, Identifiable, Hashable, Sendable {
    /// Plaid `item_id`.
    public var id: String
    /// Institution display name (e.g. "US Bank", "Revolut").
    public var institution: String
    /// Current item status.
    public var status: PlaidItemStatus
    /// When the item was linked.
    public var createdAt: Date
    /// Last successful sync, if any.
    public var lastSyncedAt: Date?

    public init(
        id: String,
        institution: String,
        status: PlaidItemStatus = .active,
        createdAt: Date = Date(),
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.institution = institution
        self.status = status
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
    }
}

extension PlaidItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "plaid_items"

    public enum Columns {
        public static let id = Column("id")
        public static let institution = Column("institution")
        public static let status = Column("status")
        public static let createdAt = Column("created_at")
        public static let lastSyncedAt = Column("last_synced_at")
    }

    public init(row: Row) {
        id = row["id"]
        institution = row["institution"]
        status = PlaidItemStatus(rawValue: row["status"]) ?? .active
        createdAt = row["created_at"]
        lastSyncedAt = row["last_synced_at"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["institution"] = institution
        container["status"] = status.rawValue
        container["created_at"] = createdAt
        container["last_synced_at"] = lastSyncedAt
    }
}
