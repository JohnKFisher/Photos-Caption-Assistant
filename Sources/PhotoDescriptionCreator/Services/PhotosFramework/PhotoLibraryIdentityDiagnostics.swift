import Foundation
import Photos

protocol PhotoLibraryDiagnosticsAppleScriptAccessing: Sendable {
    func count(scope: ScopeSource) async throws -> Int
    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset]
    func listUserAlbums() async throws -> [AlbumSummary]
    func verifyAutomationAccess() async -> Bool
    func inspectResolvedMediaItem(id: String) async throws -> PhotoLibraryResolvedMediaItem
    func readMetadata(id: String) async throws -> ExistingMetadataState
    func writeMetadata(id: String, caption: String, keywords: [String]) async throws
    func isMediaItem(id: String, inAlbumID: String) async throws -> Bool
    func photoPreviewJPEGData(id: String, maxPixelSize: Int) async throws -> Data?
    func exportAssetToTemporaryURL(id: String, kind: MediaKind) async throws -> URL
}

protocol PhotoLibraryDiagnosticsPhotoKitAccessing: Sendable {
    func count(scope: ScopeSource) async throws -> Int
    func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset]
    func canResolveAlbum(id: String) async -> Bool
    func inspectAsset(id: String) async -> PhotoLibraryResolvedMediaItem?
}

enum PhotoLibraryIdentityResolutionStrategy: String, Codable, Sendable {
    case exact
    case baseIdentifierFallback
    case alternateResolvedID
}

struct PhotoLibraryResolvedMediaItem: Codable, Sendable, Equatable {
    let requestedID: String
    let resolvedID: String
    let filename: String
    let captureDate: Date?
    let kind: MediaKind
    let resolutionStrategy: PhotoLibraryIdentityResolutionStrategy

    init(
        requestedID: String,
        resolvedID: String,
        filename: String,
        captureDate: Date?,
        kind: MediaKind
    ) {
        self.requestedID = requestedID
        self.resolvedID = resolvedID
        self.filename = filename
        self.captureDate = captureDate
        self.kind = kind
        self.resolutionStrategy = Self.strategy(requestedID: requestedID, resolvedID: resolvedID)
    }

    var usedFallbackResolution: Bool {
        resolutionStrategy != .exact
    }

    var baseResolvedID: String {
        Self.baseIdentifier(from: resolvedID)
    }

    func matchesIdentity(of other: PhotoLibraryResolvedMediaItem) -> Bool {
        baseResolvedID == other.baseResolvedID
    }

    static func strategy(
        requestedID: String,
        resolvedID: String
    ) -> PhotoLibraryIdentityResolutionStrategy {
        if requestedID == resolvedID {
            return .exact
        }

        if baseIdentifier(from: requestedID) == resolvedID {
            return .baseIdentifierFallback
        }

        return .alternateResolvedID
    }

    static func baseIdentifier(from identifier: String) -> String {
        guard let slashIndex = identifier.firstIndex(of: "/") else {
            return identifier
        }
        return String(identifier[..<slashIndex])
    }
}

struct PhotoLibraryMetadataSnapshot: Codable, Sendable, Equatable {
    let caption: String?
    let keywords: [String]

    init(caption: String?, keywords: [String]) {
        self.caption = caption
        self.keywords = keywords
    }

    init(state: ExistingMetadataState) {
        self.init(caption: state.caption, keywords: state.keywords)
    }
}

struct PhotoLibraryIdentityAcquireCheck: Codable, Sendable, Equatable {
    let verified: Bool
    let method: String
    let errorMessage: String?
}

struct PhotoLibraryIdentitySample: Codable, Sendable, Equatable {
    let requestedPhotoKitID: String
    let photoKitResolvedID: String
    let appleScriptResolvedID: String?
    let resolutionStrategy: PhotoLibraryIdentityResolutionStrategy?
    let canonicalIDMatch: Bool
    let filenameMatch: Bool
    let mediaKindMatch: Bool
    let captureDateMatch: Bool
    let writePathResolvable: Bool
    let writePathSafe: Bool
    let acquisitionCheck: PhotoLibraryIdentityAcquireCheck?
    let notes: [String]
}

