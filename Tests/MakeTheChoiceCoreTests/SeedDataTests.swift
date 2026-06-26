import XCTest
@testable import MakeTheChoiceCore

final class SeedDataTests: XCTestCase {

    func testTwelveCategoriesSeeded() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let categories = try CategoryRepository(db).all()
        XCTAssertEqual(categories.count, 12)
        XCTAssertEqual(Set(categories.map(\.id)), Set(AppCategory.allCases.map(\.rawValue)))
    }

    func testCategoriesInSortOrder() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let categories = try CategoryRepository(db).all()
        XCTAssertEqual(categories.map(\.sortOrder), Array(0..<12))
        XCTAssertEqual(categories.first?.id, AppCategory.housing.rawValue)
        XCTAssertEqual(categories.last?.id, AppCategory.uncategorized.rawValue)
    }

    func testMerchantSeedHasAtLeast200() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let count = try MerchantRepository(db).count()
        XCTAssertGreaterThanOrEqual(count, 200, "expected ~200 seeded merchants, got \(count)")
    }

    func testKnownMerchantsResolve() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        let repo = MerchantRepository(db)
        let cases: [(String, AppCategory)] = [
            ("Netflix", .subscriptions),
            ("  netflix ", .subscriptions),
            ("Uber", .transport),
            ("Whole Foods", .food),
            ("Charles Schwab", .savings),
            ("Zara", .clothing),
            ("Delta", .travel)
        ]
        for (raw, expected) in cases {
            let merchant = try repo.lookup(rawMerchant: raw)
            XCTAssertEqual(merchant?.categoryId, expected.rawValue, "\(raw) → \(expected)")
        }
    }

    func testSeedIsIdempotent() throws {
        let db = try AppDatabase.makeInMemory(seed: true)
        // Re-running seedIfEmpty must not duplicate.
        try db.seedIfEmpty()
        XCTAssertEqual(try CategoryRepository(db).all().count, 12)
    }

    func testAllSeedMerchantsMapToValidCategory() throws {
        let validIds = Set(AppCategory.allCases.map(\.rawValue))
        for (_, category) in SeedData.merchantSeed {
            XCTAssertTrue(validIds.contains(category.rawValue))
        }
    }
}
