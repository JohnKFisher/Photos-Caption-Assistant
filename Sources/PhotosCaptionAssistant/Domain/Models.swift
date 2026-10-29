import Foundation

public enum ScopeSource: Sendable, Equatable {
    case library
    case album(id: String)
    case picker(ids: [String])
    case captionWorkflow
}

public struct CaptionWorkflowQueueEntry: Sendable, Equatable, Codable {
    public let albumID: String?
    public let albumName: String?

    public init(albumID: String? = nil, albumName: String? = nil) {
        self.albumID = CaptionWorkflowQueueEntry.normalized(albumID)
        self.albumName = CaptionWorkflowQueueEntry.normalized(albumName)
    }

    public var isConfigured: Bool {
        guard let albumID, let albumName else {
            return false
        }
        return !albumID.isEmpty && !albumName.isEmpty
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

public struct CaptionWorkflowConfiguration: Sendable, Equatable, Codable {
    public static let minimumQueueLength = 2
    public let queue: [CaptionWorkflowQueueEntry]

    public init(queue: [CaptionWorkflowQueueEntry]) {
        self.queue = queue
    }

    public var duplicateAlbumIDs: [String] {
        Dictionary(grouping: queue.compactMap(\.albumID), by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
    }

    public var missingQueuePositions: [Int] {
        queue.enumerated().compactMap { index, entry in
            entry.isConfigured ? nil : index
        }
    }

    public var isRunnable: Bool {
        queue.count >= Self.minimumQueueLength
            && missingQueuePositions.isEmpty
            && duplicateAlbumIDs.isEmpty
    }
}

public struct CaptureDateRange: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public func contains(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date >= start && date <= end
    }
}

public enum EngineTier: String, Sendable, Equatable, Codable {
    case vision
    case foundationModels
    case qwen25vl7b
}

public struct LogicVersion: Sendable, Equatable, Codable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: LogicVersion, rhs: LogicVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public static let current = LogicVersion(major: 3, minor: 0, patch: 0)
}

public struct OwnershipTag: Sendable, Equatable, Codable {
    public let logicVersion: LogicVersion
    public let engineTier: EngineTier

    public init(logicVersion: LogicVersion, engineTier: EngineTier) {
        self.logicVersion = logicVersion
        self.engineTier = engineTier
    }
}

public enum MediaKind: String, Sendable, Equatable, Codable {
    case photo
    case video
}

public struct MediaAsset: Sendable, Equatable, Identifiable {
    public let id: String
    public let filename: String
    public let captureDate: Date?
    public let kind: MediaKind

    public init(id: String, filename: String, captureDate: Date?, kind: MediaKind) {
        self.id = id
        self.filename = filename
        self.captureDate = captureDate
        self.kind = kind
    }
}

public struct AlbumSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let itemCount: Int

    public init(id: String, name: String, itemCount: Int) {
        self.id = id
        self.name = name
        self.itemCount = itemCount
    }
}

public struct ExistingMetadataState: Sendable, Equatable {
    public let caption: String?
    public let keywords: [String]
    public let ownershipTag: OwnershipTag?
    public let isExternal: Bool
    public let snapshot: PhotosMetadataSnapshot

    public init(
        caption: String?,
        keywords: [String],
        ownershipTag: OwnershipTag?,
        isExternal: Bool,
        snapshot: PhotosMetadataSnapshot? = nil
    ) {
        self.caption = caption
        self.keywords = keywords
        self.ownershipTag = ownershipTag
        self.isExternal = isExternal
        self.snapshot = snapshot ?? PhotosMetadataSnapshot(caption: caption, keywords: keywords)
    }
}

public struct PhotosMetadataSnapshot: Sendable, Equatable {
    public let caption: String?
    public let keywords: [String]

    public init(caption: String?, keywords: [String]) {
        self.caption = caption
        self.keywords = keywords
    }
}

public struct GeneratedMetadata: Sendable, Equatable {
    public let caption: String
    public let keywords: [String]

    public init(caption: String, keywords: [String]) {
        self.caption = caption
        self.keywords = keywords
    }
}

public enum RunTraversalOrder: String, Sendable, Equatable, Codable {
    case photosOrderFast
    case oldestToNewest
    case newestToOldest
    case random
    case cycle
}

public struct RunOptions: Sendable, Equatable {
    public let source: ScopeSource
    public let optionalCaptureDateRange: CaptureDateRange?
    public let traversalOrder: RunTraversalOrder
    public let overwriteAppOwnedSameOrNewer: Bool
    public let alwaysOverwriteExternalMetadata: Bool
    public let captionWorkflowConfiguration: CaptionWorkflowConfiguration?

