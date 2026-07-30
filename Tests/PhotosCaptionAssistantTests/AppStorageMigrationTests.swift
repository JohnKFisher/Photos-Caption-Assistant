import Foundation
import XCTest
@testable import PhotosCaptionAssistant

final class AppStorageMigrationTests: XCTestCase {
    func testRunResumeStoreRoundTripsSessionAndReportsFailures() async throws {
        let root = try makeIsolatedRoot()
        let stateURL = root.appendingPathComponent("run-state.json")
        let sessionID = UUID()
        let state = PersistedRunState(
            runSessionID: sessionID,
            savedAt: Date(timeIntervalSince1970: 123),
            options: PersistedRunOptions(
                runOptions: RunOptions(
                    source: .picker(ids: ["asset-1"]),
                    optionalCaptureDateRange: nil,
                    overwriteAppOwnedSameOrNewer: false
                )
            ),
            pendingIDs: ["asset-1"]
        )

        let store = RunResumeStore(fileURL: stateURL)
        await store.beginSession(sessionID)
        assertSuccess(await store.save(state, for: sessionID))
        let loadedState = await store.load()
        XCTAssertEqual(loadedState, .success(state))
        let nextSessionID = UUID()
        await store.beginSession(nextSessionID)
        switch await store.save(state, for: nextSessionID) {
        case .success:
            XCTFail("Expected an older session snapshot to be rejected")
        case .failure(.staleSession):
            break
        case let .failure(error):
            XCTFail("Expected stale-session failure, got \(error)")
        }
        assertSuccess(await store.clear(for: nextSessionID))
        await store.endSession(nextSessionID)

        try Data("not-json".utf8).write(to: stateURL)
        let corruptStore = RunResumeStore(fileURL: stateURL)
        switch await corruptStore.load() {
        case .success:
            XCTFail("Expected corrupt JSON to be reported")
        case let .failure(error):
            guard case .corruptData = error else {
                return XCTFail("Expected corrupt-data failure, got \(error)")
            }
        }

        let failure = TestPersistenceError(message: "injected failure")
        let failingAccess = PersistenceFileAccess(
            fileExists: { _ in true },
            read: { _ in throw failure },
            createDirectory: { _ in throw failure },
            write: { _, _ in throw failure },
            remove: { _ in throw failure }
        )
        let failingStore = RunResumeStore(fileURL: stateURL, fileAccess: failingAccess)
        switch await failingStore.load() {
        case .success:
            XCTFail("Expected the injected read failure to be reported")
        case let .failure(error):
            guard case .corruptData = error else {
                return XCTFail("Expected corrupt-data failure, got \(error)")
            }
        }
        switch await failingStore.save(state) {
        case .success:
            XCTFail("Expected the injected save failure to be reported")
        case let .failure(error):
            guard case let .operationFailed(operation, _, _) = error else {
                return XCTFail("Expected save operation failure, got \(error)")
            }
            XCTAssertEqual(operation, "Saving run state")
        }
        switch await failingStore.clear() {
        case .success:
            XCTFail("Expected the injected clear failure to be reported")
        case let .failure(error):
            guard case let .operationFailed(operation, _, _) = error else {
                return XCTFail("Expected clear operation failure, got \(error)")
            }
            XCTAssertEqual(operation, "Clearing saved run state")
        }
    }

    func testCaptionWorkflowStoreRoundTripsAndReportsFailures() async throws {
        let root = try makeIsolatedRoot()
        let stateURL = root.appendingPathComponent("queued-albums.json")
        let configuration = CaptionWorkflowConfiguration(
            queue: [CaptionWorkflowQueueEntry(albumID: "album-1", albumName: "Album 1")]
        )

        let store = CaptionWorkflowConfigurationStore(fileURL: stateURL)
        assertSuccess(await store.save(configuration))
        let loadedConfiguration = await store.load()
        XCTAssertEqual(loadedConfiguration, .success(configuration))
        assertSuccess(await store.clear())

        let failure = TestPersistenceError(message: "injected failure")
        let failingAccess = PersistenceFileAccess(
            fileExists: { _ in true },
            read: { _ in throw failure },
            createDirectory: { _ in throw failure },
            write: { _, _ in throw failure },
            remove: { _ in throw failure }
        )
        let failingStore = CaptionWorkflowConfigurationStore(fileURL: stateURL, fileAccess: failingAccess)
        switch await failingStore.load() {
        case .success:
            XCTFail("Expected the injected read failure to be reported")
        case let .failure(error):
            guard case .corruptData = error else {
                return XCTFail("Expected corrupt-data failure, got \(error)")
            }
        }
        switch await failingStore.save(configuration) {
        case .success:
            XCTFail("Expected the injected save failure to be reported")
        case let .failure(error):
            guard case let .operationFailed(operation, _, _) = error else {
                return XCTFail("Expected save operation failure, got \(error)")
            }
            XCTAssertEqual(operation, "Saving queued-albums configuration")
        }
        switch await failingStore.clear() {
        case .success:
            XCTFail("Expected the injected clear failure to be reported")
        case let .failure(error):
            guard case let .operationFailed(operation, _, _) = error else {
                return XCTFail("Expected clear operation failure, got \(error)")
            }
            XCTAssertEqual(operation, "Clearing queued-albums configuration")
        }
    }

