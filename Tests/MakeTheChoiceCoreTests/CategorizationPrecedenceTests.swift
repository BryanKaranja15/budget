import XCTest
@testable import MakeTheChoiceCore

final class CategorizationPrecedenceTests: XCTestCase {

    func testPrecedenceOrdering() {
        XCTAssertLessThan(CategorySource.user.precedence, CategorySource.receipt.precedence)
        XCTAssertLessThan(CategorySource.receipt.precedence, CategorySource.merchant.precedence)
        XCTAssertLessThan(CategorySource.merchant.precedence, CategorySource.model.precedence)
        XCTAssertLessThan(CategorySource.model.precedence, CategorySource.plaid.precedence)
        XCTAssertLessThan(CategorySource.plaid.precedence, CategorySource.grok.precedence)
        XCTAssertLessThan(CategorySource.grok.precedence, CategorySource.unset.precedence)
    }

    func testHigherPriorityCanOverrideLower() {
        XCTAssertTrue(CategorySource.user.canOverride(.receipt))
        XCTAssertTrue(CategorySource.receipt.canOverride(.merchant))
        XCTAssertTrue(CategorySource.merchant.canOverride(.plaid))
        XCTAssertTrue(CategorySource.model.canOverride(.grok))
    }

    func testLowerPriorityCannotOverrideHigher() {
        XCTAssertFalse(CategorySource.plaid.canOverride(.user))
        XCTAssertFalse(CategorySource.merchant.canOverride(.receipt))
        XCTAssertFalse(CategorySource.grok.canOverride(.merchant))
        XCTAssertFalse(CategorySource.unset.canOverride(.plaid))
    }

    func testReceiptOverridesAutomaticButNotUser() {
        XCTAssertTrue(CategorySource.receipt.canOverride(.plaid))
        XCTAssertTrue(CategorySource.receipt.canOverride(.merchant))
        XCTAssertFalse(CategorySource.receipt.canOverride(.user))
    }

    func testSourceCanRefreshItself() {
        for source in CategorySource.allCases {
            XCTAssertTrue(source.canOverride(source), "\(source) should refresh itself")
        }
    }
}
