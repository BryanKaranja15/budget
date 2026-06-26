import Foundation

/// Categorizes receipt line-item descriptions into the 12 app categories.
/// Returns one category per input string, index-aligned with `items`.
public protocol ItemCategorizing: Sendable {
    func categorize(items: [String], merchant: String?) async throws -> [AppCategory]
}

/// Offline, deterministic categorizer backed by `ItemCategorizer`'s keyword rules.
/// Always available, no network — the fallback when Grok is unreachable.
public struct KeywordItemCategorizer: ItemCategorizing {
    public init() {}

    public func categorize(items: [String], merchant: String?) async throws -> [AppCategory] {
        items.map { ItemCategorizer.categorize($0) }
    }
}

/// Orchestrates item categorization with precedence `Grok > keyword > uncategorized`
/// (the on-device product classifier slots in above Grok in Phase 4). When a remote
/// (Grok) categorizer is configured it runs first; the keyword categorizer backfills
/// any item the remote left `.uncategorized`, and fully replaces the result if the
/// remote throws or returns a mismatched count (e.g. offline). User-locked lines are
/// handled upstream at the `ReceiptItem` level, so this string-based entry point never
/// overwrites a user choice.
public struct LayeredItemCategorizer: ItemCategorizing {
    private let remote: ItemCategorizing?
    private let keyword: ItemCategorizing

    public init(remote: ItemCategorizing?, keyword: ItemCategorizing = KeywordItemCategorizer()) {
        self.remote = remote
        self.keyword = keyword
    }

    public func categorize(items: [String], merchant: String?) async throws -> [AppCategory] {
        guard !items.isEmpty else { return [] }

        // Keyword baseline is always computed — it's the fallback and the per-item backfill.
        let keywordResults = try await keyword.categorize(items: items, merchant: merchant)

        guard let remote else { return keywordResults }

        let remoteResults: [AppCategory]
        do {
            remoteResults = try await remote.categorize(items: items, merchant: merchant)
        } catch {
            // Offline / Grok failure → degrade gracefully to keyword.
            return keywordResults
        }

        // Defensive: a length mismatch means we can't trust the alignment → keyword.
        guard remoteResults.count == items.count else { return keywordResults }

        // Remote wins when confident; keyword backfills anything it punted on.
        return zip(remoteResults, keywordResults).map { remote, fallback in
            remote == .uncategorized ? fallback : remote
        }
    }
}
