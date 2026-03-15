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
    }

    let sourceKind: SourceKind
    let sourceAlbumID: String?
    let sourcePickerIDs: [String]?
    let dateRangeStart: Date?
    let dateRangeEnd: Date?
    let traversalOrder: RunTraversalOrder
    let overwriteAppOwnedSameOrNewer: Bool
    let alwaysOverwriteExternalMetadata: Bool

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
        }

        self.dateRangeStart = runOptions.optionalCaptureDateRange?.start
        self.dateRangeEnd = runOptions.optionalCaptureDateRange?.end
        self.traversalOrder = runOptions.traversalOrder
        self.overwriteAppOwnedSameOrNewer = runOptions.overwriteAppOwnedSameOrNewer
        self.alwaysOverwriteExternalMetadata = runOptions.alwaysOverwriteExternalMetadata
    }

    func toRunOptions(sourceOverride: ScopeSource? = nil, dateRangeOverride: CaptureDateRange? = nil) -> RunOptions {
        let source = sourceOverride ?? decodedSource
        let dateRange = dateRangeOverride ?? decodedDateRange
        return RunOptions(
            source: source,
            optionalCaptureDateRange: dateRange,
            traversalOrder: traversalOrder,
            overwriteAppOwnedSameOrNewer: overwriteAppOwnedSameOrNewer,
            alwaysOverwriteExternalMetadata: alwaysOverwriteExternalMetadata
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

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.stateFileURL = appSupport
            .appendingPathComponent("PhotoDescriptionCreator", isDirectory: true)
            .appendingPathComponent("run_resume_state.json", isDirectory: false)
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
