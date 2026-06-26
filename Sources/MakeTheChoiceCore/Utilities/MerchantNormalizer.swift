import Foundation

/// Collapses raw merchant strings into a stable key for the merchant→category table.
///
/// Bank/Plaid merchant strings are noisy: "AMZN Mktp US*2X9G8", "SQ *BLUE BOTTLE",
/// "UBER   *EATS 8005928996". Normalization lowercases, strips processor prefixes,
/// reference/transaction noise, and punctuation so these map to one row.
public enum MerchantNormalizer {

    /// Common payment-processor / aggregator prefixes that prepend the real merchant.
    private static let processorPrefixes: [String] = [
        "sq", "tst", "sp", "paypal", "pp", "pos", "ppl", "wlt", "ach", "intl"
    ]

    /// Normalize a raw merchant name to its lookup key.
    public static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()

        // Split off anything after a '*' processor separator when a known prefix leads.
        // e.g. "sq *blue bottle" -> "blue bottle", "uber *eats" -> "uber eats".
        if let starIndex = s.firstIndex(of: "*") {
            let head = s[..<starIndex].trimmingCharacters(in: .whitespaces)
            let tail = s[s.index(after: starIndex)...].trimmingCharacters(in: .whitespaces)
            let headToken = head.split(separator: " ").first.map(String.init) ?? head
            if processorPrefixes.contains(headToken) {
                s = tail.isEmpty ? head : tail
            } else {
                s = s.replacingOccurrences(of: "*", with: " ")
            }
        }

        // Replace non-alphanumeric characters with spaces.
        let scalars = s.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        s = String(scalars)

        // Drop pure-number tokens and very short noise tokens that look like references,
        // but keep meaningful single letters only inside multi-token names.
        var tokens = s.split(separator: " ").map(String.init)

        // Strip a leading processor prefix token (e.g. "tst merchant name").
        if let first = tokens.first, processorPrefixes.contains(first), tokens.count > 1 {
            tokens.removeFirst()
        }

        tokens = tokens.filter { token in
            // Remove tokens that are entirely digits (store ids, ref numbers).
            if token.allSatisfy(\.isNumber) { return false }
            return true
        }

        // Remove trailing alphanumeric reference tokens like "us2x9g8" (mixed, len>=5
        // with both letters and digits) — typical Plaid suffixes.
        tokens = tokens.filter { token in
            let hasDigit = token.contains(where: \.isNumber)
            let hasAlpha = token.contains(where: \.isLetter)
            if hasDigit && hasAlpha && token.count >= 5 { return false }
            return true
        }

        return tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
