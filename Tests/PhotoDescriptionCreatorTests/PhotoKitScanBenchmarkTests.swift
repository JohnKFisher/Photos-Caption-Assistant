import Foundation
import Photos
import XCTest
@testable import PhotoDescriptionCreator

final class PhotoKitScanBenchmarkTests: XCTestCase {
    func testExperimentalPhotoKitReaderRejectsUnsupportedScopes() async {
        let reader = ExperimentalPhotoKitScanReader()

        do {
            _ = try await reader.count(scope: .picker(ids: ["one"]))
            XCTFail("Expected picker scope to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("picker"))
        }

        do {
            _ = try await reader.enumerate(scope: .captionWorkflow, offset: 0, limit: 1)
            XCTFail("Expected caption workflow scope to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("captionWorkflow"))
        }
    }

    func testExperimentalPhotoKitIdentifierCandidatesIncludeBaseIdentifier() {
        XCTAssertEqual(
            ExperimentalPhotoKitScanReader.identifierCandidates(from: "abc/def"),
            ["abc/def", "abc"]
        )
        XCTAssertEqual(
            ExperimentalPhotoKitScanReader.identifierCandidates(from: "abc"),
            ["abc"]
        )
    }

    func testExperimentalPhotoKitPageRangeClampsBounds() {
        XCTAssertEqual(ExperimentalPhotoKitScanReader.pageRange(totalCount: 10, offset: 2, limit: 3), 2..<5)
        XCTAssertEqual(ExperimentalPhotoKitScanReader.pageRange(totalCount: 10, offset: 9, limit: 5), 9..<10)
        XCTAssertNil(ExperimentalPhotoKitScanReader.pageRange(totalCount: 0, offset: 0, limit: 1))
        XCTAssertNil(ExperimentalPhotoKitScanReader.pageRange(totalCount: 5, offset: 5, limit: 1))
    }

    func testGenerateLocalParityAndSpeedReportWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PDC_RUN_PHOTOS_SCAN_BENCHMARK"] == "1" else {
            throw XCTSkip("Set PDC_RUN_PHOTOS_SCAN_BENCHMARK=1 to run the local Photos parity benchmark.")
        }

        let authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw XCTSkip("Photos library access is unavailable for the test process (status=\(authorizationStatus.rawValue)).")
        }

        let appleScriptClient = PhotosAppleScriptClient()
        guard await appleScriptClient.verifyAutomationAccess() else {
            throw XCTSkip("Photos automation access is unavailable for the test process.")
        }

        let photoKitReader = ExperimentalPhotoKitScanReader()
        let pageSizes = benchmarkPageSizes()
        let warmIterations = benchmarkWarmIterations()
        let maxItems = benchmarkMaxItems()

        var scopePlans: [BenchmarkScopePlan] = [.library]
        if let albumScope = try await discoverAlbumScope(using: appleScriptClient) {
            scopePlans.append(albumScope)
        }

        let report = try await buildReport(
            scopePlans: scopePlans,
            pageSizes: pageSizes,
            warmIterations: warmIterations,
            maxItems: maxItems,
            appleScriptClient: appleScriptClient,
            photoKitReader: photoKitReader
        )

        let reportURL = try writeReport(report)
        print("[PhotoKitScanBenchmarkTests] wrote report to \(reportURL.path)")

        for scope in report.scopes {
            print(scope.summaryLine)
        }

