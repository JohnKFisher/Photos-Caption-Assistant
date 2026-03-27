import Foundation
import Photos
import XCTest
@testable import PhotoDescriptionCreator

final class PhotoKitScanBenchmarkTests: XCTestCase {
    func testBenchmarkEnvironmentDefaultsToCappedSample() {
        let configuration = PhotoLibraryScanBenchmarkConfiguration.fromEnvironment([:])
        XCTAssertEqual(configuration.maxItems, PhotoLibraryScanBenchmarkConfiguration.defaultMaxItems)
        XCTAssertEqual(configuration.pageSizes, PhotoLibraryScanBenchmarkConfiguration.defaultPageSizes)
    }

    func testBenchmarkEnvironmentAllowsFullScanOverride() {
        let configuration = PhotoLibraryScanBenchmarkConfiguration.fromEnvironment([
            "PDC_BENCHMARK_MAX_ITEMS": "full"
        ])
        XCTAssertNil(configuration.maxItems)
    }

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

    func testBenchmarkSummaryTreatsIdentitySafetySeparatelyFromOrderDrift() async throws {
        let photoKitAssets = [
            MediaAsset(id: "A/1", filename: "a.jpg", captureDate: Date(timeIntervalSince1970: 10), kind: .photo),
            MediaAsset(id: "B/1", filename: "b.jpg", captureDate: Date(timeIntervalSince1970: 20), kind: .photo)
        ]
        let appleScriptAssets = Array(photoKitAssets.reversed())

        let appleScript = FakeAppleScriptDiagnosticsClient(
            libraryAssets: appleScriptAssets,
            inspections: Dictionary(uniqueKeysWithValues: photoKitAssets.map {
                ($0.id, PhotoLibraryResolvedMediaItem(
                    requestedID: $0.id,
                    resolvedID: PhotoLibraryResolvedMediaItem.baseIdentifier(from: $0.id),
                    filename: $0.filename,
                    captureDate: $0.captureDate,
                    kind: $0.kind
                ))
            }),
            metadata: [:],
            listedAlbums: [],
            albumMembers: [:],
            previewCapableIDs: Set(photoKitAssets.map(\.id))
        )
        let photoKit = FakePhotoKitDiagnosticsReader(
            libraryAssets: photoKitAssets,
            albumAssets: [:]
        )

        let runner = PhotoLibraryScanBenchmarkRunner(
            appleScriptClient: appleScript,
            photoKitReader: photoKit,
            authorizationStatusProvider: { .authorized }
        )
        let outcome = try await runner.run(
            configuration: PhotoLibraryScanBenchmarkConfiguration(pageSizes: [2], warmIterations: 0, maxItems: 2)
        )

        guard case let .completed(run) = outcome else {
            return XCTFail("Expected completed benchmark report")
        }

        let scope = try XCTUnwrap(run.report.scopes.first)
        XCTAssertTrue(scope.countParity)
        XCTAssertTrue(scope.identityProof.writePathSafe)
        XCTAssertFalse(scope.parityByPageSize[0].fullyMatches)
        XCTAssertTrue(scope.summaryLine.contains("identity-safe"))
        XCTAssertTrue(scope.summaryLine.contains("order-parity-drift"))
    }