    public init(
        source: ScopeSource,
        optionalCaptureDateRange: CaptureDateRange?,
        traversalOrder: RunTraversalOrder = .photosOrderFast,
        overwriteAppOwnedSameOrNewer: Bool,
        alwaysOverwriteExternalMetadata: Bool = false,
        captionWorkflowConfiguration: CaptionWorkflowConfiguration? = nil
    ) {
        self.source = source
        self.optionalCaptureDateRange = optionalCaptureDateRange
        self.traversalOrder = traversalOrder
        self.overwriteAppOwnedSameOrNewer = overwriteAppOwnedSameOrNewer
        self.alwaysOverwriteExternalMetadata = alwaysOverwriteExternalMetadata
        self.captionWorkflowConfiguration = captionWorkflowConfiguration
    }
}

public struct RunProgress: Sendable, Equatable {
    public var totalDiscovered: Int
    public var processed: Int
    public var changed: Int
    public var skipped: Int
    public var failed: Int

    public init(totalDiscovered: Int = 0, processed: Int = 0, changed: Int = 0, skipped: Int = 0, failed: Int = 0) {
        self.totalDiscovered = totalDiscovered
        self.processed = processed
        self.changed = changed
        self.skipped = skipped
        self.failed = failed
    }
}

public struct RunPerformanceStats: Sendable, Equatable {
    public let elapsedSeconds: Int
    public let itemsPerMinute: Double?
    public let etaSeconds: Int?

    public init(elapsedSeconds: Int = 0, itemsPerMinute: Double? = nil, etaSeconds: Int? = nil) {
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.itemsPerMinute = itemsPerMinute
        self.etaSeconds = etaSeconds
    }
}

public struct RunStageTiming: Sendable, Equatable, Identifiable {
    public let stage: String
    public let elapsedSeconds: Double

    public var id: String { stage }

    public init(stage: String, elapsedSeconds: Double) {
        self.stage = stage
        self.elapsedSeconds = max(0, elapsedSeconds)
    }
}

public struct RunDiagnostics: Sendable, Equatable {
    public let wallSeconds: Double
    public let analysisConcurrency: Int
    public let prepareAheadLimit: Int
    public let writeBatchSize: Int
    public let stageTimings: [RunStageTiming]

    public init(
        wallSeconds: Double,
        analysisConcurrency: Int,
        prepareAheadLimit: Int,
        writeBatchSize: Int,
        stageTimings: [RunStageTiming]
    ) {
        self.wallSeconds = max(0, wallSeconds)
        self.analysisConcurrency = max(1, analysisConcurrency)
        self.prepareAheadLimit = max(0, prepareAheadLimit)
        self.writeBatchSize = max(1, writeBatchSize)
        self.stageTimings = stageTimings
    }
}

public struct RunSummary: Sendable, Equatable {
    public let progress: RunProgress
    public let errors: [String]
    public let failedAssets: [MediaAsset]
    public let diagnostics: RunDiagnostics?

    public init(
        progress: RunProgress,
        errors: [String],
        failedAssets: [MediaAsset] = [],
        diagnostics: RunDiagnostics? = nil
    ) {
        self.progress = progress
        self.errors = errors
        self.failedAssets = failedAssets
        self.diagnostics = diagnostics
    }
}

public struct CompletedItemPreview: Sendable, Equatable {
    public let assetID: String
    public let filename: String
    public let sourceContext: String
    public let captureDate: Date?
    public let kind: MediaKind
    public let previewFileURL: URL?
    public let caption: String
    public let keywords: [String]

    public init(
        assetID: String,
        filename: String,
        sourceContext: String,
        captureDate: Date?,
        kind: MediaKind,
        previewFileURL: URL?,
        caption: String,
        keywords: [String]
    ) {
        self.assetID = assetID
        self.filename = filename
        self.sourceContext = sourceContext
        self.captureDate = captureDate
        self.kind = kind
        self.previewFileURL = previewFileURL
        self.caption = caption
        self.keywords = keywords
    }
}

public struct PreparedAnalysisPayload: Sendable, Equatable {
    public let prompt: String
    public let images: [Data]

    public init(prompt: String, images: [Data]) {
        self.prompt = prompt
        self.images = images
    }
}

public enum AnalysisInput: Sendable, Equatable {
    case fileURL(URL)
    case photoPreviewJPEGData(Data)
}

public protocol Analyzer: Sendable {
    func analyze(input: AnalysisInput, kind: MediaKind) async throws -> GeneratedMetadata
}

public protocol PreparedInputAnalyzer: Analyzer {
    func prepareAnalysis(input: AnalysisInput, kind: MediaKind) async throws -> PreparedAnalysisPayload
    func analyze(preparedPayload: PreparedAnalysisPayload) async throws -> GeneratedMetadata
}

