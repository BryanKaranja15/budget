import Foundation

/// Screen 5 — Receipt Scan & Splits review. The parsed receipt, its per-item categories,
/// and (once matched) how the transaction was split. Build via
/// `AppPresenter.receiptSplit(receiptId:)`.
public struct ReceiptSplitViewModel: Codable, Hashable, Sendable {
    public var receiptId: Int64
    public var merchant: String
    public var purchaseDate: Date
    public var total: Money
    public var matchStatus: ReceiptMatchStatus
    /// 0...1 confidence in the transaction match, if matched.
    public var matchConfidence: Double?
    /// Per-item lines with their categories (review before saving).
    public var items: [ItemRow]
    /// The category-level splits applied to the matched transaction (empty until matched).
    public var splits: [SplitRow]

    public init(receiptId: Int64, merchant: String, purchaseDate: Date, total: Money,
                matchStatus: ReceiptMatchStatus, matchConfidence: Double?,
                items: [ItemRow], splits: [SplitRow]) {
        self.receiptId = receiptId
        self.merchant = merchant
        self.purchaseDate = purchaseDate
        self.total = total
        self.matchStatus = matchStatus
        self.matchConfidence = matchConfidence
        self.items = items
        self.splits = splits
    }

    public struct ItemRow: Codable, Hashable, Identifiable, Sendable {
        public var id: Int64
        public var name: String
        public var amount: Money
        public var categoryId: String
        public var categoryName: String
        public var categorySource: CategorySource
        public init(id: Int64, name: String, amount: Money, categoryId: String,
                    categoryName: String, categorySource: CategorySource) {
            self.id = id; self.name = name; self.amount = amount
            self.categoryId = categoryId; self.categoryName = categoryName
            self.categorySource = categorySource
        }
    }

    /// One category's share of the matched transaction (amounts scaled to the real charge).
    public struct SplitRow: Codable, Hashable, Identifiable, Sendable {
        public var id: String { categoryId }
        public var categoryId: String
        public var categoryName: String
        public var amount: Money
        public init(categoryId: String, categoryName: String, amount: Money) {
            self.categoryId = categoryId; self.categoryName = categoryName; self.amount = amount
        }
    }
}

public extension ReceiptSplitViewModel {
    static var preview: ReceiptSplitViewModel {
        ReceiptSplitViewModel(
            receiptId: 1, merchant: "Target",
            purchaseDate: Date(timeIntervalSince1970: 1_715_472_000),
            total: Money(87.34, "USD"), matchStatus: .matched, matchConfidence: 0.94,
            items: [
                .init(id: 1, name: "Whole Wheat Bread", amount: Money(4.99, "USD"),
                      categoryId: "food", categoryName: "Food", categorySource: .receipt),
                .init(id: 2, name: "Cabernet Wine", amount: Money(18.99, "USD"),
                      categoryId: "enjoyment", categoryName: "Enjoyment", categorySource: .receipt),
                .init(id: 3, name: "Nonstick Oven Tray", amount: Money(24.99, "USD"),
                      categoryId: "housing", categoryName: "Housing", categorySource: .receipt)
            ],
            splits: [
                .init(categoryId: "housing", categoryName: "Housing", amount: Money(24.99, "USD")),
                .init(categoryId: "enjoyment", categoryName: "Enjoyment", amount: Money(18.99, "USD")),
                .init(categoryId: "food", categoryName: "Food", amount: Money(43.36, "USD"))
            ])
    }
}
