import XCTest
@testable import MakeTheChoiceCore

final class MonthKeyTests: XCTestCase {

    func testDescriptionFormatting() {
        XCTAssertEqual(MonthKey(year: 2024, month: 5).description, "2024-05")
        XCTAssertEqual(MonthKey(year: 2024, month: 12).description, "2024-12")
    }

    func testParsingValid() {
        let key = MonthKey("2024-05")
        XCTAssertEqual(key, MonthKey(year: 2024, month: 5))
    }

    func testParsingInvalid() {
        XCTAssertNil(MonthKey("2024-13"))
        XCTAssertNil(MonthKey("2024"))
        XCTAssertNil(MonthKey("not-a-month"))
    }

    func testBoundsAreExclusiveUpper() {
        let may = MonthKey(year: 2024, month: 5)
        let start = may.startDate()
        let end = may.endDate()
        XCTAssertEqual(MonthKey(date: start), may)
        // end is the first instant of June.
        XCTAssertEqual(MonthKey(date: end), MonthKey(year: 2024, month: 6))
    }

    func testDecemberRollsToNextYear() {
        let dec = MonthKey(year: 2024, month: 12)
        XCTAssertEqual(MonthKey(date: dec.endDate()), MonthKey(year: 2025, month: 1))
    }

    func testComparable() {
        XCTAssertLessThan(MonthKey(year: 2024, month: 1), MonthKey(year: 2024, month: 2))
        XCTAssertLessThan(MonthKey(year: 2023, month: 12), MonthKey(year: 2024, month: 1))
    }

    func testDateFromUTC() {
        let date = FixtureLoader.date("2024-05-15")
        XCTAssertEqual(MonthKey(date: date), MonthKey(year: 2024, month: 5))
    }
}
