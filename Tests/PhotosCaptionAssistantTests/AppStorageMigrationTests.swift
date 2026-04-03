import Foundation
import XCTest
@testable import PhotosCaptionAssistant

final class AppStorageMigrationTests: XCTestCase {
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
}
