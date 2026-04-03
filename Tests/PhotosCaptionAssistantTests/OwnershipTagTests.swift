import XCTest
@testable import PhotosCaptionAssistant

final class OwnershipTagTests: XCTestCase {
    func testAppendTagsWritesLogicTagOnly() {
        let tag = OwnershipTag(
            logicVersion: LogicVersion(major: 1, minor: 2, patch: 3),
            engineTier: .qwen25vl7b
        )

        let baseKeywords = ["travel", "mountains"]
        let tagged = OwnershipTagCodec.appendTags(tag, to: baseKeywords)

        XCTAssertEqual(tagged, ["travel", "mountains", "__pdc_logic_1_2_3"])
        XCTAssertEqual(OwnershipTagCodec.removeOwnedTags(from: tagged), baseKeywords)
    }

    func testExtractLogicOnlyDefaultsToCurrentQwenEngine() {
        let onlyLogic = ["__pdc_logic_1_0_0", "beach"]
        let extracted = OwnershipTagCodec.extract(from: onlyLogic)

        XCTAssertEqual(extracted?.logicVersion, LogicVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(extracted?.engineTier, .qwen25vl7b)
    }

    func testExtractFailsWhenLogicTagMissing() {
        let onlyEngine = ["__pdc_engine_vision", "beach"]
        XCTAssertNil(OwnershipTagCodec.extract(from: onlyEngine))
    }

    func testExtractParsesLegacyEngineTag() {
        let keywords = ["__pdc_logic_1_0_0", "__pdc_engine_vision", "city"]
        XCTAssertEqual(
            OwnershipTagCodec.extract(from: keywords),
            OwnershipTag(logicVersion: LogicVersion(major: 1, minor: 0, patch: 0), engineTier: .vision)
        )
    }

    func testInvalidVersionTagIsIgnored() {
        let keywords = ["__pdc_logic_bad_value", "__pdc_engine_vision", "city"]
        XCTAssertNil(OwnershipTagCodec.extract(from: keywords))
    }

    func testInvalidEngineTagFailsExtraction() {
        let keywords = ["__pdc_logic_1_1_0", "__pdc_engine_not_real", "city"]
        XCTAssertNil(OwnershipTagCodec.extract(from: keywords))
    }

    func testQwen3EngineTagIsNowTreatedAsExternal() {
        let keywords = ["__pdc_logic_2_0_0", "__pdc_engine_qwen3vl8b", "city"]
        XCTAssertNil(OwnershipTagCodec.extract(from: keywords))
    }
}
