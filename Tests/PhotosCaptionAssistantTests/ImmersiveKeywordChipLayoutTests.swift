import XCTest
@testable import PhotosCaptionAssistant

final class ImmersiveKeywordChipLayoutTests: XCTestCase {
    func testEmptyKeywordsReturnNoRows() {
        let rows = ImmersiveKeywordChipLayout.rows(for: [], maxWidth: 240)

        XCTAssertTrue(rows.isEmpty)
    }

    func testNormalKeywordsFitWithoutOverflowChip() {
        let keywords = [
            "group",
            "soccer",
            "players",
            "coach",
            "field",
            "listening",
            "uniforms",
            "outdoor"
        ]

        let rows = ImmersiveKeywordChipLayout.rows(for: keywords, maxWidth: 320)

        XCTAssertLessThanOrEqual(rows.count, 2)
        XCTAssertFalse(rows.flatMap(\.chips).contains(where: \.isOverflow))
    }

    func testLongKeywordGetsTruncatedToFitChipWidth() {
        let keyword = "very-long-keyword-that-needs-to-be-truncated"

        let rows = ImmersiveKeywordChipLayout.rows(for: [keyword], maxWidth: 150)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].chips.count, 1)
        XCTAssertNotEqual(rows[0].chips[0].text, keyword)
        XCTAssertTrue(rows[0].chips[0].text.hasSuffix("..."))
    }

    func testOverflowCollapsesIntoMoreChipWithinTwoRows() {
        let keywords = [
            "group",
            "soccer",
            "players",
            "coach",
            "field",
            "listening",
            "uniforms",
            "outdoor",
            "training",
            "sideline",
            "practice",
            "youth"
        ]

        let rows = ImmersiveKeywordChipLayout.rows(for: keywords, maxWidth: 220)
        let chips = rows.flatMap(\.chips)

        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(chips.contains(where: { $0.isOverflow && $0.text.hasPrefix("+") && $0.text.hasSuffix(" more") }))
    }
}
