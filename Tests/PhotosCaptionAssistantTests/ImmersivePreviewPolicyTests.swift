import XCTest
@testable import PhotosCaptionAssistant

final class ImmersivePreviewPolicyTests: XCTestCase {
    func testDisplaySecondsUsesRegularCadenceUpToCatchUpThreshold() {
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 0), 30)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 20), 30)
    }

    func testDisplaySecondsUsesCatchUpCadenceBeyondThreshold() {
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 21), 10)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 60), 10)
    }

    func testRetainedIndicesKeepsFirstAndLastDuringSampling() {
        let indices = ImmersivePreviewPolicy.retainedIndices(for: 61)

        XCTAssertEqual(indices.count, 30)
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, 60)
        XCTAssertEqual(indices, Array(Set(indices)).sorted())
    }
}
