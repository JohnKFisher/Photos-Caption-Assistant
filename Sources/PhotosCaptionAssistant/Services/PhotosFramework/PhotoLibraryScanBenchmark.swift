import Foundation
import Photos

struct PhotoLibraryScanBenchmarkConfiguration: Sendable, Equatable {
    static let defaultPageSizes = [250, 128, 64]
    static let defaultMaxItems = 1000

    let pageSizes: [Int]
    let warmIterations: Int
    let maxItems: Int?
    let configuredAlbumID: String?
    let configuredAlbumName: String?

    init(
        pageSizes: [Int] = [250, 128, 64],
        warmIterations: Int = 1,
        maxItems: Int? = nil,
        configuredAlbumID: String? = nil,
        configuredAlbumName: String? = nil
    ) {
        let normalizedPageSizes = pageSizes.filter { $0 > 0 }
        self.pageSizes = normalizedPageSizes.isEmpty ? Self.defaultPageSizes : normalizedPageSizes
        self.warmIterations = max(0, warmIterations)
        self.maxItems = maxItems.flatMap { $0 > 0 ? $0 : nil }
        self.configuredAlbumID = Self.normalized(configuredAlbumID)
        self.configuredAlbumName = Self.normalized(configuredAlbumName)
    }

    static let appHostedDefault = PhotoLibraryScanBenchmarkConfiguration(maxItems: defaultMaxItems)

    static func fromEnvironment(_ environment: [String: String]) -> PhotoLibraryScanBenchmarkConfiguration {
        let rawPageSizes = environment["PDC_BENCHMARK_PAGE_SIZES"] ?? defaultPageSizes.map(String.init).joined(separator: ",")
        let parsedPageSizes = rawPageSizes
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        return PhotoLibraryScanBenchmarkConfiguration(
            pageSizes: parsedPageSizes,
            warmIterations: Int(environment["PDC_BENCHMARK_WARM_ITERATIONS"] ?? "1") ?? 1,
            maxItems: maxItems(from: environment["PDC_BENCHMARK_MAX_ITEMS"]),
            configuredAlbumID: environment["PDC_BENCHMARK_ALBUM_ID"],
            configuredAlbumName: environment["PDC_BENCHMARK_ALBUM_NAME"]
        )
    }

