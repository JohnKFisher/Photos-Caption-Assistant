import Foundation

struct PersistedRunState: Codable, Equatable {
    let runSessionID: UUID?
    let savedAt: Date
    let options: PersistedRunOptions
    let pendingIDs: [String]

    init(
        runSessionID: UUID? = nil,
        savedAt: Date,
        options: PersistedRunOptions,
        pendingIDs: [String]
    ) {
        self.runSessionID = runSessionID
        self.savedAt = savedAt
        self.options = options
        self.pendingIDs = pendingIDs
    }

    private enum CodingKeys: String, CodingKey {
        case runSessionID
        case savedAt
        case options
        case pendingIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runSessionID = try container.decodeIfPresent(UUID.self, forKey: .runSessionID)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        options = try container.decode(PersistedRunOptions.self, forKey: .options)
        pendingIDs = try container.decode([String].self, forKey: .pendingIDs)
    }
}

struct PersistedRunOptions: Codable, Equatable {
    enum SourceKind: String, Codable {
        case library
        case album
        case picker
        case captionWorkflow
    }

    let sourceKind: SourceKind
    let sourceAlbumID: String?
    let sourcePickerIDs: [String]?
    let dateRangeStart: Date?
    let dateRangeEnd: Date?
    let traversalOrder: RunTraversalOrder
    let overwriteAppOwnedSameOrNewer: Bool
    let alwaysOverwriteExternalMetadata: Bool
    let captionWorkflowConfiguration: CaptionWorkflowConfiguration?

    private enum CodingKeys: String, CodingKey {
        case sourceKind
        case sourceAlbumID
        case sourcePickerIDs
        case dateRangeStart
        case dateRangeEnd
        case traversalOrder
        case overwriteAppOwnedSameOrNewer
        case alwaysOverwriteExternalMetadata
        case captionWorkflowConfiguration
    }

    init(runOptions: RunOptions) {
        switch runOptions.source {
        case .library:
            self.sourceKind = .library
            self.sourceAlbumID = nil
            self.sourcePickerIDs = nil
        case let .album(id):
            self.sourceKind = .album
            self.sourceAlbumID = id
            self.sourcePickerIDs = nil
        case let .picker(ids):
            self.sourceKind = .picker
            self.sourceAlbumID = nil
            self.sourcePickerIDs = ids
        case .captionWorkflow:
            self.sourceKind = .captionWorkflow
            self.sourceAlbumID = nil
            self.sourcePickerIDs = nil
        }

        self.dateRangeStart = runOptions.optionalCaptureDateRange?.start
        self.dateRangeEnd = runOptions.optionalCaptureDateRange?.end
        self.traversalOrder = runOptions.traversalOrder
        self.overwriteAppOwnedSameOrNewer = runOptions.overwriteAppOwnedSameOrNewer
        self.alwaysOverwriteExternalMetadata = runOptions.alwaysOverwriteExternalMetadata
        self.captionWorkflowConfiguration = runOptions.captionWorkflowConfiguration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceKind = try container.decode(SourceKind.self, forKey: .sourceKind)
        self.sourceAlbumID = try container.decodeIfPresent(String.self, forKey: .sourceAlbumID)
        self.sourcePickerIDs = try container.decodeIfPresent([String].self, forKey: .sourcePickerIDs)
        self.dateRangeStart = try container.decodeIfPresent(Date.self, forKey: .dateRangeStart)
        self.dateRangeEnd = try container.decodeIfPresent(Date.self, forKey: .dateRangeEnd)
        self.traversalOrder = try container.decode(RunTraversalOrder.self, forKey: .traversalOrder)
        self.overwriteAppOwnedSameOrNewer = try container.decode(Bool.self, forKey: .overwriteAppOwnedSameOrNewer)
        self.alwaysOverwriteExternalMetadata = try container.decode(Bool.self, forKey: .alwaysOverwriteExternalMetadata)
        self.captionWorkflowConfiguration = try? container.decode(
            CaptionWorkflowConfiguration.self,
            forKey: .captionWorkflowConfiguration
        )
    }

    func toRunOptions(sourceOverride: ScopeSource? = nil, dateRangeOverride: CaptureDateRange? = nil) -> RunOptions {
        let source = sourceOverride ?? decodedSource
        let dateRange = dateRangeOverride ?? decodedDateRange
        return RunOptions(
            source: source,
            optionalCaptureDateRange: dateRange,
            traversalOrder: traversalOrder,
            overwriteAppOwnedSameOrNewer: overwriteAppOwnedSameOrNewer,
            alwaysOverwriteExternalMetadata: alwaysOverwriteExternalMetadata,
            captionWorkflowConfiguration: captionWorkflowConfiguration
        )
    }

