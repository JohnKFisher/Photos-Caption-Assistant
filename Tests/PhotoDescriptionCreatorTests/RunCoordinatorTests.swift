import Foundation
import XCTest
@testable import PhotoDescriptionCreator

@MainActor
final class RunCoordinatorTests: XCTestCase {
    func testCheckpointPromptFiresAt250Intervals() async {
        let assets = makeAssets(count: 760)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 250
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
                confirmExternalOverwrite: { _, _ in
                    XCTFail("No external prompt expected")
                    return false
                },
                confirmContinueAfterCheckpoint: { changed in
                    await recorder.recordCheckpoint(changed)
                    return true
                }
            )
        )

        let checkpoints = await recorder.checkpointsValue()
        XCTAssertEqual(checkpoints, [250, 500, 750])
        XCTAssertEqual(summary.progress.changed, 760)
        XCTAssertEqual(summary.progress.failed, 0)
        XCTAssertEqual(summary.progress.skipped, 0)
    }

    func testPhotosRefreshPromptFiresAtConfiguredInterval() async {
        let assets = makeAssets(count: 620)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(assets: assets, metadataByID: metadata)
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 1000,
            photosRefreshPromptInterval: 300,
            photosMemoryCheckInterval: 10_000
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
                confirmContinueAfterCheckpoint: { _ in true },
                confirmSafetyPause: { prompt in
                    await recorder.recordSafetyPrompt(prompt)
                    return true
                }
            )
        )

        let safetyTitles = await recorder.safetyPromptTitlesValue()
        XCTAssertEqual(safetyTitles, ["Refresh Photos Before Continuing?", "Refresh Photos Before Continuing?"])
        XCTAssertEqual(summary.progress.changed, 620)
        XCTAssertEqual(summary.progress.failed, 0)
    }

    func testHighPhotosMemoryPromptCanStopRun() async {
        let assets = makeAssets(count: 12)
        let metadata = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (asset.id, ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false))
        })

        let writer = MockPhotosWriter(
            assets: assets,
            metadataByID: metadata,
            photosResidentMemoryBytes: 25 * 1024 * 1024 * 1024
        )
        let coordinator = RunCoordinator(
            photosWriter: writer,
            analyzer: MockAnalyzer(result: GeneratedMetadata(caption: "caption", keywords: ["k1"])),
            checkpointInterval: 1000,
            photosRefreshPromptInterval: 1000,
            photosMemoryCheckInterval: 1,
            photosMemoryWarningBytes: 1024
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
                confirmContinueAfterCheckpoint: { _ in true },
                confirmSafetyPause: { prompt in
                    await recorder.recordSafetyPrompt(prompt)
                    return false
                }
            )
        )

        let safetyTitles = await recorder.safetyPromptTitlesValue()
        XCTAssertEqual(safetyTitles, ["Photos Memory Is High"])
        XCTAssertEqual(summary.progress.changed, 1)
        XCTAssertEqual(summary.progress.processed, 1)
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

private actor MockPhotosWriter: PhotosWriter, PhotosProcessMonitoring, PhotoPreviewSource, BatchMetadataPhotosWriter, IncrementalPhotosWriter {
    private let assets: [MediaAsset]
    private let photosResidentMemoryBytesValue: UInt64?
    private let previewDataByID: [String: Data]
    private var metadataByID: [String: ExistingMetadataState]
    private(set) var writes: [String: (caption: String, keywords: [String])] = [:]
    private(set) var writeOrder: [String] = []
    private(set) var previewRequests: [String] = []
    private(set) var previewRequestedPixelSizes: [Int] = []
    private(set) var exportRequests: [String] = []
    private(set) var batchReadSizes: [Int] = []
    private(set) var enumeratePageCallCount = 0
    private(set) var firstWriteAfterEnumeratePageCount: Int?
    private(set) var countCallCount = 0

    init(
        assets: [MediaAsset],
        metadataByID: [String: ExistingMetadataState],
        photosResidentMemoryBytes: UInt64? = nil,
        previewDataByID: [String: Data] = [:]
    ) {
        self.assets = assets
        self.metadataByID = metadataByID
        self.photosResidentMemoryBytesValue = photosResidentMemoryBytes
        self.previewDataByID = previewDataByID
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
    }

    func exportAssetToTemporaryURL(id: String) async throws -> URL {
        exportRequests.append(id)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdc-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("\(id).jpg")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
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
        true
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

    func enumeratePageCallCountValue() async -> Int {
        enumeratePageCallCount
    }

    func firstWriteAfterEnumeratePageCountValue() async -> Int? {
        firstWriteAfterEnumeratePageCount
    }

    func countCallCountValue() async -> Int {
        countCallCount
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
