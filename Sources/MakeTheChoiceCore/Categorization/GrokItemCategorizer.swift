import Foundation

/// Categorizes receipt items via Grok, reached through HermesTrial. Builds the
/// de-identified request (merchant + items only), calls the client, and maps returned
/// slugs to `AppCategory` — coercing any unknown/invalid slug to `.uncategorized` so a
/// stray model output can never produce an invalid category.
///
/// Length mismatches are surfaced as-is (the response's count); `LayeredItemCategorizer`
/// detects a count != items.count and falls back to keyword.
public struct GrokItemCategorizer: ItemCategorizing {
    private let client: any RemoteCategorizationClient

    public init(client: any RemoteCategorizationClient) {
        self.client = client
    }

    public func categorize(items: [String], merchant: String?) async throws -> [AppCategory] {
        guard !items.isEmpty else { return [] }
        let request = ItemCategorizationRequest(merchant: merchant, items: items)
        let response = try await client.categorizeItems(request)
        return response.categories.map { slug in
            AppCategory(rawValue: slug) ?? .uncategorized
        }
    }
}
