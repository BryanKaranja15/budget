import Foundation
import GRDB

/// Read/write access to the fixed category catalog and its monthly budget limits.
public struct CategoryRepository {
    private let writer: DatabaseWriter
    public init(_ db: AppDatabase) { self.writer = db.writer }
    public init(writer: DatabaseWriter) { self.writer = writer }

    /// All categories in display order.
    public func all() throws -> [Category] {
        try writer.read { db in
            try Category
                .order(Category.Columns.sortOrder)
                .fetchAll(db)
        }
    }

    /// Fetch one category by slug.
    public func find(_ id: String) throws -> Category? {
        try writer.read { db in try Category.fetchOne(db, key: id) }
    }

    /// Set (or clear) a category's current monthly budget limit. Also records the limit
    /// in `budgets` history for the given month when a value is provided.
    @discardableResult
    public func setBudget(_ categoryId: String, limit: Double?, month: MonthKey? = nil) throws -> Category? {
        try writer.write { db in
            guard var category = try Category.fetchOne(db, key: categoryId) else { return nil }
            category.monthlyBudgetLimit = limit
            try category.update(db)

            if let limit, let month {
                // Upsert budget history (unique on category_id + month).
                if var existing = try Budget
                    .filter(Budget.Columns.categoryId == categoryId)
                    .filter(Budget.Columns.month == month.description)
                    .fetchOne(db) {
                    existing.limit = limit
                    try existing.update(db)
                } else {
                    var b = Budget(categoryId: categoryId, month: month.description, limit: limit)
                    try b.insert(db)
                }
            }
            return category
        }
    }

    /// The budget limit in effect for a category in a given month: the recorded history
    /// row if present, else the category's current limit.
    public func budget(_ categoryId: String, for month: MonthKey) throws -> Double? {
        try writer.read { db in
            if let b = try Budget
                .filter(Budget.Columns.categoryId == categoryId)
                .filter(Budget.Columns.month == month.description)
                .fetchOne(db) {
                return b.limit
            }
            return try Category.fetchOne(db, key: categoryId)?.monthlyBudgetLimit
        }
    }
}
