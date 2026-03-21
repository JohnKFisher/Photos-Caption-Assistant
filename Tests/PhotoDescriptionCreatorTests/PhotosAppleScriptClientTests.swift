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

    func testChunkedMetadataWritesRespectsCountAndArgumentBudgets() {
        let writes = [
            MetadataWritePayload(id: "a", caption: "cat", keywords: ["pet"]),
            MetadataWritePayload(id: "bb", caption: "dog", keywords: ["pet"]),
            MetadataWritePayload(id: "ccc", caption: "bird", keywords: ["animal"]),
            MetadataWritePayload(id: "dddd", caption: "fish", keywords: ["aquatic"])
        ]

        let chunks = PhotosAppleScriptClient.chunkedMetadataWrites(
            writes,
            maxItems: 2,
            maxArgumentBytes: 40
        )

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].map(\.id), ["a", "bb"])
        XCTAssertEqual(chunks[1].map(\.id), ["ccc", "dddd"])
    }

    func testChunkedMetadataWritesSplitsOversizedEntryIntoOwnChunk() {
        let oversizedCaption = String(repeating: "x", count: 60)
        let writes = [
            MetadataWritePayload(id: "one", caption: "ok", keywords: ["k1"]),
            MetadataWritePayload(id: "two", caption: oversizedCaption, keywords: ["k2"]),
            MetadataWritePayload(id: "three", caption: "ok", keywords: ["k3"])
        ]

        let chunks = PhotosAppleScriptClient.chunkedMetadataWrites(
            writes,
            maxItems: 10,
            maxArgumentBytes: 24
        )

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].map(\.id), ["one"])
        XCTAssertEqual(chunks[1].map(\.id), ["two"])
        XCTAssertEqual(chunks[2].map(\.id), ["three"])
    }

    func testExportAssetTimeoutUsesLongerLimitForVideos() {
        XCTAssertEqual(PhotosAppleScriptClient.exportAssetTimeout(for: .photo), 120)
        XCTAssertEqual(PhotosAppleScriptClient.exportAssetTimeout(for: .video), 300)
    }

    func testWaitForConditionReturnsTrueBeforeTimeout() async {
        let result = await PhotosAppleScriptClient.waitForCondition(
            timeoutSeconds: 0.05,
            pollIntervalSeconds: 0.005
        ) {
            true
        }

        XCTAssertTrue(result)
    }

    func testWaitForConditionReturnsFalseOnTimeout() async {
        let result = await PhotosAppleScriptClient.waitForCondition(
            timeoutSeconds: 0.02,
            pollIntervalSeconds: 0.005
        ) {
            false
        }

        XCTAssertFalse(result)
    }

    func testAwaitLaunchSucceedsWhenCompletionHasNoError() async throws {
        try await PhotosAppleScriptClient.awaitLaunch { completion in
            completion(nil)
        }
    }

    func testAwaitLaunchThrowsWhenCompletionReturnsError() async {
        enum LaunchError: Error {
            case failed
        }

        do {
            try await PhotosAppleScriptClient.awaitLaunch { completion in
                completion(LaunchError.failed)
            }
            XCTFail("Expected launch helper to throw")
        } catch LaunchError.failed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCountRejectsCaptionWorkflowDirectResolution() async {
        let client = PhotosAppleScriptClient()

        do {
            _ = try await client.count(scope: .captionWorkflow)
            XCTFail("Expected direct caption-workflow count to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Caption Workflow"))
        }
    }

    func testEnumerateRejectsCaptionWorkflowDirectResolution() async {
        let client = PhotosAppleScriptClient()

        do {
            _ = try await client.enumerate(scope: .captionWorkflow, dateRange: nil)
            XCTFail("Expected direct caption-workflow enumerate to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Caption Workflow"))
        }
    }
}