    func testIdentityWriteProbeRestoresMetadataAndTracksSmartAlbumHandoff() async throws {
        let sacrificialID = "S/1"
        let controlID = "C/1"
        let smartAlbumID = "smart-1"
        let sacrificialInspection = PhotoLibraryResolvedMediaItem(
            requestedID: sacrificialID,
            resolvedID: "S",
            filename: "s.jpg",
            captureDate: Date(timeIntervalSince1970: 10),
            kind: .photo
        )
        let controlInspection = PhotoLibraryResolvedMediaItem(
            requestedID: controlID,
            resolvedID: "C",
            filename: "c.jpg",
            captureDate: Date(timeIntervalSince1970: 20),
            kind: .photo
        )

        let appleScript = FakeAppleScriptDiagnosticsClient(
            libraryAssets: [],
            inspections: [
                sacrificialID: sacrificialInspection,
                controlID: controlInspection
            ],
            metadata: [
                sacrificialID: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false),
                controlID: ExistingMetadataState(caption: "keep", keywords: ["original"], ownershipTag: nil, isExternal: true)
            ],
            listedAlbums: [],
            albumMembers: [smartAlbumID: Set([sacrificialID])],
            previewCapableIDs: [sacrificialID, controlID],
            removalAlbumIDsOnWrite: Set([smartAlbumID])
        )
        let photoKit = FakePhotoKitDiagnosticsReader(
            libraryAssets: [],
            albumAssets: [:],
            inspections: [
                sacrificialID: PhotoLibraryResolvedMediaItem(
                    requestedID: sacrificialID,
                    resolvedID: sacrificialID,
                    filename: "s.jpg",
                    captureDate: Date(timeIntervalSince1970: 10),
                    kind: .photo
                ),
                controlID: PhotoLibraryResolvedMediaItem(
                    requestedID: controlID,
                    resolvedID: controlID,
                    filename: "c.jpg",
                    captureDate: Date(timeIntervalSince1970: 20),
                    kind: .photo
                )
            ]
        )

        let runner = PhotoLibraryIdentityWriteProbeRunner(
            appleScriptClient: appleScript,
            photoKitReader: photoKit,
            authorizationStatusProvider: { .authorized }
        )
        let configuration = try XCTUnwrap(
            PhotoLibraryIdentityWriteProbeConfiguration(
                sacrificialAssetID: sacrificialID,
                controlAssetID: controlID,
                expectedSmartAlbumID: smartAlbumID,
                expectedSmartAlbumName: "Smart"
            )
        )

        let outcome = try await runner.run(configuration: configuration)
        guard case let .completed(run) = outcome else {
            return XCTFail("Expected completed write probe report")
        }

