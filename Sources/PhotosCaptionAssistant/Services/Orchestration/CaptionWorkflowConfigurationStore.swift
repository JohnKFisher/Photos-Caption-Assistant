import Foundation

actor CaptionWorkflowConfigurationStore {
    private let fileAccess: PersistenceFileAccess
    private let stateFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileAccess = .live(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.stateFileURL = AppStoragePaths.make(fileManager: fileManager).captionWorkflowConfigurationFile
    }

    init(fileURL: URL, fileAccess: PersistenceFileAccess = .live()) {
        self.fileAccess = fileAccess
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.stateFileURL = fileURL
    }

    func load() -> Result<CaptionWorkflowConfiguration?, PersistenceStoreError> {
        guard fileAccess.fileExists(stateFileURL) else {
            return .success(nil)
        }

        do {
            let data = try fileAccess.read(stateFileURL)
            return .success(try decoder.decode(CaptionWorkflowConfiguration.self, from: data))
        } catch {
            return .failure(
                .corruptData(path: stateFileURL.path, reason: error.localizedDescription)
            )
        }
    }

    func save(_ configuration: CaptionWorkflowConfiguration) -> Result<Void, PersistenceStoreError> {
        let data: Data
        do {
            data = try encoder.encode(configuration)
        } catch {
            return .failure(
                .operationFailed(
                    operation: "Encoding queued-albums configuration",
                    path: stateFileURL.path,
                    reason: error.localizedDescription
                )
            )
        }

        do {
            let parent = stateFileURL.deletingLastPathComponent()
            try fileAccess.createDirectory(parent)
            try fileAccess.write(data, stateFileURL)
            return .success(())
        } catch {
            return .failure(
                .operationFailed(
                    operation: "Saving queued-albums configuration",
                    path: stateFileURL.path,
                    reason: error.localizedDescription
                )
            )
        }
    }

    func clear() -> Result<Void, PersistenceStoreError> {
        guard fileAccess.fileExists(stateFileURL) else {
            return .success(())
        }

        do {
            try fileAccess.remove(stateFileURL)
            return .success(())
        } catch {
            return .failure(
                .operationFailed(
                    operation: "Clearing queued-albums configuration",
                    path: stateFileURL.path,
                    reason: error.localizedDescription
                )
            )
        }
    }
}