        XCTAssertFalse(report.scopes.isEmpty)
    }

    private func buildReport(
        scopePlans: [BenchmarkScopePlan],
        pageSizes: [Int],
        warmIterations: Int,
        maxItems: Int?,
        appleScriptClient: PhotosAppleScriptClient,
        photoKitReader: ExperimentalPhotoKitScanReader
    ) async throws -> PhotoKitScanBenchmarkReport {
        let backends = [
            BenchmarkBackend(
                name: "AppleScript",
                count: { scope in try await appleScriptClient.count(scope: scope) },
                enumerate: { scope, offset, limit in
                    try await appleScriptClient.enumerate(scope: scope, offset: offset, limit: limit)
                }
            ),
            BenchmarkBackend(
                name: "PhotoKitExperimental",
                count: { scope in try await photoKitReader.count(scope: scope) },
                enumerate: { scope, offset, limit in
                    try await photoKitReader.enumerate(scope: scope, offset: offset, limit: limit)
                }
            )
        ]

        var scopeReports: [BenchmarkScopeReport] = []
        for scopePlan in scopePlans {
            scopeReports.append(
                try await benchmarkScope(
                    scopePlan: scopePlan,
                    pageSizes: pageSizes,
                    warmIterations: warmIterations,
                    maxItems: maxItems,
                    backends: backends
                )
            )
        }

        return PhotoKitScanBenchmarkReport(
            generatedAt: Date(),
            pageSizes: pageSizes,
            warmIterations: warmIterations,
            maxItems: maxItems,
            scopes: scopeReports
        )
    }

    private func benchmarkScope(
        scopePlan: BenchmarkScopePlan,
        pageSizes: [Int],
        warmIterations: Int,
        maxItems: Int?,
        backends: [BenchmarkBackend]
    ) async throws -> BenchmarkScopeReport {
        var countMeasurements: [String: BenchmarkOperationMeasurement<Int>] = [:]
        var firstAssetMeasurements: [String: BenchmarkOperationMeasurement<Int>] = [:]
        var firstPageMeasurements: [String: BenchmarkOperationMeasurement<Int>] = [:]

        for backend in backends {
            countMeasurements[backend.name] = try await measureCount(
                backend: backend,
                scope: scopePlan.scope,
                warmIterations: warmIterations
            )
            firstAssetMeasurements[backend.name] = try await measureEnumerateCall(
                backend: backend,
                scope: scopePlan.scope,
                offset: 0,
                limit: 1,
                warmIterations: warmIterations
            )
            firstPageMeasurements[backend.name] = try await measureEnumerateCall(
                backend: backend,
                scope: scopePlan.scope,
                offset: 0,
                limit: pageSizes[0],
                warmIterations: warmIterations
            )
        }

        var parityByPageSize: [BenchmarkPageParityReport] = []
        var fullScanMeasurements: [String: BenchmarkFullScanMeasurement] = [:]

        for (index, pageSize) in pageSizes.enumerated() {
            let appleScriptScan = try await scanAllAssets(
                backend: backends[0],
                scope: scopePlan.scope,
                pageSize: pageSize,
                warmIterations: index == 0 ? warmIterations : 0,
                maxItems: maxItems
            )
            let photoKitScan = try await scanAllAssets(
                backend: backends[1],
                scope: scopePlan.scope,
                pageSize: pageSize,
                warmIterations: index == 0 ? warmIterations : 0,
                maxItems: maxItems
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

        return BenchmarkScopeReport(
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
    ) -> BenchmarkPageParityReport {
        let countMatch = appleScriptAssets.count == photoKitAssets.count
        let idMatch = appleScriptAssets.map(\.id) == photoKitAssets.map(\.id)
        let filenameMatch = appleScriptAssets.map(\.filename) == photoKitAssets.map(\.filename)
        let kindMatch = appleScriptAssets.map(\.kind) == photoKitAssets.map(\.kind)
        let captureDateMatch = appleScriptAssets.map(\.captureDate) == photoKitAssets.map(\.captureDate)

        let firstMismatchIndex = zip(appleScriptAssets, photoKitAssets).enumerated().first { _, pair in
            pair.0 != pair.1
        }?.offset ?? {
            countMatch ? nil : min(appleScriptAssets.count, photoKitAssets.count)
        }()

        return BenchmarkPageParityReport(
            pageSize: pageSize,
            appleScriptAssetCount: appleScriptAssets.count,
            photoKitAssetCount: photoKitAssets.count,
            idsMatch: idMatch,
            filenamesMatch: filenameMatch,
            mediaKindsMatch: kindMatch,
            captureDatesMatch: captureDateMatch,
            firstMismatchIndex: firstMismatchIndex
        )
    }

    private func measureCount(
        backend: BenchmarkBackend,
        scope: ScopeSource,
        warmIterations: Int
    ) async throws -> BenchmarkOperationMeasurement<Int> {
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

        return BenchmarkOperationMeasurement(
            result: cold.value,
            coldSeconds: cold.elapsedSeconds,
            warmSeconds: warmSeconds,
            memoryDeltaBytes: nil,
            notes: []
        )
    }

    private func measureEnumerateCall(
        backend: BenchmarkBackend,
        scope: ScopeSource,
        offset: Int,
        limit: Int,
        warmIterations: Int
    ) async throws -> BenchmarkOperationMeasurement<Int> {
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

        return BenchmarkOperationMeasurement(
            result: cold.value.count,
            coldSeconds: cold.elapsedSeconds,
            warmSeconds: warmSeconds,
            memoryDeltaBytes: nil,
            notes: []
        )
    }

    private func scanAllAssets(
        backend: BenchmarkBackend,
        scope: ScopeSource,
        pageSize: Int,
        warmIterations: Int,
        maxItems: Int?
    ) async throws -> BenchmarkScanResult {
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

        return BenchmarkScanResult(
            assets: cold.assets,
            measurement: BenchmarkFullScanMeasurement(
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
        backend: BenchmarkBackend,
        scope: ScopeSource,
        pageSize: Int,
        maxItems: Int?
    ) async throws -> BenchmarkScanResult {
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

        return BenchmarkScanResult(
            assets: assets,
            measurement: BenchmarkFullScanMeasurement(
                result: assets.count,
                coldSeconds: elapsedSeconds,
                warmSeconds: [],
                memoryDeltaBytes: memoryDelta,
                timeoutCount: timeoutCount,
                notes: maxItems.map { ["Capped at \($0) assets for this run."] } ?? []
            )
        )
    }

    private func discoverAlbumScope(using client: PhotosAppleScriptClient) async throws -> BenchmarkScopePlan? {
        if let configuredAlbumID = ProcessInfo.processInfo.environment["PDC_BENCHMARK_ALBUM_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredAlbumID.isEmpty
        {
            let albumName = ProcessInfo.processInfo.environment["PDC_BENCHMARK_ALBUM_NAME"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return BenchmarkScopePlan(
                label: albumName?.isEmpty == false ? albumName! : "Configured Album",
                description: "album(\(configuredAlbumID))",
                scope: .album(id: configuredAlbumID)
            )
        }

        let albums = try await client.listUserAlbums()
        for album in albums.prefix(10) {
            let count = try await client.count(scope: .album(id: album.id))
            if count > 0 {
                return BenchmarkScopePlan(
                    label: album.name,
                    description: "album(\(album.id))",
                    scope: .album(id: album.id)
                )
            }
        }

        return nil
    }

    private func benchmarkPageSizes() -> [Int] {
        let rawValue = ProcessInfo.processInfo.environment["PDC_BENCHMARK_PAGE_SIZES"] ?? "250,128,64"
        let parsed = rawValue
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
        return parsed.isEmpty ? [250, 128, 64] : parsed
    }

    private func benchmarkWarmIterations() -> Int {
        let rawValue = ProcessInfo.processInfo.environment["PDC_BENCHMARK_WARM_ITERATIONS"] ?? "1"
        return max(0, Int(rawValue) ?? 1)
    }

    private func benchmarkMaxItems() -> Int? {
        guard let rawValue = ProcessInfo.processInfo.environment["PDC_BENCHMARK_MAX_ITEMS"] else {
            return nil
        }
        let parsed = Int(rawValue) ?? 0
        return parsed > 0 ? parsed : nil
    }

    private func writeReport(_ report: PhotoKitScanBenchmarkReport) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoDescriptionCreatorBenchmarks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("photokit-scan-benchmark-report.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: [.atomic])
        return url
    }

    private func measureOnce<T>(
        operation: () async throws -> T
    ) async throws -> TimedValue<T> {
        let started = DispatchTime.now().uptimeNanoseconds
        let value = try await operation()
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        return TimedValue(value: value, elapsedSeconds: elapsedSeconds)
    }

    private func currentResidentMemoryBytes() -> UInt64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]

        let pipe = Pipe()
        process.standardOutput = pipe
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

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let kilobytes = UInt64(text) else {
            return nil
        }
        return kilobytes * 1024
    }
}

private struct BenchmarkBackend {
    let name: String
    let count: @Sendable (ScopeSource) async throws -> Int
    let enumerate: @Sendable (ScopeSource, Int, Int) async throws -> [MediaAsset]
}

private struct BenchmarkScopePlan {
    let label: String
    let description: String
    let scope: ScopeSource

    static let library = BenchmarkScopePlan(
        label: "Whole Library",
        description: "library",
        scope: .library
    )
}

private struct TimedValue<T> {
    let value: T
    let elapsedSeconds: Double
}

private struct BenchmarkScanResult {
    let assets: [MediaAsset]
    let measurement: BenchmarkFullScanMeasurement
}

private struct PhotoKitScanBenchmarkReport: Codable {
    let generatedAt: Date
    let pageSizes: [Int]
    let warmIterations: Int
    let maxItems: Int?
    let scopes: [BenchmarkScopeReport]
}

private struct BenchmarkScopeReport: Codable {
    let scopeLabel: String
    let scopeDescription: String
    let appleScriptCount: Int
    let photoKitCount: Int
    let countParity: Bool
    let countMeasurements: [String: BenchmarkOperationMeasurement<Int>]
    let firstAssetMeasurements: [String: BenchmarkOperationMeasurement<Int>]
    let firstPageMeasurements: [String: BenchmarkOperationMeasurement<Int>]
    let fullScanMeasurements: [String: BenchmarkFullScanMeasurement]
    let parityByPageSize: [BenchmarkPageParityReport]

    var summaryLine: String {
        let countText = countParity ? "count-match" : "count-mismatch"
        let parityText = parityByPageSize.allSatisfy(\.fullyMatches) ? "page-parity-ok" : "page-parity-drift"
        return "[PhotoKitScanBenchmarkTests] \(scopeLabel): \(countText), \(parityText)"
    }
}

private struct BenchmarkOperationMeasurement<ResultValue: Codable>: Codable {
    let result: ResultValue
    let coldSeconds: Double
    let warmSeconds: [Double]
    let memoryDeltaBytes: Int64?
    let notes: [String]
}

private struct BenchmarkFullScanMeasurement: Codable {
    let result: Int
    let coldSeconds: Double
    let warmSeconds: [Double]
    let memoryDeltaBytes: Int64?
    let timeoutCount: Int
    let notes: [String]
}

private struct BenchmarkPageParityReport: Codable {
    let pageSize: Int
    let appleScriptAssetCount: Int
    let photoKitAssetCount: Int
    let idsMatch: Bool
    let filenamesMatch: Bool
    let mediaKindsMatch: Bool
    let captureDatesMatch: Bool
    let firstMismatchIndex: Int?

    var fullyMatches: Bool {
        idsMatch && filenamesMatch && mediaKindsMatch && captureDatesMatch && appleScriptAssetCount == photoKitAssetCount
    }
}
