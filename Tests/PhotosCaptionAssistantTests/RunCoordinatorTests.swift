import Foundation
import XCTest
@testable import PhotosCaptionAssistant

private enum CaptionWorkflowAlbumStage: String, CaseIterable {
    case priorityCaptioning = "0 - Priority Captioning"
    case noCaptionNewPhotos = "1 - No Caption - New Photos"
    case noCaptionAll = "2 - No Caption - All"
    case olderCaptionLogic = "3 - Older Caption Logic"
}

private struct CaptionWorkflowAlbumAssignment {
    let stage: CaptionWorkflowAlbumStage
    let albumID: String
    let albumName: String
}

private extension CaptionWorkflowConfiguration {
    init(assignments: [CaptionWorkflowAlbumAssignment]) {
        let orderedQueue = CaptionWorkflowAlbumStage.allCases.compactMap { stage -> CaptionWorkflowQueueEntry? in
            guard let assignment = assignments.first(where: { $0.stage == stage }) else {
                return nil
            }
            return CaptionWorkflowQueueEntry(
                albumID: assignment.albumID,
                albumName: assignment.albumName
            )
        }
        self.init(queue: orderedQueue)
    }
}

@MainActor
final class RunCoordinatorTests: XCTestCase {
    func testAutomaticPhotosRestartFiresAtConfiguredIntervalWithoutManualPrompts() async {
        let assets = makeAssets(count: 620)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            quitResults: [true],
            waitForReadyResults: [true]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 500,
            photosMemoryCheckInterval: 10_000,
            photosRestartCooldownSeconds: 0,
            photosRestartLaunchTimeoutSeconds: 1
        )

