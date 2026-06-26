import Foundation

/// Screen 2 — Category Drilldown. The transactions behind one category in one month,
/// plus the totals. Build via `AppPresenter.categoryDetail(categoryId:month:)`.
public struct CategoryDetailViewModel: Codable, Hashable, Sendable {
    public var categoryId: String
    public var categoryName: String
    public var month: String
    public var total: Money
    public var transactions: [TransactionRow]

    public init(categoryId: String, categoryName: String, month: String, total: Money,
                transactions: [TransactionRow]) {
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.month = month
        self.total = total
        self.transactions = transactions
    }

    public struct TransactionRow: Codable, Hashable, Identifiable, Sendable {
        /// Local transaction id.
        public var id: Int64
        public var merchant: String
        public var date: Date
        /// Amount in base currency (what totals use).
        public var baseAmount: Money
        /// Original amount + currency, shown when it differs from base.
        public var originalAmount: Money
        /// True when the original currency differs from base (show both).
        public var isForeignCurrency: Bool
        /// True when this transaction has receipt-driven item splits.
        public var hasItemSplits: Bool
        /// Where the current category came from (drives the "Wrong category?" affordance).
        public var categorySource: CategorySource

        public init(id: Int64, merchant: String, date: Date, baseAmount: Money,
                    originalAmount: Money, isForeignCurrency: Bool, hasItemSplits: Bool,
                    categorySource: CategorySource) {
            self.id = id
            self.merchant = merchant
            self.date = date
            self.baseAmount = baseAmount
            self.originalAmount = originalAmount
            self.isForeignCurrency = isForeignCurrency
            self.hasItemSplits = hasItemSplits
            self.categorySource = categorySource
        }
    }
}

public extension CategoryDetailViewModel {
    static var preview: CategoryDetailViewModel {
        CategoryDetailViewModel(
            categoryId: "food", categoryName: "Food", month: "2024-05",
            total: Money(103.35, "USD"),
            transactions: [
                .init(id: 1, merchant: "Whole Foods", date: Date(timeIntervalSince1970: 1_714_608_000),
                      baseAmount: Money(84.20, "USD"), originalAmount: Money(84.20, "USD"),
                      isForeignCurrency: false, hasItemSplits: false, categorySource: .merchant),
                .init(id: 2, merchant: "Chipotle", date: Date(timeIntervalSince1970: 1_716_019_200),
                      baseAmount: Money(12.40, "USD"), originalAmount: Money(12.40, "USD"),
                      isForeignCurrency: false, hasItemSplits: false, categorySource: .merchant)
            ]
        )
    }
}
