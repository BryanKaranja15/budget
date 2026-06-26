import Foundation
import GRDB

/// Read/write access to Plaid items and their accounts.
public struct ItemAccountRepository {
    private let writer: DatabaseWriter
    public init(_ db: AppDatabase) { self.writer = db.writer }
    public init(writer: DatabaseWriter) { self.writer = writer }

    // MARK: - Items

    public func allItems() throws -> [PlaidItem] {
        try writer.read { db in try PlaidItem.order(PlaidItem.Columns.createdAt).fetchAll(db) }
    }

    @discardableResult
    public func save(_ item: PlaidItem) throws -> PlaidItem {
        try writer.write { db in try item.save(db) }
        return item
    }

    public func setStatus(itemId: String, status: PlaidItemStatus) throws {
        try writer.write { db in
            guard var item = try PlaidItem.fetchOne(db, key: itemId) else { return }
            item.status = status
            try item.update(db)
        }
    }

    /// Items that require user re-consent (Link update mode).
    public func itemsNeedingReauth() throws -> [PlaidItem] {
        try writer.read { db in
            try PlaidItem
                .filter(PlaidItem.Columns.status == PlaidItemStatus.loginRequired.rawValue)
                .fetchAll(db)
        }
    }

    // MARK: - Accounts

    public func allAccounts() throws -> [Account] {
        try writer.read { db in try Account.fetchAll(db) }
    }

    public func accounts(forItem itemId: String) throws -> [Account] {
        try writer.read { db in
            try Account.filter(Account.Columns.itemId == itemId).fetchAll(db)
        }
    }

    @discardableResult
    public func save(_ account: Account) throws -> Account {
        try writer.write { db in try account.save(db) }
        return account
    }

    @discardableResult
    public func save(_ accounts: [Account]) throws -> [Account] {
        try writer.write { db in try accounts.forEach { try $0.save(db) } }
        return accounts
    }
}