        let recorder = PromptRecorder()
        let statusRecorder = StatusRecorder()

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                onStatusChanged: { status in
                    statusRecorder.record(status: status)
                },
                confirmExternalOverwrite: { _, _ in
                    XCTFail("No external prompt expected")
                    return false
                },
                confirmContinueAfterCheckpoint: { changed in
                    await recorder.recordCheckpoint(changed)
                    return true
                },
                confirmSafetyPause: { prompt in
                    await recorder.recordSafetyPrompt(prompt)
                    return true
                }
            )
        )

        let checkpoints = await recorder.checkpointsValue()
        let safetyTitles = await recorder.safetyPromptTitlesValue()
        let statuses = statusRecorder.values()
        let quitCount = await writer.quitRequestCountValue()
        let launchCount = await writer.launchRequestCountValue()
        let readinessWaitCount = await writer.waitForReadyCallCountValue()

        XCTAssertEqual(checkpoints, [])
        XCTAssertEqual(safetyTitles, [])
        XCTAssertEqual(quitCount, 1)
        XCTAssertEqual(launchCount, 1)
        XCTAssertEqual(readinessWaitCount, 1)
        XCTAssertTrue(statuses.contains("Pausing for Photos restart"))
        XCTAssertTrue(statuses.contains("Waiting 60s before relaunch"))
        XCTAssertTrue(statuses.contains("Waiting for Photos to become ready"))
        XCTAssertEqual(summary.progress.changed, 620)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(summary.progress.skipped, 0)
    }

    func testHighPhotosMemoryTriggersAutomaticRestartWithoutPrompt() async {
        let assets = makeAssets(count: 3)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            photosResidentMemoryBytes: 25 * 1024 * 1024 * 1024,
            quitResults: [true],
            waitForReadyResults: [true]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 1000,
            photosMemoryCheckInterval: 1,
            photosMemoryWarningBytes: 1024,
            photosRestartCooldownSeconds: 0,
            photosRestartLaunchTimeoutSeconds: 1
        )

        let recorder = PromptRecorder()
        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmSafetyPause: { prompt in
                    await recorder.recordSafetyPrompt(prompt)
                    return true
                }
            )
        )

        let safetyTitles = await recorder.safetyPromptTitlesValue()
        let quitCount = await writer.quitRequestCountValue()
        let launchCount = await writer.launchRequestCountValue()
        let readinessWaitCount = await writer.waitForReadyCallCountValue()
        XCTAssertEqual(safetyTitles, [])
        XCTAssertEqual(quitCount, 1)
        XCTAssertEqual(launchCount, 1)
        XCTAssertEqual(readinessWaitCount, 1)
        XCTAssertEqual(summary.progress.changed, 3)
        XCTAssertEqual(summary.progress.failed, 0)
    }

    func testFailedQuitSkipsRestartOnceAndContinuesRun() async {
        let assets = makeAssets(count: 520)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            quitResults: [false]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 500,
            photosMemoryCheckInterval: 10_000,
            photosRestartCooldownSeconds: 0,
            photosRestartLaunchTimeoutSeconds: 1
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false }
            )
        )

        let quitCount = await writer.quitRequestCountValue()
        let launchCount = await writer.launchRequestCountValue()
        XCTAssertEqual(quitCount, 1)
        XCTAssertEqual(launchCount, 0)
        XCTAssertEqual(summary.progress.changed, 520)
        XCTAssertTrue(summary.errors.contains(where: { $0.contains("did not quit cleanly") }))
    }

    func testPhotosReadyTimeoutStopsRunBeforeNextWindow() async {
        let assets = makeAssets(count: 40)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            quitResults: [true],
            waitForReadyResults: [false]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10,
            photosMemoryCheckInterval: 10_000,
            photosRestartCooldownSeconds: 0,
            photosRestartLaunchTimeoutSeconds: 1
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false }
            )
        )

        let launchCount = await writer.launchRequestCountValue()
        let readinessWaitCount = await writer.waitForReadyCallCountValue()
        XCTAssertEqual(launchCount, 1)
        XCTAssertEqual(readinessWaitCount, 1)
        XCTAssertEqual(summary.progress.changed, 32)
        XCTAssertTrue(summary.errors.contains(where: { $0.contains("automation-ready") }))
    }

    func testCancelDuringRestartCooldownRelaunchesPhotosBeforeStopping() async {
        let assets = makeAssets(count: 40)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            quitResults: [true]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10,
            photosMemoryCheckInterval: 10_000,
            photosRestartCooldownSeconds: 0.2,
            photosRestartLaunchTimeoutSeconds: 1
        )

        let runTask = Task {
            await coordinator.run(
                options: RunOptions(
                    source: .library,
                    optionalCaptureDateRange: nil,
                    overwriteAppOwnedSameOrNewer: false
                ),
                capabilities: AppCapabilities(
                    photosAutomationAvailable: true,
                    qwenModelAvailable: true,
                    pickerCapability: .supported
                ),
                callbacks: RunCallbacks(
                    onProgress: { _ in },
                    confirmExternalOverwrite: { _, _ in false }
                )
            )
        }

        while await writer.quitRequestCountValue() == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        coordinator.cancel()

        let summary = await runTask.value
        let launchCount = await writer.launchRequestCountValue()
        XCTAssertEqual(launchCount, 1)
        XCTAssertEqual(summary.progress.changed, 32)
    }

    func testPhotoPreviewPathPreferredOverExport() async {
        let asset = MediaAsset(id: "asset-preview", filename: "IMG_preview.jpg", captureDate: Date(), kind: .photo)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]

        let writer = MockPhotosWriter(
            assets: [asset],
            metadataByID: metadata,
            previewDataByID: [asset.id: Data([0xFF, 0xD8, 0xFF, 0xD9])]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10_000,
            photosMemoryCheckInterval: 10_000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let previewRequests = await writer.previewRequestsValue()
        let previewSizes = await writer.previewRequestedPixelSizesValue()
        let exportRequests = await writer.exportRequestsValue()
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(previewRequests, [asset.id])
        XCTAssertEqual(previewSizes, [2048])
        XCTAssertEqual(exportRequests, [])
    }

    func testPhotoPreviewPathFeedsAnalyzerFromMemory() async {
        let asset = MediaAsset(id: "asset-preview", filename: "IMG_preview.jpg", captureDate: Date(), kind: .photo)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]
        let inputRecorder = AnalysisInputRecorder()
        let writer = MockPhotosWriter(
            assets: [asset],
            metadataByID: metadata,
            previewDataByID: [asset.id: Data([0xFF, 0xD8, 0xFF, 0xD9])]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: RecordingAnalyzer(
                result: GeneratedMetadata(caption: "caption", keywords: ["k1"]),
                recorder: inputRecorder
            ),
            checkpointInterval: 10_000,
            photosMemoryCheckInterval: 10_000
        )

        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let recordedInputs = await inputRecorder.values()
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(recordedInputs, ["photo-preview-data"])
    }

    func testPhotoPreviewPathAlsoFeedsCompletedPreviewWithoutExtraExport() async {
        let asset = MediaAsset(id: "asset-preview", filename: "IMG_preview.jpg", captureDate: Date(), kind: .photo)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]
        let previewInputRecorder = AnalysisInputRecorder()
        let previewRecorder = PreviewRecorder()
        let writer = MockPhotosWriter(
            assets: [asset],
            metadataByID: metadata,
            previewDataByID: [asset.id: Data([0xFF, 0xD8, 0xFF, 0xD9])]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10_000,
            photosMemoryCheckInterval: 10_000,
            previewRenderer: RecordingPreviewRenderer(recorder: previewInputRecorder)
        )

        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks(
                onItemCompleted: { preview in
                    previewRecorder.record(preview: preview)
                }
            )
        )

        let previewInputs = await previewInputRecorder.values()
        let exportRequests = await writer.exportRequestsValue()
        let completedPreview = previewRecorder.firstValue()

        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(previewInputs, ["photo-preview-data"])
        XCTAssertEqual(exportRequests, [])
        XCTAssertEqual(completedPreview?.previewFileURL?.pathExtension.lowercased(), "jpg")
    }

    func testPhotoPreviewFallsBackToExportWhenUnavailable() async {
        let asset = MediaAsset(id: "asset-fallback", filename: "IMG_fallback.jpg", captureDate: Date(), kind: .photo)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]

        let writer = MockPhotosWriter(
            assets: [asset],
            metadataByID: metadata,
            previewDataByID: [:]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10_000,
            photosMemoryCheckInterval: 10_000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let previewRequests = await writer.previewRequestsValue()
        let previewSizes = await writer.previewRequestedPixelSizesValue()
        let exportRequests = await writer.exportRequestsValue()
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(previewRequests, [asset.id])
        XCTAssertEqual(previewSizes, [2048])
        XCTAssertEqual(exportRequests, [asset.id])
    }

    func testVideoUsesExportPathAndSkipsPhotoPreviewPath() async {
        let asset = MediaAsset(id: "asset-video", filename: "VID_test.mov", captureDate: Date(), kind: .video)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]

        let writer = MockPhotosWriter(
            assets: [asset],
            metadataByID: metadata,
            previewDataByID: [asset.id: Data([0xFF, 0xD8, 0xFF, 0xD9])]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10_000,
            photosMemoryCheckInterval: 10_000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let previewRequests = await writer.previewRequestsValue()
        let previewSizes = await writer.previewRequestedPixelSizesValue()
        let exportRequests = await writer.exportRequestsValue()
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(previewRequests, [])
        XCTAssertEqual(previewSizes, [])
        XCTAssertEqual(exportRequests, [asset.id])
    }

    func testCompletedPreviewUsesLibrarySourceContext() async {
        let asset = MediaAsset(id: "asset-library", filename: "IMG_library.jpg", captureDate: Date(), kind: .photo)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]

        let writer = MockPhotosWriter(assets: [asset], metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10_000,
            photosMemoryCheckInterval: 10_000
        )
        let previewRecorder = PreviewRecorder()

        _ = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks(
                onItemCompleted: { preview in
                    previewRecorder.record(preview: preview)
                }
            )
        )

        XCTAssertEqual(previewRecorder.firstValue()?.sourceContext, "Whole Library")
    }

    func testCompletedPreviewUsesAlbumSourceContext() async {
        let asset = MediaAsset(id: "asset-album", filename: "IMG_album.jpg", captureDate: Date(), kind: .photo)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]
        let album = AlbumSummary(id: "album-1", name: "Family Favorites", itemCount: 1)

        let writer = MockPhotosWriter(
            assets: [asset],
            metadataByID: metadata,
            listedAlbums: [album],
            albumAssetIDsByID: [album.id: [asset.id]]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )
        let previewRecorder = PreviewRecorder()

        _ = await coordinator.run(
            options: RunOptions(
                source: .album(id: album.id),
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks(
                onItemCompleted: { preview in
                    previewRecorder.record(preview: preview)
                }
            )
        )

        XCTAssertEqual(previewRecorder.firstValue()?.sourceContext, album.name)
    }

    func testCompletedPreviewUsesPickerSourceContext() async {
        let asset = MediaAsset(id: "asset-picker", filename: "IMG_picker.jpg", captureDate: Date(), kind: .photo)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]

        let writer = MockPhotosWriter(assets: [asset], metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )
        let previewRecorder = PreviewRecorder()

        _ = await coordinator.run(
            options: RunOptions(
                source: .picker(ids: [asset.id]),
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks(
                onItemCompleted: { preview in
                    previewRecorder.record(preview: preview)
                }
            )
        )

        XCTAssertEqual(previewRecorder.firstValue()?.sourceContext, "Photos Picker")
    }

    func testCompletedPreviewUsesCaptionWorkflowStageSourceContext() async {
        let asset = MediaAsset(id: "asset-workflow", filename: "IMG_workflow.jpg", captureDate: Date(), kind: .photo)
        let metadata = [
            asset.id: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        ]

        let writer = MockPhotosWriter(
            assets: [asset],
            metadataByID: metadata,
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [asset.id],
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )
        let previewRecorder = PreviewRecorder()

        _ = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks(
                onItemCompleted: { preview in
                    previewRecorder.record(preview: preview)
                }
            )
        )

        XCTAssertEqual(
            previewRecorder.firstValue()?.sourceContext,
            CaptionWorkflowAlbumStage.priorityCaptioning.rawValue
        )
    }

    func testExternalConflictPromptIsPerPhoto() async {
        let assets = makeAssets(count: 2)
        let metadata = [
            assets[0].id: ExistingMetadataState(caption: "User caption", keywords: ["family"], ownershipTag: nil, isExternal: true),
            assets[1].id: ExistingMetadataState(caption: "User caption", keywords: ["travel"], ownershipTag: nil, isExternal: true)
        ]

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "generated", keywords: ["auto"]))
        )

        let recorder = PromptRecorder()

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { asset, _ in
                    await recorder.recordExternalPrompt()
                    return asset.id == assets[0].id
                },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let externalCount = await recorder.externalPromptCountValue()
        XCTAssertEqual(externalCount, 2)
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(summary.progress.skipped, 1)
    }

    func testExternalConflictCanAutoOverwriteWithoutPrompt() async {
        let assets = makeAssets(count: 2)
        let metadata = [
            assets[0].id: ExistingMetadataState(caption: "User caption", keywords: ["family"], ownershipTag: nil, isExternal: true),
            assets[1].id: ExistingMetadataState(caption: "User caption", keywords: ["travel"], ownershipTag: nil, isExternal: true)
        ]

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "generated", keywords: ["auto"]))
        )

        let recorder = PromptRecorder()

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                alwaysOverwriteExternalMetadata: true
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in
                    await recorder.recordExternalPrompt()
                    return false
                },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let externalCount = await recorder.externalPromptCountValue()
        XCTAssertEqual(externalCount, 0)
        XCTAssertEqual(summary.progress.changed, 2)
        XCTAssertEqual(summary.progress.skipped, 0)
    }

    func testOwnedDifferentEngineGetsRewritten() async {
        let assets = makeAssets(count: 3)
        let ownership = OwnershipTag(logicVersion: .current, engineTier: .vision)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (
                asset.id,
                ExistingMetadataState(
                    caption: "Existing",
                    keywords: OwnershipTagCodec.tags(for: ownership),
                    ownershipTag: ownership,
                    isExternal: false
                )
            )
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "qwen", keywords: ["qwen"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        XCTAssertEqual(summary.progress.changed, 3)
        XCTAssertEqual(summary.progress.skipped, 0)
    }

    func testFailedAssetsAreTrackedForRetry() async {
        let assets = makeAssets(count: 3)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: ConditionalFailAnalyzer(
                failedAssetIDs: [assets[0].id, assets[2].id],
                successResult: GeneratedMetadata(caption: "ok", keywords: ["k"])
            )
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        XCTAssertEqual(summary.progress.failed, 2)
        XCTAssertEqual(summary.failedAssets.map(\.id), [assets[0].id, assets[2].id])
    }

    func testTraversalOrderOldestToNewestUsesCaptureDate() async {
        let assets = [
            MediaAsset(id: "asset-c", filename: "IMG_c.jpg", captureDate: Date(timeIntervalSince1970: 300), kind: .photo),
            MediaAsset(id: "asset-a", filename: "IMG_a.jpg", captureDate: Date(timeIntervalSince1970: 100), kind: .photo),
            MediaAsset(id: "asset-b", filename: "IMG_b.jpg", captureDate: Date(timeIntervalSince1970: 200), kind: .photo)
        ]
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"]))
        )

        _ = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .oldestToNewest,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let writeOrder = await writer.writeOrderValue()
        XCTAssertEqual(writeOrder, ["asset-a", "asset-b", "asset-c"])
    }

    func testTraversalOrderNewestToOldestUsesCaptureDate() async {
        let assets = [
            MediaAsset(id: "asset-c", filename: "IMG_c.jpg", captureDate: Date(timeIntervalSince1970: 300), kind: .photo),
            MediaAsset(id: "asset-a", filename: "IMG_a.jpg", captureDate: Date(timeIntervalSince1970: 100), kind: .photo),
            MediaAsset(id: "asset-b", filename: "IMG_b.jpg", captureDate: Date(timeIntervalSince1970: 200), kind: .photo)
        ]
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"]))
        )

        _ = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .newestToOldest,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let writeOrder = await writer.writeOrderValue()
        XCTAssertEqual(writeOrder, ["asset-c", "asset-b", "asset-a"])
    }

    func testTraversalOrderPutsMissingCaptureDateAfterDatedAssets() async {
        let assets = [
            MediaAsset(id: "dated-new", filename: "A.jpg", captureDate: Date(timeIntervalSince1970: 200), kind: .photo),
            MediaAsset(id: "undated-b", filename: "D.jpg", captureDate: nil, kind: .photo),
            MediaAsset(id: "dated-old", filename: "B.jpg", captureDate: Date(timeIntervalSince1970: 100), kind: .photo),
            MediaAsset(id: "undated-a", filename: "C.jpg", captureDate: nil, kind: .photo)
        ]
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"]))
        )

        _ = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .oldestToNewest,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let writeOrder = await writer.writeOrderValue()
        XCTAssertEqual(writeOrder, ["dated-old", "dated-new", "undated-a", "undated-b"])
    }

    func testTraversalOrderRandomProcessesEachSelectedAssetExactlyOnce() async {
        let assets = [
            MediaAsset(id: "asset-1", filename: "one.jpg", captureDate: Date(timeIntervalSince1970: 10), kind: .photo),
            MediaAsset(id: "asset-2", filename: "two.jpg", captureDate: Date(timeIntervalSince1970: 20), kind: .photo),
            MediaAsset(id: "asset-3", filename: "three.jpg", captureDate: Date(timeIntervalSince1970: 30), kind: .photo),
            MediaAsset(id: "asset-4", filename: "four.jpg", captureDate: Date(timeIntervalSince1970: 40), kind: .photo)
        ]
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .random,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let writeOrder = await writer.writeOrderValue()
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertEqual(writeOrder.count, assets.count)
        XCTAssertEqual(Set(writeOrder), Set(assets.map(\.id)))
    }

    func testTraversalOrderCycleAlternatesOldestThenNewestThenRandom() async {
        let assets = [
            MediaAsset(id: "asset-1", filename: "one.jpg", captureDate: Date(timeIntervalSince1970: 10), kind: .photo),
            MediaAsset(id: "asset-2", filename: "two.jpg", captureDate: Date(timeIntervalSince1970: 20), kind: .photo),
            MediaAsset(id: "asset-3", filename: "three.jpg", captureDate: Date(timeIntervalSince1970: 30), kind: .photo),
            MediaAsset(id: "asset-4", filename: "four.jpg", captureDate: Date(timeIntervalSince1970: 40), kind: .photo),
            MediaAsset(id: "asset-5", filename: "five.jpg", captureDate: Date(timeIntervalSince1970: 50), kind: .photo)
        ]
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .cycle,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let writeOrder = await writer.writeOrderValue()
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertEqual(writeOrder.count, assets.count)
        XCTAssertEqual(Set(writeOrder), Set(assets.map(\.id)))
        XCTAssertEqual(writeOrder.first, "asset-1")
        XCTAssertGreaterThan(writeOrder.count, 1)
        XCTAssertEqual(writeOrder[1], "asset-5")
    }

    func testFastTraversalStartsProcessingAfterFirstPageEnumeration() async {
        let assets = makeAssets(count: 620)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "fast", keywords: ["k"])),
            checkpointInterval: 1000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .photosOrderFast,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let firstWriteAfterEnumeratePages = await writer.firstWriteAfterEnumeratePageCountValue()
        let countCalls = await writer.countCallCountValue()
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertEqual(firstWriteAfterEnumeratePages, 1)
        XCTAssertEqual(countCalls, 0)
    }

    func testFastLibraryTraversalUsesAlternateIncrementalScanSourceWhenSafe() async {
        let assets = makeAssets(count: 620)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let alternateScanSource = MockScopedIncrementalScanSource(assets: assets)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "fast", keywords: ["k"])),
            incrementalScanSource: alternateScanSource,
            checkpointInterval: 1000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .photosOrderFast,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let primaryPageCalls = await writer.enumeratePageCallCountValue()
        let alternatePageCalls = await alternateScanSource.enumeratePageCallCountValue()
        let alternateCountCalls = await alternateScanSource.countCallCountValue()
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertEqual(primaryPageCalls, 0)
        XCTAssertGreaterThan(alternatePageCalls, 0)
        XCTAssertEqual(alternateCountCalls, 0)
    }

    func testDateSensitiveTraversalKeepsPrimaryIncrementalScanPath() async {
        let assets = makeAssets(count: 80)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let alternateScanSource = MockScopedIncrementalScanSource(assets: assets)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"])),
            incrementalScanSource: alternateScanSource,
            checkpointInterval: 1000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .oldestToNewest,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let primaryPageCalls = await writer.enumeratePageCallCountValue()
        let primaryCountCalls = await writer.countCallCountValue()
        let alternatePageCalls = await alternateScanSource.enumeratePageCallCountValue()
        let alternateCountCalls = await alternateScanSource.countCallCountValue()
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertGreaterThan(primaryPageCalls, 0)
        XCTAssertGreaterThan(primaryCountCalls, 0)
        XCTAssertEqual(alternatePageCalls, 0)
        XCTAssertEqual(alternateCountCalls, 0)
    }

    func testUnresolvableAlbumFallsBackToPrimaryIncrementalScanPath() async {
        let assets = makeAssets(count: 10)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let albumID = "album-1"

        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            albumAssetIDsByID: [albumID: assets.map(\.id)]
        )
        let alternateScanSource = MockScopedIncrementalScanSource(
            assets: assets,
            supportedAlbumIDs: []
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "album", keywords: ["k"])),
            incrementalScanSource: alternateScanSource,
            checkpointInterval: 1000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .album(id: albumID),
                optionalCaptureDateRange: nil,
                traversalOrder: .photosOrderFast,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let primaryPageCalls = await writer.enumeratePageCallCountValue()
        let alternatePageCalls = await alternateScanSource.enumeratePageCallCountValue()
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertGreaterThan(primaryPageCalls, 0)
        XCTAssertEqual(alternatePageCalls, 0)
    }

    func testFastTraversalRetriesEnumeratePageWithSmallerLimitAfterTimeout() async {
        let assets = makeAssets(count: 300)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            enumerateTimeoutWhenLimitExceeds: 200
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "retry", keywords: ["k"])),
            checkpointInterval: 1000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .photosOrderFast,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let enumeratePageCallCount = await writer.enumeratePageCallCountValue()
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertTrue(summary.errors.isEmpty)
        XCTAssertGreaterThan(enumeratePageCallCount, 3)
    }

    func testLargeOrderedRunReadsBatchMetadataInProcessingChunks() async {
        let assets = makeAssets(count: 620)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"])),
            checkpointInterval: 1000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .oldestToNewest,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let batchReadSizes = await writer.batchReadSizesValue()
        let firstWriteAfterEnumeratePages = await writer.firstWriteAfterEnumeratePageCountValue()
        let countCalls = await writer.countCallCountValue()
        let prefetchedAssetCount = batchReadSizes.reduce(0, +)
        let minimumExpectedPrefetchedAssets = max(0, assets.count - (32 * 3))
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertFalse(batchReadSizes.isEmpty)
        XCTAssertGreaterThanOrEqual(prefetchedAssetCount, minimumExpectedPrefetchedAssets)
        XCTAssertLessThan(prefetchedAssetCount, assets.count)
        XCTAssertTrue(batchReadSizes.allSatisfy { $0 <= 32 })
        XCTAssertEqual(firstWriteAfterEnumeratePages, 3)
        XCTAssertEqual(countCalls, 1)
    }

    func testWriteBatchingUsesConfiguredChunkSize() async {
        let assets = makeAssets(count: 70)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "batched", keywords: ["k"])),
            checkpointInterval: 1000,
            writeBatchSize: 16
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .photosOrderFast,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let batchWriteSizes = await writer.batchWriteSizesValue()
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertFalse(batchWriteSizes.isEmpty)
        XCTAssertEqual(batchWriteSizes.reduce(0, +), assets.count)
        XCTAssertTrue(batchWriteSizes.allSatisfy { $0 <= 16 })
    }

    func testOrderedPreparationProgressReportsEnumeratedCounts() async {
        let assets = makeAssets(count: 620)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"])),
            checkpointInterval: 1000
        )
        let preparationRecorder = PreparationProgressRecorder()

        _ = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .oldestToNewest,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                onPreparationProgress: { enumerated, total in
                    preparationRecorder.record(enumerated: enumerated, total: total)
                },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true }
            )
        )

        let snapshots = preparationRecorder.snapshotsValue()
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertEqual(snapshots.first?.0, 0)
        XCTAssertEqual(snapshots.first?.1, 620)
        XCTAssertEqual(snapshots.last?.0, 620)
        XCTAssertEqual(snapshots.last?.1, 620)
    }

    func testSlowOrderedRunThresholdPromptCanCancelBeforePrescan() async {
        let assets = makeAssets(count: 5_000)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "ordered", keywords: ["k"])),
            checkpointInterval: 1000
        )
        let recorder = PromptRecorder()

        let summary = await coordinator.run(
            options: RunOptions(
                source: .library,
                optionalCaptureDateRange: nil,
                traversalOrder: .oldestToNewest,
                overwriteAppOwnedSameOrNewer: false
            ),
            capabilities: AppCapabilities(
                photosAutomationAvailable: true,
                qwenModelAvailable: true,
                pickerCapability: .supported
            ),
            callbacks: RunCallbacks(
                onProgress: { _ in },
                confirmExternalOverwrite: { _, _ in false },
                confirmContinueAfterCheckpoint: { _ in true },
                confirmSafetyPause: { prompt in
                    await recorder.recordSafetyPrompt(prompt)
                    if prompt.title == "Slow Ordered Run" {
                        return false
                    }
                    return true
                }
            )
        )

        let safetyTitles = await recorder.safetyPromptTitlesValue()
        let enumeratePageCount = await writer.enumeratePageCallCountValue()
        XCTAssertEqual(summary.progress.processed, 0)
        XCTAssertEqual(summary.progress.changed, 0)
        XCTAssertEqual(safetyTitles, ["Slow Ordered Run"])
        XCTAssertEqual(enumeratePageCount, 0)
    }

    func testPrepareAheadOverlapsNextExportWithCurrentAnalysis() async {
        let assets = makeAssets(count: 3)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let timeline = TimelineRecorder()
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            exportDelayNanoseconds: 120_000_000,
            exportDelayByID: ["asset-0": 20_000_000],
            timelineRecorder: timeline
        )
        let analyzerState = ContentionAwareAnalyzerState(
            result: GeneratedMetadata(caption: "caption", keywords: ["k1"]),
            baseDelayNanoseconds: 180_000_000,
            concurrentPenaltyNanoseconds: 0,
            timelineRecorder: timeline
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: ContentionAwareAnalyzer(state: analyzerState),
            analysisConcurrency: 1,
            prepareAheadLimit: 1
        )

        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let analyzeStart = await timeline.timestamp(for: "analyze-start:asset-0")
        let analyzeEnd = await timeline.timestamp(for: "analyze-end:asset-0")
        let exportStart = await timeline.timestamp(for: "export-start:asset-2")
        let exportEnd = await timeline.timestamp(for: "export-end:asset-2")
        let maxActive = await analyzerState.maxActiveCountValue()

        XCTAssertEqual(summary.progress.changed, 3)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(maxActive, 1)
        XCTAssertNotNil(analyzeStart)
        XCTAssertNotNil(analyzeEnd)
        XCTAssertNotNil(exportStart)
        XCTAssertNotNil(exportEnd)
        XCTAssertLessThan(exportStart!, analyzeEnd!)
        XCTAssertGreaterThan(exportEnd!, analyzeStart!)
    }

    func testStreamingMetadataGatingStartsAssetAcquireBeforeWindowMetadataFinishes() async {
        let assets = makeAssets(count: 3)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let timeline = TimelineRecorder()
        let previewData = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, Data(asset.id.utf8))
        })
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            previewDataByID: previewData,
            metadataReadDelayByID: [
                "asset-1": 180_000_000,
                "asset-2": 180_000_000
            ],
            timelineRecorder: timeline
        )
        let analyzerState = PreparedOverlapAnalyzerState(
            result: GeneratedMetadata(caption: "caption", keywords: ["k1"]),
            preparationDelayNanoseconds: 20_000_000,
            analysisDelayNanoseconds: 10_000_000,
            timelineRecorder: timeline
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: PreparedOverlapAnalyzer(state: analyzerState),
            analysisConcurrency: 1,
            prepareAheadLimit: 1
        )

        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let firstPrepareStart = await timeline.timestamp(for: "prepare-start:asset-0")
        let lastMetadataReadEnd = await timeline.timestamp(for: "metadata-read-end:asset-2")

        XCTAssertEqual(summary.progress.changed, 3)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertNotNil(firstPrepareStart)
        XCTAssertNotNil(lastMetadataReadEnd)
        XCTAssertLessThan(firstPrepareStart!, lastMetadataReadEnd!)
    }

    func testPreparedAnalyzerBuildsNextPayloadDuringCurrentAnalysis() async {
        let assets = makeAssets(count: 3)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let timeline = TimelineRecorder()
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            exportDelayByID: [
                "asset-0": 10_000_000,
                "asset-1": 150_000_000
            ],
            timelineRecorder: timeline
        )
        let analyzerState = PreparedOverlapAnalyzerState(
            result: GeneratedMetadata(caption: "caption", keywords: ["k1"]),
            preparationDelayNanoseconds: 60_000_000,
            analysisDelayNanoseconds: 180_000_000,
            timelineRecorder: timeline
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: PreparedOverlapAnalyzer(state: analyzerState),
            analysisConcurrency: 1,
            prepareAheadLimit: 1
        )

        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let analyzeStart = await timeline.timestamp(for: "analyze-start:asset-0")
        let analyzeEnd = await timeline.timestamp(for: "analyze-end:asset-0")
        let prepareStart = await timeline.timestamp(for: "prepare-start:asset-1")
        let prepareEnd = await timeline.timestamp(for: "prepare-end:asset-1")
        let maxActive = await analyzerState.maxActiveCountValue()

        XCTAssertEqual(summary.progress.changed, 3)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(maxActive, 1)
        XCTAssertNotNil(analyzeStart)
        XCTAssertNotNil(analyzeEnd)
        XCTAssertNotNil(prepareStart)
        XCTAssertNotNil(prepareEnd)
        XCTAssertLessThan(prepareStart!, analyzeEnd!)
        XCTAssertGreaterThan(prepareEnd!, analyzeStart!)
    }

    func testPreviewGenerationDoesNotBlockLaterWrites() async {
        let assets = makeAssets(count: 3)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let timeline = TimelineRecorder()
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            timelineRecorder: timeline
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            writeBatchSize: 1,
            previewRenderer: MockPreviewRenderer(
                delayNanoseconds: 180_000_000,
                timelineRecorder: timeline
            )
        )

        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let firstPreviewEnd = await timeline.timestamp(for: "preview-end:asset-0")
        let secondWriteStart = await timeline.timestamp(for: "write-start:asset-1")

        XCTAssertEqual(summary.progress.changed, 3)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertNotNil(firstPreviewEnd)
        XCTAssertNotNil(secondWriteStart)
        XCTAssertLessThan(secondWriteStart!, firstPreviewEnd!)
    }

    func testWritesStartBeforeEntireAnalysisWindowFinishes() async {
        let assets = makeAssets(count: 3)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let timeline = TimelineRecorder()
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            timelineRecorder: timeline
        )
        let analyzerState = ContentionAwareAnalyzerState(
            result: GeneratedMetadata(caption: "caption", keywords: ["k1"]),
            baseDelayNanoseconds: 180_000_000,
            concurrentPenaltyNanoseconds: 0,
            timelineRecorder: timeline
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: ContentionAwareAnalyzer(state: analyzerState),
            analysisConcurrency: 1,
            prepareAheadLimit: 1,
            writeBatchSize: 16
        )

        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let firstWriteStart = await timeline.timestamp(for: "write-start:asset-0")
        let lastAnalyzeEnd = await timeline.timestamp(for: "analyze-end:asset-2")

        XCTAssertEqual(summary.progress.changed, 3)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertNotNil(firstWriteStart)
        XCTAssertNotNil(lastAnalyzeEnd)
        XCTAssertLessThan(firstWriteStart!, lastAnalyzeEnd!)
    }

    func testRunSummaryIncludesTimingDiagnostics() async throws {
        let assets = makeAssets(count: 2)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let coordinator = RunCoordinator(
            photosWriter: MockPhotosWriter(assets: assets, metadataByID: metadata),
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            analysisConcurrency: 1,
            prepareAheadLimit: 1,
            writeBatchSize: 4
        )

        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let diagnostics = try XCTUnwrap(summary.diagnostics)
        XCTAssertEqual(diagnostics.analysisConcurrency, 1)
        XCTAssertEqual(diagnostics.prepareAheadLimit, 1)
        XCTAssertEqual(diagnostics.writeBatchSize, 4)
        XCTAssertEqual(diagnostics.stageTimings.count, 6)
        XCTAssertGreaterThan(diagnostics.wallSeconds, 0)
        XCTAssertTrue(diagnostics.stageTimings.contains(where: { $0.stage == "asset-acquire" }))
        XCTAssertTrue(diagnostics.stageTimings.contains(where: { $0.stage == "write" }))
    }

    func testCaptionWorkflowRefreshesLaterStageAfterEarlierWrites() async {
        let assets = makeAssets(count: 1)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let albums = makeCaptionWorkflowAlbums()
        let statusRecorder = StatusRecorder()
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: albums,
            albumAssetIDsByID: [
                "cw-0": [assets[0].id],
                "cw-1": [assets[0].id],
                "cw-2": [],
                "cw-3": []
            ],
            removeWrittenAssetsFromAllAlbums: true
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks(
                onStatusChanged: { status in
                    statusRecorder.record(status: status)
                }
            )
        )

        let writeOrder = await writer.writeOrderValue()
        let listAlbumsCount = await writer.listUserAlbumsCallCountValue()
        let statuses = statusRecorder.values()

        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(writeOrder, [assets[0].id])
        XCTAssertGreaterThanOrEqual(listAlbumsCount, 5)
        XCTAssertTrue(statuses.contains(where: { $0.contains("0 - Priority Captioning") }))
        XCTAssertTrue(statuses.contains(where: { $0.contains("1 - No Caption - New Photos") && $0.contains("no eligible items") }))
    }

    func testCaptionWorkflowUsesConfiguredAlbumIDsAfterAlbumsAreRenamed() async {
        let assets = makeAssets(count: 1)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let renamedAlbums = [
            AlbumSummary(id: "cw-0", name: "Priority Queue", itemCount: 1),
            AlbumSummary(id: "cw-1", name: "New Photos Queue", itemCount: 0),
            AlbumSummary(id: "cw-2", name: "All Photos Queue", itemCount: 0),
            AlbumSummary(id: "cw-3", name: "Legacy Queue", itemCount: 0)
        ]
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: renamedAlbums,
            albumAssetIDsByID: [
                "cw-0": [assets[0].id],
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertTrue(summary.errors.isEmpty)
    }

    func testCaptionWorkflowFallsBackToSecondStageWhenFirstIsEmpty() async {
        let assets = makeAssets(count: 1)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [],
                "cw-1": [assets[0].id],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let writeOrder = await writer.writeOrderValue()
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(writeOrder, [assets[0].id])
    }

    func testCaptionWorkflowRetriesTemporarilyEmptyNextStageAfterPriorWrites() async {
        let assets = makeAssets(count: 2)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let statusRecorder = StatusRecorder()
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [assets[0].id],
                "cw-1": [assets[1].id],
                "cw-2": [],
                "cw-3": []
            ],
            albumAssetIDSequenceByID: [
                "cw-1": [[], [assets[1].id]]
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks(
                onStatusChanged: { status in
                    statusRecorder.record(status: status)
                }
            )
        )

        let writeOrder = await writer.writeOrderValue()
        let statuses = statusRecorder.values()
        XCTAssertEqual(summary.progress.changed, 2)
        XCTAssertEqual(writeOrder, [assets[0].id, assets[1].id])
        XCTAssertTrue(statuses.contains(where: { $0.contains("waiting for Photos to refresh") }))
    }

    func testCaptionWorkflowFallsBackToThirdStageWhenFirstTwoAreEmpty() async {
        let assets = makeAssets(count: 1)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [],
                "cw-1": [],
                "cw-2": [assets[0].id],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let writeOrder = await writer.writeOrderValue()
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(writeOrder, [assets[0].id])
    }

    func testCaptionWorkflowStopsWhenAllStagesAreEmpty() async {
        let writer = MockPhotosWriter(
            assets: [],
            metadataByID: [:],
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [],
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        XCTAssertEqual(summary.progress.processed, 0)
        XCTAssertEqual(summary.progress.changed, 0)
        XCTAssertTrue(summary.errors.contains(where: { $0.contains("no eligible items") }))
    }

    func testCaptionWorkflowFailsWhenQueueHasFewerThanTwoConfiguredAlbums() async {
        let writer = MockPhotosWriter(
            assets: [],
            metadataByID: [:],
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [],
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: CaptionWorkflowConfiguration(queue: [
                    CaptionWorkflowQueueEntry(
                        albumID: "cw-0",
                        albumName: CaptionWorkflowAlbumStage.priorityCaptioning.rawValue
                    )
                ])
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        XCTAssertEqual(summary.progress.changed, 0)
        XCTAssertTrue(summary.errors.contains(where: { $0.contains("queue item 2") }))
    }

    func testCaptionWorkflowFailsWhenConfiguredAlbumIsMissing() async {
        let listedAlbums = [
            AlbumSummary(id: "cw-1", name: CaptionWorkflowAlbumStage.noCaptionNewPhotos.rawValue, itemCount: 0),
            AlbumSummary(id: "cw-2", name: CaptionWorkflowAlbumStage.noCaptionAll.rawValue, itemCount: 0),
            AlbumSummary(id: "cw-3", name: CaptionWorkflowAlbumStage.olderCaptionLogic.rawValue, itemCount: 0)
        ]
        let writer = MockPhotosWriter(
            assets: [],
            metadataByID: [:],
            listedAlbums: listedAlbums,
            albumAssetIDsByID: [
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        XCTAssertEqual(summary.progress.changed, 0)
        XCTAssertTrue(summary.errors.contains(where: { $0.contains(CaptionWorkflowAlbumStage.priorityCaptioning.rawValue) }))
    }

    func testCaptionWorkflowFailsWhenConfiguredAlbumIDIsMissingEvenIfNameStillExists() async {
        let listedAlbums = makeCaptionWorkflowAlbums()
        let writer = MockPhotosWriter(
            assets: [],
            metadataByID: [:],
            listedAlbums: listedAlbums,
            albumAssetIDsByID: [
                "cw-0": [],
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let configuration = CaptionWorkflowConfiguration(assignments: [
            CaptionWorkflowAlbumAssignment(
                stage: .priorityCaptioning,
                albumID: "cw-old-priority",
                albumName: CaptionWorkflowAlbumStage.priorityCaptioning.rawValue
            ),
            CaptionWorkflowAlbumAssignment(
                stage: .noCaptionNewPhotos,
                albumID: "cw-1",
                albumName: CaptionWorkflowAlbumStage.noCaptionNewPhotos.rawValue
            ),
            CaptionWorkflowAlbumAssignment(
                stage: .noCaptionAll,
                albumID: "cw-2",
                albumName: CaptionWorkflowAlbumStage.noCaptionAll.rawValue
            ),
            CaptionWorkflowAlbumAssignment(
                stage: .olderCaptionLogic,
                albumID: "cw-3",
                albumName: CaptionWorkflowAlbumStage.olderCaptionLogic.rawValue
            )
        ])
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: configuration
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        XCTAssertEqual(summary.progress.changed, 0)
        XCTAssertTrue(summary.errors.contains(where: { $0.contains("Repair the queue") }))
    }

    func testCaptionWorkflowFailsWhenConfiguredAlbumIsDuplicated() async {
        let writer = MockPhotosWriter(
            assets: [],
            metadataByID: [:],
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [],
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: CaptionWorkflowConfiguration(queue: [
                    CaptionWorkflowQueueEntry(
                        albumID: "cw-0",
                        albumName: CaptionWorkflowAlbumStage.priorityCaptioning.rawValue
                    ),
                    CaptionWorkflowQueueEntry(
                        albumID: "cw-0",
                        albumName: CaptionWorkflowAlbumStage.priorityCaptioning.rawValue
                    ),
                    CaptionWorkflowQueueEntry(
                        albumID: "cw-2",
                        albumName: CaptionWorkflowAlbumStage.noCaptionAll.rawValue
                    ),
                    CaptionWorkflowQueueEntry(
                        albumID: "cw-3",
                        albumName: CaptionWorkflowAlbumStage.olderCaptionLogic.rawValue
                    )
                ])
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        XCTAssertEqual(summary.progress.changed, 0)
        XCTAssertTrue(summary.errors.contains(where: { $0.contains("Duplicate selections") }))
    }

    func testCaptionWorkflowFastOrderChunksLargeShrinkingStageWithoutSkippingAssets() async {
        let assets = makeAssets(count: 1_001)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let statusRecorder = StatusRecorder()
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": assets.map(\.id),
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ],
            removeWrittenAssetsFromAllAlbums: true
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10_000,
            photosMemoryCheckInterval: 10_000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                traversalOrder: .photosOrderFast,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks(
                onStatusChanged: { status in
                    statusRecorder.record(status: status)
                }
            )
        )

        let writeOrder = await writer.writeOrderValue()
        let enumeratePageCount = await writer.enumeratePageCallCountValue()
        let firstWriteAfterEnumeratePages = await writer.firstWriteAfterEnumeratePageCountValue()
        let statuses = statusRecorder.values()

        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(firstWriteAfterEnumeratePages, 2)
        XCTAssertGreaterThan(enumeratePageCount, 4)
        XCTAssertEqual(writeOrder.count, assets.count)
        XCTAssertEqual(Set(writeOrder), Set(assets.map(\.id)))
        XCTAssertTrue(statuses.contains(where: { $0.contains("collecting next chunk") }))
    }

    func testCaptionWorkflowOrderedTraversalUsesSnapshotsNotPagedEnumeration() async {
        let assets = makeAssets(count: 1)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [assets[0].id],
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                traversalOrder: .oldestToNewest,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let enumeratePageCount = await writer.enumeratePageCallCountValue()
        let countCallCount = await writer.countCallCountValue()

        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(enumeratePageCount, 0)
        XCTAssertEqual(countCallCount, 0)
    }

    func testCaptionWorkflowOrderedTraversalFallsBackToPagedEnumerationWhenDirectSnapshotFails() async {
        let assets = makeAssets(count: 1)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": [],
                "cw-1": [assets[0].id],
                "cw-2": [],
                "cw-3": []
            ],
            directEnumerateTimeoutsByAlbumID: [
                "cw-1": 1
            ]
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: nil,
                traversalOrder: .oldestToNewest,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let enumeratePageCount = await writer.enumeratePageCallCountValue()
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertGreaterThan(enumeratePageCount, 0)
    }

    func testCaptionWorkflowFastOrderDateFilterRespectsChunking() async {
        let now = Date()
        let inRangeAssets = 1_001
        let assets = makeAssets(count: 1_020).enumerated().map { index, asset in
            MediaAsset(
                id: asset.id,
                filename: asset.filename,
                captureDate: index < inRangeAssets ? now : now.addingTimeInterval(-10 * 86_400),
                kind: asset.kind
            )
        }
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            listedAlbums: makeCaptionWorkflowAlbums(),
            albumAssetIDsByID: [
                "cw-0": assets.map(\.id),
                "cw-1": [],
                "cw-2": [],
                "cw-3": []
            ],
            removeWrittenAssetsFromAllAlbums: true
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 10_000,
            photosMemoryCheckInterval: 10_000
        )

        let summary = await coordinator.run(
            options: RunOptions(
                source: .captionWorkflow,
                optionalCaptureDateRange: CaptureDateRange(
                    start: now.addingTimeInterval(-86_400),
                    end: now.addingTimeInterval(86_400)
                ),
                traversalOrder: .photosOrderFast,
                overwriteAppOwnedSameOrNewer: false,
                captionWorkflowConfiguration: makeCaptionWorkflowConfiguration()
            ),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )

        let writeOrder = await writer.writeOrderValue()
        let expectedIDs = Set(assets.prefix(inRangeAssets).map(\.id))

        XCTAssertEqual(summary.progress.changed, inRangeAssets)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(Set(writeOrder), expectedIDs)
    }

    func testSingleAnalysisWithPrepareAheadBeatsDualAnalysisUnderContention() async {
        let dualAnalysis = await runSyntheticContentionScenario(
            analysisConcurrency: 2,
            prepareAheadLimit: 0
        )
        let pipelinedSingleAnalysis = await runSyntheticContentionScenario(
            analysisConcurrency: 1,
            prepareAheadLimit: 1
        )

        let dualMilliseconds = Double(dualAnalysis.elapsedNanoseconds) / 1_000_000
        let pipelinedMilliseconds = Double(pipelinedSingleAnalysis.elapsedNanoseconds) / 1_000_000
        print(
            String(
                format: "[RunCoordinatorTests] synthetic contention benchmark dual=%.1fms pipelined=%.1fms",
                dualMilliseconds,
                pipelinedMilliseconds
            )
        )

        XCTAssertEqual(dualAnalysis.summary.progress.failed, 0)
        XCTAssertEqual(pipelinedSingleAnalysis.summary.progress.failed, 0)
        XCTAssertGreaterThanOrEqual(dualAnalysis.maxActiveAnalyses, 2)
        XCTAssertEqual(pipelinedSingleAnalysis.maxActiveAnalyses, 1)
        XCTAssertLessThan(
            pipelinedSingleAnalysis.elapsedNanoseconds,
            dualAnalysis.elapsedNanoseconds - 80_000_000
        )
    }

    private func defaultRunOptions() -> RunOptions {
        RunOptions(
            source: .library,
            optionalCaptureDateRange: nil,
            overwriteAppOwnedSameOrNewer: false
        )
    }

    private func defaultCapabilities() -> AppCapabilities {
        AppCapabilities(
            photosAutomationAvailable: true,
            qwenModelAvailable: true,
            pickerCapability: .supported
        )
    }

    private func runSyntheticContentionScenario(
        analysisConcurrency: Int,
        prepareAheadLimit: Int
    ) async -> SyntheticContentionResult {
        let assets = makeAssets(count: 4)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })
        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            exportDelayNanoseconds: 80_000_000
        )
        let analyzerState = ContentionAwareAnalyzerState(
            result: GeneratedMetadata(caption: "caption", keywords: ["k1"]),
            baseDelayNanoseconds: 150_000_000,
            concurrentPenaltyNanoseconds: 220_000_000
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: ContentionAwareAnalyzer(state: analyzerState),
            analysisConcurrency: analysisConcurrency,
            prepareAheadLimit: prepareAheadLimit
        )

        let started = DispatchTime.now().uptimeNanoseconds
        let summary = await coordinator.run(
            options: defaultRunOptions(),
            capabilities: defaultCapabilities(),
            callbacks: RunCallbacks()
        )
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let maxActiveAnalyses = await analyzerState.maxActiveCountValue()

        return SyntheticContentionResult(
            summary: summary,
            elapsedNanoseconds: elapsed,
            maxActiveAnalyses: maxActiveAnalyses
        )
    }

    private func makeAssets(count: Int) -> [MediaAsset] {
        (0..<count).map { index in
            MediaAsset(
                id: "asset-\(index)",
                filename: "IMG_\(index).jpg",
                captureDate: Date(),
                kind: .photo
            )
        }
    }

    private func makeCaptionWorkflowAlbums() -> [AlbumSummary] {
        [
            AlbumSummary(id: "cw-0", name: CaptionWorkflowAlbumStage.priorityCaptioning.rawValue, itemCount: 0),
            AlbumSummary(id: "cw-1", name: CaptionWorkflowAlbumStage.noCaptionNewPhotos.rawValue, itemCount: 0),
            AlbumSummary(id: "cw-2", name: CaptionWorkflowAlbumStage.noCaptionAll.rawValue, itemCount: 0),
            AlbumSummary(id: "cw-3", name: CaptionWorkflowAlbumStage.olderCaptionLogic.rawValue, itemCount: 0)
        ]
    }

    private func makeCaptionWorkflowConfiguration() -> CaptionWorkflowConfiguration {
        CaptionWorkflowConfiguration(assignments: [
            CaptionWorkflowAlbumAssignment(
                stage: .priorityCaptioning,
                albumID: "cw-0",
                albumName: CaptionWorkflowAlbumStage.priorityCaptioning.rawValue
            ),
            CaptionWorkflowAlbumAssignment(
                stage: .noCaptionNewPhotos,
                albumID: "cw-1",
                albumName: CaptionWorkflowAlbumStage.noCaptionNewPhotos.rawValue
            ),
            CaptionWorkflowAlbumAssignment(
                stage: .noCaptionAll,
                albumID: "cw-2",
                albumName: CaptionWorkflowAlbumStage.noCaptionAll.rawValue
            ),
            CaptionWorkflowAlbumAssignment(
                stage: .olderCaptionLogic,
                albumID: "cw-3",
                albumName: CaptionWorkflowAlbumStage.olderCaptionLogic.rawValue
            )
        ])
    }
}

