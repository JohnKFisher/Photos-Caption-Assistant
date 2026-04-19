import XCTest
@testable import PhotosCaptionAssistant

final class RunPreflightTests: XCTestCase {
    func testRunSetupDefaultsMatchProjectDefaults() {
        XCTAssertEqual(RunSetupDefaults.sourceSelection, .album)
        XCTAssertTrue(RunSetupDefaults.alwaysOverwriteExternalMetadata)
    }

    func testWholeLibraryPreflightRequiresConfirmationForLibraryScopeAndMissingModel() {
        let snapshot = RunSetupSnapshot(
            sourceSelection: .library,
            selectedAlbum: nil,
            pickerIDs: [],
            captionWorkflowConfiguration: CaptionWorkflowConfiguration(queue: []),
            useDateFilter: false,
            dateRange: nil,
            overwriteAppOwnedSameOrNewer: false,
            alwaysOverwriteExternalMetadata: false
        )
        let capabilities = AppCapabilities(
            photosAutomationAvailable: true,
            qwenModelAvailable: false,
            ollamaServiceReachable: true,
            pickerCapability: .supported
        )

        let summary = RunPreflightSummaryBuilder.build(
            snapshot: snapshot,
            capabilities: capabilities,
            countState: .exact(120)
        )

        XCTAssertEqual(summary.sourceTitle, "Whole Library")
        XCTAssertEqual(summary.countDescription, "Exact current scope count before overwrite checks: 120 items.")
        XCTAssertTrue(summary.confirmationReasons.contains("This run will target the whole library, subject to the current filter and overwrite settings."))
        XCTAssertTrue(summary.modelDescription.contains("not installed locally"))
        XCTAssertEqual(summary.confirmationLabel, "Start Run")
    }

    func testQueuedAlbumsPreflightExplainsDeferredCountAndConfiguredAlbums() {
        let configuration = CaptionWorkflowConfiguration(queue: [
            CaptionWorkflowQueueEntry(albumID: "cw-0", albumName: "Priority Queue"),
            CaptionWorkflowQueueEntry(albumID: "cw-1", albumName: "Review Queue")
        ])
        let snapshot = RunSetupSnapshot(
            sourceSelection: .captionWorkflow,
            selectedAlbum: nil,
            pickerIDs: [],
            captionWorkflowConfiguration: configuration,
            useDateFilter: false,
            dateRange: nil,
            overwriteAppOwnedSameOrNewer: false,
            alwaysOverwriteExternalMetadata: false
        )

        let summary = RunPreflightSummaryBuilder.build(
            snapshot: snapshot,
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                ollamaServiceReachable: true,
                pickerCapability: .supported
            ),
            countState: .message("unused")
        )

        XCTAssertEqual(summary.sourceTitle, AppPresentation.queuedAlbumsTitle)
        XCTAssertEqual(summary.countDescription, "Counts are resolved stage-by-stage during the run for \(AppPresentation.queuedAlbumsTitle), so the exact write scope is not precomputed up front.")
        XCTAssertTrue(summary.sourceDetails.contains("Queue length: 2"))
        XCTAssertTrue(summary.sourceDetails.contains("Scope: only the configured albums below, processed in queue order."))
        XCTAssertTrue(summary.sourceDetails.contains("Queue item 1: Priority Queue"))
        XCTAssertTrue(summary.sourceDetails.contains("Queue item 2: Review Queue"))
        XCTAssertTrue(summary.confirmationReasons.isEmpty)
    }

    func testExternalOverwriteWithoutPromptsRequiresConfirmation() {
        let snapshot = RunSetupSnapshot(
            sourceSelection: .album,
            selectedAlbum: AlbumSummary(id: "album-1", name: "Trips", itemCount: 42),
            pickerIDs: [],
            captionWorkflowConfiguration: CaptionWorkflowConfiguration(queue: []),
            useDateFilter: true,
            dateRange: CaptureDateRange(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 86_400)
            ),
            overwriteAppOwnedSameOrNewer: false,
            alwaysOverwriteExternalMetadata: true
        )

        let summary = RunPreflightSummaryBuilder.build(
            snapshot: snapshot,
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                ollamaServiceReachable: true,
                pickerCapability: .supported
            ),
            countState: .exact(42)
        )

        XCTAssertTrue(summary.overwriteDescriptions.contains("Metadata not tagged as app-owned will be overwritten without per-item prompts."))
        XCTAssertTrue(summary.confirmationReasons.contains("This run will overwrite metadata not tagged as app-owned without per-item confirmation."))
        XCTAssertEqual(summary.confirmationLabel, "Start Run")
        XCTAssertNotNil(summary.filterDescription)
    }

    func testPreflightBlocksWhenOllamaIsNotInstalledYet() {
        let snapshot = RunSetupSnapshot(
            sourceSelection: .album,
            selectedAlbum: AlbumSummary(id: "album-1", name: "Trips", itemCount: 42),
            pickerIDs: [],
            captionWorkflowConfiguration: CaptionWorkflowConfiguration(queue: []),
            useDateFilter: false,
            dateRange: nil,
            overwriteAppOwnedSameOrNewer: false,
            alwaysOverwriteExternalMetadata: false
        )

        let summary = RunPreflightSummaryBuilder.build(
            snapshot: snapshot,
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                ollamaAvailability: .notInstalled,
                pickerCapability: .supported
            ),
            countState: .exact(42)
        )

        XCTAssertEqual(summary.modelDescription, "Model status: qwen2.5vl:7b cannot be checked until Ollama is installed locally.")
        XCTAssertEqual(summary.serviceDescription, "Ollama service: not available because Ollama is not installed yet.")
        XCTAssertTrue(summary.blockingReasons.contains("Install Ollama locally before starting a run. Use the setup card to open the official download page, then click Re-check Setup."))
    }
}