struct PhotoLibraryIdentityProofReport: Codable, Sendable, Equatable {
    let sampledAssetCount: Int
    let acquisitionSampleCount: Int
    let unresolvedAssetIDs: [String]
    let fallbackResolutionCount: Int
    let canonicalIDParityCount: Int
    let filenameParityCount: Int
    let mediaKindParityCount: Int
    let captureDateParityCount: Int
    let acquisitionVerifiedCount: Int
    let writePathSafeCount: Int
    let samples: [PhotoLibraryIdentitySample]

    var writePathSafe: Bool {
        sampledAssetCount > 0 && writePathSafeCount == sampledAssetCount
    }

    var captureDateDriftDetected: Bool {
        captureDateParityCount < sampledAssetCount
    }
}

struct PhotoLibraryIdentityWriteProbeConfiguration: Sendable, Equatable {
    let sacrificialAssetID: String
    let controlAssetID: String
    let expectedSmartAlbumID: String?
    let expectedSmartAlbumName: String?

    init?(
        sacrificialAssetID: String,
        controlAssetID: String,
        expectedSmartAlbumID: String? = nil,
        expectedSmartAlbumName: String? = nil
    ) {
        guard let normalizedSacrificial = Self.normalized(sacrificialAssetID),
              let normalizedControl = Self.normalized(controlAssetID)
        else {
            return nil
        }

        self.sacrificialAssetID = normalizedSacrificial
        self.controlAssetID = normalizedControl
        self.expectedSmartAlbumID = Self.normalized(expectedSmartAlbumID)
        self.expectedSmartAlbumName = Self.normalized(expectedSmartAlbumName)
    }