private struct SyntheticContentionResult {
    let summary: RunSummary
    let elapsedNanoseconds: UInt64
    let maxActiveAnalyses: Int
}

private actor TimelineRecorder {
    private var timestamps: [String: UInt64] = [:]

    func record(_ event: String) {
        timestamps[event] = DispatchTime.now().uptimeNanoseconds
    }

    func timestamp(for event: String) -> UInt64? {
        timestamps[event]
    }
}

private actor ContentionAwareAnalyzerState {
    private let result: GeneratedMetadata
    private let baseDelayNanoseconds: UInt64
    private let concurrentPenaltyNanoseconds: UInt64
    private let timelineRecorder: TimelineRecorder?
    private var activeCount = 0
    private var maxActiveCount = 0

    init(
        result: GeneratedMetadata,
        baseDelayNanoseconds: UInt64,
        concurrentPenaltyNanoseconds: UInt64,
        timelineRecorder: TimelineRecorder? = nil
    ) {
        self.result = result
        self.baseDelayNanoseconds = baseDelayNanoseconds
        self.concurrentPenaltyNanoseconds = concurrentPenaltyNanoseconds
        self.timelineRecorder = timelineRecorder
    }

    func begin(assetID: String) async -> (delayNanoseconds: UInt64, result: GeneratedMetadata) {
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        await timelineRecorder?.record("analyze-start:\(assetID)")
        let contentionPenalty = concurrentPenaltyNanoseconds * UInt64(max(0, activeCount - 1))
        return (baseDelayNanoseconds + contentionPenalty, result)
    }

    func end(assetID: String) async {
        await timelineRecorder?.record("analyze-end:\(assetID)")
        activeCount = max(0, activeCount - 1)
    }

    func maxActiveCountValue() -> Int {
        maxActiveCount
    }
}

