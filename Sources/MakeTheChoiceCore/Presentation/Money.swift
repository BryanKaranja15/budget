import Foundation

/// A currency amount + its ISO code, with a localized display string. Presentation-layer
/// value type so SwiftUI views never format raw `Double`s themselves.
public struct Money: Codable, Hashable, Sendable {
    public var amount: Double
    public var currencyCode: String

    public init(_ amount: Double, _ currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    /// Localized currency string, e.g. "$17.99" / "£59.99".
    public var formatted: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.string(from: NSNumber(value: amount)) ?? "\(amount) \(currencyCode)"
    }
}

/// Budget health for a category in a month. The UI maps these to green/amber/red.
public enum BudgetStatus: String, Codable, Sendable {
    /// No budget set for this category.
    case none
    /// Comfortably under budget (< warning threshold).
    case ok
    /// Approaching the limit (≥ warning threshold, ≤ 100%).
    case warning
    /// Over the limit (> 100%).
    case over

    /// Classify `spent` against `limit`. `warningRatio` defaults to 0.8 (80%).
    public static func classify(spent: Double, limit: Double?, warningRatio: Double = 0.8) -> BudgetStatus {
        guard let limit, limit > 0 else { return .none }
        let ratio = spent / limit
        if ratio > 1 { return .over }
        if ratio >= warningRatio { return .warning }
        return .ok
    }
}