    func testAppStoragePathsUseRenamedLocations() throws {
        let fileManager = FileManager.default
        let root = try makeIsolatedRoot()
        let paths = AppStoragePaths.make(
            fileManager: fileManager,
            applicationSupportBase: root,
            temporaryDirectory: root
        )

        XCTAssertEqual(paths.applicationSupportDirectory.lastPathComponent, AppStoragePaths.applicationSupportDirectoryName)
        XCTAssertEqual(paths.legacyApplicationSupportDirectory.lastPathComponent, AppStoragePaths.legacyApplicationSupportDirectoryName)
        XCTAssertEqual(paths.benchmarkTempRoot.lastPathComponent, AppStoragePaths.benchmarkTempDirectoryName)
        XCTAssertEqual(paths.previewTempRoot.lastPathComponent, AppStoragePaths.previewTempDirectoryName)
        XCTAssertEqual(paths.photoExportTempRoot.lastPathComponent, AppStoragePaths.photoExportTempDirectoryName)
        XCTAssertEqual(paths.videoExportTempRoot.lastPathComponent, AppStoragePaths.videoExportTempDirectoryName)
        XCTAssertEqual(paths.photoPreviewTempRoot.lastPathComponent, AppStoragePaths.photoPreviewTempDirectoryName)
    }

    func testMigratorCopiesLegacyPersistentStateWhenNewFolderIsMissing() async throws {
        let fileManager = FileManager.default
        let root = try makeIsolatedRoot()
        let paths = AppStoragePaths.make(
            fileManager: fileManager,
            applicationSupportBase: root,
            temporaryDirectory: root
        )

        try fileManager.createDirectory(at: paths.legacyApplicationSupportDirectory, withIntermediateDirectories: true)
        let legacyRunState = Data("legacy-run-state".utf8)
        let legacyWorkflowState = Data("legacy-workflow-state".utf8)
        try legacyRunState.write(to: paths.legacyRunResumeStateFile)
        try legacyWorkflowState.write(to: paths.legacyCaptionWorkflowConfigurationFile)

        let migrator = AppStorageMigrator(paths: paths)
        await migrator.migrateLegacyPersistentStateIfNeeded()

        XCTAssertTrue(fileManager.fileExists(atPath: paths.runResumeStateFile.path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.captionWorkflowConfigurationFile.path))
        XCTAssertEqual(try Data(contentsOf: paths.runResumeStateFile), legacyRunState)
        XCTAssertEqual(try Data(contentsOf: paths.captionWorkflowConfigurationFile), legacyWorkflowState)
        XCTAssertTrue(fileManager.fileExists(atPath: paths.legacyRunResumeStateFile.path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.legacyCaptionWorkflowConfigurationFile.path))
    }

    func testMigratorDoesNothingWhenNewFolderAlreadyExists() async throws {
        let fileManager = FileManager.default
        let root = try makeIsolatedRoot()
        let paths = AppStoragePaths.make(
            fileManager: fileManager,
            applicationSupportBase: root,
            temporaryDirectory: root
        )

        try fileManager.createDirectory(at: paths.applicationSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.legacyApplicationSupportDirectory, withIntermediateDirectories: true)

        let existingRunState = Data("new-run-state".utf8)
        let legacyRunState = Data("legacy-run-state".utf8)
        try existingRunState.write(to: paths.runResumeStateFile)
        try legacyRunState.write(to: paths.legacyRunResumeStateFile)

        let migrator = AppStorageMigrator(paths: paths)
        await migrator.migrateLegacyPersistentStateIfNeeded()

        XCTAssertEqual(try Data(contentsOf: paths.runResumeStateFile), existingRunState)
        XCTAssertFalse(fileManager.fileExists(atPath: paths.captionWorkflowConfigurationFile.path))
    }

    private func makeIsolatedRoot() throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func assertSuccess<T>(_ result: Result<T, PersistenceStoreError>, file: StaticString = #filePath, line: UInt = #line) {
        if case let .failure(error) = result {
            XCTFail("Expected persistence success, got \(error)", file: file, line: line)
        }
    }
}

private struct TestPersistenceError: Error, Sendable {
    let message: String
}
