import Foundation
import GRDB

/// Rule-based recurring-charge detection (see plan.md "Subscription Detection").
/// Groups money-out charges by normalized merchant, accepts groups with a regular
/// cadence (≈ 7/14/30/365 days) and stable-ish amounts, and flags price creep.
public struct SubscriptionDetector {

    public struct Config: Sendable {
        /// Minimum number of charges required to call something recurring.
        public var minCharges: Int
        /// Max coefficient of variation (stdev/mean) of amounts — rejects noisy
        /// same-merchant spending while still allowing price creep.
        public var maxAmountCV: Double
        /// A charge above `min seen × (1 + this)` marks price creep.
        public var creepThreshold: Double
        public init(minCharges: Int = 2, maxAmountCV: Double = 0.25, creepThreshold: Double = 0.05) {
            self.minCharges = minCharges
            self.maxAmountCV = maxAmountCV
            self.creepThreshold = creepThreshold
        }
    }

    public let config: Config
    public init(config: Config = .init()) { self.config = config }

    /// Map a raw inter-charge gap (days) to the nearest canonical cadence, or nil.
    static func canonicalCadence(_ days: Double) -> Int? {
        switch days {
        case 5...9:     return 7
        case 11...17:   return 14
        case 26...35:   return 30
        case 350...380: return 365
        default:        return nil
        }
    }

    /// Detect subscriptions from a transaction set. `baseCurrency` labels the produced
    /// amounts (which are in base currency); `asOf` (default: latest charge seen) decides
    /// lapsed status.
    public func detect(_ transactions: [Transaction], baseCurrency: String,
                       asOf: Date? = nil) -> [Subscription] {
        // Only money-out, non-transfer charges participate.
        let spend = transactions.filter { $0.baseAmount > 0 && !$0.isInternalTransfer }
        let groups = Dictionary(grouping: spend) { MerchantNormalizer.normalize($0.merchantName) }

        var result: [Subscription] = []
        for (key, charges) in groups where !key.isEmpty {
            guard let sub = subscription(from: charges, baseCurrency: baseCurrency, asOf: asOf) else {
                continue
            }
            result.append(sub)
        }
        // Stable, useful ordering: biggest annual cost first.
        return result.sorted { $0.annualCost > $1.annualCost }
    }

    private func subscription(from charges: [Transaction], baseCurrency: String,
                              asOf: Date?) -> Subscription? {
        guard charges.count >= config.minCharges else { return nil }
        let sorted = charges.sorted { $0.date < $1.date }

        // Cadence: every consecutive gap must map to the SAME canonical cadence.
        var cadence: Int?
        for i in 1..<sorted.count {
            let gap = sorted[i].date.timeIntervalSince(sorted[i - 1].date) / 86_400
            guard let c = Self.canonicalCadence(gap) else { return nil }
            if let existing = cadence, existing != c { return nil }
            cadence = c
        }
        guard let cadenceDays = cadence else { return nil }

        // Amount stability (allows creep, rejects noise).
        let amounts = sorted.map(\.baseAmount)
        let mean = amounts.reduce(0, +) / Double(amounts.count)
        guard mean > 0 else { return nil }
        let variance = amounts.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(amounts.count)
        let cv = variance.squareRoot() / mean
        guard cv <= config.maxAmountCV else { return nil }

        let latest = sorted.last!
        let minAmount = amounts.min()!
        let priceCreep = latest.baseAmount > minAmount * (1 + config.creepThreshold)

        let nextExpected = latest.date.addingTimeInterval(Double(cadenceDays) * 86_400)
        let annualCost = latest.baseAmount * (365.0 / Double(cadenceDays))

        // Lapsed if we've gone ~2 cycles past the last charge without a new one.
        let reference = asOf ?? latest.date
        let status: SubscriptionStatus =
            reference.timeIntervalSince(latest.date) > Double(cadenceDays) * 2 * 86_400
            ? .lapsed : .active

        // Confidence: more charges + tighter amounts → higher, capped at 0.95.
        let countScore = min(0.95, 0.55 + 0.15 * Double(sorted.count - 1))
        let confidence = max(0.5, countScore * (1 - cv))

        return Subscription(
            merchant: latest.merchantName,
            amount: latest.baseAmount,
            currency: baseCurrency,
            cadenceDays: cadenceDays,
            lastCharged: latest.date,
            nextExpectedDate: nextExpected,
            annualCost: annualCost,
            status: status,
            confidence: confidence,
            priceCreep: priceCreep
        )
    }

    /// Detect over all stored transactions, replace the `subscriptions` table with the
    /// results, and set `is_subscription` on member transactions. Returns the rows saved.
    @discardableResult
    public func detectAndStore(in db: AppDatabase, baseCurrency: String,
                               asOf: Date? = nil) throws -> [Subscription] {
        try db.writer.write { database in
            let all = try Transaction.fetchAll(database)
            let subs = detect(all, baseCurrency: baseCurrency, asOf: asOf)

            // Replace prior detection results.
            try Subscription.deleteAll(database)
            var saved: [Subscription] = []
            for var sub in subs {
                try sub.insert(database)
                saved.append(sub)
            }

            // Flag member transactions (authoritative).
            let subscribedMerchants = Set(subs.map { MerchantNormalizer.normalize($0.merchant) })
            for var txn in all {
                let isMember = txn.baseAmount > 0 && !txn.isInternalTransfer
                    && subscribedMerchants.contains(MerchantNormalizer.normalize(txn.merchantName))
                if txn.isSubscription != isMember {
                    txn.isSubscription = isMember
                    try txn.update(database)
                }
            }
            return saved
        }
    }
}
