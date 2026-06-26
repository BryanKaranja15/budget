import Foundation
import GRDB

/// Supplies FX rates for backfill — the network seam. Phase 1 uses an in-memory mock;
/// Phase 3 swaps in a Frankfurter/ECB-backed implementation. A rate means:
/// `1 unit of base = rate units of quote` on `day`.
public protocol FXRateProviding: Sendable {
    /// Rates to seed for a date range (inclusive). Implementations may return fewer days
    /// than requested (e.g. weekends/holidays have no published rate).
    func rates(base: String, quote: String, from: Date, to: Date) async throws -> [FXRate]
}

/// A canned rate source for fixtures and tests — no network. Returns the same flat rate
/// for every requested day (good enough to exercise conversion + fallback logic).
public struct MockFXRateProvider: FXRateProviding {
    private let table: [String: Double]  // "BASE>QUOTE" → rate

    public init(_ table: [String: Double]) { self.table = table }

    public func rates(base: String, quote: String, from: Date, to: Date) async throws -> [FXRate] {
        guard let rate = table["\(base)>\(quote)"] else { return [] }
        var out: [FXRate] = []
        var day = Calendar.utc.startOfDay(for: from)
        let last = Calendar.utc.startOfDay(for: to)
        while day <= last {
            out.append(FXRate(day: FXService.dayString(day), base: base, quote: quote, rate: rate))
            day = Calendar.utc.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}

/// Read/write access to the `fx_rates` table.
public struct FXRateStore {
    private let writer: DatabaseWriter
    public init(_ db: AppDatabase) { self.writer = db.writer }
    public init(writer: DatabaseWriter) { self.writer = writer }

    @discardableResult
    public func save(_ rates: [FXRate]) throws -> Int {
        try writer.write { db in
            for rate in rates { try rate.save(db) }
            return rates.count
        }
    }

    public func count() throws -> Int {
        try writer.read { db in try FXRate.fetchCount(db) }
    }

    /// The rate to multiply a `base`-denominated amount by to get `quote`, for `day` or
    /// the closest earlier day available. Returns nil if no usable rate (direct or
    /// inverse) exists at all.
    public func rate(from base: String, to quote: String, on day: String) throws -> Double? {
        if base == quote { return 1 }
        return try writer.read { db in
            try Self.rate(from: base, to: quote, on: day, db)
        }
    }

    static func rate(from base: String, to quote: String, on day: String, _ db: Database) throws -> Double? {
        if base == quote { return 1 }
        // Exact day, else most recent earlier day, else earliest later day.
        if let direct = try lookup(base: base, quote: quote, on: day, db) { return direct }
        if let inverse = try lookup(base: quote, quote: base, on: day, db), inverse != 0 {
            return 1 / inverse
        }
        return nil
    }

    private static func lookup(base: String, quote: String, on day: String, _ db: Database) throws -> Double? {
        // Prefer the rate on/just before the day; fall back to the earliest rate after it.
        if let r = try FXRate
            .filter(FXRate.Columns.base == base && FXRate.Columns.quote == quote)
            .filter(FXRate.Columns.day <= day)
            .order(FXRate.Columns.day.desc)
            .fetchOne(db) {
            return r.rate
        }
        if let r = try FXRate
            .filter(FXRate.Columns.base == base && FXRate.Columns.quote == quote)
            .filter(FXRate.Columns.day > day)
            .order(FXRate.Columns.day.asc)
            .fetchOne(db) {
            return r.rate
        }
        return nil
    }
}

/// Converts transaction amounts from their original currency into the user's base
/// currency using stored historical rates (transaction-date rate, with closest-day
/// fallback). See plan.md "Currency Handling".
public struct FXService {
    private let store: FXRateStore
    /// The user's base currency (chosen at onboarding).
    public let baseCurrency: String

    public init(_ db: AppDatabase, baseCurrency: String) {
        self.store = FXRateStore(db)
        self.baseCurrency = baseCurrency
    }

    public init(store: FXRateStore, baseCurrency: String) {
        self.store = store
        self.baseCurrency = baseCurrency
    }

    /// "YYYY-MM-DD" in UTC — matches the `fx_rates.day` format.
    public static func dayString(_ date: Date) -> String {
        let c = Calendar.utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// Convert `amount` (in `currency`) to the base currency at the rate for `date`.
    /// Throws `FXError.missingRate` if no rate is available for that currency pair.
    public func toBase(_ amount: Double, currency: String, on date: Date) throws -> Double {
        if currency == baseCurrency { return amount }
        let day = Self.dayString(date)
        guard let rate = try store.rate(from: currency, to: baseCurrency, on: day) else {
            throw FXError.missingRate(from: currency, to: baseCurrency, day: day)
        }
        return amount * rate
    }

    /// Return a copy of `transaction` with `baseAmount` recomputed from its
    /// `originalAmount`/`isoCurrencyCode` at its own date.
    public func normalizing(_ transaction: Transaction) throws -> Transaction {
        var t = transaction
        t.baseAmount = try toBase(transaction.originalAmount,
                                  currency: transaction.isoCurrencyCode,
                                  on: transaction.date)
        return t
    }
}

/// Errors raised by `FXService`.
public enum FXError: Error, Equatable, Sendable {
    case missingRate(from: String, to: String, day: String)
}