    var sampleDescription: String {
        if let maxItems {
            return "first \(maxItems) assets per scope"
        }
        return "full scope"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func maxItems(from rawValue: String?) -> Int? {
        guard let normalized = normalized(rawValue) else {
            return defaultMaxItems
        }

        switch normalized.lowercased() {
        case "full", "all", "none", "unlimited":
            return nil
        default:
            guard let parsed = Int(normalized) else {
                return defaultMaxItems
            }
            return parsed > 0 ? parsed : nil
        }
    }
}

enum PhotoLibraryScanBenchmarkOutcome {
    case completed(PhotoLibraryScanBenchmarkCompletedRun)
    case skipped(String)
}

struct PhotoLibraryScanBenchmarkCompletedRun {
    let report: PhotoKitScanBenchmarkReport
    let reportURL: URL
    let notices: [String]
}

actor PhotoLibraryScanBenchmarkRunner {
    typealias ProgressHandler = @Sendable (String) async -> Void
    private static let identitySampleLimit = 24
    private static let acquisitionProofSampleLimit = 8
    private static let acquisitionPreviewPixelSize = 1600

    private let appleScriptClient: any PhotoLibraryDiagnosticsAppleScriptAccessing
    private let photoKitReader: any PhotoLibraryDiagnosticsPhotoKitAccessing
    private let fileManager: FileManager
    private let authorizationStatusProvider: @Sendable () -> PHAuthorizationStatus

    init(
        appleScriptClient: any PhotoLibraryDiagnosticsAppleScriptAccessing,
        photoKitReader: any PhotoLibraryDiagnosticsPhotoKitAccessing = ExperimentalPhotoKitScanReader(),
        fileManager: FileManager = .default,
        authorizationStatusProvider: @escaping @Sendable () -> PHAuthorizationStatus = {
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
    ) {
        self.appleScriptClient = appleScriptClient
        self.photoKitReader = photoKitReader
        self.fileManager = fileManager
        self.authorizationStatusProvider = authorizationStatusProvider
    }

    func run(
        configuration: PhotoLibraryScanBenchmarkConfiguration = .appHostedDefault,
        progressHandler: ProgressHandler? = nil
    ) async throws -> PhotoLibraryScanBenchmarkOutcome {
        let authorizationStatus = authorizationStatusProvider()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return .skipped("Photos library access is unavailable for this process (status=\(authorizationStatus.rawValue)).")
        }

        await reportProgress(
            "Preparing scan benchmark (\(configuration.sampleDescription))...",
            using: progressHandler
        )

        guard await appleScriptClient.verifyAutomationAccess() else {
            return .skipped("Photos automation access is unavailable for this process.")
        }

        await reportProgress("Checking benchmark scopes...", using: progressHandler)
        var scopePlans: [PhotoLibraryBenchmarkScopePlan] = [.library]
        let discoveredAlbumScope = try await discoverAlbumScope(configuration: configuration)
        if let notice = discoveredAlbumScope.notice {
            await reportProgress(notice, using: progressHandler)
        }
        if let albumScope = discoveredAlbumScope.scope {
            scopePlans.append(albumScope)
            await reportProgress(
                "Benchmarking whole library plus album “\(albumScope.label)” (\(configuration.sampleDescription)).",
                using: progressHandler
            )
        } else {
            await reportProgress(
                "Benchmarking whole library only (\(configuration.sampleDescription)).",
                using: progressHandler
            )
        }

        let report = try await buildReport(
            scopePlans: scopePlans,
            configuration: configuration,
            progressHandler: progressHandler
        )
        let reportURL = try writeReport(report)
        return .completed(
            PhotoLibraryScanBenchmarkCompletedRun(
                report: report,
                reportURL: reportURL,
                notices: discoveredAlbumScope.notice.map { [$0] } ?? []
            )
        )
    }

    private func buildReport(
        scopePlans: [PhotoLibraryBenchmarkScopePlan],
        configuration: PhotoLibraryScanBenchmarkConfiguration,
        progressHandler: ProgressHandler?
    ) async throws -> PhotoKitScanBenchmarkReport {
        let backends = [
            PhotoLibraryBenchmarkBackend(
                name: "AppleScript",
                count: { scope in try await self.appleScriptClient.count(scope: scope) },
                enumerate: { scope, offset, limit in
                    try await self.appleScriptClient.enumerate(scope: scope, offset: offset, limit: limit)
                }
            ),
            PhotoLibraryBenchmarkBackend(
                name: "PhotoKitExperimental",
                count: { scope in try await self.photoKitReader.count(scope: scope) },
                enumerate: { scope, offset, limit in
                    try await self.photoKitReader.enumerate(scope: scope, offset: offset, limit: limit)
                }
            )
        ]

        var scopeReports: [PhotoKitScanBenchmarkScopeReport] = []
        for scopePlan in scopePlans {
            scopeReports.append(
                try await benchmarkScope(
                    scopePlan: scopePlan,
                    configuration: configuration,
                    backends: backends,
                    progressHandler: progressHandler
                )
            )
        }

        return PhotoKitScanBenchmarkReport(
            generatedAt: Date(),
            pageSizes: configuration.pageSizes,
            warmIterations: configuration.warmIterations,
            maxItems: configuration.maxItems,
            scopes: scopeReports
        )
    }

    private func benchmarkScope(
        scopePlan: PhotoLibraryBenchmarkScopePlan,
        configuration: PhotoLibraryScanBenchmarkConfiguration,
        backends: [PhotoLibraryBenchmarkBackend],
        progressHandler: ProgressHandler?
    ) async throws -> PhotoKitScanBenchmarkScopeReport {
        var countMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>] = [:]
        var firstAssetMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>] = [:]
        var firstPageMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>] = [:]

        for backend in backends {
            await reportProgress(
                "\(scopePlan.label): \(backend.name) count...",
                using: progressHandler
            )
            countMeasurements[backend.name] = try await measureCount(
                backend: backend,
                scope: scopePlan.scope,
                warmIterations: configuration.warmIterations
            )
            await reportProgress(
                "\(scopePlan.label): \(backend.name) first asset...",
                using: progressHandler
            )
            firstAssetMeasurements[backend.name] = try await measureEnumerateCall(
                backend: backend,
                scope: scopePlan.scope,
                offset: 0,
                limit: 1,
                warmIterations: configuration.warmIterations
            )
            await reportProgress(
                "\(scopePlan.label): \(backend.name) first page (\(configuration.pageSizes[0]))...",
                using: progressHandler
            )
            firstPageMeasurements[backend.name] = try await measureEnumerateCall(
                backend: backend,
                scope: scopePlan.scope,
                offset: 0,
                limit: configuration.pageSizes[0],
                warmIterations: configuration.warmIterations
            )
        }

        var parityByPageSize: [PhotoKitScanBenchmarkPageParityReport] = []
        var fullScanMeasurements: [String: PhotoKitScanBenchmarkFullScanMeasurement] = [:]
        var referencePhotoKitAssets: [MediaAsset] = []

        for (index, pageSize) in configuration.pageSizes.enumerated() {
            await reportProgress(
                "\(scopePlan.label): AppleScript parity scan page size \(pageSize) (\(progressLimitText(configuration.maxItems))).",
                using: progressHandler
            )
            let appleScriptScan = try await scanAllAssets(
                backend: backends[0],
                scope: scopePlan.scope,
                pageSize: pageSize,
                warmIterations: index == 0 ? configuration.warmIterations : 0,
                maxItems: configuration.maxItems,
                scopeLabel: scopePlan.label,
                progressHandler: progressHandler
            )
            await reportProgress(
                "\(scopePlan.label): PhotoKit parity scan page size \(pageSize) (\(progressLimitText(configuration.maxItems))).",
                using: progressHandler
            )
            let photoKitScan = try await scanAllAssets(
                backend: backends[1],
                scope: scopePlan.scope,
                pageSize: pageSize,
                warmIterations: index == 0 ? configuration.warmIterations : 0,
                maxItems: configuration.maxItems,
                scopeLabel: scopePlan.label,
                progressHandler: progressHandler
            )

            if index == 0 {
                fullScanMeasurements[backends[0].name] = appleScriptScan.measurement
                fullScanMeasurements[backends[1].name] = photoKitScan.measurement
                referencePhotoKitAssets = photoKitScan.assets
            }

            parityByPageSize.append(
                makeParityReport(
                    pageSize: pageSize,
                    appleScriptAssets: appleScriptScan.assets,
                    photoKitAssets: photoKitScan.assets
                )
            )
        }

        await reportProgress(
            "\(scopePlan.label): read-only identity proof on sampled PhotoKit assets...",
            using: progressHandler
        )
        let identityProof = try await makeIdentityProof(
            sampledAssets: referencePhotoKitAssets,
            progressHandler: progressHandler
        )

        return PhotoKitScanBenchmarkScopeReport(
            scopeLabel: scopePlan.label,
            scopeDescription: scopePlan.description,
            appleScriptCount: countMeasurements["AppleScript"]?.result ?? -1,
            photoKitCount: countMeasurements["PhotoKitExperimental"]?.result ?? -1,
            countParity: countMeasurements["AppleScript"]?.result == countMeasurements["PhotoKitExperimental"]?.result,
            countMeasurements: countMeasurements,
            firstAssetMeasurements: firstAssetMeasurements,
            firstPageMeasurements: firstPageMeasurements,
            fullScanMeasurements: fullScanMeasurements,
            parityByPageSize: parityByPageSize,
            identityProof: identityProof
        )
    }

    private func makeIdentityProof(
        sampledAssets: [MediaAsset],
        progressHandler: ProgressHandler?
    ) async throws -> PhotoLibraryIdentityProofReport {
        let samples = Array(sampledAssets.prefix(Self.identitySampleLimit))
        let acquisitionLimit = min(Self.acquisitionProofSampleLimit, samples.count)

        var identitySamples: [PhotoLibraryIdentitySample] = []
        identitySamples.reserveCapacity(samples.count)
        var unresolvedAssetIDs: [String] = []
        var fallbackResolutionCount = 0
        var canonicalIDParityCount = 0
        var filenameParityCount = 0
        var mediaKindParityCount = 0
        var captureDateParityCount = 0
        var acquisitionVerifiedCount = 0
        var writePathSafeCount = 0
        let sampleIDs = samples.map(\.id)
        let photoKitInspections = await photoKitReader.inspectAssets(ids: sampleIDs)
        let appleInspections = await appleScriptClient.inspectResolvedMediaItems(ids: sampleIDs)

        for (index, asset) in samples.enumerated() {
            if index < acquisitionLimit || index == 0 || index == samples.count - 1 {
                await reportProgress(
                    "Identity proof: resolving asset \(index + 1) of \(samples.count)...",
                    using: progressHandler
                )
            }

            guard let photoKitInspection = photoKitInspections[asset.id] else {
                unresolvedAssetIDs.append(asset.id)
                identitySamples.append(
                    PhotoLibraryIdentitySample(
                        requestedPhotoKitID: asset.id,
                        photoKitResolvedID: asset.id,
                        appleScriptResolvedID: nil,
                        resolutionStrategy: nil,
                        canonicalIDMatch: false,
                        filenameMatch: false,
                        mediaKindMatch: false,
                        captureDateMatch: false,
                        writePathResolvable: false,
                        writePathSafe: false,
                        acquisitionCheck: nil,
                        notes: ["PhotoKit could not re-resolve the sampled asset."]
                    )
                )
                continue
            }

            let appleInspection = appleInspections[asset.id]
            let canonicalIDMatch = appleInspection.map { photoKitInspection.matchesIdentity(of: $0) } ?? false
            let filenameMatch = appleInspection?.filename == photoKitInspection.filename
            let mediaKindMatch = appleInspection?.kind == photoKitInspection.kind
            let captureDateMatch = appleInspection?.captureDate == photoKitInspection.captureDate
            let writePathResolvable = appleInspection != nil
            let writePathSafe = writePathResolvable && canonicalIDMatch && filenameMatch && mediaKindMatch

            if !writePathResolvable {
                unresolvedAssetIDs.append(asset.id)
            }
            if appleInspection?.usedFallbackResolution == true {
                fallbackResolutionCount += 1
            }
            if canonicalIDMatch { canonicalIDParityCount += 1 }
            if filenameMatch { filenameParityCount += 1 }
            if mediaKindMatch { mediaKindParityCount += 1 }
            if captureDateMatch { captureDateParityCount += 1 }
            if writePathSafe { writePathSafeCount += 1 }

            let acquisitionCheck: PhotoLibraryIdentityAcquireCheck?
            if index < acquisitionLimit {
                acquisitionCheck = await verifyAcquisitionPath(for: asset)
                if acquisitionCheck?.verified == true {
                    acquisitionVerifiedCount += 1
                }
            } else {
                acquisitionCheck = nil
            }

            var notes: [String] = []
            if appleInspection?.usedFallbackResolution == true {
                notes.append("AppleScript resolved the asset using base-ID fallback.")
            }
            if !captureDateMatch {
                notes.append("Capture date drifted between PhotoKit and AppleScript.")
            }
            if !writePathResolvable {
                notes.append("AppleScript could not resolve the PhotoKit asset ID.")
            } else if !writePathSafe {
                notes.append("AppleScript resolved the asset, but canonical identity or key fields did not fully match.")
            }

            identitySamples.append(
                PhotoLibraryIdentitySample(
                    requestedPhotoKitID: asset.id,
                    photoKitResolvedID: photoKitInspection.resolvedID,
                    appleScriptResolvedID: appleInspection?.resolvedID,
                    resolutionStrategy: appleInspection?.resolutionStrategy,
                    canonicalIDMatch: canonicalIDMatch,
                    filenameMatch: filenameMatch,
                    mediaKindMatch: mediaKindMatch,
                    captureDateMatch: captureDateMatch,
                    writePathResolvable: writePathResolvable,
                    writePathSafe: writePathSafe,
                    acquisitionCheck: acquisitionCheck,
                    notes: notes
                )
            )
        }

        return PhotoLibraryIdentityProofReport(
            sampledAssetCount: samples.count,
            acquisitionSampleCount: acquisitionLimit,
            unresolvedAssetIDs: unresolvedAssetIDs,
            fallbackResolutionCount: fallbackResolutionCount,
            canonicalIDParityCount: canonicalIDParityCount,
            filenameParityCount: filenameParityCount,
            mediaKindParityCount: mediaKindParityCount,
            captureDateParityCount: captureDateParityCount,
            acquisitionVerifiedCount: acquisitionVerifiedCount,
            writePathSafeCount: writePathSafeCount,
            samples: identitySamples
        )
    }

    private func verifyAcquisitionPath(
        for asset: MediaAsset
    ) async -> PhotoLibraryIdentityAcquireCheck {
        do {
            switch asset.kind {
            case .photo:
                if let previewData = try await appleScriptClient.photoPreviewJPEGData(
                    id: asset.id,
                    maxPixelSize: Self.acquisitionPreviewPixelSize
                ), !previewData.isEmpty {
                    return PhotoLibraryIdentityAcquireCheck(
                        verified: true,
                        method: "photo-preview-jpeg",
                        errorMessage: nil
                    )
                }

                let exportedURL = try await appleScriptClient.exportAssetToTemporaryURL(id: asset.id, kind: .photo)
                cleanupTemporaryArtifact(at: exportedURL)
                return PhotoLibraryIdentityAcquireCheck(
                    verified: true,
                    method: "photo-export-fallback",
                    errorMessage: nil
                )
            case .video:
                let exportedURL = try await appleScriptClient.exportAssetToTemporaryURL(id: asset.id, kind: .video)
                cleanupTemporaryArtifact(at: exportedURL)
                return PhotoLibraryIdentityAcquireCheck(
                    verified: true,
                    method: "video-export",
                    errorMessage: nil
                )
            }
        } catch {
            return PhotoLibraryIdentityAcquireCheck(
                verified: false,
                method: asset.kind == .photo ? "photo-acquire" : "video-export",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func cleanupTemporaryArtifact(at url: URL) {
        let root = url.deletingLastPathComponent()
        let storagePaths = AppStoragePaths.make(fileManager: fileManager)
        let allowedRoots = [
            storagePaths.photoExportTempRoot,
            storagePaths.videoExportTempRoot,
            storagePaths.photoPreviewTempRoot
        ]
        guard allowedRoots.contains(where: { AppStoragePaths.contains(root, within: $0) }) else {
            return
        }
        try? fileManager.removeItem(at: root)
    }

    private func makeParityReport(
        pageSize: Int,
        appleScriptAssets: [MediaAsset],
        photoKitAssets: [MediaAsset]
    ) -> PhotoKitScanBenchmarkPageParityReport {
        let countMatch = appleScriptAssets.count == photoKitAssets.count
        let idMatch = appleScriptAssets.map(\.id) == photoKitAssets.map(\.id)
        let filenameMatch = appleScriptAssets.map(\.filename) == photoKitAssets.map(\.filename)
        let mediaKindMatch = appleScriptAssets.map(\.kind) == photoKitAssets.map(\.kind)
        let captureDateMatch = appleScriptAssets.map(\.captureDate) == photoKitAssets.map(\.captureDate)

        let firstMismatchIndex = zip(appleScriptAssets, photoKitAssets).enumerated().first { _, pair in
            pair.0 != pair.1
        }?.offset ?? {
            countMatch ? nil : min(appleScriptAssets.count, photoKitAssets.count)
        }()

        return PhotoKitScanBenchmarkPageParityReport(
            pageSize: pageSize,
            appleScriptAssetCount: appleScriptAssets.count,
            photoKitAssetCount: photoKitAssets.count,
            idsMatch: idMatch,
            filenamesMatch: filenameMatch,
            mediaKindsMatch: mediaKindMatch,
            captureDatesMatch: captureDateMatch,
            firstMismatchIndex: firstMismatchIndex
        )
    }

    private func measureCount(
        backend: PhotoLibraryBenchmarkBackend,
        scope: ScopeSource,
        warmIterations: Int
    ) async throws -> PhotoKitScanBenchmarkOperationMeasurement<Int> {
        let cold = try await measureOnce {
            try await backend.count(scope)
        }

        var warmSeconds: [Double] = []
        for _ in 0..<warmIterations {
            let warm = try await measureOnce {
                try await backend.count(scope)
            }
            warmSeconds.append(warm.elapsedSeconds)
        }

        return PhotoKitScanBenchmarkOperationMeasurement(
            result: cold.value,
            coldSeconds: cold.elapsedSeconds,
            warmSeconds: warmSeconds,
            memoryDeltaBytes: nil,
            notes: []
        )
    }

    private func measureEnumerateCall(
        backend: PhotoLibraryBenchmarkBackend,
        scope: ScopeSource,
        offset: Int,
        limit: Int,
        warmIterations: Int
    ) async throws -> PhotoKitScanBenchmarkOperationMeasurement<Int> {
        let cold = try await measureOnce {
            try await backend.enumerate(scope, offset, limit)
        }

        var warmSeconds: [Double] = []
        for _ in 0..<warmIterations {
            let warm = try await measureOnce {
                try await backend.enumerate(scope, offset, limit)
            }
            warmSeconds.append(warm.elapsedSeconds)
        }

        return PhotoKitScanBenchmarkOperationMeasurement(
            result: cold.value.count,
            coldSeconds: cold.elapsedSeconds,
            warmSeconds: warmSeconds,
            memoryDeltaBytes: nil,
            notes: []
        )
    }

    private func scanAllAssets(
        backend: PhotoLibraryBenchmarkBackend,
        scope: ScopeSource,
        pageSize: Int,
        warmIterations: Int,
        maxItems: Int?,
        scopeLabel: String,
        progressHandler: ProgressHandler?
    ) async throws -> PhotoLibraryBenchmarkScanResult {
        let cold = try await measureFullScan(
            backend: backend,
            scope: scope,
            pageSize: pageSize,
            maxItems: maxItems,
            scopeLabel: scopeLabel,
            progressHandler: progressHandler
        )

        var warmSeconds: [Double] = []
        for _ in 0..<warmIterations {
            let warm = try await measureFullScan(
                backend: backend,
                scope: scope,
                pageSize: pageSize,
                maxItems: maxItems,
                scopeLabel: scopeLabel,
                progressHandler: nil
            )
            warmSeconds.append(warm.measurement.coldSeconds)
        }

        return PhotoLibraryBenchmarkScanResult(
            assets: cold.assets,
            measurement: PhotoKitScanBenchmarkFullScanMeasurement(
                result: cold.measurement.result,
                coldSeconds: cold.measurement.coldSeconds,
                warmSeconds: warmSeconds,
                memoryDeltaBytes: cold.measurement.memoryDeltaBytes,
                timeoutCount: cold.measurement.timeoutCount,
                notes: cold.measurement.notes
            )
        )
    }

    private func measureFullScan(
        backend: PhotoLibraryBenchmarkBackend,
        scope: ScopeSource,
        pageSize: Int,
        maxItems: Int?,
        scopeLabel: String,
        progressHandler: ProgressHandler?
    ) async throws -> PhotoLibraryBenchmarkScanResult {
        let memoryBefore = currentResidentMemoryBytes()
        let started = DispatchTime.now().uptimeNanoseconds

        var assets: [MediaAsset] = []
        var offset = 0
        var timeoutCount = 0
        let progressInterval = max(1, min(pageSize, maxItems ?? pageSize))

        while true {
            do {
                let page = try await backend.enumerate(scope, offset, pageSize)
                if page.isEmpty {
                    break
                }
                assets.append(contentsOf: page)
                offset += page.count
                if !assets.isEmpty, assets.count % progressInterval == 0 || page.count < pageSize {
                    await reportProgress(
                        "\(scopeLabel): \(backend.name) scanned \(assets.count)\(progressLimitSuffix(maxItems))...",
                        using: progressHandler
                    )
                }
                if let maxItems, assets.count >= maxItems {
                    assets = Array(assets.prefix(maxItems))
                    await reportProgress(
                        "\(scopeLabel): \(backend.name) reached cap at \(assets.count) assets.",
                        using: progressHandler
                    )
                    break
                }
            } catch {
                if error.localizedDescription.localizedCaseInsensitiveContains("timed out") {
                    timeoutCount += 1
                }
                throw error
            }
        }

        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        let memoryAfter = currentResidentMemoryBytes()
        let memoryDelta: Int64? = {
            guard let memoryBefore, let memoryAfter else { return nil }
            return Int64(memoryAfter) - Int64(memoryBefore)
        }()

        return PhotoLibraryBenchmarkScanResult(
            assets: assets,
            measurement: PhotoKitScanBenchmarkFullScanMeasurement(
                result: assets.count,
                coldSeconds: elapsedSeconds,
                warmSeconds: [],
                memoryDeltaBytes: memoryDelta,
                timeoutCount: timeoutCount,
                notes: maxItems.map { ["Capped at \($0) assets for this run."] } ?? []
            )
        )
    }

    private func discoverAlbumScope(
        configuration: PhotoLibraryScanBenchmarkConfiguration
    ) async throws -> PhotoLibraryBenchmarkScopeDiscovery {
        if let configuredAlbumID = configuration.configuredAlbumID {
            let configuredScope = PhotoLibraryBenchmarkScopePlan(
                label: configuration.configuredAlbumName ?? "Configured Album",
                description: "album(\(configuredAlbumID))",
                scope: .album(id: configuredAlbumID)
            )
            guard await photoKitReader.canResolveAlbum(id: configuredAlbumID) else {
                return PhotoLibraryBenchmarkScopeDiscovery(
                    scope: nil,
                    notice: "Skipping configured album benchmark because PhotoKit could not resolve album id \(configuredAlbumID)."
                )
            }
            return PhotoLibraryBenchmarkScopeDiscovery(scope: configuredScope, notice: nil)
        }

        let albums = try await appleScriptClient.listUserAlbums()
        for album in albums.prefix(10) {
            let count = try await appleScriptClient.count(scope: .album(id: album.id))
            if count > 0 {
                guard await photoKitReader.canResolveAlbum(id: album.id) else {
                    continue
                }
                return PhotoLibraryBenchmarkScopeDiscovery(
                    scope: PhotoLibraryBenchmarkScopePlan(
                        label: album.name,
                        description: "album(\(album.id))",
                        scope: .album(id: album.id)
                    ),
                    notice: nil
                )
            }
        }

        return PhotoLibraryBenchmarkScopeDiscovery(
            scope: nil,
            notice: "Skipping album benchmark because no AppleScript album in the sampled set could be resolved by the experimental PhotoKit reader."
        )
    }

    private func writeReport(_ report: PhotoKitScanBenchmarkReport) throws -> URL {
        let root = AppStoragePaths.make(fileManager: fileManager).benchmarkTempRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("photokit-scan-benchmark-report.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: [.atomic])
        return url
    }

    private func measureOnce<T: Sendable>(
        operation: @Sendable () async throws -> T
    ) async throws -> PhotoLibraryBenchmarkTimedValue<T> {
        let started = DispatchTime.now().uptimeNanoseconds
        let value = try await operation()
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        return PhotoLibraryBenchmarkTimedValue(value: value, elapsedSeconds: elapsedSeconds)
    }

    private func currentResidentMemoryBytes() -> UInt64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let kilobytes = UInt64(text) else {
            return nil
        }
        return kilobytes * 1024
    }

    private func reportProgress(
        _ message: String,
        using progressHandler: ProgressHandler?
    ) async {
        await progressHandler?(message)
    }

    private func progressLimitText(_ maxItems: Int?) -> String {
        if let maxItems {
            return "first \(maxItems)"
        }
        return "full scope"
    }

    private func progressLimitSuffix(_ maxItems: Int?) -> String {
        if let maxItems {
            return " of ~\(maxItems)"
        }
        return ""
    }
}

private struct PhotoLibraryBenchmarkBackend {
    let name: String
    let count: @Sendable (ScopeSource) async throws -> Int
    let enumerate: @Sendable (ScopeSource, Int, Int) async throws -> [MediaAsset]
}

private struct PhotoLibraryBenchmarkScopePlan {
    let label: String
    let description: String
    let scope: ScopeSource

    static let library = PhotoLibraryBenchmarkScopePlan(
        label: "Whole Library",
        description: "library",
        scope: .library
    )
}

private struct PhotoLibraryBenchmarkScopeDiscovery {
    let scope: PhotoLibraryBenchmarkScopePlan?
    let notice: String?
}

private struct PhotoLibraryBenchmarkTimedValue<T: Sendable>: Sendable {
    let value: T
    let elapsedSeconds: Double
}

private struct PhotoLibraryBenchmarkScanResult {
    let assets: [MediaAsset]
    let measurement: PhotoKitScanBenchmarkFullScanMeasurement
}

struct PhotoKitScanBenchmarkReport: Codable, Sendable {
    let generatedAt: Date
    let pageSizes: [Int]
    let warmIterations: Int
    let maxItems: Int?
    let scopes: [PhotoKitScanBenchmarkScopeReport]
}

struct PhotoKitScanBenchmarkScopeReport: Codable, Sendable {
    let scopeLabel: String
    let scopeDescription: String
    let appleScriptCount: Int
    let photoKitCount: Int
    let countParity: Bool
    let countMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>]
    let firstAssetMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>]
    let firstPageMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>]
    let fullScanMeasurements: [String: PhotoKitScanBenchmarkFullScanMeasurement]
    let parityByPageSize: [PhotoKitScanBenchmarkPageParityReport]
    let identityProof: PhotoLibraryIdentityProofReport

    var summaryLine: String {
        let countText = countParity ? "count-match" : "count-mismatch"
        let orderText = parityByPageSize.allSatisfy(\.fullyMatches) ? "order-parity-ok" : "order-parity-drift"
        let identityText = identityProof.writePathSafe ? "identity-safe" : "identity-drift"
        let captureDateText = identityProof.captureDateDriftDetected ? "capture-date-drift" : "capture-date-ok"
        return "[PhotoKitScanBenchmark] \(scopeLabel): \(countText), \(identityText), \(orderText), \(captureDateText)"
    }
}

struct PhotoKitScanBenchmarkOperationMeasurement<ResultValue: Codable & Sendable>: Codable, Sendable {
    let result: ResultValue
    let coldSeconds: Double
    let warmSeconds: [Double]
    let memoryDeltaBytes: Int64?
    let notes: [String]
}

struct PhotoKitScanBenchmarkFullScanMeasurement: Codable, Sendable {
    let result: Int
    let coldSeconds: Double
    let warmSeconds: [Double]
    let memoryDeltaBytes: Int64?
    let timeoutCount: Int
    let notes: [String]
}

struct PhotoKitScanBenchmarkPageParityReport: Codable, Sendable {
    let pageSize: Int
    let appleScriptAssetCount: Int
    let photoKitAssetCount: Int
    let idsMatch: Bool
    let filenamesMatch: Bool
    let mediaKindsMatch: Bool
    let captureDatesMatch: Bool
    let firstMismatchIndex: Int?

    var fullyMatches: Bool {
        idsMatch
            && filenamesMatch
            && mediaKindsMatch
            && captureDatesMatch
            && appleScriptAssetCount == photoKitAssetCount
    }
}
