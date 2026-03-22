import XCTest
@testable import PhotoDescriptionCreator

final class CaptionWorkflowQueueTests: XCTestCase {
    func testCaptionWorkflowConfigurationIsRunnableWithTwoConfiguredUniqueQueueItems() {
        let configuration = CaptionWorkflowConfiguration(queue: [
            CaptionWorkflowQueueEntry(albumID: "cw-0", albumName: "Priority Queue"),
            CaptionWorkflowQueueEntry(albumID: "cw-1", albumName: "Review Queue")
        ])

        XCTAssertTrue(configuration.isRunnable)
        XCTAssertEqual(configuration.missingQueuePositions, [])
        XCTAssertEqual(configuration.duplicateAlbumIDs, [])
    }

    func testCaptionWorkflowConfigurationRequiresMinimumQueueLength() {
        let configuration = CaptionWorkflowConfiguration(queue: [
            CaptionWorkflowQueueEntry(albumID: "cw-0", albumName: "Only Queue")
        ])

        XCTAssertFalse(configuration.isRunnable)
        XCTAssertEqual(configuration.missingQueuePositions, [])
    }

    func testCaptionWorkflowConfigurationTracksMissingAndDuplicateSelections() {
        let configuration = CaptionWorkflowConfiguration(queue: [
            CaptionWorkflowQueueEntry(albumID: "cw-0", albumName: "Priority Queue"),
            CaptionWorkflowQueueEntry(),
            CaptionWorkflowQueueEntry(albumID: "cw-0", albumName: "Priority Queue")
        ])

        XCTAssertFalse(configuration.isRunnable)
        XCTAssertEqual(configuration.missingQueuePositions, [1])
        XCTAssertEqual(configuration.duplicateAlbumIDs, ["cw-0"])
    }

    func testPersistedRunOptionsRoundTripPreservesCaptionWorkflowQueue() throws {
        let configuration = CaptionWorkflowConfiguration(queue: [
            CaptionWorkflowQueueEntry(albumID: "cw-0", albumName: "Priority Queue"),
            CaptionWorkflowQueueEntry(albumID: "cw-1", albumName: "Review Queue"),
            CaptionWorkflowQueueEntry()
        ])
        let options = RunOptions(
            source: .captionWorkflow,
            optionalCaptureDateRange: nil,
            overwriteAppOwnedSameOrNewer: false,
            captionWorkflowConfiguration: configuration
        )

        let persisted = PersistedRunOptions(runOptions: options)
        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(PersistedRunOptions.self, from: data)

        XCTAssertEqual(decoded.captionWorkflowConfiguration, configuration)
        XCTAssertEqual(decoded.toRunOptions().captionWorkflowConfiguration, configuration)
    }

    func testPersistedRunStateDecodesLegacyCaptionWorkflowConfigurationAsNil() throws {
        let legacyState = """
        {
          "savedAt": 0,
          "options": {
            "sourceKind": "captionWorkflow",
            "traversalOrder": "photosOrderFast",
            "overwriteAppOwnedSameOrNewer": false,
            "alwaysOverwriteExternalMetadata": false,
            "captionWorkflowConfiguration": {
              "assignments": [
                {
                  "stage": "0 - Priority Captioning",
                  "albumID": "cw-0",
                  "albumName": "0 - Priority Captioning"
                },
                {
                  "stage": "1 - No Caption - New Photos",
                  "albumID": "cw-1",
                  "albumName": "1 - No Caption - New Photos"
                }
              ]
            }
          },
          "pendingIDs": ["asset-1", "asset-2"]
        }
        """
        let data = try XCTUnwrap(legacyState.data(using: .utf8))

        let decoded = try JSONDecoder().decode(PersistedRunState.self, from: data)

        XCTAssertEqual(decoded.pendingIDs, ["asset-1", "asset-2"])
        XCTAssertNil(decoded.options.captionWorkflowConfiguration)
    }
}