private struct ContentionAwareAnalyzer: Analyzer {
    let state: ContentionAwareAnalyzerState

    func analyze(input: AnalysisInput, kind _: MediaKind) async throws -> GeneratedMetadata {
        let assetID = analysisInputAssetID(input)
        let (delayNanoseconds, result) = await state.begin(assetID: assetID)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        await state.end(assetID: assetID)
        return result
    }
}

private actor PreparedOverlapAnalyzerState {
    private let result: GeneratedMetadata
    private let preparationDelayNanoseconds: UInt64
    private let analysisDelayNanoseconds: UInt64
    private let timelineRecorder: TimelineRecorder?
    private var activeCount = 0
    private var maxActiveCount = 0

    init(
        result: GeneratedMetadata,
        preparationDelayNanoseconds: UInt64,
        analysisDelayNanoseconds: UInt64,
        timelineRecorder: TimelineRecorder? = nil
    ) {
        self.result = result
        self.preparationDelayNanoseconds = preparationDelayNanoseconds
        self.analysisDelayNanoseconds = analysisDelayNanoseconds
        self.timelineRecorder = timelineRecorder
    }

    func beginPreparation(assetID: String) async -> UInt64 {
        await timelineRecorder?.record("prepare-start:\(assetID)")
        return preparationDelayNanoseconds
    }

    func endPreparation(assetID: String) async {
        await timelineRecorder?.record("prepare-end:\(assetID)")
    }

    func beginAnalysis(assetID: String) async -> (delayNanoseconds: UInt64, result: GeneratedMetadata) {
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        await timelineRecorder?.record("analyze-start:\(assetID)")
        return (analysisDelayNanoseconds, result)
    }

    func endAnalysis(assetID: String) async {
        await timelineRecorder?.record("analyze-end:\(assetID)")
        activeCount = max(0, activeCount - 1)
    }

    func maxActiveCountValue() -> Int {
        maxActiveCount
    }
}

