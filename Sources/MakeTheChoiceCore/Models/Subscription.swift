import Foundation
import GRDB

/// A detected recurring charge (see plan.md "Subscription Detection").
public struct Subscription: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// Merchant name (display form).
    public var merchant: String
    /// Typical charge amount in base currency.
    public var amount: Double
    /// Currency of `amount`.
    public var currency: String
    /// Cadence in days (≈ 7 / 14 / 30 / 365).
    public var cadenceDays: Int
    /// Date of the most recent charge.
    public var lastCharged: Date
    /// Predicted next charge date.
    public var nextExpectedDate: Date
    /// Projected annual cost in base currency.
    public var annualCost: Double
    /// Lifecycle status.
    public var status: SubscriptionStatus
    /// Detection confidence (0...1).
    public var confidence: Double
    /// True when the latest charge exceeds the historical amount (price creep).
    public var priceCreep: Bool

    public init(
        id: Int64? = nil,
        merchant: String,
        amount: Double,
        currency: String,
        cadenceDays: Int,
        lastCharged: Date,
        nextExpectedDate: Date,
        annualCost: Double,
        status: SubscriptionStatus = .active,
        confidence: Double,
        priceCreep: Bool = false
    ) {
        self.id = id
        self.merchant = merchant
        self.amount = amount
        self.currency = currency
        self.cadenceDays = cadenceDays
        self.lastCharged = lastCharged
        self.nextExpectedDate = nextExpectedDate
        self.annualCost = annualCost
        self.status = status
        self.confidence = confidence
        self.priceCreep = priceCreep
    }
}

extension Subscription: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "subscriptions"

    public enum Columns {
        public static let id = Column("id")
        public static let merchant = Column("merchant")
        public static let amount = Column("amount")
        public static let currency = Column("currency")
        public static let cadenceDays = Column("cadence_days")
        public static let lastCharged = Column("last_charged")
        public static let nextExpectedDate = Column("next_expected_date")
        public static let annualCost = Column("annual_cost")
        public static let status = Column("status")
        public static let confidence = Column("confidence")
        public static let priceCreep = Column("price_creep")
    }

    public init(row: Row) {
        id = row["id"]
        merchant = row["merchant"]
        amount = row["amount"]
        currency = row["currency"]
        cadenceDays = row["cadence_days"]
        lastCharged = row["last_charged"]
        nextExpectedDate = row["next_expected_date"]
        annualCost = row["annual_cost"]
        status = SubscriptionStatus(rawValue: row["status"]) ?? .active
        confidence = row["confidence"]
        priceCreep = row["price_creep"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["merchant"] = merchant
        container["amount"] = amount
        container["currency"] = currency
        container["cadence_days"] = cadenceDays
        container["last_charged"] = lastCharged
        container["next_expected_date"] = nextExpectedDate
        container["annual_cost"] = annualCost
        container["status"] = status.rawValue
        container["confidence"] = confidence
        container["price_creep"] = priceCreep
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