    var expectsSmartAlbumRemoval: Bool {
        expectedSmartAlbumID != nil
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

struct PhotoLibraryIdentityWriteProbeAssetReport: Codable, Sendable, Equatable {
    let requestedID: String
    let photoKitBefore: PhotoLibraryResolvedMediaItem?
    let appleScriptBefore: PhotoLibraryResolvedMediaItem?
    let metadataBefore: PhotoLibraryMetadataSnapshot?
    let appleScriptAfterWrite: PhotoLibraryResolvedMediaItem?
    let metadataAfterWrite: PhotoLibraryMetadataSnapshot?
    let appleScriptAfterRestore: PhotoLibraryResolvedMediaItem?
    let metadataAfterRestore: PhotoLibraryMetadataSnapshot?
}

enum PhotoLibrarySmartAlbumHandoffOutcome: String, Codable, Sendable {
    case notConfigured
    case expectedDisappearanceConfirmed
    case assetDidNotDisappear
    case assetNotMemberBeforeWrite
    case assetCouldNotBeResolvedAfterWrite
}

struct PhotoLibrarySmartAlbumHandoffReport: Codable, Sendable, Equatable {
    let albumID: String
    let albumName: String?
    let wasMemberBeforeWrite: Bool
    let wasMemberAfterWrite: Bool
    let assetResolvedAfterWrite: Bool
    let outcome: PhotoLibrarySmartAlbumHandoffOutcome
}

struct PhotoLibraryIdentityWriteProbeReport: Codable, Sendable, Equatable {
    let generatedAt: Date
    let sacrificialAsset: PhotoLibraryIdentityWriteProbeAssetReport
    let controlAsset: PhotoLibraryIdentityWriteProbeAssetReport
    let sentinelCaption: String
    let sentinelKeyword: String
    let smartAlbumHandoff: PhotoLibrarySmartAlbumHandoffReport?
    let controlUnchanged: Bool
    let restoreSucceeded: Bool
    let overallPass: Bool
    let failureReasons: [String]

    var summaryLine: String {
        overallPass
            ? "[PhotoKitIdentityWriteProbe] pass"
            : "[PhotoKitIdentityWriteProbe] fail: \(failureReasons.joined(separator: "; "))"
    }
}

enum PhotoLibraryIdentityWriteProbeOutcome {
    case completed(PhotoLibraryIdentityWriteProbeCompletedRun)
    case skipped(String)
}

struct PhotoLibraryIdentityWriteProbeCompletedRun {
    let report: PhotoLibraryIdentityWriteProbeReport
    let reportURL: URL
}

actor PhotoLibraryIdentityWriteProbeRunner {
    typealias ProgressHandler = @Sendable (String) async -> Void

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
        configuration: PhotoLibraryIdentityWriteProbeConfiguration,
        progressHandler: ProgressHandler? = nil
    ) async throws -> PhotoLibraryIdentityWriteProbeOutcome {
        let authorizationStatus = authorizationStatusProvider()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return .skipped("Photos library access is unavailable for this process (status=\(authorizationStatus.rawValue)).")
        }

        guard await appleScriptClient.verifyAutomationAccess() else {
            return .skipped("Photos automation access is unavailable for this process.")
        }

        let sentinelToken = UUID().uuidString.prefix(8)
        let sentinelCaption = "[PDC identity probe \(sentinelToken)]"
        let sentinelKeyword = "pdc-identity-probe-\(sentinelToken.lowercased())"

        await reportProgress("Inspecting sacrificial asset...", using: progressHandler)
        let sacrificialPhotoKitBefore = await photoKitReader.inspectAsset(id: configuration.sacrificialAssetID)
        let sacrificialAppleBefore = try? await appleScriptClient.inspectResolvedMediaItem(id: configuration.sacrificialAssetID)
        let sacrificialMetadataBefore = try? await appleScriptClient.readMetadata(id: configuration.sacrificialAssetID)

        await reportProgress("Inspecting control asset...", using: progressHandler)
        let controlPhotoKitBefore = await photoKitReader.inspectAsset(id: configuration.controlAssetID)
        let controlAppleBefore = try? await appleScriptClient.inspectResolvedMediaItem(id: configuration.controlAssetID)
        let controlMetadataBefore = try? await appleScriptClient.readMetadata(id: configuration.controlAssetID)
        let sacrificialBeforeSnapshot = sacrificialMetadataBefore.map(PhotoLibraryMetadataSnapshot.init(state:))
        let controlBeforeSnapshot = controlMetadataBefore.map(PhotoLibraryMetadataSnapshot.init(state:))

        var failures: [String] = []
        if sacrificialPhotoKitBefore == nil {
            failures.append("Sacrificial asset could not be resolved by PhotoKit.")
        }
        if sacrificialAppleBefore == nil {
            failures.append("Sacrificial asset could not be resolved by AppleScript.")
        }
        if controlPhotoKitBefore == nil {
            failures.append("Control asset could not be resolved by PhotoKit.")
        }
        if controlAppleBefore == nil {
            failures.append("Control asset could not be resolved by AppleScript.")
        }
        if sacrificialMetadataBefore == nil {
            failures.append("Sacrificial asset metadata could not be read before the probe.")
        }
        if controlMetadataBefore == nil {
            failures.append("Control asset metadata could not be read before the probe.")
        }
        if configuration.sacrificialAssetID == configuration.controlAssetID {
            failures.append("Sacrificial and control asset IDs must be different.")
        }

        var smartAlbumReport: PhotoLibrarySmartAlbumHandoffReport?
        if let smartAlbumID = configuration.expectedSmartAlbumID {
            await reportProgress("Checking smart-album membership before write...", using: progressHandler)
            let wasMemberBeforeWrite = (try? await appleScriptClient.isMediaItem(
                id: configuration.sacrificialAssetID,
                inAlbumID: smartAlbumID
            )) ?? false

            smartAlbumReport = PhotoLibrarySmartAlbumHandoffReport(
                albumID: smartAlbumID,
                albumName: configuration.expectedSmartAlbumName,
                wasMemberBeforeWrite: wasMemberBeforeWrite,
                wasMemberAfterWrite: false,
                assetResolvedAfterWrite: false,
                outcome: wasMemberBeforeWrite ? .notConfigured : .assetNotMemberBeforeWrite
            )

            if !wasMemberBeforeWrite {
                failures.append("Sacrificial asset was not in the expected smart album before the probe.")
            }
        }

        var sacrificialAfterWriteInspection: PhotoLibraryResolvedMediaItem?
        var sacrificialAfterWriteMetadata: ExistingMetadataState?
        var sacrificialAfterRestoreInspection: PhotoLibraryResolvedMediaItem?
        var sacrificialAfterRestoreMetadata: ExistingMetadataState?
        var controlAfterWriteInspection: PhotoLibraryResolvedMediaItem?
        var controlAfterWriteMetadata: ExistingMetadataState?
        var restoreSucceeded = false
        var sentinelWriteCompleted = false

        if failures.isEmpty {
            await reportProgress("Writing sacrificial sentinel metadata...", using: progressHandler)
            let originalKeywords = sacrificialMetadataBefore?.keywords ?? []
            let mergedKeywords = Array(Set(originalKeywords + [sentinelKeyword])).sorted()
            do {
                try await appleScriptClient.writeMetadata(
                    id: configuration.sacrificialAssetID,
                    caption: sentinelCaption,
                    keywords: mergedKeywords
                )
                sentinelWriteCompleted = true
            } catch {
                failures.append("Sentinel write failed: \(error.localizedDescription)")
            }
        }

        if sentinelWriteCompleted {
            await reportProgress("Verifying sacrificial write target...", using: progressHandler)
            sacrificialAfterWriteInspection = try? await appleScriptClient.inspectResolvedMediaItem(id: configuration.sacrificialAssetID)
            sacrificialAfterWriteMetadata = try? await appleScriptClient.readMetadata(id: configuration.sacrificialAssetID)
            controlAfterWriteInspection = try? await appleScriptClient.inspectResolvedMediaItem(id: configuration.controlAssetID)
            controlAfterWriteMetadata = try? await appleScriptClient.readMetadata(id: configuration.controlAssetID)

            if sacrificialAfterWriteMetadata?.caption != sentinelCaption {
                failures.append("Sentinel caption was not observed on the sacrificial asset after write.")
            }
            if !(sacrificialAfterWriteMetadata?.keywords.contains(sentinelKeyword) ?? false) {
                failures.append("Sentinel keyword was not observed on the sacrificial asset after write.")
            }

            if let before = sacrificialAppleBefore,
               let after = sacrificialAfterWriteInspection,
               !before.matchesIdentity(of: after)
            {
                failures.append("Sacrificial asset resolved to a different canonical identity after write.")
            }

            if controlAfterWriteMetadata.map(PhotoLibraryMetadataSnapshot.init(state:)) != controlBeforeSnapshot {
                failures.append("Control asset metadata changed during the probe.")
            }

            if let smartAlbumID = configuration.expectedSmartAlbumID,
               let priorSmartAlbumReport = smartAlbumReport
            {
                await reportProgress("Checking smart-album handoff after write...", using: progressHandler)
                let memberAfterWrite = (try? await appleScriptClient.isMediaItem(
                    id: configuration.sacrificialAssetID,
                    inAlbumID: smartAlbumID
                )) ?? false
                let resolvedAfterWrite = sacrificialAfterWriteInspection != nil
                let outcome: PhotoLibrarySmartAlbumHandoffOutcome
                if !priorSmartAlbumReport.wasMemberBeforeWrite {
                    outcome = .assetNotMemberBeforeWrite
                } else if !resolvedAfterWrite {
                    outcome = .assetCouldNotBeResolvedAfterWrite
                    failures.append("Sacrificial asset could not be re-resolved by identity after write.")
                } else if memberAfterWrite {
                    outcome = .assetDidNotDisappear
                    failures.append("Sacrificial asset did not leave the expected smart album after write.")
                } else {
                    outcome = .expectedDisappearanceConfirmed
                }

                smartAlbumReport = PhotoLibrarySmartAlbumHandoffReport(
                    albumID: priorSmartAlbumReport.albumID,
                    albumName: priorSmartAlbumReport.albumName,
                    wasMemberBeforeWrite: priorSmartAlbumReport.wasMemberBeforeWrite,
                    wasMemberAfterWrite: memberAfterWrite,
                    assetResolvedAfterWrite: resolvedAfterWrite,
                    outcome: outcome
                )
            }
        }

        if sentinelWriteCompleted {
            await reportProgress("Restoring sacrificial metadata...", using: progressHandler)
            do {
                try await appleScriptClient.writeMetadata(
                    id: configuration.sacrificialAssetID,
                    caption: sacrificialMetadataBefore?.caption ?? "",
                    keywords: sacrificialMetadataBefore?.keywords ?? []
                )
                restoreSucceeded = true
            } catch {
                failures.append("Restore failed: \(error.localizedDescription)")
            }

            sacrificialAfterRestoreInspection = try? await appleScriptClient.inspectResolvedMediaItem(id: configuration.sacrificialAssetID)
            sacrificialAfterRestoreMetadata = try? await appleScriptClient.readMetadata(id: configuration.sacrificialAssetID)

            if sacrificialAfterRestoreMetadata.map(PhotoLibraryMetadataSnapshot.init(state:)) != sacrificialBeforeSnapshot {
                failures.append("Sacrificial metadata was not restored to its original value.")
                restoreSucceeded = false
            }
        }

        let controlUnchanged = controlBeforeSnapshot == controlAfterWriteMetadata.map(PhotoLibraryMetadataSnapshot.init(state:))

        let report = PhotoLibraryIdentityWriteProbeReport(
            generatedAt: Date(),
            sacrificialAsset: PhotoLibraryIdentityWriteProbeAssetReport(
                requestedID: configuration.sacrificialAssetID,
                photoKitBefore: sacrificialPhotoKitBefore,
                appleScriptBefore: sacrificialAppleBefore,
                metadataBefore: sacrificialBeforeSnapshot,
                appleScriptAfterWrite: sacrificialAfterWriteInspection,
                metadataAfterWrite: sacrificialAfterWriteMetadata.map(PhotoLibraryMetadataSnapshot.init(state:)),
                appleScriptAfterRestore: sacrificialAfterRestoreInspection,
                metadataAfterRestore: sacrificialAfterRestoreMetadata.map(PhotoLibraryMetadataSnapshot.init(state:))
            ),
            controlAsset: PhotoLibraryIdentityWriteProbeAssetReport(
                requestedID: configuration.controlAssetID,
                photoKitBefore: controlPhotoKitBefore,
                appleScriptBefore: controlAppleBefore,
                metadataBefore: controlBeforeSnapshot,
                appleScriptAfterWrite: controlAfterWriteInspection,
                metadataAfterWrite: controlAfterWriteMetadata.map(PhotoLibraryMetadataSnapshot.init(state:)),
                appleScriptAfterRestore: nil,
                metadataAfterRestore: nil
            ),
            sentinelCaption: sentinelCaption,
            sentinelKeyword: sentinelKeyword,
            smartAlbumHandoff: smartAlbumReport,
            controlUnchanged: controlUnchanged,
            restoreSucceeded: restoreSucceeded,
            overallPass: failures.isEmpty && controlUnchanged && restoreSucceeded,
            failureReasons: failures
        )

        let reportURL = try writeReport(report)
        return .completed(
            PhotoLibraryIdentityWriteProbeCompletedRun(
                report: report,
                reportURL: reportURL
            )
        )
    }

    private func writeReport(_ report: PhotoLibraryIdentityWriteProbeReport) throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoDescriptionCreatorBenchmarks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("photokit-identity-write-probe-report.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: [.atomic])
        return url
    }

    private func reportProgress(
        _ message: String,
        using progressHandler: ProgressHandler?
    ) async {
        await progressHandler?(message)
    }
}

extension PhotosAppleScriptClient: PhotoLibraryDiagnosticsAppleScriptAccessing {}

extension ExperimentalPhotoKitScanReader: PhotoLibraryDiagnosticsPhotoKitAccessing {}
