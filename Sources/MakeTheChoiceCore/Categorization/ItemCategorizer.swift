import Foundation

/// Maps a receipt line-item description to a category using keyword rules. This is the
/// deterministic fallback used before the on-device product classifier ships (Phase 4):
/// it lets a Target run split into bread (Food), wine (Enjoyment), an oven tray
/// (Housing) instead of one lumped "$87.34".
public struct ItemCategorizer {

    /// Ordered keyword → category rules. First match wins, so put specific terms first.
    public static let rules: [(keywords: [String], category: AppCategory)] = [
        (["pharmacy", "ibuprofen", "vitamin", "advil", "tylenol", "bandage", "toothpaste",
          "shampoo", "soap", "deodorant", "prescription", "medicine", "supplement"], .health),
        (["tray", "pan", "pot", "plate", "bowl", "cutlery", "towel", "detergent",
          "cleaner", "sponge", "bulb", "battery", "candle", "cushion", "lamp",
          "furniture", "bedding", "trash bag", "paper towel", "kitchen"], .housing),
        (["shirt", "jeans", "shoes", "socks", "jacket", "dress", "sweater", "hat",
          "scarf", "underwear", "trousers", "sneakers", "coat"], .clothing),
        (["book", "notebook", "pen", "pencil", "course", "textbook", "stationery"], .education),
        (["wine", "beer", "whiskey", "vodka", "alcohol", "spirits", "champagne",
          "candy", "chocolate", "snack", "soda", "ice cream"], .enjoyment),
        (["bread", "milk", "eggs", "cheese", "butter", "coffee", "tea", "rice",
          "pasta", "chicken", "beef", "fish", "vegetable", "fruit", "yogurt",
          "cereal", "produce", "grocery", "water", "juice", "flour", "sugar"], .food),
        (["cable", "charger", "headphone", "mouse", "keyboard", "adapter", "usb",
          "hdmi", "monitor", "ssd", "drive", "ink", "toner"], .business)
    ]

    /// Categorize one item name. Returns `.uncategorized` when nothing matches.
    public static func categorize(_ name: String) -> AppCategory {
        let lower = name.lowercased()
        for rule in rules {
            if rule.keywords.contains(where: { lower.contains($0) }) {
                return rule.category
            }
        }
        return .uncategorized
    }

    /// Categorize a batch, returning items with `categoryId`/`categorySource` filled in.
    public static func categorize(items: [ReceiptItem]) -> [ReceiptItem] {
        items.map { item in
            var updated = item
            // Never override a user-corrected line.
            guard item.categorySource != .user else { return updated }
            updated.categoryId = categorize(item.name).rawValue
            updated.categorySource = .receipt
            return updated
        }
    }
}
