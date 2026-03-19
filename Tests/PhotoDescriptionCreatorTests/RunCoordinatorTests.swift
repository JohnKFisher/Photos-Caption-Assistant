import Foundation
import XCTest
@testable import PhotoDescriptionCreator

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
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
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
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
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
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"]))
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
        XCTAssertEqual(summary.progress.changed, assets.count)
        XCTAssertFalse(batchReadSizes.isEmpty)
        XCTAssertEqual(batchReadSizes.reduce(0, +), assets.count)
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

    func analyze(mediaURL: URL, kind: MediaKind) async throws -> GeneratedMetadata {
        let assetID = mediaURL.deletingPathExtension().lastPathComponent
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

    func analyze(mediaURL: URL, kind: MediaKind) async throws -> GeneratedMetadata {
        let payload = try await prepareAnalysis(mediaURL: mediaURL, kind: kind)
        return try await analyze(preparedPayload: payload)
    }

    func prepareAnalysis(mediaURL: URL, kind: MediaKind) async throws -> PreparedAnalysisPayload {
        let assetID = mediaURL.deletingPathExtension().lastPathComponent
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

    func persistPreviewFile(from inputURL: URL, fallbackFilename: String, kind: MediaKind) async -> URL? {
        let assetID = inputURL.deletingPathExtension().lastPathComponent
        await timelineRecorder?.record("preview-start:\(assetID)")
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        let fallbackExtension = (fallbackFilename as NSString).pathExtension
        let pathExtension = inputURL.pathExtension.isEmpty
            ? (fallbackExtension.isEmpty ? "jpg" : fallbackExtension)
            : inputURL.pathExtension
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

private actor MockPhotosWriter: PhotosWriter, PhotosProcessMonitoring, PhotosLifecycleControlling, PhotoPreviewSource, BatchMetadataPhotosWriter, BatchWritePhotosWriter, IncrementalPhotosWriter {
    private let assets: [MediaAsset]
    private let photosResidentMemoryBytesValue: UInt64?
    private let previewDataByID: [String: Data]
    private let enumerateTimeoutWhenLimitExceeds: Int?
    private let exportDelayNanoseconds: UInt64
    private let exportDelayByID: [String: UInt64]
    private let timelineRecorder: TimelineRecorder?
    private let quitResults: [Bool]
    private let waitForReadyResults: [Bool]
    private var metadataByID: [String: ExistingMetadataState]
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

    init(
        assets: [MediaAsset],
        metadataByID: [String: ExistingMetadataState],
        photosResidentMemoryBytes: UInt64? = nil,
        previewDataByID: [String: Data] = [:],
        enumerateTimeoutWhenLimitExceeds: Int? = nil,
        exportDelayNanoseconds: UInt64 = 0,
        exportDelayByID: [String: UInt64] = [:],
        quitResults: [Bool] = [],
        waitForReadyResults: [Bool] = [],
        timelineRecorder: TimelineRecorder? = nil
    ) {
        self.assets = assets
        self.metadataByID = metadataByID
        self.photosResidentMemoryBytesValue = photosResidentMemoryBytes
        self.previewDataByID = previewDataByID
        self.enumerateTimeoutWhenLimitExceeds = enumerateTimeoutWhenLimitExceeds
        self.exportDelayNanoseconds = exportDelayNanoseconds
        self.exportDelayByID = exportDelayByID
        self.quitResults = quitResults
        self.waitForReadyResults = waitForReadyResults
        self.timelineRecorder = timelineRecorder
    }

    func enumerate(scope: ScopeSource, dateRange: CaptureDateRange?) async throws -> [MediaAsset] {
        var selected: [MediaAsset]
        switch scope {
        case .library:
            selected = assets
        case let .album(id):
            selected = assets.filter { $0.id.contains(id) }
        case let .picker(ids):
            let idSet = Set(ids)
            selected = assets.filter { idSet.contains($0.id) }
        }

        if let dateRange {
            selected = selected.filter { dateRange.contains($0.captureDate) }
        }

        return selected
    }

    func readMetadata(id: String) async throws -> ExistingMetadataState {
        metadataByID[id] ?? ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
    }

    func count(scope: ScopeSource) async throws -> Int {
        countCallCount += 1
        let selected = try await enumerate(scope: scope, dateRange: nil)
        return selected.count
    }

    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset] {
        enumeratePageCallCount += 1
        let selected = try await enumerate(scope: scope, dateRange: nil)
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
        previewRequests.append(id)
        previewRequestedPixelSizes.append(maxPixelSize)
        guard let data = previewDataByID[id] else {
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
}

private struct MockAnalyzer: Analyzer {
    let result: GeneratedMetadata

    func analyze(mediaURL: URL, kind: MediaKind) async throws -> GeneratedMetadata {
        result
    }
}

private struct ConditionalFailAnalyzer: Analyzer {
    let failedAssetIDs: Set<String>
    let successResult: GeneratedMetadata

    init(failedAssetIDs: [String], successResult: GeneratedMetadata) {
        self.failedAssetIDs = Set(failedAssetIDs)
        self.successResult = successResult
    }

    func analyze(mediaURL: URL, kind: MediaKind) async throws -> GeneratedMetadata {
        let stem = mediaURL.deletingPathExtension().lastPathComponent
        if failedAssetIDs.contains(stem) {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "intentional failure"])
        }
        return successResult
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
