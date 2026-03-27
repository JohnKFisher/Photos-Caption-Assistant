@preconcurrency import Photos
import Foundation

enum ExperimentalPhotoKitScanError: Error, LocalizedError {
    case unsupportedScope(String)
    case albumNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedScope(scopeDescription):
            return "Experimental PhotoKit scan reader supports only library and plain album scopes. Unsupported scope: \(scopeDescription)."
        case let .albumNotFound(albumID):
            return "Experimental PhotoKit scan reader could not resolve album id: \(albumID)."
        }
    }
}

actor ExperimentalPhotoKitScanReader {
    private let includeHiddenAssets: Bool

    init(includeHiddenAssets: Bool = true) {
        self.includeHiddenAssets = includeHiddenAssets
    }

    func count(scope: ScopeSource) async throws -> Int {
        try fetchResult(for: scope).count
    }

    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset] {
        guard let pageRange = Self.pageRange(
            totalCount: try fetchResult(for: scope).count,
            offset: offset,
            limit: limit
        ) else {
            return []
        }

        let result = try fetchResult(for: scope)
        var assets: [MediaAsset] = []
        assets.reserveCapacity(pageRange.count)

        for index in pageRange {
            assets.append(makeMediaAsset(from: result.object(at: index)))
        }

        return assets
    }

    func canResolveAlbum(id: String) async -> Bool {
        resolveAlbumCollection(id: id) != nil
    }

    func withResolvedPlainAlbumCounts(_ albums: [AlbumSummary]) async -> [AlbumSummary] {
        guard !albums.isEmpty else {
            return []
        }

        let assetFetchOptions = PHFetchOptions()
        assetFetchOptions.includeHiddenAssets = includeHiddenAssets
        assetFetchOptions.wantsIncrementalChangeDetails = false

        return albums.map { album in
            guard let collection = resolveAlbumCollection(id: album.id) else {
                return album
            }

            return AlbumSummary(
                id: album.id,
                name: album.name,
                itemCount: PHAsset.fetchAssets(in: collection, options: assetFetchOptions).count
            )
        }
    }

    func canHandleIncrementalScan(scope: ScopeSource) async -> Bool {
        switch scope {
        case .library:
            return true
        case let .album(id):
            return await canResolveAlbum(id: id)
        case .picker, .captionWorkflow:
            return false
        }
    }

    func inspectAsset(id: String) async -> PhotoLibraryResolvedMediaItem? {
        guard let asset = resolveAsset(id: id) else {
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
        var inspections: [String: PhotoLibraryResolvedMediaItem] = [:]
        inspections.reserveCapacity(ids.count)

        for id in ids {
            if let inspection = await inspectAsset(id: id) {
                inspections[id] = inspection
            }
        }

        return inspections
    }

    static func identifierCandidates(from rawID: String) -> [String] {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates = [trimmed]
        let base = baseIdentifier(from: trimmed)
        if !base.isEmpty, !candidates.contains(base) {
            candidates.append(base)
        }
        return candidates
    }

    static func pageRange(totalCount: Int, offset: Int, limit: Int) -> Range<Int>? {
        guard totalCount > 0 else { return nil }
        let safeOffset = max(0, offset)
        guard safeOffset < totalCount else { return nil }
        let safeLimit = max(1, limit)
        let endIndex = min(totalCount, safeOffset + safeLimit)
        return safeOffset..<endIndex
    }

    private func fetchResult(for scope: ScopeSource) throws -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeHiddenAssets = includeHiddenAssets
        options.wantsIncrementalChangeDetails = false

        switch scope {
        case .library:
            return PHAsset.fetchAssets(with: options)
        case let .album(id):
            guard let collection = resolveAlbumCollection(id: id) else {
                throw ExperimentalPhotoKitScanError.albumNotFound(id)
            }
            return PHAsset.fetchAssets(in: collection, options: options)
        case .picker:
            throw ExperimentalPhotoKitScanError.unsupportedScope("picker")
        case .captionWorkflow:
            throw ExperimentalPhotoKitScanError.unsupportedScope("captionWorkflow")
        }
    }

    private func resolveAlbumCollection(id: String) -> PHAssetCollection? {
        let candidates = Self.identifierCandidates(from: id)
        guard !candidates.isEmpty else { return nil }

        let direct = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: candidates, options: nil)
        if let match = direct.firstObject {
            return match
        }

        for candidate in candidates where !candidate.contains("/") {
            let options = PHFetchOptions()
            options.fetchLimit = 5
            options.predicate = NSPredicate(format: "localIdentifier BEGINSWITH %@", "\(candidate)/")
            let prefix = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
            if let match = prefix.firstObject {
                return match
            }
        }

        return nil
    }

    private func resolveAsset(id: String) -> PHAsset? {
        let candidates = Self.identifierCandidates(from: id)
        guard !candidates.isEmpty else { return nil }

        let direct = PHAsset.fetchAssets(withLocalIdentifiers: candidates, options: nil)
        if let match = direct.firstObject {
            return match
        }

        for candidate in candidates where !candidate.contains("/") {
            let options = PHFetchOptions()
            options.fetchLimit = 5
            options.predicate = NSPredicate(format: "localIdentifier BEGINSWITH %@", "\(candidate)/")
            let prefix = PHAsset.fetchAssets(with: options)
            if let match = prefix.firstObject {
                return match
            }
        }

        return nil
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
        if let preferred = preferredResource(from: resources, mediaKind: mediaKind(for: asset)),
           !preferred.originalFilename.isEmpty
        {
            return preferred.originalFilename
        }

        if let fallback = resources.first, !fallback.originalFilename.isEmpty {
            return fallback.originalFilename
        }

        return fallbackFilename(for: asset)
    }

    private func preferredResource(
        from resources: [PHAssetResource],
        mediaKind: MediaKind
    ) -> PHAssetResource? {
        let preferredTypes: [PHAssetResourceType]
        switch mediaKind {
        case .photo:
            preferredTypes = [.photo, .fullSizePhoto, .alternatePhoto]
        case .video:
            preferredTypes = [.video, .fullSizeVideo, .pairedVideo, .fullSizePairedVideo]
        }

        for preferredType in preferredTypes {
            if let match = resources.first(where: { $0.type == preferredType }) {
                return match
            }
        }

        return nil
    }

    private func mediaKind(for asset: PHAsset) -> MediaKind {
        asset.mediaType == .video ? .video : .photo
    }

    private func fallbackFilename(for asset: PHAsset) -> String {
        let base = Self.baseIdentifier(from: asset.localIdentifier)
        let suffix = mediaKind(for: asset) == .video ? "mov" : "jpg"
        return base.isEmpty ? "asset.\(suffix)" : "\(base).\(suffix)"
    }

    private static func baseIdentifier(from identifier: String) -> String {
        guard let slashIndex = identifier.firstIndex(of: "/") else {
            return identifier
        }
        return String(identifier[..<slashIndex])
    }
}

extension ExperimentalPhotoKitScanReader: ScopedIncrementalScanSource {}
