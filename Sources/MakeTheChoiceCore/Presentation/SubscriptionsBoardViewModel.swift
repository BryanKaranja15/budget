import Foundation

/// Screen 3 — Subscriptions Board. Detected recurring charges sorted by annual cost,
/// plus roll-up totals. Build via `AppPresenter.subscriptionsBoard()`.
public struct SubscriptionsBoardViewModel: Codable, Hashable, Sendable {
    public var rows: [Row]
    /// Sum of all active subscriptions' annual cost.
    public var totalAnnual: Money
    /// `totalAnnual / 12` — the headline "per month" figure.
    public var totalMonthly: Money

    public init(rows: [Row], totalAnnual: Money, totalMonthly: Money) {
        self.rows = rows
        self.totalAnnual = totalAnnual
        self.totalMonthly = totalMonthly
    }

    public struct Row: Codable, Hashable, Identifiable, Sendable {
        public var id: Int64
        public var merchant: String
        public var amount: Money
        public var cadenceDays: Int
        /// "Weekly" / "Every 2 weeks" / "Monthly" / "Yearly" / "Every N days".
        public var cadenceLabel: String
        public var nextExpectedDate: Date
        public var annualCost: Money
        public var status: SubscriptionStatus
        public var priceCreep: Bool

        public init(id: Int64, merchant: String, amount: Money, cadenceDays: Int,
                    cadenceLabel: String, nextExpectedDate: Date, annualCost: Money,
                    status: SubscriptionStatus, priceCreep: Bool) {
            self.id = id
            self.merchant = merchant
            self.amount = amount
            self.cadenceDays = cadenceDays
            self.cadenceLabel = cadenceLabel
            self.nextExpectedDate = nextExpectedDate
            self.annualCost = annualCost
            self.status = status
            self.priceCreep = priceCreep
        }
    }

    /// Human label for a cadence in days.
    public static func cadenceLabel(_ days: Int) -> String {
        switch days {
        case 7:   return "Weekly"
        case 14:  return "Every 2 weeks"
        case 30:  return "Monthly"
        case 365: return "Yearly"
        default:  return "Every \(days) days"
        }
    }
}

public extension SubscriptionsBoardViewModel {
    static var preview: SubscriptionsBoardViewModel {
        SubscriptionsBoardViewModel(
            rows: [
                .init(id: 1, merchant: "Netflix", amount: Money(17.99, "USD"), cadenceDays: 30,
                      cadenceLabel: "Monthly", nextExpectedDate: Date(timeIntervalSince1970: 1_718_323_200),
                      annualCost: Money(218.88, "USD"), status: .active, priceCreep: true),
                .init(id: 2, merchant: "iCloud+", amount: Money(2.99, "USD"), cadenceDays: 30,
                      cadenceLabel: "Monthly", nextExpectedDate: Date(timeIntervalSince1970: 1_718_323_200),
                      annualCost: Money(36.38, "USD"), status: .active, priceCreep: false)
            ],
            totalAnnual: Money(255.26, "USD"), totalMonthly: Money(21.27, "USD"))
    }
}