    private var decodedSource: ScopeSource {
        switch sourceKind {
        case .library:
            return .library
        case .album:
            if let sourceAlbumID, !sourceAlbumID.isEmpty {
                return .album(id: sourceAlbumID)
            }
            return .library
        case .picker:
            return .picker(ids: sourcePickerIDs ?? [])
        case .captionWorkflow:
            return .captionWorkflow
        }
    }

    private var decodedDateRange: CaptureDateRange? {
        guard let start = dateRangeStart, let end = dateRangeEnd else {
            return nil
        }
        return CaptureDateRange(start: start, end: end)
    }
}

enum PersistenceStoreError: LocalizedError, Equatable, Sendable {
    case operationFailed(operation: String, path: String, reason: String)
    case corruptData(path: String, reason: String)
    case staleSession

    var errorDescription: String? {
        switch self {
        case let .operationFailed(operation, path, reason):
            return "\(operation) failed for \(path): \(reason)"
        case let .corruptData(path, reason):
            return "Saved data at \(path) is unreadable: \(reason)"
        case .staleSession:
            return "The saved state belongs to an earlier run session and was ignored."
        }
    }
}

struct PersistenceFileAccess: @unchecked Sendable {
    let fileExists: (URL) -> Bool
    let read: (URL) throws -> Data
    let createDirectory: (URL) throws -> Void
    let write: (Data, URL) throws -> Void
    let remove: (URL) throws -> Void

    init(
        fileExists: @escaping (URL) -> Bool,
        read: @escaping (URL) throws -> Data,
        createDirectory: @escaping (URL) throws -> Void,
        write: @escaping (Data, URL) throws -> Void,
        remove: @escaping (URL) throws -> Void
    ) {
        self.fileExists = fileExists
        self.read = read
        self.createDirectory = createDirectory
        self.write = write
        self.remove = remove
    }

    static func live(fileManager: FileManager = .default) -> PersistenceFileAccess {
        PersistenceFileAccess(
            fileExists: { url in
                fileManager.fileExists(atPath: url.path)
            },
            read: { url in
                try Data(contentsOf: url)
            },
            createDirectory: { url in
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            },
            write: { data, url in
                try data.write(to: url, options: [.atomic])
            },
            remove: { url in
                try fileManager.removeItem(at: url)
            }
        )
    }
}

actor RunResumeStore {
    private let fileAccess: PersistenceFileAccess
    private let stateFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var activeSessionID: UUID?

    init(fileManager: FileManager = .default) {
        self.fileAccess = .live(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.stateFileURL = AppStoragePaths.make(fileManager: fileManager).runResumeStateFile
    }

    init(fileURL: URL, fileAccess: PersistenceFileAccess = .live()) {
        self.fileAccess = fileAccess
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.stateFileURL = fileURL
    }

    func beginSession(_ sessionID: UUID) {
        activeSessionID = sessionID
    }

    func endSession(_ sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
    }

    func load() -> Result<PersistedRunState?, PersistenceStoreError> {
        guard fileAccess.fileExists(stateFileURL) else {
            return .success(nil)
        }

        do {
            let data = try fileAccess.read(stateFileURL)
            return .success(try decoder.decode(PersistedRunState.self, from: data))
        } catch let error as PersistenceStoreError {
            return .failure(error)
        } catch {
            return .failure(
                .corruptData(path: stateFileURL.path, reason: error.localizedDescription)
            )
        }
    }

    func save(
        _ state: PersistedRunState,
        for sessionID: UUID? = nil
    ) -> Result<Void, PersistenceStoreError> {
        if let sessionID {
            guard activeSessionID == sessionID,
                  state.runSessionID == nil || state.runSessionID == sessionID
            else {
                return .failure(.staleSession)
            }
        }

        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            return .failure(
                .operationFailed(
                    operation: "Encoding saved run state",
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
                    operation: "Saving run state",
                    path: stateFileURL.path,
                    reason: error.localizedDescription
                )
            )
        }
    }

    func clear(for sessionID: UUID? = nil) -> Result<Void, PersistenceStoreError> {
        if let sessionID, activeSessionID != sessionID {
            return .failure(.staleSession)
        }
        guard fileAccess.fileExists(stateFileURL) else {
            return .success(())
        }

        do {
            try fileAccess.remove(stateFileURL)
            return .success(())
        } catch {
            return .failure(
                .operationFailed(
                    operation: "Clearing saved run state",
                    path: stateFileURL.path,
                    reason: error.localizedDescription
                )
            )
        }
    }
}
