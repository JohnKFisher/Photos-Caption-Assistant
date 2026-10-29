@preconcurrency import AVFoundation
@preconcurrency import Photos
import AppKit
import Foundation
import UniformTypeIdentifiers

enum PhotoKitPhotosClientError: Error, LocalizedError {
    case accessRequired
    case accessDenied
    case accessRestricted
    case limitedLibraryAccess
    case unsupportedScope(String)
    case albumNotFound(String)
    case ambiguousAlbumIdentifier(String)
    case assetNotFound(String)
    case ambiguousAssetIdentifier(String)
    case assetNotEditable(String)
    case metadataChanged(String)
    case writeFailed(String)
    case writeVerificationFailed(String)
    case mediaUnavailable(String)
    case mediaRequestTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            return "Allow Photos Caption Assistant to access the Photos library, then reload the album list or start the run again."
        case .accessDenied:
            return "Photos library access is denied. Allow full read and write access in System Settings > Privacy & Security > Photos."
        case .accessRestricted:
            return "Photos library access is restricted by macOS or device management."
        case .limitedLibraryAccess:
            return "Photos Caption Assistant needs full library access to scan albums and safely update metadata."
        case let .unsupportedScope(scope):
            return "PhotoKit cannot enumerate this source directly: \(scope)."
        case let .albumNotFound(id):
            return "PhotoKit could not resolve album identifier \(id)."
        case let .ambiguousAlbumIdentifier(id):
            return "PhotoKit found more than one album for legacy identifier \(id), so the source was left unresolved."
        case let .assetNotFound(id):
            return "PhotoKit could not resolve asset identifier \(id). The item may have been removed or library access may have changed."
        case let .ambiguousAssetIdentifier(id):
            return "PhotoKit found more than one asset for legacy identifier \(id), so the item was left unchanged."
        case let .assetNotEditable(id):
            return "Photos does not allow metadata edits for asset \(id)."
        case let .metadataChanged(id):
            return "Metadata changed after this item was approved. PhotoKit left \(id) unchanged; start a fresh run to review the current metadata."
        case let .writeFailed(message):
            return "Photos could not commit the metadata change: \(message)"
        case let .writeVerificationFailed(id):
            return "PhotoKit committed a change for \(id), but reading the requested metadata back did not verify it. The item may have changed concurrently; it was not rolled back."
        case let .mediaUnavailable(id):
            return "Photos could not provide media data for asset \(id). It may still be downloading from iCloud or may use an unsupported representation."
        case let .mediaRequestTimedOut(id):
            return "The media request for asset \(id) timed out. Retry after the item finishes downloading."
        }
    }
}

private protocol PhotoKitRequestCancelling: Sendable {
    func cancel()
}

private final class PhotoKitRequestState<Value: Sendable>: PhotoKitRequestCancelling, @unchecked Sendable {
    private let lock = NSLock()
    private let manager: PHImageManager
    private var continuation: CheckedContinuation<Value, Error>?
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var timeout: DispatchWorkItem?
    private var isFinished = false

    init(manager: PHImageManager) {
        self.manager = manager
    }

    func installContinuation(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func installRequestID(_ requestID: PHImageRequestID) {
        lock.lock()
        let cancelRequest = isFinished
        if !cancelRequest {
            self.requestID = requestID
        }
        lock.unlock()
        if cancelRequest, requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
        }
    }

    func installTimeout(after seconds: TimeInterval, error: Error) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(error))
        }
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            workItem.cancel()
            return
        }
        timeout = workItem
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        let requestID = self.requestID
        self.requestID = PHInvalidImageRequestID
        let timeout = self.timeout
        self.timeout = nil
        lock.unlock()

        timeout?.cancel()
        if requestID != PHInvalidImageRequestID {
            manager.cancelImageRequest(requestID)
        }
        guard let continuation else { return }
        switch result {
        case let .success(value): continuation.resume(returning: value)
        case let .failure(error): continuation.resume(throwing: error)
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }
}

