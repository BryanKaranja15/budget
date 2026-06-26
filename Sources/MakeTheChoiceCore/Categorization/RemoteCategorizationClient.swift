import Foundation

/// The **de-identified** payload sent off-device for item categorization. By
/// construction it can carry only the merchant name and item descriptions — there is
/// no field for amounts, account/card numbers, dates, or any user identifier. This is
/// the type-level guarantee behind "protect card info; nothing tied back to me".
public struct ItemCategorizationRequest: Codable, Equatable, Sendable {
    /// Merchant name for context (e.g. "Target"), or nil to withhold it.
    public let merchant: String?
    /// Receipt line-item descriptions to classify, in order.
    public let items: [String]

    public init(merchant: String?, items: [String]) {
        self.merchant = merchant
        self.items = items
    }
}

/// Response from the categorization service: one category slug per requested item.
public struct ItemCategorizationResponse: Codable, Equatable, Sendable {
    /// Category slugs (must match `AppCategory` raw values), index-aligned with the request.
    public let categories: [String]
    /// Optional per-item confidence (0...1), index-aligned.
    public let confidences: [Double]?

    public init(categories: [String], confidences: [Double]? = nil) {
        self.categories = categories
        self.confidences = confidences
    }
}

/// Abstracts the network call to HermesTrial's `POST /categorize/items`, which forwards
/// to Grok. The real HTTP implementation is wired in Phase 3 with the backend; tests use
/// `MockRemoteCategorizationClient`.
public protocol RemoteCategorizationClient: Sendable {
    func categorizeItems(_ request: ItemCategorizationRequest) async throws -> ItemCategorizationResponse
}

/// Test double. Either returns a fixed response, computes one from a closure, or throws.
/// Records the last request so tests can assert exactly what would leave the device.
public final class MockRemoteCategorizationClient: RemoteCategorizationClient, @unchecked Sendable {
    public enum Behavior: Sendable {
        case respond(ItemCategorizationResponse)
        case compute(@Sendable (ItemCategorizationRequest) -> ItemCategorizationResponse)
        case fail(any Error)
    }

    public private(set) var lastRequest: ItemCategorizationRequest?
    public private(set) var callCount = 0
    private let behavior: Behavior

    public init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    public func categorizeItems(_ request: ItemCategorizationRequest) async throws -> ItemCategorizationResponse {
        lastRequest = request
        callCount += 1
        switch behavior {
        case .respond(let response): return response
        case .compute(let make): return make(request)
        case .fail(let error): throw error
        }
    }
}

/// A generic error for categorization failures (e.g. offline).
public struct CategorizationError: Error, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
