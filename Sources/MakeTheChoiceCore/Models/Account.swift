import Foundation
import GRDB

/// A bank account belonging to a Plaid Item.
public struct Account: Codable, Identifiable, Hashable, Sendable {
    /// Plaid `account_id`.
    public var id: String
    /// Owning Plaid Item (`plaid_items.id`).
    public var itemId: String
    /// Institution display name (denormalized for convenience).
    public var institution: String
    /// Account display name.
    public var name: String
    /// Last 2-4 digits, if provided.
    public var mask: String?
    /// Plaid account type (e.g. "depository", "credit").
    public var type: String?
    /// ISO currency code of the account.
    public var currency: String
    /// Current balance, if known.
    public var currentBalance: Double?
    /// Available balance, if known.
    public var availableBalance: Double?

    public init(
        id: String,
        itemId: String,
        institution: String,
        name: String,
        mask: String? = nil,
        type: String? = nil,
        currency: String,
        currentBalance: Double? = nil,
        availableBalance: Double? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.institution = institution
        self.name = name
        self.mask = mask
        self.type = type
        self.currency = currency
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
    }
}

extension Account: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "accounts"

    public enum Columns {
        public static let id = Column("id")
        public static let itemId = Column("item_id")
        public static let institution = Column("institution")
        public static let name = Column("name")
        public static let mask = Column("mask")
        public static let type = Column("type")
        public static let currency = Column("currency")
        public static let currentBalance = Column("current_balance")
        public static let availableBalance = Column("available_balance")
    }

    public init(row: Row) {
        id = row["id"]
        itemId = row["item_id"]
        institution = row["institution"]
        name = row["name"]
        mask = row["mask"]
        type = row["type"]
        currency = row["currency"]
        currentBalance = row["current_balance"]
        availableBalance = row["available_balance"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["item_id"] = itemId
        container["institution"] = institution
        container["name"] = name
        container["mask"] = mask
        container["type"] = type
        container["currency"] = currency
        container["current_balance"] = currentBalance
        container["available_balance"] = availableBalance
    }
}
