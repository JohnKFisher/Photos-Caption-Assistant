import Foundation
import Photos

struct PhotoLibraryScanBenchmarkConfiguration: Sendable, Equatable {
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
        self.pageSizes = normalizedPageSizes.isEmpty ? [250, 128, 64] : normalizedPageSizes
        self.warmIterations = max(0, warmIterations)
        self.maxItems = maxItems.flatMap { $0 > 0 ? $0 : nil }
        self.configuredAlbumID = Self.normalized(configuredAlbumID)
        self.configuredAlbumName = Self.normalized(configuredAlbumName)
    }

    static let appHostedDefault = PhotoLibraryScanBenchmarkConfiguration()

    static func fromEnvironment(_ environment: [String: String]) -> PhotoLibraryScanBenchmarkConfiguration {
        let rawPageSizes = environment["PDC_BENCHMARK_PAGE_SIZES"] ?? "250,128,64"
        let parsedPageSizes = rawPageSizes
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        return PhotoLibraryScanBenchmarkConfiguration(
            pageSizes: parsedPageSizes,
            warmIterations: Int(environment["PDC_BENCHMARK_WARM_ITERATIONS"] ?? "1") ?? 1,
            maxItems: Int(environment["PDC_BENCHMARK_MAX_ITEMS"] ?? ""),
            configuredAlbumID: environment["PDC_BENCHMARK_ALBUM_ID"],
            configuredAlbumName: environment["PDC_BENCHMARK_ALBUM_NAME"]
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum PhotoLibraryScanBenchmarkOutcome {
    case completed(PhotoLibraryScanBenchmarkCompletedRun)
    case skipped(String)
}

struct PhotoLibraryScanBenchmarkCompletedRun {
    let report: PhotoKitScanBenchmarkReport
    let reportURL: URL
}

actor PhotoLibraryScanBenchmarkRunner {
    private let appleScriptClient: PhotosAppleScriptClient
    private let photoKitReader: ExperimentalPhotoKitScanReader
    private let fileManager: FileManager

    init(
        appleScriptClient: PhotosAppleScriptClient,
        photoKitReader: ExperimentalPhotoKitScanReader = ExperimentalPhotoKitScanReader(),
        fileManager: FileManager = .default
    ) {
        self.appleScriptClient = appleScriptClient
        self.photoKitReader = photoKitReader
        self.fileManager = fileManager
    }

    func run(
        configuration: PhotoLibraryScanBenchmarkConfiguration = .appHostedDefault
    ) async throws -> PhotoLibraryScanBenchmarkOutcome {
        let authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return .skipped("Photos library access is unavailable for this process (status=\(authorizationStatus.rawValue)).")
        }

        guard await appleScriptClient.verifyAutomationAccess() else {
            return .skipped("Photos automation access is unavailable for this process.")
        }

        var scopePlans: [PhotoLibraryBenchmarkScopePlan] = [.library]
        if let albumScope = try await discoverAlbumScope(configuration: configuration) {
            scopePlans.append(albumScope)
        }

        let report = try await buildReport(
            scopePlans: scopePlans,
            configuration: configuration
        )
        let reportURL = try writeReport(report)
        return .completed(
            PhotoLibraryScanBenchmarkCompletedRun(
                report: report,
                reportURL: reportURL
            )
        )
    }

    private func buildReport(
        scopePlans: [PhotoLibraryBenchmarkScopePlan],
        configuration: PhotoLibraryScanBenchmarkConfiguration
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
                    backends: backends
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
        backends: [PhotoLibraryBenchmarkBackend]
    ) async throws -> PhotoKitScanBenchmarkScopeReport {
        var countMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>] = [:]
        var firstAssetMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>] = [:]
        var firstPageMeasurements: [String: PhotoKitScanBenchmarkOperationMeasurement<Int>] = [:]

        for backend in backends {
            countMeasurements[backend.name] = try await measureCount(
                backend: backend,
                scope: scopePlan.scope,
                warmIterations: configuration.warmIterations
            )
            firstAssetMeasurements[backend.name] = try await measureEnumerateCall(
                backend: backend,
                scope: scopePlan.scope,
                offset: 0,
                limit: 1,
                warmIterations: configuration.warmIterations
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

        for (index, pageSize) in configuration.pageSizes.enumerated() {
            let appleScriptScan = try await scanAllAssets(
                backend: backends[0],
                scope: scopePlan.scope,
                pageSize: pageSize,
                warmIterations: index == 0 ? configuration.warmIterations : 0,
                maxItems: configuration.maxItems
            )
            let photoKitScan = try await scanAllAssets(
                backend: backends[1],
                scope: scopePlan.scope,
                pageSize: pageSize,
                warmIterations: index == 0 ? configuration.warmIterations : 0,
                maxItems: configuration.maxItems
            )

            if index == 0 {
                fullScanMeasurements[backends[0].name] = appleScriptScan.measurement
                fullScanMeasurements[backends[1].name] = photoKitScan.measurement
            }

            parityByPageSize.append(
                makeParityReport(
                    pageSize: pageSize,
                    appleScriptAssets: appleScriptScan.assets,
                    photoKitAssets: photoKitScan.assets
                )
            )
        }

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
            parityByPageSize: parityByPageSize
        )
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
        maxItems: Int?
    ) async throws -> PhotoLibraryBenchmarkScanResult {
        let cold = try await measureFullScan(
            backend: backend,
            scope: scope,
            pageSize: pageSize,
            maxItems: maxItems
        )

        var warmSeconds: [Double] = []
        for _ in 0..<warmIterations {
            let warm = try await measureFullScan(
                backend: backend,
                scope: scope,
                pageSize: pageSize,
                maxItems: maxItems
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
        maxItems: Int?
    ) async throws -> PhotoLibraryBenchmarkScanResult {
        let memoryBefore = currentResidentMemoryBytes()
        let started = DispatchTime.now().uptimeNanoseconds

        var assets: [MediaAsset] = []
        var offset = 0
        var timeoutCount = 0

        while true {
            do {
                let page = try await backend.enumerate(scope, offset, pageSize)
                if page.isEmpty {
                    break
                }
                assets.append(contentsOf: page)
                offset += page.count
                if let maxItems, assets.count >= maxItems {
                    assets = Array(assets.prefix(maxItems))
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
    ) async throws -> PhotoLibraryBenchmarkScopePlan? {
        if let configuredAlbumID = configuration.configuredAlbumID {
            return PhotoLibraryBenchmarkScopePlan(
                label: configuration.configuredAlbumName ?? "Configured Album",
                description: "album(\(configuredAlbumID))",
                scope: .album(id: configuredAlbumID)
            )
        }

        let albums = try await appleScriptClient.listUserAlbums()
        for album in albums.prefix(10) {
            let count = try await appleScriptClient.count(scope: .album(id: album.id))
            if count > 0 {
                return PhotoLibraryBenchmarkScopePlan(
                    label: album.name,
                    description: "album(\(album.id))",
                    scope: .album(id: album.id)
                )
            }
        }

        return nil
    }

    private func writeReport(_ report: PhotoKitScanBenchmarkReport) throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoDescriptionCreatorBenchmarks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("photokit-scan-benchmark-report.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: [.atomic])
        return url
    }

    private func measureOnce<T>(
        operation: () async throws -> T
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

private struct PhotoLibraryBenchmarkTimedValue<T> {
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

    var summaryLine: String {
        let countText = countParity ? "count-match" : "count-mismatch"
        let parityText = parityByPageSize.allSatisfy(\.fullyMatches) ? "page-parity-ok" : "page-parity-drift"
        return "[PhotoKitScanBenchmark] \(scopeLabel): \(countText), \(parityText)"
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