private struct PreparedOverlapAnalyzer: PreparedInputAnalyzer {
    let state: PreparedOverlapAnalyzerState

    func analyze(input: AnalysisInput, kind: MediaKind) async throws -> GeneratedMetadata {
        let payload = try await prepareAnalysis(input: input, kind: kind)
        return try await analyze(preparedPayload: payload)
    }

    func prepareAnalysis(input: AnalysisInput, kind: MediaKind) async throws -> PreparedAnalysisPayload {
        let assetID = analysisInputAssetID(input)
        let delayNanoseconds = await state.beginPreparation(assetID: assetID)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        await state.endPreparation(assetID: assetID)
        return PreparedAnalysisPayload(prompt: assetID, images: [])
    }

    func analyze(preparedPayload: PreparedAnalysisPayload) async throws -> GeneratedMetadata {
        let assetID = preparedPayload.prompt
        let (delayNanoseconds, result) = await state.beginAnalysis(assetID: assetID)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        await state.endAnalysis(assetID: assetID)
        return result
    }
}

private actor MockPreviewRenderer: PreviewRendering {
    private let delayNanoseconds: UInt64
    private let timelineRecorder: TimelineRecorder?

    init(delayNanoseconds: UInt64 = 0, timelineRecorder: TimelineRecorder? = nil) {
        self.delayNanoseconds = delayNanoseconds
        self.timelineRecorder = timelineRecorder
    }

    func persistPreviewFile(
        from input: AnalysisInput,
        assetID: String,
        fallbackFilename: String,
        kind _: MediaKind
    ) async -> URL? {
        await timelineRecorder?.record("preview-start:\(assetID)")
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        let fallbackExtension = (fallbackFilename as NSString).pathExtension
        let pathExtension: String
        switch input {
        case let .fileURL(inputURL):
            pathExtension = inputURL.pathExtension.isEmpty
                ? (fallbackExtension.isEmpty ? "jpg" : fallbackExtension)
                : inputURL.pathExtension
        case .photoPreviewJPEGData:
            pathExtension = "jpg"
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdc-tests-rendered-preview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let fileURL = root.appendingPathComponent("preview.\(pathExtension)")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
            await timelineRecorder?.record("preview-end:\(assetID)")
            return fileURL
        } catch {
            await timelineRecorder?.record("preview-end:\(assetID)")
            return nil
        }
    }
}

