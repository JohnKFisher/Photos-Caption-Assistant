import Photos
import XCTest
@testable import PhotoDescriptionCreator

final class PhotosAppleScriptClientTests: XCTestCase {
    func testPreviewDecisionWaitsForDegradedImage() {
        let info: [AnyHashable: Any] = [PHImageResultIsDegradedKey: NSNumber(value: true)]
        let decision = PhotosAppleScriptClient.previewRequestDecision(imagePresent: true, info: info)
        XCTAssertEqual(decision, .wait)
    }

    func testPreviewDecisionReturnsImageForNonDegradedImage() {
        let info: [AnyHashable: Any] = [PHImageResultIsDegradedKey: NSNumber(value: false)]
        let decision = PhotosAppleScriptClient.previewRequestDecision(imagePresent: true, info: info)
        XCTAssertEqual(decision, .returnImage)
    }

    func testPreviewDecisionFallsBackWhenImageIsInCloud() {
        let info: [AnyHashable: Any] = [PHImageResultIsInCloudKey: NSNumber(value: true)]
        let decision = PhotosAppleScriptClient.previewRequestDecision(imagePresent: false, info: info)
        XCTAssertEqual(decision, .returnNil)
    }

    func testPreviewDecisionFallsBackWhenCancelled() {
        let info: [AnyHashable: Any] = [PHImageCancelledKey: NSNumber(value: true)]
        let decision = PhotosAppleScriptClient.previewRequestDecision(imagePresent: false, info: info)
        XCTAssertEqual(decision, .returnNil)
    }

    func testPreviewDecisionFallsBackWhenImageManagerReturnsError() {
        let info: [AnyHashable: Any] = [PHImageErrorKey: NSError(domain: "test", code: 1)]
        let decision = PhotosAppleScriptClient.previewRequestDecision(imagePresent: false, info: info)
        XCTAssertEqual(decision, .returnNil)
    }

    func testChunkedMetadataIDsRespectsCountAndArgumentByteBudgets() {
        let ids = ["a", "bb", "ccc", "dddd"]
        let chunks = PhotosAppleScriptClient.chunkedMetadataIDs(
            ids,
            maxIDs: 2,
            maxArgumentBytes: 5
        )
        XCTAssertEqual(chunks, [["a", "bb"], ["ccc"], ["dddd"]])
    }

    func testChunkedMetadataIDsSplitsOversizedIDIntoOwnChunk() {
        let oversizedID = String(repeating: "x", count: 40)
        let chunks = PhotosAppleScriptClient.chunkedMetadataIDs(
            ["one", oversizedID, "two"],
            maxIDs: 10,
            maxArgumentBytes: 10
        )
        XCTAssertEqual(chunks, [["one"], [oversizedID], ["two"]])
    }
}
