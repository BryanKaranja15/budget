import Foundation
import GRDB

/// The 12 fixed spending categories (see plan.md "Categories"). Slugs are stable
/// identifiers used as the primary key in the `categories` table and as foreign keys
/// elsewhere — never rename a raw value once shipped.
public enum AppCategory: String, CaseIterable, Codable, Sendable {
    case housing
    case food
    case transport
    case health
    case education
    case clothing
    case travel
    case subscriptions
    case business
    case enjoyment
    case savings
    case uncategorized

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .housing: return "Housing"
        case .food: return "Food"
        case .transport: return "Transport"
        case .health: return "Health"
        case .education: return "Education"
        case .clothing: return "Clothing"
        case .travel: return "Travel"
        case .subscriptions: return "Subscriptions"
        case .business: return "Business"
        case .enjoyment: return "Enjoyment"
        case .savings: return "Savings"
        case .uncategorized: return "Uncategorized"
        }
    }

    /// Display/sort order matching the plan's table ordering.
    public var sortOrder: Int {
        AppCategory.allCases.firstIndex(of: self) ?? 0
    }

    /// The fallback category used before/without a better assignment.
    public static var fallback: AppCategory { .uncategorized }
}

/// A persisted category row. The catalog of rows is fixed (the 12 `AppCategory`
/// values); the editable part is `monthlyBudgetLimit`.
public struct Category: Codable, Identifiable, Hashable, Sendable {
    /// Stable slug — matches an `AppCategory` raw value.
    public var id: String
    /// Display name.
    public var name: String
    /// Display/sort order.
    public var sortOrder: Int
    /// Optional monthly budget limit in the user's base currency. `nil` = no budget set.
    public var monthlyBudgetLimit: Double?

    public init(id: String, name: String, sortOrder: Int, monthlyBudgetLimit: Double? = nil) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.monthlyBudgetLimit = monthlyBudgetLimit
    }

    /// Convenience initializer from the fixed enum.
    public init(_ category: AppCategory, monthlyBudgetLimit: Double? = nil) {
        self.init(
            id: category.rawValue,
            name: category.displayName,
            sortOrder: category.sortOrder,
            monthlyBudgetLimit: monthlyBudgetLimit
        )
    }

    /// The matching `AppCategory`, if the id is a known slug.
    public var appCategory: AppCategory? { AppCategory(rawValue: id) }
}

extension Category: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "categories"

    public enum Columns {
        public static let id = Column("id")
        public static let name = Column("name")
        public static let sortOrder = Column("sort_order")
        public static let monthlyBudgetLimit = Column("monthly_budget_limit")
    }

    public init(row: Row) {
        id = row["id"]
        name = row["name"]
        sortOrder = row["sort_order"]
        monthlyBudgetLimit = row["monthly_budget_limit"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["name"] = name
        container["sort_order"] = sortOrder
        container["monthly_budget_limit"] = monthlyBudgetLimit
    }
}