private actor RecordingPreviewRenderer: PreviewRendering {
    private let recorder: AnalysisInputRecorder

    init(recorder: AnalysisInputRecorder) {
        self.recorder = recorder
    }

    func persistPreviewFile(
        from input: AnalysisInput,
        assetID _: String,
        fallbackFilename _: String,
        kind _: MediaKind
    ) async -> URL? {
        switch input {
        case .fileURL:
            await recorder.record("file-url")
        case .photoPreviewJPEGData:
            await recorder.record("photo-preview-data")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdc-tests-rendered-preview-recording", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("preview.jpg")

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: fileURL.path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))
            return fileURL
        } catch {
            return nil
        }
    }
}

private actor PromptRecorder {
    private(set) var checkpoints: [Int] = []
    private(set) var externalPromptCount = 0
    private(set) var safetyPromptTitles: [String] = []

    func recordCheckpoint(_ changed: Int) {
        checkpoints.append(changed)
    }

    func recordExternalPrompt() {
        externalPromptCount += 1
    }

    func recordSafetyPrompt(_ prompt: RunSafetyPausePrompt) {
        safetyPromptTitles.append(prompt.title)
    }

    func externalPromptCountValue() -> Int {
        externalPromptCount
    }

    func checkpointsValue() -> [Int] {
        checkpoints
    }

    func safetyPromptTitlesValue() -> [String] {
        safetyPromptTitles
    }

}

