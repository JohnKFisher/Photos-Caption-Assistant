import XCTest
@testable import PhotoDescriptionCreator

final class VideoFrameSamplerTests: XCTestCase {
    func testEvenlySpacedProgressesUseInteriorCoverage() {
        let midpointProgresses = VideoFrameSampler.evenlySpacedProgresses(count: 1)
        XCTAssertEqual(midpointProgresses.count, 1)
        XCTAssertEqual(midpointProgresses[0], 0.5, accuracy: 0.0001)

        let progresses = VideoFrameSampler.evenlySpacedProgresses(count: 9)
        XCTAssertEqual(progresses.count, 9)
        for (actual, expected) in zip(progresses, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }
}
