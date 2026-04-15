import XCTest
@testable import PhotosCaptionAssistant

final class AppSettingsTests: XCTestCase {
    func testAppSettingsLoadConservativeDefaults() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let snapshot = AppSettings.load(from: defaults)

        XCTAssertEqual(snapshot, .default)
    }

    func testAppSettingsLoadStoredValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(SourceSelection.picker.rawValue, forKey: AppSettings.Keys.defaultSourceSelection)
        defaults.set(RunTraversalOrder.random.rawValue, forKey: AppSettings.Keys.defaultTraversalOrder)
        defaults.set(true, forKey: AppSettings.Keys.defaultOverwriteAppOwnedSameOrNewer)
        defaults.set(true, forKey: AppSettings.Keys.defaultAlwaysOverwriteExternalMetadata)
        defaults.set(PreviewOpenBehavior.fullScreenOnOpen.rawValue, forKey: AppSettings.Keys.previewOpenBehavior)

        let snapshot = AppSettings.load(from: defaults)

        XCTAssertEqual(snapshot.defaultSourceSelection, .picker)
        XCTAssertEqual(snapshot.defaultTraversalOrder, .random)
        XCTAssertTrue(snapshot.defaultOverwriteAppOwnedSameOrNewer)
        XCTAssertTrue(snapshot.defaultAlwaysOverwriteExternalMetadata)
        XCTAssertEqual(snapshot.previewOpenBehavior, .fullScreenOnOpen)
    }

    @MainActor
    func testViewModelAppliesStoredDefaultsAndPreviewState() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(SourceSelection.captionWorkflow.rawValue, forKey: AppSettings.Keys.defaultSourceSelection)
        defaults.set(RunTraversalOrder.newestToOldest.rawValue, forKey: AppSettings.Keys.defaultTraversalOrder)
        defaults.set(true, forKey: AppSettings.Keys.defaultOverwriteAppOwnedSameOrNewer)
        defaults.set(PreviewOpenBehavior.fullScreenOnOpen.rawValue, forKey: AppSettings.Keys.previewOpenBehavior)

        let viewModel = AppViewModel(appSettingsDefaults: defaults)

        XCTAssertEqual(viewModel.sourceSelection, .captionWorkflow)
        XCTAssertEqual(viewModel.traversalOrder, .newestToOldest)
        XCTAssertTrue(viewModel.overwriteAppOwnedSameOrNewer)
        XCTAssertEqual(viewModel.previewOpenBehavior, .fullScreenOnOpen)
        XCTAssertFalse(viewModel.canOpenPreviewWindow)

        let preview = CompletedItemPreview(
            assetID: "asset-1",
            filename: "IMG_0001.JPG",
            sourceContext: "Album",
            captureDate: Date(timeIntervalSince1970: 1_000),
            kind: .photo,
            previewFileURL: nil,
            caption: "A lighthouse",
            keywords: ["coast"]
        )

        viewModel.receiveCompletedItemPreview(preview, scheduleAdvance: false)

        XCTAssertTrue(viewModel.canOpenPreviewWindow)
        XCTAssertFalse(viewModel.canResumeSavedRun)
        viewModel.resumablePendingCount = 12
        XCTAssertTrue(viewModel.canResumeSavedRun)
    }
}