actor PhotoKitPhotosClient: PhotosIntegrationClient, ScopedIncrementalScanSource, PhotosEnumerationSnapshotting, PhotosResumeSnapshotting, ContextualMetadataPhotosWriter, PhotosOperationCancellation {
    private enum EnumerationSnapshot {
        case fetchResult(PHFetchResult<PHAsset>)
        case assets([PHAsset])

        var count: Int {
            switch self {
            case let .fetchResult(result): result.count
            case let .assets(assets): assets.count
            }
        }

        func asset(at index: Int) -> PHAsset {
            switch self {
            case let .fetchResult(result): result.object(at: index)
            case let .assets(assets): assets[index]
            }
        }
    }

    private struct PendingChange {
        let payload: MetadataWritePayload
        let asset: PHAsset
        let current: PhotosMetadataSnapshot
        let desired: PhotosMetadataSnapshot
        let additions: [String]
        let removals: [String]
    }

    private struct UncheckedAVAsset: @unchecked Sendable {
        let value: AVAsset
    }

    private struct UncheckedExportSession: @unchecked Sendable {
        let value: AVAssetExportSession
    }

    nonisolated let backendName = "PhotoKit"
    nonisolated let requiresPhotosAppToBeOpen = false
    nonisolated let requiresAppleEventsAutomation = false

    private let fileManager: FileManager
    private let includeHiddenAssets: Bool
    private var authorizationRequest: Task<PHAuthorizationStatus, Never>?
    private var enumerationSnapshots: [String: EnumerationSnapshot] = [:]
    private var pendingPhotoRequests: [UUID: any PhotoKitRequestCancelling] = [:]
    private var activeVideoExports: [UUID: UncheckedExportSession] = [:]
    private var photoRequestsCancelledForRun = false

    init(fileManager: FileManager = .default, includeHiddenAssets: Bool = true) {
        self.fileManager = fileManager
        self.includeHiddenAssets = includeHiddenAssets
    }

    func authorizationState() async -> PhotosIntegrationAccessState {
        Self.accessState(for: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func prepareForRun(scope: ScopeSource) async throws {
        let status = await requestReadWriteAuthorizationIfNeeded()
        try Self.requireFullLibraryAccess(status)
        if case let .picker(ids) = scope {
            _ = try resolvePickerAssets(.picker(ids: ids))
        }
    }

    func count(scope: ScopeSource) async throws -> Int {
        if case .captionWorkflow = scope {
            throw PhotoKitPhotosClientError.unsupportedScope(AppPresentation.queuedAlbumsTitle)
        }
        try requireAuthorizedReadWriteAccess()
        if let snapshot = enumerationSnapshots[Self.scopeKey(scope)] {
            return snapshot.count
        }
        return try fetchResult(for: scope, prefetchExtendedMetadata: false).count
    }

    func enumerate(scope: ScopeSource, dateRange: CaptureDateRange?) async throws -> [MediaAsset] {
        if case .captionWorkflow = scope {
            throw PhotoKitPhotosClientError.unsupportedScope(AppPresentation.queuedAlbumsTitle)
        }
        try requireAuthorizedReadWriteAccess()

        let assets = try assets(for: scope, prefetchExtendedMetadata: false)
        return assets.compactMap { asset in
            let mediaAsset = makeMediaAsset(from: asset)
            guard let dateRange else { return mediaAsset }
            return dateRange.contains(mediaAsset.captureDate) ? mediaAsset : nil
        }
    }

    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset] {
        if case .captionWorkflow = scope {
            throw PhotoKitPhotosClientError.unsupportedScope(AppPresentation.queuedAlbumsTitle)
        }
        try requireAuthorizedReadWriteAccess()

        let key = Self.scopeKey(scope)
        let snapshot: EnumerationSnapshot
        if let existing = enumerationSnapshots[key] {
            snapshot = existing
        } else {
            snapshot = try makeEnumerationSnapshot(for: scope)
        }
        guard let range = Self.pageRange(totalCount: snapshot.count, offset: offset, limit: limit) else {
            return []
        }

        return range.map { makeMediaAsset(from: snapshot.asset(at: $0)) }
    }

    func beginEnumerationSnapshot(scope: ScopeSource) async throws {
        try requireAuthorizedReadWriteAccess()
        guard !Self.isUnsupported(scope) else {
            throw PhotoKitPhotosClientError.unsupportedScope(AppPresentation.queuedAlbumsTitle)
        }
        enumerationSnapshots[Self.scopeKey(scope)] = try makeEnumerationSnapshot(for: scope)
    }

    func endEnumerationSnapshot(scope: ScopeSource) async {
        enumerationSnapshots.removeValue(forKey: Self.scopeKey(scope))
    }

    func resumeSnapshotAssetIdentifiers(scope: ScopeSource) async throws -> [String] {
        try requireAuthorizedReadWriteAccess()
        let key = Self.scopeKey(scope)
        guard let snapshot = enumerationSnapshots[key] else {
            throw PhotoKitPhotosClientError.unsupportedScope("an enumeration snapshot is not active")
        }
        return (0..<snapshot.count).map { snapshot.asset(at: $0).localIdentifier }
    }

    func canHandleIncrementalScan(scope: ScopeSource) async -> Bool {
        guard !Self.isUnsupported(scope) else { return false }
        guard await authorizationState() == .available else { return false }
        do {
            if case .album = scope {
                _ = try resolveAlbumCollection(for: scope)
            } else if case .picker = scope {
                _ = try resolvePickerAssets(scope)
            }
            return true
        } catch {
            return false
        }
    }

    func canResolveAlbum(id: String) async -> Bool {
        guard await authorizationState() == .available else { return false }
        return (try? resolveAlbumCollection(identifier: id)) != nil
    }

    func resolveAlbumID(_ id: String) async -> String? {
        guard await authorizationState() == .available else { return nil }
        return try? resolveAlbumCollection(identifier: id).localIdentifier
    }

    func withResolvedAlbumCounts(_ albums: [AlbumSummary]) async -> [AlbumSummary] {
        guard await authorizationState() == .available else { return albums }
        return albums.map { album in
            guard let collection = try? resolveAlbumCollection(identifier: album.id) else { return album }
            let options = makeFetchOptions(prefetchExtendedMetadata: false)
            return AlbumSummary(
                id: collection.localIdentifier,
                name: collection.localizedTitle ?? album.name,
                itemCount: PHAsset.fetchAssets(in: collection, options: options).count
            )
        }
    }

    func listAlbums() async throws -> [AlbumSummary] {
        try requireAuthorizedReadWriteAccess()
        let collections = fetchVisibleAlbumCollections()
        var albums: [AlbumSummary] = []
        albums.reserveCapacity(collections.count)

        for collection in collections {
            if let title = collection.localizedTitle {
                albums.append(AlbumSummary(id: collection.localIdentifier, name: title, itemCount: -1))
            }
        }

        return albums.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    func inspectAsset(id: String) async -> PhotoLibraryResolvedMediaItem? {
        guard await authorizationState() == .available,
              let asset = try? resolveAsset(identifier: id)
        else {
            return nil
        }
        return PhotoLibraryResolvedMediaItem(
            requestedID: id,
            resolvedID: asset.localIdentifier,
            filename: preferredFilename(for: asset),
            captureDate: asset.creationDate ?? asset.modificationDate,
            kind: mediaKind(for: asset)
        )
    }

    func inspectAssets(ids: [String]) async -> [String: PhotoLibraryResolvedMediaItem] {
        var result: [String: PhotoLibraryResolvedMediaItem] = [:]
        result.reserveCapacity(ids.count)
        for id in ids {
            if let inspection = await inspectAsset(id: id) {
                result[id] = inspection
            }
        }
        return result
    }

    func readMetadata(id: String) async throws -> ExistingMetadataState {
        guard #available(macOS 27.0, *) else {
            throw PhotoKitPhotosClientError.unsupportedScope("metadata APIs require macOS 27 or later")
        }
        try requireAuthorizedReadWriteAccess()
        return Self.existingMetadata(from: try metadataSnapshot(for: resolveAsset(identifier: id)))
    }

    func readMetadata(ids: [String]) async throws -> [String: ExistingMetadataState] {
        guard #available(macOS 27.0, *) else {
            throw PhotoKitPhotosClientError.unsupportedScope("metadata APIs require macOS 27 or later")
        }
        try requireAuthorizedReadWriteAccess()
        guard !ids.isEmpty else { return [:] }

        let options = makeFetchOptions(prefetchExtendedMetadata: true)
        let resolvedByRequestedID = resolveAssets(identifiers: ids, options: options)
        let fetched = PHAsset.fetchAssets(
            withLocalIdentifiers: Array(Set(resolvedByRequestedID.values.map(\.localIdentifier))),
            options: options
        )
        var statesByLocalID: [String: ExistingMetadataState] = [:]
        statesByLocalID.reserveCapacity(fetched.count)
        fetched.enumerateObjects { asset, _, _ in
            statesByLocalID[asset.localIdentifier] = Self.existingMetadata(from: Self.metadataSnapshot(from: asset))
        }
        var result: [String: ExistingMetadataState] = [:]
        result.reserveCapacity(ids.count)
        for requestedID in ids {
            guard let asset = resolvedByRequestedID[requestedID],
                  let state = statesByLocalID[asset.localIdentifier]
            else { continue }
            result[requestedID] = state
        }
        return result
    }

    func writeMetadata(id: String, caption: String, keywords: [String]) async throws {
        let current = try await readMetadata(id: id)
        let result = try await writeMetadata(
            MetadataWritePayload(
                id: id,
                caption: caption,
                keywords: keywords,
                expectedMetadata: current.snapshot
            )
        )
        guard result.success else {
            throw PhotoKitPhotosClientError.writeFailed(result.errorMessage ?? "The metadata update did not complete.")
        }
    }

    func writeMetadata(_ payload: MetadataWritePayload) async throws -> MetadataWriteResult {
        let results = try await writeMetadata(batch: [payload])
        return results.first ?? MetadataWriteResult(
            id: payload.id,
            success: false,
            errorMessage: "PhotoKit returned no result for this item."
        )
    }

    func writeMetadata(batch writes: [MetadataWritePayload]) async throws -> [MetadataWriteResult] {
        guard #available(macOS 27.0, *) else {
            throw PhotoKitPhotosClientError.unsupportedScope("metadata APIs require macOS 27 or later")
        }
        try requireAuthorizedReadWriteAccess()
        guard !writes.isEmpty else { return [] }

        let duplicatedRequestedIDs = Set(writes.map(\.id).filter { id in writes.filter { $0.id == id }.count > 1 })
        let resolutionOptions = makeFetchOptions(prefetchExtendedMetadata: true)
        let resolvedAssets = resolveAssets(
            identifiers: writes.map(\.id).filter { !duplicatedRequestedIDs.contains($0) },
            options: resolutionOptions
        )
        let duplicateLocalIdentifiers = Set(
            Dictionary(grouping: resolvedAssets, by: { $0.value.localIdentifier })
                .filter { $0.value.count > 1 }
                .keys
        )
        let duplicateAssetIDs = Set(resolvedAssets.compactMap { requestedID, asset in
            duplicateLocalIdentifiers.contains(asset.localIdentifier) ? requestedID : nil
        }).union(duplicatedRequestedIDs)
        var results: [String: MetadataWriteResult] = [:]
        var changes: [PendingChange] = []
        changes.reserveCapacity(writes.count)

        for payload in writes where !duplicateAssetIDs.contains(payload.id) {
            do {
                guard let asset = resolvedAssets[payload.id] else {
                    throw PhotoKitPhotosClientError.assetNotFound(payload.id)
                }
                let current = Self.metadataSnapshot(from: asset)
                let desired = PhotosMetadataSnapshot(
                    caption: Self.normalizedCaption(payload.caption),
                    keywords: Self.uniqueKeywords(payload.keywords)
                )

                if Self.matchesTarget(current, desired) {
                    results[payload.id] = MetadataWriteResult(id: payload.id, success: true)
                    continue
                }

                if let expected = payload.expectedMetadata, !Self.matchesBaseline(current, expected) {
                    results[payload.id] = MetadataWriteResult(
                        id: payload.id,
                        success: false,
                        errorMessage: PhotoKitPhotosClientError.metadataChanged(payload.id).localizedDescription
                    )
                    continue
                }

                guard asset.canPerform(.properties) else {
                    throw PhotoKitPhotosClientError.assetNotEditable(payload.id)
                }

                let delta = Self.keywordDelta(current: current.keywords, desired: desired.keywords)
                changes.append(
                    PendingChange(
                        payload: payload,
                        asset: asset,
                        current: current,
                        desired: desired,
                        additions: delta.additions,
                        removals: delta.removals
                    )
                )
            } catch {
                results[payload.id] = MetadataWriteResult(
                    id: payload.id,
                    success: false,
                    errorMessage: error.localizedDescription
                )
            }
        }

        for id in duplicateAssetIDs {
            results[id] = MetadataWriteResult(
                id: id,
                success: false,
                errorMessage: "The same asset appeared more than once in one metadata batch; no change was made."
            )
        }

        guard !changes.isEmpty else {
            return writes.map { results[$0.id] ?? MetadataWriteResult(id: $0.id, success: false, errorMessage: "No write result was produced.") }
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for change in changes {
                    let request = PHAssetChangeRequest(for: change.asset)
                    let caption = change.desired.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
                    request.caption = caption?.isEmpty == false ? caption : nil
                    for keyword in change.removals {
                        request.removeKeyword(keyword)
                    }
                    for keyword in change.additions {
                        request.addKeyword(keyword)
                    }
                }
            }
        } catch {
            let afterFailure = await readSnapshotsAfterChange(for: changes)
            for change in changes {
                let current = afterFailure[change.payload.id]
                if let current, Self.matchesTarget(current, change.desired) {
                    results[change.payload.id] = MetadataWriteResult(id: change.payload.id, success: true)
                } else if let current, Self.matchesBaseline(current, change.current) {
                    results[change.payload.id] = MetadataWriteResult(
                        id: change.payload.id,
                        success: false,
                        errorMessage: PhotoKitPhotosClientError.writeFailed(error.localizedDescription).localizedDescription
                    )
                } else {
                    results[change.payload.id] = MetadataWriteResult(
                        id: change.payload.id,
                        success: false,
                        errorMessage: PhotoKitPhotosClientError.metadataChanged(change.payload.id).localizedDescription
                    )
                }
            }
            return writes.map { results[$0.id] ?? MetadataWriteResult(id: $0.id, success: false, errorMessage: "No write result was produced.") }
        }

        let verifiedSnapshots = await readSnapshotsAfterChange(for: changes)
        for change in changes {
            if let snapshot = verifiedSnapshots[change.payload.id], Self.matchesTarget(snapshot, change.desired) {
                results[change.payload.id] = MetadataWriteResult(id: change.payload.id, success: true)
            } else {
                results[change.payload.id] = MetadataWriteResult(
                    id: change.payload.id,
                    success: false,
                    errorMessage: PhotoKitPhotosClientError.writeVerificationFailed(change.payload.id).localizedDescription
                )
            }
        }

        return writes.map { results[$0.id] ?? MetadataWriteResult(id: $0.id, success: false, errorMessage: "No write result was produced.") }
    }

    func exportAssetToTemporaryURL(id: String, kind: MediaKind) async throws -> URL {
        try requireAuthorizedReadWriteAccess()
        let asset = try resolveAsset(identifier: id)
        guard (kind == .video) == (asset.mediaType == .video) else {
            throw PhotoKitPhotosClientError.mediaUnavailable(id)
        }
        if kind == .photo {
            return try await exportPhotoAsset(asset, assetID: id)
        }
        return try await exportVideoAsset(asset, assetID: id)
    }

    func photoPreviewJPEGData(id: String, maxPixelSize: Int) async throws -> Data? {
        try requireAuthorizedReadWriteAccess()
        let asset = try resolveAsset(identifier: id)
        guard asset.mediaType == .image else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        let edge = max(512, maxPixelSize)
        guard let imageData = try await requestImage(
            for: asset,
            targetSize: CGSize(width: edge, height: edge),
            options: options
        ), let image = NSImage(data: imageData) else {
            return nil
        }
        return jpegData(from: image)
    }

    func photoPreviewToTemporaryURL(id: String, maxPixelSize: Int) async throws -> URL? {
        guard let data = try await photoPreviewJPEGData(id: id, maxPixelSize: maxPixelSize) else { return nil }
        let root = AppStoragePaths.make(fileManager: fileManager).photoPreviewTempRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(Self.safeFilenameComponent(id) + ".jpg")
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    func isPhotosAppRunning() async -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Photos").isEmpty
    }

    func cancelPendingPhotosRequests() async {
        photoRequestsCancelledForRun = true
        let states = Array(pendingPhotoRequests.values)
        pendingPhotoRequests.removeAll()
        states.forEach { $0.cancel() }
        let exports = Array(activeVideoExports.values)
        activeVideoExports.removeAll()
        exports.forEach { $0.value.cancelExport() }
    }

    func beginPhotosRequests() async {
        photoRequestsCancelledForRun = false
    }

    func endPhotosRequests() async {
        photoRequestsCancelledForRun = false
    }

    static func identifierCandidates(from rawID: String) -> [String] {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let base = baseIdentifier(from: trimmed)
        return base == trimmed ? [trimmed] : [trimmed, base]
    }

    static func pageRange(totalCount: Int, offset: Int, limit: Int) -> Range<Int>? {
        guard totalCount > 0 else { return nil }
        let start = max(0, offset)
        guard start < totalCount else { return nil }
        return start..<min(totalCount, start + max(1, limit))
    }

    private func requestReadWriteAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }
        if let authorizationRequest {
            return await authorizationRequest.value
        }
        let request = Task<PHAuthorizationStatus, Never> {
            await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
            }
        }
        authorizationRequest = request
        let result = await request.value
        authorizationRequest = nil
        return result
    }

    private func requireAuthorizedReadWriteAccess() throws {
        try Self.requireFullLibraryAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func requireFullLibraryAccess(_ status: PHAuthorizationStatus) throws {
        switch status {
        case .authorized:
            return
        case .notDetermined:
            throw PhotoKitPhotosClientError.accessRequired
        case .denied:
            throw PhotoKitPhotosClientError.accessDenied
        case .restricted:
            throw PhotoKitPhotosClientError.accessRestricted
        case .limited:
            throw PhotoKitPhotosClientError.limitedLibraryAccess
        @unknown default:
            throw PhotoKitPhotosClientError.accessRestricted
        }
    }

    private static func accessState(for status: PHAuthorizationStatus) -> PhotosIntegrationAccessState {
        switch status {
        case .authorized: .available
        case .notDetermined: .notDetermined
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    private func makeFetchOptions(prefetchExtendedMetadata: Bool) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = includeHiddenAssets
        options.wantsIncrementalChangeDetails = false
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        if prefetchExtendedMetadata, #available(macOS 27.0, *) {
            options.prefetchAssetExtendedMetadata = true
        }
        return options
    }

    private func fetchResult(for scope: ScopeSource, prefetchExtendedMetadata: Bool) throws -> PHFetchResult<PHAsset> {
        let options = makeFetchOptions(prefetchExtendedMetadata: prefetchExtendedMetadata)
        switch scope {
        case .library:
            return PHAsset.fetchAssets(with: options)
        case let .album(id):
            let collection = try resolveAlbumCollection(identifier: id)
            return PHAsset.fetchAssets(in: collection, options: options)
        case .picker:
            let assets = try resolvePickerAssets(scope)
            return PHAsset.fetchAssets(withLocalIdentifiers: assets.map(\.localIdentifier), options: options)
        case .captionWorkflow:
            throw PhotoKitPhotosClientError.unsupportedScope(AppPresentation.queuedAlbumsTitle)
        }
    }

    private func assets(for scope: ScopeSource, prefetchExtendedMetadata: Bool) throws -> [PHAsset] {
        switch scope {
        case .library, .album:
            let result = try fetchResult(for: scope, prefetchExtendedMetadata: prefetchExtendedMetadata)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in assets.append(asset) }
            return assets
        case .picker:
            return try resolvePickerAssets(scope)
        case .captionWorkflow:
            throw PhotoKitPhotosClientError.unsupportedScope(AppPresentation.queuedAlbumsTitle)
        }
    }

    private func makeEnumerationSnapshot(for scope: ScopeSource) throws -> EnumerationSnapshot {
        switch scope {
        case .picker:
            return .assets(try resolvePickerAssets(scope))
        case .library, .album:
            return .fetchResult(try fetchResult(for: scope, prefetchExtendedMetadata: false))
        case .captionWorkflow:
            throw PhotoKitPhotosClientError.unsupportedScope(AppPresentation.queuedAlbumsTitle)
        }
    }

    private func resolveAlbumCollection(for scope: ScopeSource) throws -> PHAssetCollection {
        guard case let .album(id) = scope else {
            throw PhotoKitPhotosClientError.unsupportedScope("non-album scope")
        }
        return try resolveAlbumCollection(identifier: id)
    }

    private func resolveAlbumCollection(identifier: String) throws -> PHAssetCollection {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PhotoKitPhotosClientError.albumNotFound(identifier) }
        let exact = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [trimmed], options: nil)
        if let collection = exact.firstObject { return collection }
        guard !trimmed.contains("/") else { throw PhotoKitPhotosClientError.albumNotFound(identifier) }

        let matches = fetchAlbumCollections(matchingPrefix: trimmed)
        guard matches.count == 1, let collection = matches.first else {
            if matches.count > 1 { throw PhotoKitPhotosClientError.ambiguousAlbumIdentifier(identifier) }
            throw PhotoKitPhotosClientError.albumNotFound(identifier)
        }
        return collection
    }

    private func fetchVisibleAlbumCollections() -> [PHAssetCollection] {
        let regular = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        var collections: [PHAssetCollection] = []
        collections.reserveCapacity(regular.count + smart.count)
        regular.enumerateObjects { assetCollection, _, _ in collections.append(assetCollection) }
        smart.enumerateObjects { assetCollection, _, _ in collections.append(assetCollection) }
        var seen = Set<String>()
        return collections.filter { seen.insert($0.localIdentifier).inserted }
    }

    private func fetchAlbumCollections(matchingPrefix prefix: String) -> [PHAssetCollection] {
        var result: [PHAssetCollection] = []
        for type in [PHAssetCollectionType.album, .smartAlbum] {
            let options = PHFetchOptions()
            options.fetchLimit = 2
            options.predicate = NSPredicate(format: "localIdentifier BEGINSWITH %@", "\(prefix)/")
            let matches = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: options)
            matches.enumerateObjects { assetCollection, _, _ in result.append(assetCollection) }
        }
        return result
    }

    private func resolveAssets(
        identifiers: [String],
        options: PHFetchOptions
    ) -> [String: PHAsset] {
        let trimmedIDs = identifiers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let exactIDs = Array(Set(trimmedIDs.filter { !$0.isEmpty }))
        let exactFetch = PHAsset.fetchAssets(withLocalIdentifiers: exactIDs, options: options)
        var assetsByExactID: [String: PHAsset] = [:]
        assetsByExactID.reserveCapacity(exactFetch.count)
        exactFetch.enumerateObjects { asset, _, _ in
            assetsByExactID[asset.localIdentifier] = asset
        }

        var resolved: [String: PHAsset] = [:]
        resolved.reserveCapacity(identifiers.count)
        for (requestedID, trimmedID) in zip(identifiers, trimmedIDs) {
            guard !trimmedID.isEmpty else { continue }
            if let exact = assetsByExactID[trimmedID] {
                resolved[requestedID] = exact
            } else if let legacy = try? resolveAsset(identifier: trimmedID) {
                resolved[requestedID] = legacy
            }
        }
        return resolved
    }

    private func resolvePickerAssets(_ scope: ScopeSource) throws -> [PHAsset] {
        guard case let .picker(ids) = scope else {
            throw PhotoKitPhotosClientError.unsupportedScope("non-picker scope")
        }
        var seen = Set<String>()
        var result: [PHAsset] = []
        result.reserveCapacity(ids.count)
        let resolvedByID = resolveAssets(identifiers: ids, options: makeFetchOptions(prefetchExtendedMetadata: false))
        for id in ids {
            guard let asset = resolvedByID[id] else {
                _ = try resolveAsset(identifier: id)
                throw PhotoKitPhotosClientError.assetNotFound(id)
            }
            if seen.insert(asset.localIdentifier).inserted {
                result.append(asset)
            }
        }
        return result
    }

    private func resolveAsset(identifier: String) throws -> PHAsset {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PhotoKitPhotosClientError.assetNotFound(identifier) }
        let exact = PHAsset.fetchAssets(withLocalIdentifiers: [trimmed], options: nil)
        if let asset = exact.firstObject { return asset }
        guard !trimmed.contains("/") else { throw PhotoKitPhotosClientError.assetNotFound(identifier) }

        let options = PHFetchOptions()
        options.includeHiddenAssets = includeHiddenAssets
        options.fetchLimit = 2
        options.predicate = NSPredicate(format: "localIdentifier BEGINSWITH %@", "\(trimmed)/")
        let matches = PHAsset.fetchAssets(with: options)
        guard matches.count == 1, let asset = matches.firstObject else {
            if matches.count > 1 { throw PhotoKitPhotosClientError.ambiguousAssetIdentifier(identifier) }
            throw PhotoKitPhotosClientError.assetNotFound(identifier)
        }
        return asset
    }

    private static func isUnsupported(_ scope: ScopeSource) -> Bool {
        if case .captionWorkflow = scope { return true }
        return false
    }

    private static func scopeKey(_ scope: ScopeSource) -> String {
        switch scope {
        case .library: "library"
        case let .album(id): "album:\(id)"
        case let .picker(ids): "picker:\(ids.joined(separator: "\u{1f}"))"
        case .captionWorkflow: "captionWorkflow"
        }
    }

    private func makeMediaAsset(from asset: PHAsset) -> MediaAsset {
        MediaAsset(
            id: asset.localIdentifier,
            filename: preferredFilename(for: asset),
            captureDate: asset.creationDate ?? asset.modificationDate,
            kind: mediaKind(for: asset)
        )
    }

    private func preferredFilename(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredTypes: [PHAssetResourceType] = asset.mediaType == .video
            ? [.video, .fullSizeVideo, .pairedVideo, .fullSizePairedVideo]
            : [.photo, .fullSizePhoto, .alternatePhoto]
        if let resource = preferredTypes.lazy.compactMap({ type in resources.first { $0.type == type } }).first,
           let filename = resourceFilename(resource),
           !filename.isEmpty
        {
            return filename
        }
        return resources.lazy.compactMap(resourceFilename).first(where: { !$0.isEmpty })
            ?? Self.baseIdentifier(from: asset.localIdentifier)
    }

    private func resourceFilename(_ resource: PHAssetResource) -> String? {
        if #available(macOS 27.0, *) {
            return resource.filename
        }
        return resource.originalFilename
    }

    private func mediaKind(for asset: PHAsset) -> MediaKind {
        asset.mediaType == .video ? .video : .photo
    }

    private func metadataSnapshot(for asset: PHAsset) throws -> PhotosMetadataSnapshot {
        guard #available(macOS 27.0, *) else {
            throw PhotoKitPhotosClientError.unsupportedScope("metadata APIs require macOS 27 or later")
        }
        return Self.metadataSnapshot(from: asset)
    }

    @available(macOS 27.0, *)
    private static func metadataSnapshot(from asset: PHAsset) -> PhotosMetadataSnapshot {
        let metadata = asset.extendedMetadata
        return PhotosMetadataSnapshot(caption: metadata.caption, keywords: metadata.keywords)
    }

    static func existingMetadata(from snapshot: PhotosMetadataSnapshot) -> ExistingMetadataState {
        let caption = snapshot.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaningfulCaption = caption.flatMap { $0.isEmpty ? nil : $0 }
        let keywords = snapshot.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let ownershipTag = OwnershipTagCodec.extract(from: keywords)
        return ExistingMetadataState(
            caption: meaningfulCaption,
            keywords: keywords,
            ownershipTag: ownershipTag,
            isExternal: ownershipTag == nil && (meaningfulCaption != nil || !keywords.isEmpty),
            snapshot: snapshot
        )
    }

    @available(macOS 27.0, *)
    private func readSnapshotsAfterChange(for changes: [PendingChange]) async -> [String: PhotosMetadataSnapshot] {
        var snapshots: [String: PhotosMetadataSnapshot] = [:]
        let options = makeFetchOptions(prefetchExtendedMetadata: true)
        let fetched = PHAsset.fetchAssets(
            withLocalIdentifiers: changes.map { $0.asset.localIdentifier },
            options: options
        )
        let payloadIDByLocalID = Dictionary(uniqueKeysWithValues: changes.map {
            ($0.asset.localIdentifier, $0.payload.id)
        })
        fetched.enumerateObjects { asset, _, _ in
            guard let payloadID = payloadIDByLocalID[asset.localIdentifier] else { return }
            snapshots[payloadID] = Self.metadataSnapshot(from: asset)
        }
        return snapshots
    }

    static func uniqueKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.compactMap { keyword in
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return seen.insert(keywordComparisonKey(trimmed)).inserted ? trimmed : nil
        }
    }

    static func keywordComparisonKey(_ keyword: String) -> String {
        keyword.precomposedStringWithCanonicalMapping
    }

    static func normalizedCaption(_ caption: String) -> String? {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func keywordDelta(current: [String], desired: [String]) -> (additions: [String], removals: [String]) {
        let desiredKeys = Set(desired.map(keywordComparisonKey))
        let currentKeys = Set(current.map(keywordComparisonKey))
        return (
            additions: desired.filter { !currentKeys.contains(keywordComparisonKey($0)) },
            removals: current.filter { !desiredKeys.contains(keywordComparisonKey($0)) }
        )
    }

    static func matchesBaseline(_ lhs: PhotosMetadataSnapshot, _ rhs: PhotosMetadataSnapshot) -> Bool {
        let leftCaption = lhs.caption ?? ""
        let rightCaption = rhs.caption ?? ""
        return leftCaption == rightCaption && keywordMultiset(lhs.keywords) == keywordMultiset(rhs.keywords)
    }

    static func keywordMultiset(_ keywords: [String]) -> [String: Int] {
        keywords.reduce(into: [:]) { counts, keyword in
            counts[keyword.precomposedStringWithCanonicalMapping, default: 0] += 1
        }
    }

    static func matchesTarget(_ lhs: PhotosMetadataSnapshot, _ rhs: PhotosMetadataSnapshot) -> Bool {
        let leftCaption = normalizedCaption(lhs.caption ?? "") ?? ""
        let rightCaption = normalizedCaption(rhs.caption ?? "") ?? ""
        guard leftCaption == rightCaption else { return false }
        return keywordMultiset(lhs.keywords) == keywordMultiset(rhs.keywords)
    }

    private static func baseIdentifier(from identifier: String) -> String {
        guard let slash = identifier.firstIndex(of: "/") else { return identifier }
        return String(identifier[..<slash])
    }

    private static func safeFilenameComponent(_ value: String) -> String {
        let safe = value.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return safe.isEmpty ? UUID().uuidString : safe
    }

    private func exportPhotoAsset(_ asset: PHAsset, assetID: String) async throws -> URL {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        let (data, uti) = try await requestImageData(for: asset, options: options, assetID: assetID)
        let pathExtension = uti.flatMap(UTType.init)?.preferredFilenameExtension ?? "jpg"
        let root = AppStoragePaths.make(fileManager: fileManager).photoExportTempRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(Self.safeFilenameComponent(assetID) + "." + pathExtension)
        do {
            try data.write(to: destination, options: [.atomic])
            return destination
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    private func requestImageData(
        for asset: PHAsset,
        options: PHImageRequestOptions,
        assetID: String
    ) async throws -> (Data, String?) {
        let manager = PHImageManager.default()
        let state = PhotoKitRequestState<(Data, String?)>(manager: manager)
        let token = registerPhotoRequest(state)
        defer { pendingPhotoRequests.removeValue(forKey: token) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, String?), Error>) in
                guard state.installContinuation(continuation) else { return }
                state.installTimeout(after: 900, error: PhotoKitPhotosClientError.mediaRequestTimedOut(assetID))
                let requestID = manager.requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else if ((info?[PHImageCancelledKey] as? NSNumber)?.boolValue) == true {
                        state.finish(.failure(CancellationError()))
                    } else if let data {
                        state.finish(.success((data, uti)))
                    } else {
                        state.finish(.failure(PhotoKitPhotosClientError.mediaUnavailable(assetID)))
                    }
                }
                state.installRequestID(requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func exportVideoAsset(_ asset: PHAsset, assetID: String) async throws -> URL {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true
        let requestedAsset = try await requestVideoAsset(for: asset, options: options, assetID: assetID)
        if let urlAsset = requestedAsset.value as? AVURLAsset, urlAsset.url.isFileURL {
            let root = AppStoragePaths.make(fileManager: fileManager).videoExportTempRoot
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let ext = urlAsset.url.pathExtension.isEmpty ? "mov" : urlAsset.url.pathExtension
            let destination = root.appendingPathComponent(Self.safeFilenameComponent(assetID) + "." + ext)
            do {
                try fileManager.copyItem(at: urlAsset.url, to: destination)
                return destination
            } catch {
                try? fileManager.removeItem(at: root)
                throw error
            }
        }

        var session = try await requestVideoExportSession(
            for: asset,
            options: options,
            exportPreset: AVAssetExportPresetPassthrough
        )
        if session == nil {
            session = try await requestVideoExportSession(
                for: asset,
                options: options,
                exportPreset: AVAssetExportPresetHighestQuality
            )
        }
        guard let session else {
            throw PhotoKitPhotosClientError.mediaUnavailable(assetID)
        }
        guard let fileType = session.value.supportedFileTypes.first(where: { [.mov, .mp4, .m4v].contains($0) })
            ?? session.value.supportedFileTypes.first
        else {
            throw PhotoKitPhotosClientError.mediaUnavailable(assetID)
        }
        let ext = UTType(fileType.rawValue)?.preferredFilenameExtension ?? "mov"
        let root = AppStoragePaths.make(fileManager: fileManager).videoExportTempRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let exportToken = UUID()
        activeVideoExports[exportToken] = session
        defer { activeVideoExports.removeValue(forKey: exportToken) }
        if photoRequestsCancelledForRun {
            session.value.cancelExport()
            try? fileManager.removeItem(at: root)
            throw CancellationError()
        }
        let destination = root.appendingPathComponent(Self.safeFilenameComponent(assetID) + "." + ext)
        session.value.shouldOptimizeForNetworkUse = false
        do {
            try await withTaskCancellationHandler {
                try await session.value.export(to: destination, as: fileType)
            } onCancel: {
                session.value.cancelExport()
            }
            return destination
        } catch {
            try? fileManager.removeItem(at: root)
            if photoRequestsCancelledForRun {
                throw CancellationError()
            }
            throw error
        }
    }

    private func requestVideoAsset(
        for asset: PHAsset,
        options: PHVideoRequestOptions,
        assetID: String
    ) async throws -> UncheckedAVAsset {
        let manager = PHImageManager.default()
        let state = PhotoKitRequestState<UncheckedAVAsset>(manager: manager)
        let token = registerPhotoRequest(state)
        defer { pendingPhotoRequests.removeValue(forKey: token) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UncheckedAVAsset, Error>) in
                guard state.installContinuation(continuation) else { return }
                state.installTimeout(after: 900, error: PhotoKitPhotosClientError.mediaRequestTimedOut(assetID))
                let requestID = manager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else if ((info?[PHImageCancelledKey] as? NSNumber)?.boolValue) == true {
                        state.finish(.failure(CancellationError()))
                    } else if let avAsset {
                        state.finish(.success(UncheckedAVAsset(value: avAsset)))
                    } else {
                        state.finish(.failure(PhotoKitPhotosClientError.mediaUnavailable(assetID)))
                    }
                }
                state.installRequestID(requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func requestVideoExportSession(
        for asset: PHAsset,
        options: PHVideoRequestOptions,
        exportPreset: String
    ) async throws -> UncheckedExportSession? {
        let manager = PHImageManager.default()
        let state = PhotoKitRequestState<UncheckedExportSession?>(manager: manager)
        let token = registerPhotoRequest(state)
        defer { pendingPhotoRequests.removeValue(forKey: token) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UncheckedExportSession?, Error>) in
                guard state.installContinuation(continuation) else { return }
                state.installTimeout(
                    after: 60,
                    error: PhotoKitPhotosClientError.mediaRequestTimedOut(asset.localIdentifier)
                )
                let requestID = manager.requestExportSession(
                    forVideo: asset,
                    options: options,
                    exportPreset: exportPreset
                ) { session, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else if ((info?[PHImageCancelledKey] as? NSNumber)?.boolValue) == true {
                        state.finish(.failure(CancellationError()))
                    } else {
                        state.finish(.success(session.map { UncheckedExportSession(value: $0) }))
                    }
                }
                state.installRequestID(requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        options: PHImageRequestOptions
    ) async throws -> Data? {
        let manager = PHImageManager.default()
        let state = PhotoKitRequestState<Data?>(manager: manager)
        let token = registerPhotoRequest(state)
        defer { pendingPhotoRequests.removeValue(forKey: token) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                guard state.installContinuation(continuation) else { return }
                state.installTimeout(
                    after: 3,
                    error: PhotoKitPhotosClientError.mediaRequestTimedOut(asset.localIdentifier)
                )
                let requestID = manager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                        return
                    }
                    if ((info?[PHImageCancelledKey] as? NSNumber)?.boolValue) == true {
                        state.finish(.failure(CancellationError()))
                        return
                    }
                    if ((info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue) == true { return }
                    guard let image, let tiff = image.tiffRepresentation else {
                        state.finish(.success(nil))
                        return
                    }
                    state.finish(.success(tiff))
                }
                state.installRequestID(requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func registerPhotoRequest(_ state: any PhotoKitRequestCancelling) -> UUID {
        let token = UUID()
        if photoRequestsCancelledForRun {
            state.cancel()
        } else {
            pendingPhotoRequests[token] = state
        }
        return token
    }

    private func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }

}

extension PhotoKitPhotosClient: PhotoLibraryDiagnosticsPhotoKitAccessing {}
