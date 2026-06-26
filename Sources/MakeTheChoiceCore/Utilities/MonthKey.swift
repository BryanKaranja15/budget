import Foundation

/// A calendar month identifier in "YYYY-MM" form, used for month-scoped budget queries.
/// Budgets "reset on the 1st" by being computed per `MonthKey` — there is no reset job
/// (see plan.md "Currency/Budget").
public struct MonthKey: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let year: Int
    public let month: Int  // 1...12

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "month must be 1...12")
        self.year = year
        self.month = month
    }

    /// Parse a "YYYY-MM" string. Returns nil if malformed.
    public init?(_ string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              (1...12).contains(m) else { return nil }
        self.year = y
        self.month = m
    }

    /// The month containing `date` in the given calendar (UTC by default).
    public init(date: Date, calendar: Calendar = .utc) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        self.year = comps.year ?? 1970
        self.month = comps.month ?? 1
    }

    /// "YYYY-MM".
    public var description: String { String(format: "%04d-%02d", year, month) }

    /// First instant of the month (UTC).
    public func startDate(calendar: Calendar = .utc) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// First instant of the following month (UTC) — exclusive upper bound for queries.
    public func endDate(calendar: Calendar = .utc) -> Date {
        let start = startDate(calendar: calendar)
        return calendar.date(byAdding: .month, value: 1, to: start)!
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

public extension Calendar {
    /// A Gregorian calendar fixed to UTC — transactions are stored on a UTC calendar day
    /// so month boundaries are deterministic regardless of device timezone.
    static var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}
