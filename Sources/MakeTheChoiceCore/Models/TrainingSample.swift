import Foundation
import GRDB

/// A labeled example collected for periodic re-fine-tuning of the on-device classifier
/// (and chat model feedback). Never auto-uploaded — exported only with user consent.
public struct TrainingSample: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64?
    /// Model input text (e.g. merchant name [+ Plaid category, amount sign]).
    public var text: String
    /// Ground-truth label — a category slug for classifier samples.
    public var label: String
    /// Origin of the sample (e.g. "correction", "chat_feedback", "seed").
    public var source: String
    /// When collected.
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        text: String,
        label: String,
        source: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.label = label
        self.source = source
        self.createdAt = createdAt
    }
}

extension TrainingSample: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "training_samples"

    public enum Columns {
        public static let id = Column("id")
        public static let text = Column("text")
        public static let label = Column("label")
        public static let source = Column("source")
        public static let createdAt = Column("created_at")
    }

    public init(row: Row) {
        id = row["id"]
        text = row["text"]
        label = row["label"]
        source = row["source"]
        createdAt = row["created_at"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["text"] = text
        container["label"] = label
        container["source"] = source
        container["created_at"] = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
