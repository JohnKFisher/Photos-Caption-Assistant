import Foundation

actor AppStorageMigrator {
    private let fileManager: FileManager
    private let paths: AppStoragePaths

    init(
        fileManager: FileManager = .default,
        paths: AppStoragePaths? = nil
    ) {
        self.fileManager = fileManager
        self.paths = paths ?? AppStoragePaths.make(fileManager: fileManager)
    }

    func migrateLegacyPersistentStateIfNeeded() {
        guard !fileManager.fileExists(atPath: paths.applicationSupportDirectory.path) else {
            return
        }
        guard fileManager.fileExists(atPath: paths.legacyApplicationSupportDirectory.path) else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: paths.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            try copyIfPresent(from: paths.legacyRunResumeStateFile, to: paths.runResumeStateFile)
            try copyIfPresent(
                from: paths.legacyCaptionWorkflowConfigurationFile,
                to: paths.captionWorkflowConfigurationFile
            )
        } catch {
            return
        }
    }

    private func copyIfPresent(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            return
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
