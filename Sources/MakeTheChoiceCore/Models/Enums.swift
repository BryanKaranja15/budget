import Foundation
import GRDB

/// Where a transaction's category assignment came from. Higher in this list = higher
/// precedence in the categorization engine (see plan.md "Categorization Engine").
///
/// Precedence: user > receipt > merchant > model > plaid > grok > unset.
public enum CategorySource: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    /// User explicitly corrected/locked this transaction's category. Wins over everything.
    case user
    /// Item-level truth from a scanned receipt / order (Layer 0). Beats automatic
    /// sources because it reflects what was actually bought, but a user can still
    /// correct an individual line.
    case receipt
    /// Resolved via the local merchant→category table (Layer 2).
    case merchant
    /// Assigned by the on-device classifier when confidence ≥ threshold.
    case model
    /// Fell back to Plaid's built-in category.
    case plaid
    /// Cold-start fallback via Grok (merchant name only).
    case grok
    /// Not yet categorized.
    case unset

    /// Precedence rank — lower means higher priority. Used to decide whether a new
    /// assignment is allowed to overwrite an existing one.
    public var precedence: Int {
        switch self {
        case .user: return 0
        case .receipt: return 1
        case .merchant: return 2
        case .model: return 3
        case .plaid: return 4
        case .grok: return 5
        case .unset: return 6
        }
    }

    /// True if an assignment from `self` may overwrite an existing assignment from `other`.
    /// A source can always refresh its own assignment; otherwise it must be strictly
    /// higher priority (lower rank).
    public func canOverride(_ other: CategorySource) -> Bool {
        self == other || self.precedence < other.precedence
    }
}

/// Source of a merchant→category mapping row.
public enum MerchantSource: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    /// Shipped with the app (the ~200 seeded merchants).
    case seed
    /// Created/updated by a user correction.
    case user
    /// Learned from the on-device classifier.
    case model
}

/// Lifecycle status of a detected subscription.
public enum SubscriptionStatus: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    /// Charging on schedule.
    case active
    /// No charge seen within the expected window + tolerance.
    case lapsed
    /// User dismissed it as not a subscription.
    case dismissed
}

/// How a receipt was captured.
public enum ReceiptSource: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    /// Photographed with the camera (paper receipt).
    case camera
    /// Imported via the share sheet (e.g. an Amazon order screenshot / PDF).
    case shareSheet = "share_sheet"
    /// Entered/split manually with no scan.
    case manual
}

/// Whether a receipt has been linked to a Plaid transaction.
public enum ReceiptMatchStatus: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    /// Not yet linked to a transaction.
    case unmatched
    /// Confidently linked to exactly one transaction.
    case matched
    /// Multiple plausible transactions — needs user disambiguation.
    case ambiguous
}

/// Status of a Plaid Item (one per linked institution).
public enum PlaidItemStatus: String, Codable, CaseIterable, DatabaseValueConvertible, Sendable {
    /// Healthy and syncing.
    case active
    /// Needs Link update mode (e.g. ITEM_LOGIN_REQUIRED, Revolut 90-day consent).
    case loginRequired = "login_required"
    /// User removed the item.
    case removed
}
