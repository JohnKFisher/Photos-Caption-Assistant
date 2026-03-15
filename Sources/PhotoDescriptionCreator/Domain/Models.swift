import Foundation

public enum ScopeSource: Sendable, Equatable {
    case library
    case album(id: String)
    case picker(ids: [String])
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

    public static let current = LogicVersion(major: 2, minor: 3, patch: 0)
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

    public init(caption: String?, keywords: [String], ownershipTag: OwnershipTag?, isExternal: Bool) {
        self.caption = caption
        self.keywords = keywords
        self.ownershipTag = ownershipTag
        self.isExternal = isExternal
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

    public init(
        source: ScopeSource,
        optionalCaptureDateRange: CaptureDateRange?,
        traversalOrder: RunTraversalOrder = .photosOrderFast,
        overwriteAppOwnedSameOrNewer: Bool,
        alwaysOverwriteExternalMetadata: Bool = false
    ) {
        self.source = source
        self.optionalCaptureDateRange = optionalCaptureDateRange
        self.traversalOrder = traversalOrder
        self.overwriteAppOwnedSameOrNewer = overwriteAppOwnedSameOrNewer
        self.alwaysOverwriteExternalMetadata = alwaysOverwriteExternalMetadata
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

public struct RunSummary: Sendable, Equatable {
    public let progress: RunProgress
    public let errors: [String]
    public let failedAssets: [MediaAsset]

    public init(progress: RunProgress, errors: [String], failedAssets: [MediaAsset] = []) {
        self.progress = progress
        self.errors = errors
        self.failedAssets = failedAssets
    }
}

public struct CompletedItemPreview: Sendable, Equatable {
    public let filename: String
    public let kind: MediaKind
    public let previewFileURL: URL?
    public let caption: String
    public let keywords: [String]

    public init(
        filename: String,
        kind: MediaKind,
        previewFileURL: URL?,
        caption: String,
        keywords: [String]
    ) {
        self.filename = filename
        self.kind = kind
        self.previewFileURL = previewFileURL
        self.caption = caption
        self.keywords = keywords
    }
}

public protocol Analyzer: Sendable {
    func analyze(mediaURL: URL, kind: MediaKind) async throws -> GeneratedMetadata
}

public protocol PhotosWriter: Sendable {
    func enumerate(scope: ScopeSource, dateRange: CaptureDateRange?) async throws -> [MediaAsset]
    func readMetadata(id: String) async throws -> ExistingMetadataState
    func writeMetadata(id: String, caption: String, keywords: [String]) async throws
    func exportAssetToTemporaryURL(id: String) async throws -> URL
    func isPhotosAppRunning() async -> Bool
}

public protocol PhotosProcessMonitoring: Sendable {
    func photosResidentMemoryBytes() async -> UInt64?
}

public protocol PhotoPreviewSource: Sendable {
    func photoPreviewToTemporaryURL(id: String, maxPixelSize: Int) async throws -> URL?
}

public protocol IncrementalPhotosWriter: PhotosWriter {
    func count(scope: ScopeSource) async throws -> Int
    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset]
}

public protocol BatchMetadataPhotosWriter: PhotosWriter {
    func readMetadata(ids: [String]) async throws -> [String: ExistingMetadataState]
}

public struct MetadataWritePayload: Sendable, Equatable {
    public let id: String
    public let caption: String
    public let keywords: [String]

    public init(id: String, caption: String, keywords: [String]) {
        self.id = id
        self.caption = caption
        self.keywords = keywords
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

public struct AppCapabilities: Sendable, Equatable {
    public let photosAutomationAvailable: Bool
    public let qwenModelAvailable: Bool
    public let pickerCapability: PickerCapability

    public init(
        photosAutomationAvailable: Bool,
        qwenModelAvailable: Bool,
        pickerCapability: PickerCapability
    ) {
        self.photosAutomationAvailable = photosAutomationAvailable
        self.qwenModelAvailable = qwenModelAvailable
        self.pickerCapability = pickerCapability
    }
}

public protocol CapabilityProbing: Sendable {
    func probe() async -> AppCapabilities
}