public protocol PhotosWriter: Sendable {
    func enumerate(scope: ScopeSource, dateRange: CaptureDateRange?) async throws -> [MediaAsset]
    func readMetadata(id: String) async throws -> ExistingMetadataState
    func writeMetadata(id: String, caption: String, keywords: [String]) async throws
    func exportAssetToTemporaryURL(id: String, kind: MediaKind) async throws -> URL
    func isPhotosAppRunning() async -> Bool
}

public protocol PhotosRuntimeRequirements: Sendable {
    var backendName: String { get }
    var requiresPhotosAppToBeOpen: Bool { get }
    var requiresAppleEventsAutomation: Bool { get }
    func authorizationState() async -> PhotosIntegrationAccessState
    func prepareForRun(scope: ScopeSource) async throws
}

public protocol PhotosIntegrationClient:
    PhotosWriter,
    IncrementalPhotosWriter,
    BatchMetadataPhotosWriter,
    BatchWritePhotosWriter,
    AlbumListingPhotosSource,
    PhotoPreviewSource,
    PhotoPreviewDataSource,
    PhotosRuntimeRequirements
{
    func withResolvedAlbumCounts(_ albums: [AlbumSummary]) async -> [AlbumSummary]
    func resolveAlbumID(_ id: String) async -> String?
}

public protocol PhotosEnumerationSnapshotting: Sendable {
    func beginEnumerationSnapshot(scope: ScopeSource) async throws
    func endEnumerationSnapshot(scope: ScopeSource) async
}

public protocol PhotosResumeSnapshotting: Sendable {
    /// Returns every identifier in the active enumeration snapshot so resumable state is complete before writes begin.
    func resumeSnapshotAssetIdentifiers(scope: ScopeSource) async throws -> [String]
}

public protocol PhotosOperationCancellation: Sendable {
    func beginPhotosRequests() async
    func cancelPendingPhotosRequests() async
    func endPhotosRequests() async
}

public protocol ContextualMetadataPhotosWriter: Sendable {
    func writeMetadata(_ payload: MetadataWritePayload) async throws -> MetadataWriteResult
}

public protocol AlbumListingPhotosSource: Sendable {
    func listAlbums() async throws -> [AlbumSummary]
}

public protocol PhotosProcessMonitoring: Sendable {
    func photosResidentMemoryBytes() async -> UInt64?
}

public protocol PhotosLifecycleControlling: Sendable {
    func quitPhotosAppGracefully() async -> Bool
    func launchPhotosApp() async throws
    func waitForPhotosReady(timeoutSeconds: TimeInterval) async -> Bool
}

public protocol PhotoPreviewSource: Sendable {
    func photoPreviewToTemporaryURL(id: String, maxPixelSize: Int) async throws -> URL?
}

public protocol PhotoPreviewDataSource: Sendable {
    func photoPreviewJPEGData(id: String, maxPixelSize: Int) async throws -> Data?
}

public protocol IncrementalScanSource: Sendable {
    func count(scope: ScopeSource) async throws -> Int
    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset]
}

public protocol ScopedIncrementalScanSource: IncrementalScanSource {
    func canHandleIncrementalScan(scope: ScopeSource) async -> Bool
}

public protocol IncrementalPhotosWriter: PhotosWriter, IncrementalScanSource {}

public protocol BatchMetadataPhotosWriter: PhotosWriter {
    func readMetadata(ids: [String]) async throws -> [String: ExistingMetadataState]
}

public struct MetadataWritePayload: Sendable, Equatable {
    public let id: String
    public let caption: String
    public let keywords: [String]
    public let expectedMetadata: PhotosMetadataSnapshot?

    public init(
        id: String,
        caption: String,
        keywords: [String],
        expectedMetadata: PhotosMetadataSnapshot? = nil
    ) {
        self.id = id
        self.caption = caption
        self.keywords = keywords
        self.expectedMetadata = expectedMetadata
    }
}

public struct MetadataWriteResult: Sendable, Equatable {
    public let id: String
    public let success: Bool
    public let errorMessage: String?

    public init(id: String, success: Bool, errorMessage: String? = nil) {
        self.id = id
        self.success = success
        self.errorMessage = errorMessage
    }
}

public protocol BatchWritePhotosWriter: PhotosWriter {
    func writeMetadata(batch writes: [MetadataWritePayload]) async throws -> [MetadataWriteResult]
}

public enum PickerCapability: Sendable, Equatable {
    case supported
    case unsupported(reason: String)
}

public enum PhotosIntegrationAccessState: Sendable, Equatable {
    case available
    case notDetermined
    case limited
    case denied
    case restricted

    public var permitsRunAdmission: Bool {
        self == .available
    }

    public var needsAccessRequest: Bool {
        self == .notDetermined
    }
}