        XCTAssertTrue(run.report.overallPass)
        XCTAssertTrue(run.report.restoreSucceeded)
        XCTAssertTrue(run.report.controlUnchanged)
        XCTAssertEqual(run.report.smartAlbumHandoff?.outcome, .expectedDisappearanceConfirmed)
        let writeCallCount = await appleScript.writeCallCount()
        let restoredMetadata = await appleScript.metadataState(for: sacrificialID)
        XCTAssertEqual(writeCallCount, 2)
        XCTAssertNil(restoredMetadata?.caption)
    }

    func testIdentityWriteProbeFailsWhenSmartAlbumDidNotContainSacrificialAssetBeforeWrite() async throws {
        let sacrificialID = "S/1"
        let controlID = "C/1"
        let smartAlbumID = "smart-1"

        let appleScript = FakeAppleScriptDiagnosticsClient(
            libraryAssets: [],
            inspections: [
                sacrificialID: PhotoLibraryResolvedMediaItem(
                    requestedID: sacrificialID,
                    resolvedID: "S",
                    filename: "s.jpg",
                    captureDate: Date(timeIntervalSince1970: 10),
                    kind: .photo
                ),
                controlID: PhotoLibraryResolvedMediaItem(
                    requestedID: controlID,
                    resolvedID: "C",
                    filename: "c.jpg",
                    captureDate: Date(timeIntervalSince1970: 20),
                    kind: .photo
                )
            ],
            metadata: [
                sacrificialID: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false),
                controlID: ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
            ],
            listedAlbums: [],
            albumMembers: [:],
            previewCapableIDs: [sacrificialID, controlID]
        )
        let photoKit = FakePhotoKitDiagnosticsReader(
            libraryAssets: [],
            albumAssets: [:],
            inspections: [
                sacrificialID: PhotoLibraryResolvedMediaItem(
                    requestedID: sacrificialID,
                    resolvedID: sacrificialID,
                    filename: "s.jpg",
                    captureDate: Date(timeIntervalSince1970: 10),
                    kind: .photo
                ),
                controlID: PhotoLibraryResolvedMediaItem(
                    requestedID: controlID,
                    resolvedID: controlID,
                    filename: "c.jpg",
                    captureDate: Date(timeIntervalSince1970: 20),
                    kind: .photo
                )
            ]
        )

        let runner = PhotoLibraryIdentityWriteProbeRunner(
            appleScriptClient: appleScript,
            photoKitReader: photoKit,
            authorizationStatusProvider: { .authorized }
        )
        let configuration = try XCTUnwrap(
            PhotoLibraryIdentityWriteProbeConfiguration(
                sacrificialAssetID: sacrificialID,
                controlAssetID: controlID,
                expectedSmartAlbumID: smartAlbumID,
                expectedSmartAlbumName: "Smart"
            )
        )

        let outcome = try await runner.run(configuration: configuration)
        guard case let .completed(run) = outcome else {
            return XCTFail("Expected completed write probe report")
        }

        XCTAssertFalse(run.report.overallPass)
        XCTAssertTrue(run.report.failureReasons.contains(where: { $0.contains("not in the expected smart album") }))
    }

    func testGenerateLocalParityAndSpeedReportWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PDC_RUN_PHOTOS_SCAN_BENCHMARK"] == "1" else {
            throw XCTSkip("Set PDC_RUN_PHOTOS_SCAN_BENCHMARK=1 to run the local Photos parity benchmark.")
        }

        let configuration = PhotoLibraryScanBenchmarkConfiguration.fromEnvironment(
            ProcessInfo.processInfo.environment
        )
        let runner = PhotoLibraryScanBenchmarkRunner(appleScriptClient: PhotosAppleScriptClient())
        let outcome = try await runner.run(configuration: configuration)

        switch outcome {
        case let .completed(run):
            print("[PhotoKitScanBenchmarkTests] wrote report to \(run.reportURL.path)")
            for scope in run.report.scopes {
                print(scope.summaryLine)
            }
            XCTAssertFalse(run.report.scopes.isEmpty)
        case let .skipped(reason):
            throw XCTSkip(reason)
        }
    }
}

