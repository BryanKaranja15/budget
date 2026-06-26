import XCTest
@testable import MakeTheChoiceCore

final class MerchantNormalizerTests: XCTestCase {

    func testLowercasesAndTrims() {
        XCTAssertEqual(MerchantNormalizer.normalize("  Netflix  "), "netflix")
        XCTAssertEqual(MerchantNormalizer.normalize("STARBUCKS"), "starbucks")
    }

    func testStripsProcessorStarPrefix() {
        XCTAssertEqual(MerchantNormalizer.normalize("SQ *BLUE BOTTLE"), "blue bottle")
        XCTAssertEqual(MerchantNormalizer.normalize("PAYPAL *SPOTIFY"), "spotify")
    }

    func testKeepsRealMerchantWithStarButUnknownPrefix() {
        // Unknown prefix before '*' is not stripped, just de-punctuated.
        XCTAssertEqual(MerchantNormalizer.normalize("UBER *EATS"), "uber eats")
    }

    func testStripsTrailingReferenceTokens() {
        XCTAssertEqual(MerchantNormalizer.normalize("AMZN Mktp US*2X9G8"), "amzn mktp us")
        XCTAssertEqual(MerchantNormalizer.normalize("Costco Gas #1043"), "costco gas")
    }

    func testStripsPureNumberTokens() {
        XCTAssertEqual(MerchantNormalizer.normalize("UBER 8005928996"), "uber")
    }

    func testStripsLeadingProcessorTokenWithoutStar() {
        XCTAssertEqual(MerchantNormalizer.normalize("TST MERCHANT CAFE"), "merchant cafe")
    }

    func testDeterministic() {
        let a = MerchantNormalizer.normalize("SQ *Blue Bottle Coffee #22")
        let b = MerchantNormalizer.normalize("SQ *BLUE BOTTLE COFFEE #22")
        XCTAssertEqual(a, b)
    }
}