private actor AnalysisInputRecorder {
    private var valuesStorage: [String] = []

    func record(_ value: String) {
        valuesStorage.append(value)
    }

    func values() -> [String] {
        valuesStorage
    }
}

private actor MockScopedIncrementalScanSource: ScopedIncrementalScanSource {
    private let assets: [MediaAsset]
    private let supportedAlbumIDs: Set<String>
    private let supportsLibrary: Bool
    private let albumAssetIDsByID: [String: [String]]
    private(set) var countCallCount = 0
    private(set) var enumeratePageCallCount = 0

    init(
        assets: [MediaAsset],
        supportedAlbumIDs: Set<String> = [],
        supportsLibrary: Bool = true,
        albumAssetIDsByID: [String: [String]] = [:]
    ) {
        self.assets = assets
        self.supportedAlbumIDs = supportedAlbumIDs
        self.supportsLibrary = supportsLibrary
        self.albumAssetIDsByID = albumAssetIDsByID
    }

    func canHandleIncrementalScan(scope: ScopeSource) async -> Bool {
        switch scope {
        case .library:
            return supportsLibrary
        case let .album(id):
            return supportedAlbumIDs.contains(id)
        case .picker, .captionWorkflow:
            return false
        }
    }

    func count(scope: ScopeSource) async throws -> Int {
        countCallCount += 1
        return try selectedAssets(for: scope).count
    }

    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset] {
        enumeratePageCallCount += 1
        let selected = try selectedAssets(for: scope)
        guard offset < selected.count, limit > 0 else { return [] }
        let end = min(offset + limit, selected.count)
        return Array(selected[offset..<end])
    }

    func countCallCountValue() async -> Int {
        countCallCount
    }

    func enumeratePageCallCountValue() async -> Int {
        enumeratePageCallCount
    }

    private func selectedAssets(for scope: ScopeSource) throws -> [MediaAsset] {
        switch scope {
        case .library:
            return assets
        case let .album(id):
            guard let assetIDs = albumAssetIDsByID[id] else {
                throw ExperimentalPhotoKitScanError.albumNotFound(id)
            }
            let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            return assetIDs.compactMap { assetsByID[$0] }
        case .picker:
            throw ExperimentalPhotoKitScanError.unsupportedScope("picker")
        case .captionWorkflow:
            throw ExperimentalPhotoKitScanError.unsupportedScope("captionWorkflow")
        }
    }
}

