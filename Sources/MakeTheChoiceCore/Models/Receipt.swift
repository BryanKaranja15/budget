import Foundation
import GRDB

/// A scanned receipt or online-order confirmation. The header holds capture metadata,
/// the OCR raw text, and the link to the matching Plaid transaction. Line items live in
/// `receipt_items`; the reconciled category splits live in `transaction_items`.
///
/// Receipts unlock item-level granularity that Plaid cannot provide: Plaid only ever
/// reports "Target — $87.34", but a receipt breaks that into bread (Food), wine
/// (Enjoyment), an oven tray (Housing), etc.
public struct Receipt: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// Merchant name as read from the receipt.
    public var merchantName: String
    /// Normalized merchant key (for matching).
    public var normalizedMerchant: String
    /// Purchase date read from the receipt (UTC calendar day).
    public var purchaseDate: Date
    /// Receipt grand total in `currency`.
    public var totalAmount: Double
    /// Currency code of `totalAmount`.
    public var currency: String
    /// How it was captured.
    public var source: ReceiptSource
    /// Raw OCR text (kept on device only; useful for re-parsing/debugging).
    public var rawText: String?
    /// When the scan happened.
    public var scannedAt: Date
    /// Linked transaction (`transactions.id`), nil until matched.
    public var transactionId: Int64?
    /// Match lifecycle.
    public var matchStatus: ReceiptMatchStatus
    /// Confidence of the transaction match (0...1).
    public var matchConfidence: Double?

    public init(
        id: Int64? = nil,
        merchantName: String,
        normalizedMerchant: String? = nil,
        purchaseDate: Date,
        totalAmount: Double,
        currency: String,
        source: ReceiptSource,
        rawText: String? = nil,
        scannedAt: Date = Date(),
        transactionId: Int64? = nil,
        matchStatus: ReceiptMatchStatus = .unmatched,
        matchConfidence: Double? = nil
    ) {
        self.id = id
        self.merchantName = merchantName
        self.normalizedMerchant = normalizedMerchant ?? MerchantNormalizer.normalize(merchantName)
        self.purchaseDate = purchaseDate
        self.totalAmount = totalAmount
        self.currency = currency
        self.source = source
        self.rawText = rawText
        self.scannedAt = scannedAt
        self.transactionId = transactionId
        self.matchStatus = matchStatus
        self.matchConfidence = matchConfidence
    }
}

extension Receipt: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "receipts"

    public enum Columns {
        public static let id = Column("id")
        public static let merchantName = Column("merchant_name")
        public static let normalizedMerchant = Column("normalized_merchant")
        public static let purchaseDate = Column("purchase_date")
        public static let totalAmount = Column("total_amount")
        public static let currency = Column("currency")
        public static let source = Column("source")
        public static let rawText = Column("raw_text")
        public static let scannedAt = Column("scanned_at")
        public static let transactionId = Column("transaction_id")
        public static let matchStatus = Column("match_status")
        public static let matchConfidence = Column("match_confidence")
    }

    public init(row: Row) {
        id = row["id"]
        merchantName = row["merchant_name"]
        normalizedMerchant = row["normalized_merchant"]
        purchaseDate = row["purchase_date"]
        totalAmount = row["total_amount"]
        currency = row["currency"]
        source = ReceiptSource(rawValue: row["source"]) ?? .manual
        rawText = row["raw_text"]
        scannedAt = row["scanned_at"]
        transactionId = row["transaction_id"]
        matchStatus = ReceiptMatchStatus(rawValue: row["match_status"]) ?? .unmatched
        matchConfidence = row["match_confidence"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["merchant_name"] = merchantName
        container["normalized_merchant"] = normalizedMerchant
        container["purchase_date"] = purchaseDate
        container["total_amount"] = totalAmount
        container["currency"] = currency
        container["source"] = source.rawValue
        container["raw_text"] = rawText
        container["scanned_at"] = scannedAt
        container["transaction_id"] = transactionId
        container["match_status"] = matchStatus.rawValue
        container["match_confidence"] = matchConfidence
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
