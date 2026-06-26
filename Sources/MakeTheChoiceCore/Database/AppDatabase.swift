import Foundation
import GRDB

/// Owns the GRDB connection and schema. Construct with `makeOnDisk(at:)` for the app
/// or `makeInMemory()` for tests/previews. Schema is versioned via `DatabaseMigrator`
/// (GRDB records applied migrations, giving us `schema_version` for free).
public final class AppDatabase {
    /// The underlying writer (queue). Exposed for repositories.
    public let writer: DatabaseWriter

    /// A reader for read-only access.
    public var reader: DatabaseReader { writer }

    public init(_ writer: DatabaseWriter, seed: Bool = true) throws {
        self.writer = writer
        try migrator.migrate(writer)
        if seed {
            try seedIfEmpty()
        }
    }

    // MARK: - Factories

    /// An on-disk database at the given file URL (creates parent dir if needed).
    public static func makeOnDisk(at url: URL, seed: Bool = true) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        return try AppDatabase(queue, seed: seed)
    }

    /// An ephemeral in-memory database — ideal for unit tests.
    public static func makeInMemory(seed: Bool = false) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        return try AppDatabase(queue, seed: seed)
    }

    // MARK: - Migrations

    /// The applied schema version (count of migrations applied). 0 if none.
    public func schemaVersion() throws -> Int {
        try reader.read { db in
            try migrator.appliedMigrations(db).count
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // Fail loudly in debug if a shipped migration is ever edited.
        migrator.eraseDatabaseOnSchemaChange = false
        #endif

        migrator.registerMigration("v1_initial_schema") { db in
            try Self.createV1Schema(db)
        }

        migrator.registerMigration("v2_receipts") { db in
            try Self.createV2Schema(db)
        }

        return migrator
    }

    /// Creates every table + index for the initial schema.
    static func createV1Schema(_ db: Database) throws {
        // categories — the 12 fixed categories + editable monthly budget.
        try db.create(table: "categories") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("sort_order", .integer).notNull()
            t.column("monthly_budget_limit", .double)
        }

        // plaid_items — one per linked institution (device keeps metadata only).
        try db.create(table: "plaid_items") { t in
            t.primaryKey("id", .text)
            t.column("institution", .text).notNull()
            t.column("status", .text).notNull()
            t.column("created_at", .datetime).notNull()
            t.column("last_synced_at", .datetime)
        }

        // accounts — bank accounts under an item.
        try db.create(table: "accounts") { t in
            t.primaryKey("id", .text)
            t.column("item_id", .text).notNull()
                .references("plaid_items", onDelete: .cascade)
            t.column("institution", .text).notNull()
            t.column("name", .text).notNull()
            t.column("mask", .text)
            t.column("type", .text)
            t.column("currency", .text).notNull()
            t.column("current_balance", .double)
            t.column("available_balance", .double)
        }

        // merchants — normalized merchant → category (Layer 2).
        try db.create(table: "merchants") { t in
            t.primaryKey("normalized_name", .text)
            t.column("category_id", .text).notNull()
                .references("categories", onDelete: .restrict)
            t.column("source", .text).notNull()
            t.column("locked", .boolean).notNull().defaults(to: false)
            t.column("updated_at", .datetime).notNull()
        }

        // transactions — the core table.
        try db.create(table: "transactions") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("plaid_transaction_id", .text).notNull().unique()
            t.column("account_id", .text).notNull()
                .references("accounts", onDelete: .cascade)
            t.column("date", .datetime).notNull()
            t.column("merchant_name", .text).notNull()
            t.column("pending", .boolean).notNull().defaults(to: false)
            t.column("pending_transaction_id", .text)
            t.column("iso_currency_code", .text).notNull()
            t.column("original_amount", .double).notNull()
            t.column("base_amount", .double).notNull()
            t.column("plaid_category", .text)
            t.column("category_id", .text).notNull()
                .references("categories", onDelete: .restrict)
            t.column("category_source", .text).notNull()
            t.column("confidence", .double)
            t.column("is_subscription", .boolean).notNull().defaults(to: false)
            t.column("is_internal_transfer", .boolean).notNull().defaults(to: false)
        }

        // budgets — optional per-month budget history.
        try db.create(table: "budgets") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("category_id", .text).notNull()
                .references("categories", onDelete: .cascade)
            t.column("month", .text).notNull()
            t.column("limit_amount", .double).notNull()
            t.uniqueKey(["category_id", "month"])
        }

        // subscriptions — detected recurring charges.
        try db.create(table: "subscriptions") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("merchant", .text).notNull()
            t.column("amount", .double).notNull()
            t.column("currency", .text).notNull()
            t.column("cadence_days", .integer).notNull()
            t.column("last_charged", .datetime).notNull()
            t.column("next_expected_date", .datetime).notNull()
            t.column("annual_cost", .double).notNull()
            t.column("status", .text).notNull()
            t.column("confidence", .double).notNull()
            t.column("price_creep", .boolean).notNull().defaults(to: false)
        }

        // fx_rates — historical conversion rates.
        try db.create(table: "fx_rates") { t in
            t.column("day", .text).notNull()
            t.column("base", .text).notNull()
            t.column("quote", .text).notNull()
            t.column("rate", .double).notNull()
            t.primaryKey(["day", "base", "quote"])
        }

        // user_corrections — audit of user re-categorizations.
        try db.create(table: "user_corrections") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("transaction_id", .integer).notNull()
                .references("transactions", onDelete: .cascade)
            t.column("normalized_merchant", .text).notNull()
            t.column("from_category_id", .text)
            t.column("to_category_id", .text).notNull()
            t.column("created_at", .datetime).notNull()
        }

        // training_samples — labeled examples for re-fine-tuning.
        try db.create(table: "training_samples") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("text", .text).notNull()
            t.column("label", .text).notNull()
            t.column("source", .text).notNull()
            t.column("created_at", .datetime).notNull()
        }

        // Indexes (from day one — 24 months of data makes scans slow).
        try db.create(index: "idx_transactions_date", on: "transactions", columns: ["date"])
        try db.create(index: "idx_transactions_category", on: "transactions", columns: ["category_id"])
        try db.create(index: "idx_transactions_account", on: "transactions", columns: ["account_id"])
        try db.create(index: "idx_merchants_normalized", on: "merchants", columns: ["normalized_name"])
        try db.create(index: "idx_subscriptions_merchant", on: "subscriptions", columns: ["merchant"])
    }

    /// v2: receipt scanning — item-level granularity (see plan.md "Receipt Scanning").
    static func createV2Schema(_ db: Database) throws {
        // receipts — header per scanned receipt / order, linked to a transaction.
        try db.create(table: "receipts") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("merchant_name", .text).notNull()
            t.column("normalized_merchant", .text).notNull()
            t.column("purchase_date", .datetime).notNull()
            t.column("total_amount", .double).notNull()
            t.column("currency", .text).notNull()
            t.column("source", .text).notNull()
            t.column("raw_text", .text)
            t.column("scanned_at", .datetime).notNull()
            t.column("transaction_id", .integer)
                .references("transactions", onDelete: .setNull)
            t.column("match_status", .text).notNull()
            t.column("match_confidence", .double)
        }

        // receipt_items — raw scanned line items.
        try db.create(table: "receipt_items") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("receipt_id", .integer).notNull()
                .references("receipts", onDelete: .cascade)
            t.column("line_no", .integer).notNull()
            t.column("name", .text).notNull()
            t.column("quantity", .double).notNull().defaults(to: 1)
            t.column("amount", .double).notNull()
            t.column("category_id", .text).notNull()
                .references("categories", onDelete: .restrict)
            t.column("category_source", .text).notNull()
            t.column("confidence", .double)
        }

        // transaction_items — reconciled category splits of a transaction.
        try db.create(table: "transaction_items") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("transaction_id", .integer).notNull()
                .references("transactions", onDelete: .cascade)
            t.column("receipt_item_id", .integer)
                .references("receipt_items", onDelete: .setNull)
            t.column("name", .text).notNull()
            t.column("amount", .double).notNull()
            t.column("base_amount", .double).notNull()
            t.column("category_id", .text).notNull()
                .references("categories", onDelete: .restrict)
            t.column("category_source", .text).notNull()
            t.column("confidence", .double)
        }

        try db.create(index: "idx_receipts_transaction", on: "receipts", columns: ["transaction_id"])
        try db.create(index: "idx_receipts_normalized", on: "receipts", columns: ["normalized_merchant"])
        try db.create(index: "idx_receipt_items_receipt", on: "receipt_items", columns: ["receipt_id"])
        try db.create(index: "idx_transaction_items_transaction", on: "transaction_items", columns: ["transaction_id"])
    }

    // MARK: - Seeding

    /// Seeds categories + merchants if the categories table is empty.
    public func seedIfEmpty() throws {
        try writer.write { db in
            let count = try Category.fetchCount(db)
            guard count == 0 else { return }
            try SeedData.installCategories(db)
            try SeedData.installMerchants(db)
        }
    }
}