private actor FakeAppleScriptDiagnosticsClient: PhotoLibraryDiagnosticsAppleScriptAccessing {
    let libraryAssets: [MediaAsset]
    let albumAssets: [String: [MediaAsset]]
    let inspections: [String: PhotoLibraryResolvedMediaItem]
    let listedAlbums: [AlbumSummary]
    let previewCapableIDs: Set<String>
    let removalAlbumIDsOnWrite: Set<String>
    private var metadata: [String: ExistingMetadataState]
    private var albumMembers: [String: Set<String>]
    private var writes: [(String, String, [String])] = []

    init(
        libraryAssets: [MediaAsset],
        inspections: [String: PhotoLibraryResolvedMediaItem],
        metadata: [String: ExistingMetadataState],
        listedAlbums: [AlbumSummary],
        albumMembers: [String: Set<String>],
        previewCapableIDs: Set<String>,
        removalAlbumIDsOnWrite: Set<String> = []
    ) {
        self.libraryAssets = libraryAssets
        self.albumAssets = [:]
        self.inspections = inspections
        self.metadata = metadata
        self.listedAlbums = listedAlbums
        self.albumMembers = albumMembers
        self.previewCapableIDs = previewCapableIDs
        self.removalAlbumIDsOnWrite = removalAlbumIDsOnWrite
    }

    func count(scope: ScopeSource) async throws -> Int {
        switch scope {
        case .library:
            return libraryAssets.count
        case let .album(id):
            return albumMembers[id]?.count ?? albumAssets[id]?.count ?? 0
        case .picker, .captionWorkflow:
            return 0
        }
    }

    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset] {
        let source: [MediaAsset]
        switch scope {
        case .library:
            source = libraryAssets
        case let .album(id):
            source = albumAssets[id] ?? []
        case .picker, .captionWorkflow:
            source = []
        }

        guard offset < source.count else { return [] }
        return Array(source[offset..<min(source.count, offset + max(1, limit))])
    }

    func listUserAlbums() async throws -> [AlbumSummary] {
        listedAlbums
    }

    func verifyAutomationAccess() async -> Bool {
        true
    }

    func inspectResolvedMediaItem(id: String) async throws -> PhotoLibraryResolvedMediaItem {
        guard let inspection = inspections[id] else {
            throw NSError(domain: "FakeAppleScriptDiagnosticsClient", code: 1)
        }
        return inspection
    }

    func readMetadata(id: String) async throws -> ExistingMetadataState {
        metadata[id] ?? ExistingMetadataState(caption: nil, keywords: [], ownershipTag: nil, isExternal: false)
    }

    func writeMetadata(id: String, caption: String, keywords: [String]) async throws {
        writes.append((id, caption, keywords))
        metadata[id] = ExistingMetadataState(
            caption: caption.isEmpty ? nil : caption,
            keywords: keywords,
            ownershipTag: nil,
            isExternal: !caption.isEmpty || !keywords.isEmpty
        )

        for albumID in removalAlbumIDsOnWrite where !caption.isEmpty {
            albumMembers[albumID]?.remove(id)
        }
    }

    func isMediaItem(id: String, inAlbumID: String) async throws -> Bool {
        albumMembers[inAlbumID]?.contains(id) ?? false
    }

    func photoPreviewJPEGData(id: String, maxPixelSize: Int) async throws -> Data? {
        previewCapableIDs.contains(id) ? Data([1, 2, 3]) : nil
    }

    func exportAssetToTemporaryURL(id: String, kind: MediaKind) async throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(id.replacingOccurrences(of: "/", with: "_")).tmp")
        try Data([1]).write(to: url)
        return url
    }

    func writeCallCount() async -> Int {
        writes.count
    }

    func metadataState(for id: String) async -> ExistingMetadataState? {
        metadata[id]
    }
}

private actor FakePhotoKitDiagnosticsReader: PhotoLibraryDiagnosticsPhotoKitAccessing {
    let libraryAssets: [MediaAsset]
    let albumAssets: [String: [MediaAsset]]
    let inspections: [String: PhotoLibraryResolvedMediaItem]

    init(
        libraryAssets: [MediaAsset],
        albumAssets: [String: [MediaAsset]],
        inspections: [String: PhotoLibraryResolvedMediaItem]? = nil
    ) {
        self.libraryAssets = libraryAssets
        self.albumAssets = albumAssets
        self.inspections = inspections ?? Dictionary(uniqueKeysWithValues: libraryAssets.map {
            ($0.id, PhotoLibraryResolvedMediaItem(
                requestedID: $0.id,
                resolvedID: $0.id,
                filename: $0.filename,
                captureDate: $0.captureDate,
                kind: $0.kind
            ))
        })
    }

    func count(scope: ScopeSource) async throws -> Int {
        switch scope {
        case .library:
            return libraryAssets.count
        case let .album(id):
            return albumAssets[id]?.count ?? 0
        case .picker, .captionWorkflow:
            return 0
        }
    }

    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset] {
        let source: [MediaAsset]
        switch scope {
        case .library:
            source = libraryAssets
        case let .album(id):
            source = albumAssets[id] ?? []
        case .picker, .captionWorkflow:
            source = []
        }

        guard offset < source.count else { return [] }
        return Array(source[offset..<min(source.count, offset + max(1, limit))])
    }

    func canResolveAlbum(id: String) async -> Bool {
        albumAssets[id] != nil
    }

    func inspectAsset(id: String) async -> PhotoLibraryResolvedMediaItem? {
        inspections[id]
    }
}
