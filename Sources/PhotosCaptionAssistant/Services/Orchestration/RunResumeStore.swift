import Foundation

struct PersistedRunState: Codable, Equatable {
    let savedAt: Date
    let options: PersistedRunOptions
    let pendingIDs: [String]
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

actor RunResumeStore {
    private let fileManager: FileManager
    private let stateFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.stateFileURL = AppStoragePaths.make(fileManager: fileManager).runResumeStateFile
    }

    func load() -> PersistedRunState? {
        guard let data = try? Data(contentsOf: stateFileURL) else {
            return nil
        }
        return try? decoder.decode(PersistedRunState.self, from: data)
    }

    func save(_ state: PersistedRunState) {
        do {
            let parent = stateFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try encoder.encode(state)
            try data.write(to: stateFileURL, options: [.atomic])
        } catch {
            return
        }
    }

    func clear() {
        try? fileManager.removeItem(at: stateFileURL)
    }
}
