import Foundation
import GRDB

/// A historical FX rate: 1 unit of `base` = `rate` units of `quote` on `day`.
/// Primary key is (day, base, quote). Used to convert `originalAmount` → `baseAmount`
/// at the transaction-date rate during 24-month backfill.
public struct FXRate: Codable, Hashable, Sendable {
    /// Rate date, "YYYY-MM-DD".
    public var day: String
    /// Base currency code.
    public var base: String
    /// Quote currency code.
    public var quote: String
    /// Conversion rate (base → quote).
    public var rate: Double

    public init(day: String, base: String, quote: String, rate: Double) {
        self.day = day
        self.base = base
        self.quote = quote
        self.rate = rate
    }
}

extension FXRate: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "fx_rates"

    public enum Columns {
        public static let day = Column("day")
        public static let base = Column("base")
        public static let quote = Column("quote")
        public static let rate = Column("rate")
    }

    public init(row: Row) {
        day = row["day"]
        base = row["base"]
        quote = row["quote"]
        rate = row["rate"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["day"] = day
        container["base"] = base
        container["quote"] = quote
        container["rate"] = rate
    }
}
