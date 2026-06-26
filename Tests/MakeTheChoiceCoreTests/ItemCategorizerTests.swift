import XCTest
@testable import MakeTheChoiceCore

final class ItemCategorizerTests: XCTestCase {

    func testCategorizesCommonItems() {
        XCTAssertEqual(ItemCategorizer.categorize("Whole Wheat Bread"), .food)
        XCTAssertEqual(ItemCategorizer.categorize("Organic Milk"), .food)
        XCTAssertEqual(ItemCategorizer.categorize("Cabernet Wine"), .enjoyment)
        XCTAssertEqual(ItemCategorizer.categorize("Nonstick Oven Tray"), .housing)
        XCTAssertEqual(ItemCategorizer.categorize("USB-C Charger Cable"), .business)
        XCTAssertEqual(ItemCategorizer.categorize("Ibuprofen 200mg"), .health)
        XCTAssertEqual(ItemCategorizer.categorize("Cotton T-Shirt"), .clothing)
    }

    func testUnknownItemIsUncategorized() {
        XCTAssertEqual(ItemCategorizer.categorize("Mystery Widget 9000"), .uncategorized)
    }

    func testBatchFillsCategoryAndSource() {
        let items = [
            ReceiptItem(receiptId: 1, lineNo: 0, name: "Bread", amount: 3, categorySource: .unset),
            ReceiptItem(receiptId: 1, lineNo: 1, name: "Wine", amount: 12, categorySource: .unset)
        ]
        let result = ItemCategorizer.categorize(items: items)
        XCTAssertEqual(result[0].categoryId, AppCategory.food.rawValue)
        XCTAssertEqual(result[0].categorySource, .receipt)
        XCTAssertEqual(result[1].categoryId, AppCategory.enjoyment.rawValue)
    }

    func testBatchNeverOverridesUserLine() {
        let userLine = ReceiptItem(receiptId: 1, lineNo: 0, name: "Bread",
                                   amount: 3, categoryId: AppCategory.business.rawValue,
                                   categorySource: .user)
        let result = ItemCategorizer.categorize(items: [userLine])
        XCTAssertEqual(result[0].categoryId, AppCategory.business.rawValue)
        XCTAssertEqual(result[0].categorySource, .user)
    }
}