private actor MockPhotosWriter: PhotosWriter, PhotosProcessMonitoring, PhotosLifecycleControlling, PhotoPreviewSource, PhotoPreviewDataSource, BatchMetadataPhotosWriter, BatchWritePhotosWriter, IncrementalPhotosWriter, AlbumListingPhotosSource {
    private let assets: [MediaAsset]
    private let photosResidentMemoryBytesValue: UInt64?
    private let previewDataByID: [String: Data]
    private let metadataReadDelayByID: [String: UInt64]
    private let enumerateTimeoutWhenLimitExceeds: Int?
    private let exportDelayNanoseconds: UInt64
    private let exportDelayByID: [String: UInt64]
    private let timelineRecorder: TimelineRecorder?
    private let quitResults: [Bool]
    private let waitForReadyResults: [Bool]
    private let listedAlbums: [AlbumSummary]
    private let albumAssetIDSequenceByID: [String: [[String]]]
    private let removeWrittenAssetsFromAllAlbums: Bool
    private var metadataByID: [String: ExistingMetadataState]
    private var albumAssetIDsByID: [String: [String]]
    private var directEnumerateTimeoutsRemainingByAlbumID: [String: Int]
    private var directAlbumEnumerateCallCounts: [String: Int] = [:]
    private var pagedEnumerateSessionAssetsByAlbumID: [String: [MediaAsset]] = [:]
    private var isPhotosRunning = true
    private var quitResultIndex = 0
    private var waitForReadyResultIndex = 0
    private(set) var writes: [String: (caption: String, keywords: [String])] = [:]
    private(set) var writeOrder: [String] = []
    private(set) var previewRequests: [String] = []
    private(set) var previewRequestedPixelSizes: [Int] = []
    private(set) var exportRequests: [String] = []
    private(set) var batchReadSizes: [Int] = []
    private(set) var batchWriteSizes: [Int] = []
    private(set) var enumeratePageCallCount = 0
    private(set) var firstWriteAfterEnumeratePageCount: Int?
    private(set) var countCallCount = 0
    private(set) var quitRequestCount = 0
    private(set) var launchRequestCount = 0
    private(set) var waitForReadyCallCount = 0
    private(set) var listUserAlbumsCallCount = 0

    init(
        assets: [MediaAsset],
        metadataByID: [String: ExistingMetadataState],
        photosResidentMemoryBytes: UInt64? = nil,
        previewDataByID: [String: Data] = [:],
        metadataReadDelayByID: [String: UInt64] = [:],
        enumerateTimeoutWhenLimitExceeds: Int? = nil,
        exportDelayNanoseconds: UInt64 = 0,
        exportDelayByID: [String: UInt64] = [:],
        quitResults: [Bool] = [],
        waitForReadyResults: [Bool] = [],
        listedAlbums: [AlbumSummary] = [],
        albumAssetIDsByID: [String: [String]] = [:],
        albumAssetIDSequenceByID: [String: [[String]]] = [:],
        directEnumerateTimeoutsByAlbumID: [String: Int] = [:],
        removeWrittenAssetsFromAllAlbums: Bool = false,
        timelineRecorder: TimelineRecorder? = nil
    ) {
        self.assets = assets
        self.metadataByID = metadataByID
        self.photosResidentMemoryBytesValue = photosResidentMemoryBytes
        self.previewDataByID = previewDataByID
        self.metadataReadDelayByID = metadataReadDelayByID
        self.enumerateTimeoutWhenLimitExceeds = enumerateTimeoutWhenLimitExceeds
        self.exportDelayNanoseconds = exportDelayNanoseconds
        self.exportDelayByID = exportDelayByID
        self.quitResults = quitResults
        self.waitForReadyResults = waitForReadyResults
        self.listedAlbums = listedAlbums
        self.albumAssetIDsByID = albumAssetIDsByID
        self.albumAssetIDSequenceByID = albumAssetIDSequenceByID
        self.directEnumerateTimeoutsRemainingByAlbumID = directEnumerateTimeoutsByAlbumID
        self.removeWrittenAssetsFromAllAlbums = removeWrittenAssetsFromAllAlbums
        self.timelineRecorder = timelineRecorder
    }

    private func captionWorkflowMisuseError() -> NSError {
        NSError(
            domain: "MockPhotosWriter",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(AppPresentation.queuedAlbumsTitle) must be resolved before direct enumeration."]
        )
    }

    private func materializedAssets(for assetIDs: [String]) -> [MediaAsset] {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        return assetIDs.compactMap { assetsByID[$0] }
    }

    private func stableResolvedAssets(forAlbumID albumID: String) -> [MediaAsset] {
        if let orderedAssetIDs = albumAssetIDsByID[albumID] {
            return materializedAssets(for: orderedAssetIDs)
        }
        return assets.filter { $0.id.contains(albumID) }
    }

    private func resolvedAssets(forAlbumID albumID: String) throws -> [MediaAsset] {
        if let remainingTimeouts = directEnumerateTimeoutsRemainingByAlbumID[albumID], remainingTimeouts > 0 {
            directEnumerateTimeoutsRemainingByAlbumID[albumID] = remainingTimeouts - 1
            throw PhotosAppleScriptError.scriptTimedOut(operation: "enumerate assets", timeoutSeconds: 180)
        }

        let callCount = directAlbumEnumerateCallCounts[albumID, default: 0]
        directAlbumEnumerateCallCounts[albumID] = callCount + 1

        if let sequences = albumAssetIDSequenceByID[albumID], !sequences.isEmpty {
            let index = min(callCount, sequences.count - 1)
            return materializedAssets(for: sequences[index])
        }

        return stableResolvedAssets(forAlbumID: albumID)
    }

    func listUserAlbums() async throws -> [AlbumSummary] {
        listUserAlbumsCallCount += 1
        guard !listedAlbums.isEmpty else { return [] }

        return listedAlbums.map { album in
            let itemCount = albumAssetIDsByID[album.id]?.count ?? album.itemCount
            return AlbumSummary(id: album.id, name: album.name, itemCount: itemCount)
        }
    }

    func enumerate(scope: ScopeSource, dateRange: CaptureDateRange?) async throws -> [MediaAsset] {
        var selected: [MediaAsset]
        switch scope {
        case .library:
            selected = assets
        case let .album(id):
            selected = try resolvedAssets(forAlbumID: id)
        case let .picker(ids):
            let idSet = Set(ids)
            selected = assets.filter { idSet.contains($0.id) }
        case .captionWorkflow:
            throw captionWorkflowMisuseError()
        }

        if let dateRange {
            selected = selected.filter { dateRange.contains($0.captureDate) }
        }

        return selected
    }

    func readMetadata(id: String) async throws -> ExistingMetadataState {
        await timelineRecorder?.record("metadata-read-start:\(id)")
        if let delayNanoseconds = metadataReadDelayByID[id], delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        await timelineRecorder?.record("metadata-read-end:\(id)")
        return metadataByID[id] ?? ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
    }

    func count(scope: ScopeSource) async throws -> Int {
        countCallCount += 1
        let selected: [MediaAsset]
        switch scope {
        case .library:
            selected = assets
        case let .album(id):
            selected = stableResolvedAssets(forAlbumID: id)
        case let .picker(ids):
            let idSet = Set(ids)
            selected = assets.filter { idSet.contains($0.id) }
        case .captionWorkflow:
            throw captionWorkflowMisuseError()
        }
        return selected.count
    }

    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset] {
        enumeratePageCallCount += 1
        let selected: [MediaAsset]
        switch scope {
        case .library:
            selected = assets
        case let .album(id):
            if offset == 0 {
                let refreshedAssets = try resolvedAssets(forAlbumID: id)
                pagedEnumerateSessionAssetsByAlbumID[id] = refreshedAssets
                selected = refreshedAssets
            } else {
                selected = pagedEnumerateSessionAssetsByAlbumID[id] ?? stableResolvedAssets(forAlbumID: id)
            }
        case let .picker(ids):
            let idSet = Set(ids)
            selected = assets.filter { idSet.contains($0.id) }
        case .captionWorkflow:
            throw captionWorkflowMisuseError()
        }
        guard offset < selected.count, limit > 0 else { return [] }
        if let threshold = enumerateTimeoutWhenLimitExceeds, limit > threshold {
            throw PhotosAppleScriptError.scriptTimedOut(operation: "enumerate page", timeoutSeconds: 45)
        }
        let end = min(offset + limit, selected.count)
        return Array(selected[offset..<end])
    }

    func readMetadata(ids: [String]) async throws -> [String: ExistingMetadataState] {
        batchReadSizes.append(ids.count)
        var batch: [String: ExistingMetadataState] = [:]
        for id in ids {
            batch[id] = metadataByID[id] ?? ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
        }
        return batch
    }

    func writeMetadata(id: String, caption: String, keywords: [String]) async throws {
        await timelineRecorder?.record("write-start:\(id)")
        if firstWriteAfterEnumeratePageCount == nil {
            firstWriteAfterEnumeratePageCount = enumeratePageCallCount
        }
        writes[id] = (caption: caption, keywords: keywords)
        writeOrder.append(id)
        if removeWrittenAssetsFromAllAlbums {
            for albumID in albumAssetIDsByID.keys {
                albumAssetIDsByID[albumID]?.removeAll { $0 == id }
            }
        }
        pagedEnumerateSessionAssetsByAlbumID.removeAll(keepingCapacity: true)
        let tag = OwnershipTagCodec.extract(from: keywords)
        metadataByID[id] = ExistingMetadataState(
            caption: caption,
            keywords: keywords,
            ownershipTag: tag,
            isExternal: false
        )
        await timelineRecorder?.record("write-end:\(id)")
    }

    func writeMetadata(batch writes: [MetadataWritePayload]) async throws -> [MetadataWriteResult] {
        batchWriteSizes.append(writes.count)
        var results: [MetadataWriteResult] = []
        results.reserveCapacity(writes.count)
        for write in writes {
            do {
                try await writeMetadata(id: write.id, caption: write.caption, keywords: write.keywords)
                results.append(MetadataWriteResult(id: write.id, success: true))
            } catch {
                results.append(
                    MetadataWriteResult(
                        id: write.id,
                        success: false,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }
        return results
    }

    func exportAssetToTemporaryURL(id: String, kind _: MediaKind) async throws -> URL {
        exportRequests.append(id)
        await timelineRecorder?.record("export-start:\(id)")
        let delayNanoseconds = exportDelayByID[id] ?? exportDelayNanoseconds
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdc-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("\(id).jpg")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        await timelineRecorder?.record("export-end:\(id)")
        return fileURL
    }

    func photoPreviewToTemporaryURL(id: String, maxPixelSize: Int) async throws -> URL? {
        guard let data = try await photoPreviewJPEGData(id: id, maxPixelSize: maxPixelSize) else {
            return nil
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdc-tests-preview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("\(id).jpg")
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    func photoPreviewJPEGData(id: String, maxPixelSize: Int) async throws -> Data? {
        previewRequests.append(id)
        previewRequestedPixelSizes.append(maxPixelSize)
        return previewDataByID[id]
    }

    func isPhotosAppRunning() async -> Bool {
        isPhotosRunning
    }

    func quitPhotosAppGracefully() async -> Bool {
        quitRequestCount += 1
        let result = quitResults.indices.contains(quitResultIndex) ? quitResults[quitResultIndex] : true
        if quitResultIndex < quitResults.count {
            quitResultIndex += 1
        }
        if result {
            isPhotosRunning = false
        }
        return result
    }

    func launchPhotosApp() async throws {
        launchRequestCount += 1
        isPhotosRunning = true
    }

    func waitForPhotosReady(timeoutSeconds _: TimeInterval) async -> Bool {
        waitForReadyCallCount += 1
        let result = waitForReadyResults.indices.contains(waitForReadyResultIndex)
            ? waitForReadyResults[waitForReadyResultIndex]
            : true
        if waitForReadyResultIndex < waitForReadyResults.count {
            waitForReadyResultIndex += 1
        }
        return result
    }

    func photosResidentMemoryBytes() async -> UInt64? {
        photosResidentMemoryBytesValue
    }

    func previewRequestsValue() async -> [String] {
        previewRequests
    }

    func exportRequestsValue() async -> [String] {
        exportRequests
    }

    func previewRequestedPixelSizesValue() async -> [Int] {
        previewRequestedPixelSizes
    }

    func writeOrderValue() async -> [String] {
        writeOrder
    }

    func batchReadSizesValue() async -> [Int] {
        batchReadSizes
    }

    func batchWriteSizesValue() async -> [Int] {
        batchWriteSizes
    }

    func enumeratePageCallCountValue() async -> Int {
        enumeratePageCallCount
    }

    func firstWriteAfterEnumeratePageCountValue() async -> Int? {
        firstWriteAfterEnumeratePageCount
    }

    func countCallCountValue() async -> Int {
        countCallCount
    }

    func quitRequestCountValue() async -> Int {
        quitRequestCount
    }

    func launchRequestCountValue() async -> Int {
        launchRequestCount
    }

    func waitForReadyCallCountValue() async -> Int {
        waitForReadyCallCount
    }

    func listUserAlbumsCallCountValue() async -> Int {
        listUserAlbumsCallCount
    }
}

private struct MockAnalyzer: Analyzer {
    let result: GeneratedMetadata

    func analyze(input _: AnalysisInput, kind _: MediaKind) async throws -> GeneratedMetadata {
        result
    }
}

private struct RecordingAnalyzer: Analyzer {
    let result: GeneratedMetadata
    let recorder: AnalysisInputRecorder

    func analyze(input: AnalysisInput, kind _: MediaKind) async throws -> GeneratedMetadata {
        switch input {
        case .fileURL:
            await recorder.record("file-url")
        case .photoPreviewJPEGData:
            await recorder.record("photo-preview-data")
        }
        return result
    }
}

private struct ConditionalFailAnalyzer: Analyzer {
    let failedAssetIDs: Set<String>
    let successResult: GeneratedMetadata

    init(failedAssetIDs: [String], successResult: GeneratedMetadata) {
        self.failedAssetIDs = Set(failedAssetIDs)
        self.successResult = successResult
    }

    func analyze(input: AnalysisInput, kind _: MediaKind) async throws -> GeneratedMetadata {
        let stem = analysisInputAssetID(input)
        if failedAssetIDs.contains(stem) {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "intentional failure"])
        }
        return successResult
    }
}

private func analysisInputAssetID(_ input: AnalysisInput) -> String {
    switch input {
    case let .fileURL(url):
        return url.deletingPathExtension().lastPathComponent
    case let .photoPreviewJPEGData(data):
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "photo-preview"
    }
}

private final class StatusRecorder {
    private let lock = NSLock()
    private var messages: [String] = []

    func record(status: String?) {
        guard let status else { return }
        lock.lock()
        messages.append(status)
        lock.unlock()
    }

    func values() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

private final class PreviewRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var previews: [CompletedItemPreview] = []

    func record(preview: CompletedItemPreview) {
        lock.lock()
        previews.append(preview)
        lock.unlock()
    }

    func firstValue() -> CompletedItemPreview? {
        lock.lock()
        defer { lock.unlock() }
        return previews.first
    }
}

private final class PreparationProgressRecorder {
    private let lock = NSLock()
    private var snapshots: [(Int, Int)] = []

    func record(enumerated: Int, total: Int) {
        lock.lock()
        defer { lock.unlock() }
        snapshots.append((enumerated, total))
    }

    func snapshotsValue() -> [(Int, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return snapshots
    }
}
