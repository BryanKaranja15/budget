import Foundation

/// Screen 1 — Dashboard (Home). Everything the donut chart + category table + month
/// selector need, already computed in base currency. Build via `AppPresenter.dashboard(for:)`.
public struct DashboardViewModel: Codable, Hashable, Sendable {
    /// The month being shown, "YYYY-MM".
    public var month: String
    /// Total spending for the month (excludes transfers + income).
    public var totalSpent: Money
    /// One slice/row per category that has spending or a budget, in display order.
    public var categories: [CategoryRow]
    /// Months that have data, newest first — drives the month selector.
    public var availableMonths: [String]

    public init(month: String, totalSpent: Money, categories: [CategoryRow], availableMonths: [String]) {
        self.month = month
        self.totalSpent = totalSpent
        self.categories = categories
        self.availableMonths = availableMonths
    }

    /// A single category line: donut slice + table row in one.
    public struct CategoryRow: Codable, Hashable, Identifiable, Sendable {
        /// Category slug (`categories.id`).
        public var id: String
        public var name: String
        public var spent: Money
        /// Budget limit in effect this month, if any.
        public var budget: Money?
        /// `budget - spent` when a budget is set (can be negative = overspent).
        public var remaining: Money?
        /// Share of the month's total spend (0...1) — donut slice size.
        public var fractionOfTotal: Double
        public var status: BudgetStatus

        public init(id: String, name: String, spent: Money, budget: Money?, remaining: Money?,
                    fractionOfTotal: Double, status: BudgetStatus) {
            self.id = id
            self.name = name
            self.spent = spent
            self.budget = budget
            self.remaining = remaining
            self.fractionOfTotal = fractionOfTotal
            self.status = status
        }
    }
}

public extension DashboardViewModel {
    /// Sample data for SwiftUI previews / Codex design — no database needed.
    static var preview: DashboardViewModel {
        DashboardViewModel(
            month: "2024-05",
            totalSpent: Money(442.92, "USD"),
            categories: [
                .init(id: "food", name: "Food", spent: Money(103.35, "USD"),
                      budget: Money(400, "USD"), remaining: Money(296.65, "USD"),
                      fractionOfTotal: 0.23, status: .ok),
                .init(id: "transport", name: "Transport", spent: Money(71.10, "USD"),
                      budget: Money(60, "USD"), remaining: Money(-11.10, "USD"),
                      fractionOfTotal: 0.16, status: .over),
                .init(id: "clothing", name: "Clothing", spent: Money(76.19, "USD"),
                      budget: nil, remaining: nil, fractionOfTotal: 0.17, status: .none),
                .init(id: "subscriptions", name: "Subscriptions", spent: Money(17.99, "USD"),
                      budget: Money(20, "USD"), remaining: Money(2.01, "USD"),
                      fractionOfTotal: 0.04, status: .warning)
            ],
            availableMonths: ["2024-05", "2024-04", "2024-03"]
        )
    }
}