public enum OllamaAvailability: Sendable, Equatable {
    case notInstalled
    case installedNotRunning
    case installedRunningModelMissing
    case ready
    case failure(reason: String, isInstalled: Bool, serviceReachable: Bool)

    public static func detected(
        isInstalled: Bool,
        serviceReachable: Bool,
        modelAvailable: Bool
    ) -> OllamaAvailability {
        guard isInstalled else {
            return .notInstalled
        }
        guard serviceReachable else {
            return .installedNotRunning
        }
        return modelAvailable ? .ready : .installedRunningModelMissing
    }

    public static func legacy(
        qwenModelAvailable: Bool,
        ollamaServiceReachable: Bool
    ) -> OllamaAvailability {
        if qwenModelAvailable {
            return .ready
        }
        if ollamaServiceReachable {
            return .installedRunningModelMissing
        }
        return .installedNotRunning
    }

    public var isInstalled: Bool {
        switch self {
        case .notInstalled:
            return false
        case let .failure(_, isInstalled, _):
            return isInstalled
        case .installedNotRunning, .installedRunningModelMissing, .ready:
            return true
        }
    }

    public var serviceReachable: Bool {
        switch self {
        case .installedRunningModelMissing, .ready:
            return true
        case .notInstalled, .installedNotRunning:
            return false
        case let .failure(_, _, serviceReachable):
            return serviceReachable
        }
    }

    public var modelAvailable: Bool {
        switch self {
        case .ready:
            return true
        case .notInstalled, .installedNotRunning, .installedRunningModelMissing, .failure:
            return false
        }
    }

    public var requiresInstallBeforeRun: Bool {
        if case .notInstalled = self {
            return true
        }
        return false
    }
}

public struct AppCapabilities: Sendable, Equatable {
    public let photosAutomationAvailable: Bool
    public let photosIntegrationAvailable: Bool
    public let photosAccessState: PhotosIntegrationAccessState
    public let photosBackendName: String
    public let photosRequiresPhotosApp: Bool
    public let photosRequiresAppleEventsAutomation: Bool
    public let ollamaAvailability: OllamaAvailability
    public let pickerCapability: PickerCapability

    public var qwenModelAvailable: Bool {
        ollamaAvailability.modelAvailable
    }

    public var ollamaServiceReachable: Bool {
        ollamaAvailability.serviceReachable
    }

    public var ollamaInstalled: Bool {
        ollamaAvailability.isInstalled
    }

    public init(
        photosAutomationAvailable: Bool,
        ollamaAvailability: OllamaAvailability,
        pickerCapability: PickerCapability
    ) {
        self.photosAutomationAvailable = photosAutomationAvailable
        self.photosIntegrationAvailable = photosAutomationAvailable
        self.photosAccessState = photosAutomationAvailable ? .available : .denied
        self.photosBackendName = "AppleScript"
        self.photosRequiresPhotosApp = true
        self.photosRequiresAppleEventsAutomation = true
        self.ollamaAvailability = ollamaAvailability
        self.pickerCapability = pickerCapability
    }

    public init(
        photosIntegrationAvailable: Bool,
        photosAccessState: PhotosIntegrationAccessState,
        photosBackendName: String,
        photosRequiresPhotosApp: Bool,
        photosRequiresAppleEventsAutomation: Bool,
        ollamaAvailability: OllamaAvailability,
        pickerCapability: PickerCapability
    ) {
        self.photosAutomationAvailable = photosRequiresAppleEventsAutomation && photosIntegrationAvailable
        self.photosIntegrationAvailable = photosIntegrationAvailable
        self.photosAccessState = photosAccessState
        self.photosBackendName = photosBackendName
        self.photosRequiresPhotosApp = photosRequiresPhotosApp
        self.photosRequiresAppleEventsAutomation = photosRequiresAppleEventsAutomation
        self.ollamaAvailability = ollamaAvailability
        self.pickerCapability = pickerCapability
    }

    public init(
        photosAutomationAvailable: Bool,
        qwenModelAvailable: Bool,
        ollamaServiceReachable: Bool = false,
        pickerCapability: PickerCapability
    ) {
        self.photosAutomationAvailable = photosAutomationAvailable
        self.photosIntegrationAvailable = photosAutomationAvailable
        self.photosAccessState = photosAutomationAvailable ? .available : .denied
        self.photosBackendName = "AppleScript"
        self.photosRequiresPhotosApp = true
        self.photosRequiresAppleEventsAutomation = true
        self.ollamaAvailability = .legacy(
            qwenModelAvailable: qwenModelAvailable,
            ollamaServiceReachable: ollamaServiceReachable
        )
        self.pickerCapability = pickerCapability
    }
}

public protocol CapabilityProbing: Sendable {
    func probe() async -> AppCapabilities
}
