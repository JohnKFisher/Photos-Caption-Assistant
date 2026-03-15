import XCTest
@testable import PhotoDescriptionCreator

final class QwenVisionLanguageAnalyzerTests: XCTestCase {
    func testPhotoPromptUsesV3Template() {
        let prompt = QwenVisionLanguageAnalyzer.photoPromptV3

        XCTAssertTrue(prompt.hasPrefix("You are generating Apple Photos metadata for one photo."))
        XCTAssertTrue(prompt.contains("Use a present participle phrase with no auxiliary verbs"))
        XCTAssertTrue(prompt.contains("Before output, verify:"))
        XCTAssertFalse(prompt.contains("Return ONLY strict JSON"))
    }

    func testVideoPromptUsesV3Template() {
        let prompt = QwenVisionLanguageAnalyzer.videoPromptV3

        XCTAssertTrue(prompt.hasPrefix("You are generating Apple Photos metadata for one video."))
        XCTAssertTrue(prompt.contains("The provided images are key frames from the same video in time order."))
        XCTAssertTrue(prompt.contains("Describe motion/action, not just a single frame snapshot."))
        XCTAssertFalse(prompt.contains("Return ONLY strict JSON"))
    }
}
