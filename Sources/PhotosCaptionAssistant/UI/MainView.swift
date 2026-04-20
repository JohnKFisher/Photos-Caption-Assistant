import AppKit
import Photos
import SwiftUI

struct ConfirmationPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmLabel: String
    let cancelLabel: String
}

struct MessagePrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum AppAlert: Identifiable {
    case confirmation(ConfirmationPrompt)
    case message(MessagePrompt)

    var id: UUID {
        switch self {
        case let .confirmation(prompt):
            return prompt.id
        case let .message(prompt):
            return prompt.id
        }
    }
}

enum ImmersivePreviewPolicy {
    static let emergencySamplingThreshold = 40
    static let sampledRetainedPreviewCount = 24
    static let cadenceRollingWindowSize = 30
    static let targetDriftMultiplier = 2.0
    static let driftDeadbandFraction = 0.25
    static let cadenceAdjustmentStepFraction = 0.05
    static let minimumCatchUpIntervalFactor = 0.5
    static let maximumBacklogIntervalFactor = 1.25
    static let bootstrapDisplaySeconds: TimeInterval = 12

    static func lagDisplayValue(for lagCount: Int) -> String {
        let clampedLagCount = max(0, lagCount)
        guard clampedLagCount > 0 else {
            return "Live"
        }
        if clampedLagCount > 99 {
            return "99+"
        }
        return "\(clampedLagCount)"
    }

    static func retainedIndices(
        for backlogCount: Int,
        targetRetainedCount: Int = sampledRetainedPreviewCount
    ) -> [Int] {
        guard backlogCount > 0 else { return [] }
        guard backlogCount > targetRetainedCount, targetRetainedCount > 1 else {
            return Array(0..<backlogCount)
        }

        let lastIndex = backlogCount - 1
        var retained = Set<Int>()
        retained.reserveCapacity(targetRetainedCount)

        for position in 0..<targetRetainedCount {
            let rawIndex = Double(position) * Double(lastIndex) / Double(targetRetainedCount - 1)
            retained.insert(min(lastIndex, max(0, Int(rawIndex.rounded()))))
        }

        if retained.count < targetRetainedCount {
            for index in 0...lastIndex where retained.count < targetRetainedCount {
                retained.insert(index)
            }
        }

        return retained.sorted()
    }
}

struct ImmersivePlaybackCadence {
    private(set) var learnedInterval: TimeInterval?
    private(set) var currentDisplayInterval: TimeInterval?
    private(set) var latestCompletionAt: Date?
    private var recentCompletionIntervals: [TimeInterval] = []

    var recentIntervalCount: Int {
        recentCompletionIntervals.count
    }

    mutating func reset() {
        learnedInterval = nil
        currentDisplayInterval = nil
        latestCompletionAt = nil
        recentCompletionIntervals.removeAll(keepingCapacity: true)
    }

    mutating func recordCompletion(at completedAt: Date) {
        if let latestCompletionAt {
            guard completedAt > latestCompletionAt else {
                return
            }
            appendCompletionInterval(completedAt.timeIntervalSince(latestCompletionAt))
        }

        latestCompletionAt = completedAt
    }

    func driftSeconds(for displayedCompletionAt: Date?) -> TimeInterval? {
        guard let latestCompletionAt, let displayedCompletionAt else {
            return nil
        }
        return max(0, latestCompletionAt.timeIntervalSince(displayedCompletionAt))
    }

    @discardableResult
    mutating func updateCurrentDisplayInterval(
        displayedCompletionAt: Date?,
        hasBacklog: Bool
    ) -> TimeInterval? {
        guard let learnedInterval else {
            currentDisplayInterval = nil
            return nil
        }

        guard hasBacklog else {
            currentDisplayInterval = learnedInterval
            return currentDisplayInterval
        }

        let targetDrift = learnedInterval * ImmersivePreviewPolicy.targetDriftMultiplier
        let deadband = targetDrift * ImmersivePreviewPolicy.driftDeadbandFraction
        let lowerDriftBound = max(0, targetDrift - deadband)
        let upperDriftBound = targetDrift + deadband
        let minimumInterval = learnedInterval * ImmersivePreviewPolicy.minimumCatchUpIntervalFactor
        let maximumInterval = learnedInterval * ImmersivePreviewPolicy.maximumBacklogIntervalFactor

        var nextInterval = currentDisplayInterval ?? learnedInterval

        if let driftSeconds = driftSeconds(for: displayedCompletionAt) {
            if driftSeconds > upperDriftBound {
                nextInterval *= 1 - ImmersivePreviewPolicy.cadenceAdjustmentStepFraction
            } else if driftSeconds < lowerDriftBound {
                nextInterval *= 1 + ImmersivePreviewPolicy.cadenceAdjustmentStepFraction
            } else {
                nextInterval += (learnedInterval - nextInterval) * ImmersivePreviewPolicy.cadenceAdjustmentStepFraction
            }
        } else {
            nextInterval = learnedInterval
        }

        currentDisplayInterval = min(max(nextInterval, minimumInterval), maximumInterval)
        return currentDisplayInterval
    }

    func effectiveDisplayInterval(
        fallback: TimeInterval = ImmersivePreviewPolicy.bootstrapDisplaySeconds
    ) -> TimeInterval {
        max(0, currentDisplayInterval ?? learnedInterval ?? fallback)
    }

    private mutating func appendCompletionInterval(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        recentCompletionIntervals.append(interval)
        if recentCompletionIntervals.count > ImmersivePreviewPolicy.cadenceRollingWindowSize {
            recentCompletionIntervals.removeFirst(
                recentCompletionIntervals.count - ImmersivePreviewPolicy.cadenceRollingWindowSize
            )
        }

        let total = recentCompletionIntervals.reduce(0, +)
        learnedInterval = total / Double(recentCompletionIntervals.count)
        if currentDisplayInterval == nil {
            currentDisplayInterval = learnedInterval
        }
    }
}

struct CaptionWorkflowQueueRowState: Identifiable, Equatable {
    let id: UUID
    var albumID: String?
    var savedAlbumName: String?

    init(id: UUID = UUID(), albumID: String? = nil, savedAlbumName: String? = nil) {
        self.id = id
        self.albumID = albumID
        self.savedAlbumName = savedAlbumName
    }

    init(entry: CaptionWorkflowQueueEntry) {
        self.init(albumID: entry.albumID, savedAlbumName: entry.albumName)
    }

    var persistedEntry: CaptionWorkflowQueueEntry {
        CaptionWorkflowQueueEntry(albumID: albumID, albumName: savedAlbumName)
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    private static let ollamaDownloadPageURL = URL(string: "https://ollama.com/download/mac")!

    private struct ImmersivePreviewQueue {
        private struct Entry {
            let preview: CompletedItemPreview
            let completedAt: Date
            let lagSpan: Int
        }

        private var storage: [Entry] = []
        private var headIndex = 0

        var count: Int {
            storage.count - headIndex
        }

        var isEmpty: Bool {
            count == 0
        }

        var totalLagSpan: Int {
            activeEntries.reduce(0) { $0 + $1.lagSpan }
        }

        var previews: [CompletedItemPreview] {
            activeEntries.map(\.preview)
        }

        var previewFileURLs: [URL] {
            previews.compactMap(\.previewFileURL)
        }

        func containsAssetID(_ assetID: String) -> Bool {
            activeEntries.contains { $0.preview.assetID == assetID }
        }

        mutating func append(_ preview: CompletedItemPreview, completedAt: Date) {
            storage.append(
                Entry(
                    preview: preview,
                    completedAt: completedAt,
                    lagSpan: 1
                )
            )
        }

        mutating func popFirst() -> (preview: CompletedItemPreview, completedAt: Date, lagSpan: Int)? {
            guard headIndex < storage.count else { return nil }
            let entry = storage[headIndex]
            headIndex += 1

            if headIndex >= 32 && headIndex * 2 >= storage.count {
                storage.removeFirst(headIndex)
                headIndex = 0
            }

            return (entry.preview, entry.completedAt, entry.lagSpan)
        }

        @discardableResult
        mutating func sampleDown(toRetainedCount retainedCount: Int) -> [CompletedItemPreview] {
            let activeEntries = self.activeEntries
            let retainedIndices = Set(
                ImmersivePreviewPolicy.retainedIndices(
                    for: activeEntries.count,
                    targetRetainedCount: retainedCount
                )
            )
            guard retainedIndices.count < activeEntries.count else {
                return []
            }

            var kept: [Entry] = []
            var dropped: [CompletedItemPreview] = []
            var accumulatedLagSpan = 0
            kept.reserveCapacity(retainedIndices.count)
            dropped.reserveCapacity(activeEntries.count - retainedIndices.count)

            for (index, entry) in activeEntries.enumerated() {
                accumulatedLagSpan += entry.lagSpan
                if retainedIndices.contains(index) {
                    kept.append(
                        Entry(
                            preview: entry.preview,
                            completedAt: entry.completedAt,
                            lagSpan: accumulatedLagSpan
                        )
                    )
                    accumulatedLagSpan = 0
                } else {
                    dropped.append(entry.preview)
                }
            }

            storage = kept
            headIndex = 0
            return dropped
        }

        mutating func removeAll() {
            storage.removeAll(keepingCapacity: true)
            headIndex = 0
        }

        private var activeEntries: ArraySlice<Entry> {
            guard headIndex < storage.count else { return [] }
            return storage[headIndex...]
        }
    }

    @Published var capabilities = AppCapabilities(
        photosAutomationAvailable: false,
        ollamaAvailability: .installedNotRunning,
        pickerCapability: .unsupported(reason: "Capabilities not loaded yet.")
    )
    @Published private(set) var capabilitiesHaveLoaded = false

    @Published var sourceSelection: SourceSelection
    @Published var selectedAlbumID: String?
    @Published var pickerIDs: [String] = []
    @Published var albums: [AlbumSummary] = []
    @Published private(set) var albumLoadState: AlbumLoadState = .loadingNames
    @Published var captionWorkflowQueueRows: [CaptionWorkflowQueueRowState] = (0..<CaptionWorkflowConfiguration.minimumQueueLength).map { _ in
        CaptionWorkflowQueueRowState()
    }
    @Published var captionWorkflowStatusMessage: String?
    @Published var benchmarkAlbumOverrideID = ""
    @Published var benchmarkAlbumOverrideName = ""
    @Published var identityProbeSacrificialAssetID = ""
    @Published var identityProbeControlAssetID = ""
    @Published var identityProbeSmartAlbumID = ""
    @Published var identityProbeSmartAlbumName = ""

    @Published var useDateFilter = false
    @Published var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var endDate = Date()
    @Published var traversalOrder: RunTraversalOrder

    @Published var overwriteAppOwnedSameOrNewer: Bool
    @Published var alwaysOverwriteExternalMetadata: Bool

    @Published var isRunning = false
    @Published var isCancelRequested = false
    @Published var isPreparingModel = false
    @Published var preflightCountState: RunPreflightCountState = .message("Select an album to estimate the current scope.")
    @Published var progress = RunProgress()
    @Published var performance = RunPerformanceStats()
    @Published var runStatusMessage: String?
    @Published var lastSummary: RunSummary?
    @Published var lastCompletedItemPreview: CompletedItemPreview?
    @Published var immersiveDisplayedItemPreview: CompletedItemPreview?
    @Published var recentRunErrors: [String] = []
    @Published var isImmersivePreviewPresented = false
    @Published private(set) var isOpeningImmersivePreview = false
    @Published var ollamaStatusMessage = "Checking Qwen 2.5VL 7B availability..."
    @Published var benchmarkStatusMessage: String?
    @Published var identityProbeStatusMessage: String?
    @Published var resumablePendingCount = 0
    @Published private(set) var lastScanBenchmarkReportURL: URL?
    @Published private(set) var lastIdentityWriteProbeReportURL: URL?

    @Published var pendingConflictPrompt: ConflictPromptData?
    @Published var activeAlert: AppAlert?

    private var conflictContinuation: CheckedContinuation<Bool, Never>?
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?
    private var lastRunOptions: RunOptions?
    private var lastFailedAssetIDs: [String] = []
    private var fastTraversalTotalCountTask: Task<Void, Never>?
    private var runStartedAt: Date?
    private var performanceTickTask: Task<Void, Never>?
    private var latestPendingIDs: [String] = []
    private var lastPersistedPendingCount: Int?
    private var persistedRunOptionsForResume: PersistedRunOptions?
    private var persistedRunState: PersistedRunState?
    private var preparationStatusMessage: String?
    private var automaticRestartStatusMessage: String?
    private var hasShownStartupAutomationAlert = false
    private var queuedImmersivePreviews = ImmersivePreviewQueue()
    private var immersivePreviewTask: Task<Void, Never>?
    private var immersiveLastPreviewPresentedAt: Date?
    private var immersiveDisplayedItemCompletedAt: Date?
    private var lastCompletedItemCompletedAt: Date?
    private var immersiveCadence = ImmersivePlaybackCadence()
    private var retainedPreviewFileURLs: Set<URL> = []
    private var lastScanBenchmarkReport: PhotoKitScanBenchmarkReport?
    private var preflightCountCache: [String: Int] = [:]
    private var albumRefreshGeneration = 0
    private var albumCountRefreshTask: Task<Void, Never>?
    private let appSettingsDefaults: UserDefaults

    private let photosClient = PhotosAppleScriptClient()
    private let photoKitIncrementalScanSource = ExperimentalPhotoKitScanReader()
    private let ollamaManager = OllamaManager()
    private let runResumeStore = RunResumeStore()
    private let captionWorkflowConfigurationStore = CaptionWorkflowConfigurationStore()
    private let storagePaths = AppStoragePaths.make()
    private let storageMigrator = AppStorageMigrator()
    private lazy var capabilityProbe = CapabilityProbe(photosClient: photosClient, ollamaManager: ollamaManager)
    private lazy var scanBenchmarkRunner = PhotoLibraryScanBenchmarkRunner(appleScriptClient: photosClient)
    private lazy var identityWriteProbeRunner = PhotoLibraryIdentityWriteProbeRunner(appleScriptClient: photosClient)
    private lazy var coordinator = RunCoordinator(
        photosWriter: photosClient,
        analyzer: QwenVisionLanguageAnalyzer(),
        incrementalScanSource: photoKitIncrementalScanSource
    )
    @Published private(set) var isRunningScanBenchmark = false
    @Published private(set) var isRunningIdentityWriteProbe = false

    init(appSettingsDefaults: UserDefaults = .standard) {
        self.appSettingsDefaults = appSettingsDefaults
        let snapshot = AppSettings.load(from: appSettingsDefaults)
        sourceSelection = snapshot.defaultSourceSelection
        traversalOrder = snapshot.defaultTraversalOrder
        overwriteAppOwnedSameOrNewer = snapshot.defaultOverwriteAppOwnedSameOrNewer
        alwaysOverwriteExternalMetadata = snapshot.defaultAlwaysOverwriteExternalMetadata
    }

    var immersiveLagCount: Int {
        guard isImmersivePreviewPresented,
              immersiveDisplayedItemPreview != nil
        else {
            return 0
        }
        return queuedImmersivePreviews.totalLagSpan
    }

    var immersiveLearnedInterval: TimeInterval? {
        immersiveCadence.learnedInterval
    }

    var immersiveCurrentDisplayInterval: TimeInterval? {
        immersiveCadence.currentDisplayInterval
    }

    var immersiveDriftSeconds: TimeInterval? {
        immersiveCadence.driftSeconds(for: immersiveDisplayedItemCompletedAt)
    }

    var runPreflightRefreshToken: String {
        let queueToken = captionWorkflowQueueRows.map { row in
            "\(row.albumID ?? "")|\(row.savedAlbumName ?? "")"
        }.joined(separator: ";")

        return [
            sourceSelection.rawValue,
            selectedAlbumID ?? "",
            pickerIDs.joined(separator: ","),
            queueToken,
            capabilities.photosAutomationAvailable.description
        ]
        .joined(separator: "||")
    }

    var runPreflightSummary: RunPreflightSummary {
        RunPreflightSummaryBuilder.build(
            snapshot: currentRunSetupSnapshot,
            capabilities: capabilities,
            countState: preflightCountState
        )
    }

    var currentStoragePaths: AppStoragePaths {
        storagePaths
    }

    var previewOpenBehavior: PreviewOpenBehavior {
        AppSettings.load(from: appSettingsDefaults).previewOpenBehavior
    }

    var shouldShowOllamaSetupCard: Bool {
        guard capabilitiesHaveLoaded else { return false }
        if case .notInstalled = capabilities.ollamaAvailability {
            return true
        }
        return false
    }

    var canOpenPreviewWindow: Bool {
        isRunning || lastCompletedItemPreview != nil || immersiveDisplayedItemPreview != nil
    }

    var canStartRun: Bool {
        !isRunning && !isPreparingModel && runPreflightSummary.blockingReasons.isEmpty
    }

    func applyAppDefaultsIfPossible() {
        guard !isRunning, !isPreparingModel else { return }
        let snapshot = AppSettings.load(from: appSettingsDefaults)
        sourceSelection = snapshot.defaultSourceSelection
        traversalOrder = snapshot.defaultTraversalOrder
        overwriteAppOwnedSameOrNewer = snapshot.defaultOverwriteAppOwnedSameOrNewer
        alwaysOverwriteExternalMetadata = snapshot.defaultAlwaysOverwriteExternalMetadata
    }

    func loadInitialData() async {
        await storageMigrator.migrateLegacyPersistentStateIfNeeded()
        await refreshCapabilities()
        if capabilities.photosAutomationAvailable {
            hasShownStartupAutomationAlert = false
        } else if !hasShownStartupAutomationAlert {
            hasShownStartupAutomationAlert = true
            showMessage(
                title: "Automation Permission Needed",
                message: "Photos automation is not available yet. Grant Apple Events permission now so caption updates and automatic Photos restarts can run unattended later."
            )
        }
        await loadCaptionWorkflowConfiguration()
        let albumRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshAlbums()
        }
        await loadPersistedRunState()
        await albumRefreshTask.value
        await refreshRunPreflightCount()
    }

    func refreshCapabilities() async {
        capabilities = await capabilityProbe.probe()
        capabilitiesHaveLoaded = true
        ollamaStatusMessage = makeOllamaStatusMessage(for: capabilities)
    }

    func recheckOllamaSetup() async {
        await refreshCapabilities()
    }

    func refreshAlbums() async {
        albumRefreshGeneration += 1
        let refreshGeneration = albumRefreshGeneration
        let retainedAlbums = albums

        albumCountRefreshTask?.cancel()
        albumCountRefreshTask = nil
        albumLoadState = .loadingNames

        do {
            let listedAlbums = try await photosClient.listUserAlbums()
            guard refreshGeneration == albumRefreshGeneration else {
                return
            }

            albums = listedAlbums
            await reconcileCaptionWorkflowSelections(persistChanges: true)

            guard !listedAlbums.isEmpty else {
                albumLoadState = .ready
                return
            }

            albumLoadState = .loadingCounts
            albumCountRefreshTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let resolvedAlbums = await self.photoKitIncrementalScanSource.withResolvedPlainAlbumCounts(listedAlbums)
                guard !Task.isCancelled else { return }
                await self.applyResolvedAlbumCounts(resolvedAlbums, generation: refreshGeneration)
            }
        } catch {
            guard refreshGeneration == albumRefreshGeneration else {
                return
            }

            if !retainedAlbums.isEmpty {
                albums = retainedAlbums
            }
            albumLoadState = .failed(message: error.localizedDescription)
        }
    }

    func startRun() async {
        guard !isRunning, !isPreparingModel else { return }

        guard capabilities.photosAutomationAvailable else {
            showMessage(
                title: "Automation Required",
                message: "Photos automation is not available. Grant Apple Events permission and try again."
            )
            return
        }

        guard let options = makeRunOptions() else {
            return
        }

        guard await ensureOllamaInstalledForRunIfNeeded() else {
            return
        }

        guard await ensurePhotosReadyForWriteRun() else {
            return
        }

        let summary = runPreflightSummary
        if !summary.confirmationReasons.isEmpty {
            let confirmed = await requestConfirmation(
                title: "Confirm Run",
                message: confirmationMessage(for: summary),
                confirmLabel: summary.confirmationLabel ?? "Start Run",
                cancelLabel: "Cancel"
            )
            guard confirmed else { return }
        }

        guard await prepareModelForRunIfNeeded() else {
            return
        }

        await run(options: options)
    }

    func retryFailedItems() async {
        guard !isRunning, !isPreparingModel else { return }
        guard capabilities.photosAutomationAvailable else {
            showMessage(
                title: "Automation Required",
                message: "Photos automation is not available. Grant Apple Events permission and try again."
            )
            return
        }
        guard !lastFailedAssetIDs.isEmpty else {
            showMessage(title: "No Failed Items", message: "There are no failed items to retry.")
            return
        }
        if case let .unsupported(reason) = capabilities.pickerCapability {
            showMessage(title: "Retry Unavailable", message: reason)
            return
        }
        guard await ensureOllamaInstalledForRunIfNeeded() else {
            return
        }
        guard await ensurePhotosReadyForWriteRun() else {
            return
        }

        let overwrite = lastRunOptions?.overwriteAppOwnedSameOrNewer ?? overwriteAppOwnedSameOrNewer
        let overwriteExternal = lastRunOptions?.alwaysOverwriteExternalMetadata ?? alwaysOverwriteExternalMetadata
        let retryTraversalOrder = lastRunOptions?.traversalOrder ?? traversalOrder
        let retryOptions = RunOptions(
            source: .picker(ids: lastFailedAssetIDs),
            optionalCaptureDateRange: nil,
            traversalOrder: retryTraversalOrder,
            overwriteAppOwnedSameOrNewer: overwrite,
            alwaysOverwriteExternalMetadata: overwriteExternal
        )
        guard await prepareModelForRunIfNeeded() else {
            return
        }
        await run(options: retryOptions)
    }

    func resumeSavedRun() async {
        guard !isRunning, !isPreparingModel else { return }
        guard capabilities.photosAutomationAvailable else {
            showMessage(
                title: "Automation Required",
                message: "Photos automation is not available. Grant Apple Events permission and try again."
            )
            return
        }
        guard case .supported = capabilities.pickerCapability else {
            showMessage(title: "Resume Unavailable", message: pickerUnavailableReason)
            return
        }
        guard let persistedRunState, !persistedRunState.pendingIDs.isEmpty else {
            showMessage(title: "Nothing To Resume", message: "No persisted pending IDs were found.")
            return
        }
        guard await ensureOllamaInstalledForRunIfNeeded() else {
            return
        }
        guard await ensurePhotosReadyForWriteRun() else {
            return
        }

        let restoredBaseOptions = persistedRunState.options.toRunOptions()
        let resumeOptions = RunOptions(
            source: .picker(ids: persistedRunState.pendingIDs),
            optionalCaptureDateRange: nil,
            traversalOrder: restoredBaseOptions.traversalOrder,
            overwriteAppOwnedSameOrNewer: restoredBaseOptions.overwriteAppOwnedSameOrNewer,
            alwaysOverwriteExternalMetadata: restoredBaseOptions.alwaysOverwriteExternalMetadata
        )
        guard await prepareModelForRunIfNeeded() else {
            return
        }
        await run(options: resumeOptions, persistedOptionsOverride: persistedRunState.options)
    }

    private func run(options: RunOptions, persistedOptionsOverride: PersistedRunOptions? = nil) async {
        let persistedOptions = persistedOptionsOverride ?? PersistedRunOptions(runOptions: options)
        persistedRunOptionsForResume = persistedOptions

        isRunning = true
        isCancelRequested = false
        progress = RunProgress()
        performance = RunPerformanceStats()
        setPreparationStatus(nil)
        setAutomaticRestartStatus(nil)
        lastSummary = nil
        lastCompletedItemPreview = nil
        resetImmersivePreviewState()
        recentRunErrors = []
        lastRunOptions = options
        lastFailedAssetIDs = []
        latestPendingIDs = []
        lastPersistedPendingCount = nil
        runStartedAt = Date()
        fastTraversalTotalCountTask?.cancel()
        fastTraversalTotalCountTask = nil
        startFastTraversalTotalCountTaskIfNeeded(options: options)
        startPerformanceTicker()
        await persistRunStateIfNeeded(pendingIDs: [], force: true)

        let callbacks = RunCallbacks(
            onProgress: { [weak self] updated in
                Task { @MainActor in
                    guard let self else { return }
                    let mergedDiscovered = max(self.progress.totalDiscovered, updated.totalDiscovered)
                    self.progress = RunProgress(
                        totalDiscovered: mergedDiscovered,
                        processed: updated.processed,
                        changed: updated.changed,
                        skipped: updated.skipped,
                        failed: updated.failed
                    )
                    self.refreshPerformance()
                    if updated.processed > 0 {
                        self.setPreparationStatus(nil)
                    }
                }
            },
            onPreparationProgress: { [weak self] enumerated, total in
                guard total > 0 else { return }
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.setPreparationStatus("Preparing ordered run (\(enumerated)/\(total) enumerated)")
                }
            },
            onStatusChanged: { [weak self] status in
                Task { @MainActor in
                    self?.setAutomaticRestartStatus(status)
                }
            },
            onItemCompleted: { [weak self] preview in
                Task { @MainActor in
                    self?.receiveCompletedItemPreview(preview)
                }
            },
            onPendingIDsUpdated: { [weak self] pendingIDs in
                Task { @MainActor in
                    guard let self else { return }
                    self.latestPendingIDs = pendingIDs
                    self.resumablePendingCount = pendingIDs.count
                    await self.persistRunStateIfNeeded(
                        pendingIDs: pendingIDs,
                        force: pendingIDs.isEmpty
                    )
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    guard let self else { return }
                    self.recentRunErrors.append(message)
                    if self.recentRunErrors.count > 12 {
                        self.recentRunErrors.removeFirst(self.recentRunErrors.count - 12)
                    }
                }
            },
            confirmExternalOverwrite: { [weak self] asset, existing in
                guard let self else { return false }
                return await self.requestConflictDecision(asset: asset, existing: existing)
            },
            confirmSafetyPause: { [weak self] prompt in
                guard let self else { return false }
                return await self.requestConfirmation(
                    title: prompt.title,
                    message: prompt.message,
                    confirmLabel: prompt.confirmLabel,
                    cancelLabel: prompt.cancelLabel
                )
            }
        )

        let summary = await coordinator.run(options: options, capabilities: capabilities, callbacks: callbacks)
        fastTraversalTotalCountTask?.cancel()
        fastTraversalTotalCountTask = nil
        performanceTickTask?.cancel()
        performanceTickTask = nil
        refreshPerformance()
        isRunning = false
        isCancelRequested = false
        runStartedAt = nil
        setPreparationStatus(nil)
        setAutomaticRestartStatus(nil)
        lastSummary = summary
        lastFailedAssetIDs = summary.failedAssets.map(\.id)
        synchronizeRetainedPreviewFiles()

        await finalizePersistedRunState()

        if !summary.errors.isEmpty {
            showMessage(
                title: "Run Completed with Errors",
                message: summary.errors.prefix(5).joined(separator: "\n")
            )
        } else if summary.progress.totalDiscovered == 0 {
            showMessage(
                title: "Run Finished: No Matching Items",
                message: emptyRunMessage(for: options)
            )
        }
    }

    func openDataFolder() {
        revealDataFolder()
    }

    func revealDataFolder() {
        do {
            try FileManager.default.createDirectory(
                at: storagePaths.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.activateFileViewerSelecting([storagePaths.applicationSupportDirectory])
        } catch {
            showMessage(title: "Open Data Folder Failed", message: error.localizedDescription)
        }
    }

    func revealSavedRunStateFile() {
        revealInFinder(storagePaths.runResumeStateFile)
    }

    func revealQueuedAlbumsConfigurationFile() {
        revealInFinder(storagePaths.captionWorkflowConfigurationFile)
    }

    func revealBenchmarkTempFolder() {
        revealInFinder(storagePaths.benchmarkTempRoot)
    }

    func revealPreviewTempFolder() {
        revealInFinder(storagePaths.previewTempRoot)
    }

    func revealLatestScanBenchmarkReport() {
        guard let lastScanBenchmarkReportURL else { return }
        revealInFinder(lastScanBenchmarkReportURL)
    }

    func revealLatestIdentityWriteProbeReport() {
        guard let lastIdentityWriteProbeReportURL else { return }
        revealInFinder(lastIdentityWriteProbeReportURL)
    }

    func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    func clearSavedRunState() async {
        guard !isRunning, !isPreparingModel else { return }

        let confirmed = await requestConfirmation(
            title: "Clear Saved Run State?",
            message: "This removes only the resumable pending-ID snapshot at:\n\(storagePaths.runResumeStateFile.path)\n\nYour saved \(AppPresentation.queuedAlbumsTitle) configuration will be kept.",
            confirmLabel: "Clear Saved Run State",
            cancelLabel: "Cancel"
        )
        guard confirmed else { return }

        await runResumeStore.clear()
        persistedRunState = nil
        resumablePendingCount = 0
        latestPendingIDs = []
        lastPersistedPendingCount = nil
        showMessage(title: "Saved Run State Cleared", message: "The resumable pending-ID snapshot was removed.")
    }

    func confirmAndOpenOllamaDownloadPage() async {
        let confirmed = await requestConfirmation(
            title: "Open Ollama Download Page?",
            message: "Photos Caption Assistant needs Ollama installed locally before caption runs can start.\n\nThe app does not install third-party software automatically. If you continue, it will open the official Ollama macOS download page in your browser. After installing Ollama, return here and click Re-check Setup.",
            confirmLabel: "Open Download Page",
            cancelLabel: "Cancel"
        )
        guard confirmed else { return }
        openOllamaDownloadPage()
    }

    func refreshRunPreflightCount() async {
        switch sourceSelection {
        case .picker:
            preflightCountState = .exact(pickerIDs.count)
            return
        case .captionWorkflow:
            preflightCountState = .message("Item count is not precomputed stage-by-stage for \(AppPresentation.queuedAlbumsTitle).")
            return
        case .album:
            guard let selectedAlbumID, !selectedAlbumID.isEmpty else {
                preflightCountState = .message("Select an album to estimate the current scope.")
                return
            }
            guard capabilities.photosAutomationAvailable else {
                preflightCountState = .message("Grant Photos automation access to estimate album and library counts.")
                return
            }

            let cacheKey = "album:\(selectedAlbumID)"
            if let cachedCount = preflightCountCache[cacheKey] {
                preflightCountState = .exact(cachedCount)
                return
            }

            preflightCountState = .loading
            let count = try? await photosClient.count(scope: .album(id: selectedAlbumID))
            guard !Task.isCancelled else { return }
            if let count {
                preflightCountCache[cacheKey] = count
                preflightCountState = .exact(count)
            } else {
                preflightCountState = .message("Unable to count the selected album right now.")
            }
        case .library:
            guard capabilities.photosAutomationAvailable else {
                preflightCountState = .message("Grant Photos automation access to estimate album and library counts.")
                return
            }

            let cacheKey = "library"
            if let cachedCount = preflightCountCache[cacheKey] {
                preflightCountState = .exact(cachedCount)
                return
            }

            preflightCountState = .loading
            let count = try? await photosClient.count(scope: .library)
            guard !Task.isCancelled else { return }
            if let count {
                preflightCountCache[cacheKey] = count
                preflightCountState = .exact(count)
            } else {
                preflightCountState = .message("Unable to count the whole library right now.")
            }
        }
    }

    private func openOllamaDownloadPage() {
        let opened = NSWorkspace.shared.open(Self.ollamaDownloadPageURL)
        if opened {
            ollamaStatusMessage = "Opened the official Ollama download page. Install Ollama, then return here and click Re-check Setup."
        } else {
            showMessage(
                title: "Open Download Page Failed",
                message: "The app could not open the official Ollama download page automatically. Visit:\n\(Self.ollamaDownloadPageURL.absoluteString)"
            )
        }
    }

    func cancelRun() {
        guard isRunning else { return }
        guard !isCancelRequested else { return }
        isCancelRequested = true
        coordinator.cancel()
    }

    func runScanBenchmarkFromMenu() async {
        guard !isRunning, !isPreparingModel, !isRunningScanBenchmark, !isRunningIdentityWriteProbe else { return }

        isRunningScanBenchmark = true
        benchmarkStatusMessage = "Preparing scan benchmark..."
        defer {
            isRunningScanBenchmark = false
        }

        do {
            let authorizationStatus = await requestPhotoLibraryAccessIfNeeded()
            guard authorizationStatus == .authorized || authorizationStatus == .limited else {
                benchmarkStatusMessage = "Scan benchmark skipped."
                showMessage(
                    title: "Scan Benchmark Skipped",
                    message: "Photos library access was not granted (status=\(authorizationStatus.rawValue))."
                )
                return
            }

            let configuration = makeScanBenchmarkConfiguration()
            benchmarkStatusMessage = "Running scan benchmark on the \(configuration.sampleDescription)..."
            let outcome = try await scanBenchmarkRunner.run(configuration: configuration) { [weak self] message in
                await MainActor.run {
                    self?.benchmarkStatusMessage = message
                }
            }
            switch outcome {
            case let .completed(run):
                lastScanBenchmarkReport = run.report
                lastScanBenchmarkReportURL = run.reportURL
                benchmarkStatusMessage = "Scan benchmark report: \(run.reportURL.lastPathComponent)"
                let noticeText = run.notices.joined(separator: "\n")
                let summaries = run.report.scopes.map(\.summaryLine).joined(separator: "\n")
                showMessage(
                    title: "Scan Benchmark Complete",
                    message: [
                        "Report saved to:\n\(run.reportURL.path)",
                        noticeText.isEmpty ? nil : noticeText,
                        summaries
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                )
            case let .skipped(reason):
                benchmarkStatusMessage = "Scan benchmark skipped."
                showMessage(
                    title: "Scan Benchmark Skipped",
                    message: reason
                )
            }
        } catch {
            benchmarkStatusMessage = "Scan benchmark failed."
            showMessage(
                title: "Scan Benchmark Failed",
                message: error.localizedDescription
            )
        }
    }

    func prefillIdentityProbeFromLatestBenchmark() {
        let preferredScope = lastScanBenchmarkReport?.scopes.first(where: { $0.scopeLabel == "Whole Library" })
            ?? lastScanBenchmarkReport?.scopes.first
        guard let preferredScope,
              preferredScope.identityProof.samples.count >= 2
        else {
            showMessage(
                title: "No Benchmark IDs Available",
                message: "Run the scan benchmark first, then use the sampled IDs listed in the Diagnostics window."
            )
            return
        }

        identityProbeSacrificialAssetID = preferredScope.identityProof.samples[0].requestedPhotoKitID
        identityProbeControlAssetID = preferredScope.identityProof.samples[1].requestedPhotoKitID
        identityProbeStatusMessage = "Prefilled write-probe IDs from the latest benchmark sample."
    }

    func runIdentityWriteProbeFromMenu() async {
        guard !isRunning, !isPreparingModel, !isRunningScanBenchmark, !isRunningIdentityWriteProbe else { return }

        guard let configuration = PhotoLibraryIdentityWriteProbeConfiguration(
            sacrificialAssetID: identityProbeSacrificialAssetID,
            controlAssetID: identityProbeControlAssetID,
            expectedSmartAlbumID: identityProbeSmartAlbumID,
            expectedSmartAlbumName: identityProbeSmartAlbumName
        ) else {
            showMessage(
                title: "Identity Write Probe Needs IDs",
                message: "Enter a sacrificial asset ID and a different control asset ID in the Diagnostics window before running the write probe."
            )
            return
        }

        let confirmationMessage = [
            "This diagnostics-only probe will temporarily write a sentinel caption and keyword to the sacrificial asset, verify the result, and then restore the original metadata.",
            "Sacrificial asset: \(configuration.sacrificialAssetID)",
            "Control asset: \(configuration.controlAssetID)",
            configuration.expectedSmartAlbumID.map { "Expected smart album handoff: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        let confirmed = await requestConfirmation(
            title: "Run Identity Write Probe?",
            message: confirmationMessage,
            confirmLabel: "Run Probe",
            cancelLabel: "Cancel"
        )
        guard confirmed else { return }

        isRunningIdentityWriteProbe = true
        identityProbeStatusMessage = "Preparing identity write probe..."
        defer {
            isRunningIdentityWriteProbe = false
        }

        do {
            let authorizationStatus = await requestPhotoLibraryAccessIfNeeded()
            guard authorizationStatus == .authorized || authorizationStatus == .limited else {
                identityProbeStatusMessage = "Identity write probe skipped."
                showMessage(
                    title: "Identity Write Probe Skipped",
                    message: "Photos library access was not granted (status=\(authorizationStatus.rawValue))."
                )
                return
            }

            let outcome = try await identityWriteProbeRunner.run(configuration: configuration) { [weak self] message in
                await MainActor.run {
                    self?.identityProbeStatusMessage = message
                }
            }

            switch outcome {
            case let .completed(run):
                lastIdentityWriteProbeReportURL = run.reportURL
                identityProbeStatusMessage = "Identity write probe report: \(run.reportURL.lastPathComponent)"
                showMessage(
                    title: run.report.overallPass ? "Identity Write Probe Passed" : "Identity Write Probe Failed",
                    message: [
                        "Report saved to:\n\(run.reportURL.path)",
                        run.report.summaryLine,
                        run.report.failureReasons.isEmpty ? nil : run.report.failureReasons.joined(separator: "\n")
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                )
            case let .skipped(reason):
                identityProbeStatusMessage = "Identity write probe skipped."
                showMessage(
                    title: "Identity Write Probe Skipped",
                    message: reason
                )
            }
        } catch {
            identityProbeStatusMessage = "Identity write probe failed."
            showMessage(
                title: "Identity Write Probe Failed",
                message: error.localizedDescription
            )
        }
    }

    private func makeScanBenchmarkConfiguration() -> PhotoLibraryScanBenchmarkConfiguration {
        PhotoLibraryScanBenchmarkConfiguration(
            pageSizes: PhotoLibraryScanBenchmarkConfiguration.defaultPageSizes,
            warmIterations: 1,
            maxItems: PhotoLibraryScanBenchmarkConfiguration.defaultMaxItems,
            configuredAlbumID: benchmarkAlbumOverrideID,
            configuredAlbumName: benchmarkAlbumOverrideName
        )
    }

    var benchmarkSampleIDsText: String? {
        guard let report = lastScanBenchmarkReport else { return nil }

        let sections = report.scopes.compactMap { scope -> String? in
            let ids = scope.identityProof.samples.prefix(12).map(\.requestedPhotoKitID)
            guard !ids.isEmpty else { return nil }
            let body = ids.enumerated().map { index, id in
                "\(index + 1). \(id)"
            }.joined(separator: "\n")
            return "\(scope.scopeLabel)\n\(body)"
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    private func requestPhotoLibraryAccessIfNeeded() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        benchmarkStatusMessage = "Waiting for Photos library access..."
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func resolveConflictPrompt(overwrite: Bool) {
        conflictContinuation?.resume(returning: overwrite)
        conflictContinuation = nil
        pendingConflictPrompt = nil
    }

    func resolveConfirmationPrompt(confirmed: Bool) {
        confirmationContinuation?.resume(returning: confirmed)
        confirmationContinuation = nil
        activeAlert = nil
    }

    func clearMessagePrompt() {
        activeAlert = nil
    }

    func openImmersivePreview() {
        isOpeningImmersivePreview = true
        if immersiveDisplayedItemPreview == nil {
            if let nextPreview = queuedImmersivePreviews.popFirst() {
                immersiveDisplayedItemPreview = nextPreview.preview
                immersiveDisplayedItemCompletedAt = nextPreview.completedAt
            } else {
                immersiveDisplayedItemPreview = lastCompletedItemPreview
                immersiveDisplayedItemCompletedAt = lastCompletedItemCompletedAt
            }
        }
        immersiveLastPreviewPresentedAt = immersiveDisplayedItemPreview == nil ? nil : Date()
        refreshImmersiveDisplayInterval()
        synchronizeRetainedPreviewFiles()
        isImmersivePreviewPresented = true
        handleImmersivePresentationChange(true)
    }

    func closeImmersivePreview() {
        guard isImmersivePreviewPresented else { return }
        isImmersivePreviewPresented = false
        handleImmersivePresentationChange(false)
    }

    func handleImmersivePresentationChange(_ isPresented: Bool) {
        if isPresented {
            scheduleImmersivePreviewAdvanceIfNeeded()
        } else {
            isOpeningImmersivePreview = false
            immersivePreviewTask?.cancel()
            immersivePreviewTask = nil
            immersiveDisplayedItemPreview = nil
            immersiveLastPreviewPresentedAt = nil
            immersiveDisplayedItemCompletedAt = nil
            synchronizeRetainedPreviewFiles()
        }
    }

    func receiveCompletedItemPreview(_ preview: CompletedItemPreview, scheduleAdvance: Bool = true) {
        receiveCompletedItemPreview(preview, completedAt: Date(), scheduleAdvance: scheduleAdvance)
    }

    func receiveCompletedItemPreview(
        _ preview: CompletedItemPreview,
        completedAt: Date,
        scheduleAdvance: Bool = true
    ) {
        let priorLastCompletedAssetID = lastCompletedItemPreview?.assetID
        lastCompletedItemPreview = preview
        lastCompletedItemCompletedAt = completedAt

        guard shouldTrackImmersivePreview(
            preview,
            priorLastCompletedAssetID: priorLastCompletedAssetID
        ) else {
            synchronizeRetainedPreviewFiles()
            return
        }

        immersiveCadence.recordCompletion(at: completedAt)

        if isImmersivePreviewPresented, immersiveDisplayedItemPreview == nil {
            immersiveDisplayedItemPreview = preview
            immersiveDisplayedItemCompletedAt = completedAt
            immersiveLastPreviewPresentedAt = Date()
            refreshImmersiveDisplayInterval()
            synchronizeRetainedPreviewFiles()
            return
        }

        queueImmersivePreview(preview, completedAt: completedAt)
        refreshImmersiveDisplayInterval()
        synchronizeRetainedPreviewFiles()
        if isImmersivePreviewPresented, scheduleAdvance {
            scheduleImmersivePreviewAdvanceIfNeeded()
        }
    }

    private func scheduleImmersivePreviewAdvanceIfNeeded() {
        guard isImmersivePreviewPresented else { return }
        guard immersivePreviewTask == nil else { return }
        guard !queuedImmersivePreviews.isEmpty else { return }

        immersivePreviewTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while self.isImmersivePreviewPresented, !self.queuedImmersivePreviews.isEmpty {
                while self.isImmersivePreviewPresented, !self.queuedImmersivePreviews.isEmpty {
                    let now = Date()
                    let targetDelay = self.immersiveCadence.effectiveDisplayInterval()
                    let elapsed = self.immersiveLastPreviewPresentedAt.map { now.timeIntervalSince($0) }
                        ?? targetDelay
                    let remainingDelay = max(0, targetDelay - elapsed)
                    guard remainingDelay > 0 else { break }

                    let sleepDuration = min(remainingDelay, 1)
                    try? await Task.sleep(nanoseconds: UInt64(sleepDuration * 1_000_000_000))
                    guard !Task.isCancelled else {
                        self.immersivePreviewTask = nil
                        return
                    }
                }

                guard self.isImmersivePreviewPresented else { break }
                guard self.advanceImmersivePreviewNowIfPossible() else { break }
            }

            self.immersivePreviewTask = nil
            if self.isImmersivePreviewPresented, !self.queuedImmersivePreviews.isEmpty {
                self.scheduleImmersivePreviewAdvanceIfNeeded()
            }
        }
    }

    @discardableResult
    func advanceImmersivePreviewNowIfPossible() -> Bool {
        guard isImmersivePreviewPresented else { return false }
        guard let nextPreview = queuedImmersivePreviews.popFirst() else { return false }

        immersiveDisplayedItemPreview = nextPreview.preview
        immersiveDisplayedItemCompletedAt = nextPreview.completedAt
        immersiveLastPreviewPresentedAt = Date()
        refreshImmersiveDisplayInterval()
        synchronizeRetainedPreviewFiles()
        return true
    }

    private func resetImmersivePreviewState() {
        isOpeningImmersivePreview = false
        immersivePreviewTask?.cancel()
        immersivePreviewTask = nil
        immersiveDisplayedItemPreview = nil
        queuedImmersivePreviews.removeAll()
        immersiveLastPreviewPresentedAt = nil
        immersiveDisplayedItemCompletedAt = nil
        lastCompletedItemCompletedAt = nil
        immersiveCadence.reset()
        synchronizeRetainedPreviewFiles()
    }

    private func shouldTrackImmersivePreview(
        _ preview: CompletedItemPreview,
        priorLastCompletedAssetID: String?
    ) -> Bool {
        if preview.assetID == priorLastCompletedAssetID {
            return false
        }
        if preview.assetID == immersiveDisplayedItemPreview?.assetID {
            return false
        }
        return !queuedImmersivePreviews.containsAssetID(preview.assetID)
    }

    private func queueImmersivePreview(_ preview: CompletedItemPreview, completedAt: Date) {
        queuedImmersivePreviews.append(preview, completedAt: completedAt)
        if queuedImmersivePreviews.count > ImmersivePreviewPolicy.emergencySamplingThreshold {
            queuedImmersivePreviews.sampleDown(
                toRetainedCount: ImmersivePreviewPolicy.sampledRetainedPreviewCount
            )
        }
    }

    private func refreshImmersiveDisplayInterval() {
        _ = immersiveCadence.updateCurrentDisplayInterval(
            displayedCompletionAt: immersiveDisplayedItemCompletedAt,
            hasBacklog: !queuedImmersivePreviews.isEmpty
        )
    }

    private func synchronizeRetainedPreviewFiles() {
        let activePreviewFileURLs = Set(currentPreviewFileURLs())
        let stalePreviewFileURLs = retainedPreviewFileURLs.subtracting(activePreviewFileURLs)
        stalePreviewFileURLs.forEach(Self.cleanupPreviewFile)
        retainedPreviewFileURLs = activePreviewFileURLs
    }

    private func currentPreviewFileURLs() -> [URL] {
        var urls = Set<URL>()
        if let fileURL = lastCompletedItemPreview?.previewFileURL {
            urls.insert(fileURL)
        }
        if let fileURL = immersiveDisplayedItemPreview?.previewFileURL {
            urls.insert(fileURL)
        }
        queuedImmersivePreviews.previewFileURLs.forEach { urls.insert($0) }
        return Array(urls)
    }

    private static func cleanupPreviewFile(at fileURL: URL) {
        let previewRoot = AppStoragePaths.make().previewTempRoot
        guard AppStoragePaths.contains(fileURL, within: previewRoot) else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func setPreparationStatus(_ message: String?) {
        preparationStatusMessage = message
        refreshRunStatusMessage()
    }

    private func setAutomaticRestartStatus(_ message: String?) {
        automaticRestartStatusMessage = message
        refreshRunStatusMessage()
    }

    private func refreshRunStatusMessage() {
        runStatusMessage = automaticRestartStatusMessage ?? preparationStatusMessage
    }

    private func startFastTraversalTotalCountTaskIfNeeded(options: RunOptions) {
        guard options.traversalOrder == .photosOrderFast else { return }
        guard options.optionalCaptureDateRange == nil else { return }
        guard options.source != .captionWorkflow else { return }

        fastTraversalTotalCountTask = Task { [weak self] in
            // Let page-1 processing begin first so count work doesn't delay startup.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }

            let totalCount = try? await self.photosClient.count(scope: options.source)
            guard let totalCount, !Task.isCancelled else { return }

            await MainActor.run {
                guard self.isRunning else { return }
                self.progress.totalDiscovered = max(self.progress.totalDiscovered, totalCount)
            }
        }
    }

    private func startPerformanceTicker() {
        performanceTickTask?.cancel()
        performanceTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                let shouldContinue = await MainActor.run { () -> Bool in
                    guard let self else { return false }
                    self.refreshPerformance()
                    return self.isRunning
                }
                if !shouldContinue {
                    break
                }
            }
        }
    }

    private func refreshPerformance() {
        guard let runStartedAt else {
            performance = RunPerformanceStats()
            return
        }

        let elapsedSeconds = max(0, Int(Date().timeIntervalSince(runStartedAt)))
        guard elapsedSeconds > 0, progress.processed > 0 else {
            performance = RunPerformanceStats(
                elapsedSeconds: elapsedSeconds,
                itemsPerMinute: nil,
                etaSeconds: nil
            )
            return
        }

        let ratePerMinute = (Double(progress.processed) / Double(elapsedSeconds)) * 60.0
        let etaSeconds: Int?
        if progress.totalDiscovered > progress.processed, ratePerMinute > 0 {
            let ratePerSecond = ratePerMinute / 60.0
            let remaining = progress.totalDiscovered - progress.processed
            etaSeconds = Int((Double(remaining) / ratePerSecond).rounded())
        } else {
            etaSeconds = nil
        }

        performance = RunPerformanceStats(
            elapsedSeconds: elapsedSeconds,
            itemsPerMinute: ratePerMinute,
            etaSeconds: etaSeconds
        )
    }

    func markImmersivePreviewOpened() {
        isOpeningImmersivePreview = false
    }

    private func applyResolvedAlbumCounts(_ resolvedAlbums: [AlbumSummary], generation: Int) async {
        guard generation == albumRefreshGeneration else {
            return
        }

        albums = resolvedAlbums
        albumLoadState = .ready
        await reconcileCaptionWorkflowSelections(persistChanges: true)
    }

    private func loadPersistedRunState() async {
        let loaded = await runResumeStore.load()
        persistedRunState = loaded
        resumablePendingCount = loaded?.pendingIDs.count ?? 0
    }

    private var currentRunSetupSnapshot: RunSetupSnapshot {
        let captionWorkflowConfiguration = CaptionWorkflowConfiguration(
            queue: normalizedCaptionWorkflowQueueRows(captionWorkflowQueueRows).map(\.persistedEntry)
        )

        return RunSetupSnapshot(
            sourceSelection: sourceSelection,
            selectedAlbum: albums.first(where: { $0.id == selectedAlbumID }),
            pickerIDs: pickerIDs,
            captionWorkflowConfiguration: captionWorkflowConfiguration,
            useDateFilter: useDateFilter,
            dateRange: useDateFilter ? CaptureDateRange(start: startDate, end: endDate) : nil,
            overwriteAppOwnedSameOrNewer: overwriteAppOwnedSameOrNewer,
            alwaysOverwriteExternalMetadata: alwaysOverwriteExternalMetadata
        )
    }

    private func makeOllamaStatusMessage(for capabilities: AppCapabilities) -> String {
        switch capabilities.ollamaAvailability {
        case .notInstalled:
            return "Ollama is not installed. Use the setup card to open the official download page, install Ollama, then click Re-check Setup."
        case .installedNotRunning:
            return "Ollama is installed but not running. The app may start it locally when you run."
        case .installedRunningModelMissing:
            return "Ollama is running, but qwen2.5vl:7b is not installed yet. The app will ask before downloading it."
        case .ready:
            return "Ollama and Qwen 2.5VL 7B are ready."
        case let .failure(reason, _, _):
            return reason
        }
    }

    private func ensurePhotosReadyForWriteRun() async -> Bool {
        let photosRunning = await photosClient.isPhotosAppRunning()
        guard photosRunning else {
            showMessage(
                title: "Photos Must Be Open",
                message: "Photos.app must be open before starting a write run."
            )
            return false
        }
        return true
    }

    private func ensureOllamaInstalledForRunIfNeeded() async -> Bool {
        await refreshCapabilities()

        switch capabilities.ollamaAvailability {
        case .notInstalled:
            let confirmed = await requestConfirmation(
                title: "Install Ollama First?",
                message: "Photos Caption Assistant needs Ollama installed locally before caption runs can start.\n\nThe app does not install third-party software automatically. If you continue, it will open the official Ollama macOS download page in your browser. After installing Ollama, return here and click Re-check Setup.",
                confirmLabel: "Open Download Page",
                cancelLabel: "Cancel"
            )
            guard confirmed else { return false }
            openOllamaDownloadPage()
            return false
        case let .failure(reason, _, _):
            showMessage(title: "Ollama Unavailable", message: reason)
            return false
        case .installedNotRunning, .installedRunningModelMissing, .ready:
            return true
        }
    }

    private func prepareModelForRunIfNeeded() async -> Bool {
        isPreparingModel = true
        let preparation = await ollamaManager.prepareForRun { [weak self] statusMessage in
            Task { @MainActor in
                self?.ollamaStatusMessage = statusMessage
            }
        }
        isPreparingModel = false
        await refreshCapabilities()

        switch preparation.action {
        case .ready:
            ollamaStatusMessage = preparation.message
            return true
        case .downloadRequired:
            ollamaStatusMessage = "Qwen 2.5VL 7B is not installed yet. Confirmation is required before downloading it."
            let confirmed = await requestConfirmation(
                title: "Download Model And Start Run?",
                message: "\(preparation.message)\n\nThe download happens locally through Ollama and may take several minutes.",
                confirmLabel: "Download Model and Start Run",
                cancelLabel: "Cancel"
            )
            guard confirmed else {
                await refreshCapabilities()
                return false
            }

            isPreparingModel = true
            let bootstrap = await ollamaManager.downloadModelAndWarm { [weak self] statusMessage in
                Task { @MainActor in
                    self?.ollamaStatusMessage = statusMessage
                }
            }
            isPreparingModel = false
            await refreshCapabilities()

            guard bootstrap.ready else {
                showMessage(title: "Qwen Model Required", message: bootstrap.message)
                ollamaStatusMessage = makeOllamaStatusMessage(for: capabilities)
                return false
            }

            ollamaStatusMessage = bootstrap.message
            return true
        case .failure:
            showMessage(title: "Ollama Required", message: preparation.message)
            ollamaStatusMessage = makeOllamaStatusMessage(for: capabilities)
            return false
        }
    }

    private func confirmationMessage(for summary: RunPreflightSummary) -> String {
        var lines: [String] = []
        let snapshot = currentRunSetupSnapshot

        lines.append(summary.sourceTitle)

        switch preflightCountState {
        case .loading:
            lines.append("Count: still estimating current scope.")
        case let .exact(count):
            let itemDescription = count == 1 ? "1 item" : "\(count) items"
            if snapshot.useDateFilter, snapshot.sourceSelection != .picker {
                lines.append("Count: \(itemDescription) before capture-date and overwrite checks.")
            } else {
                lines.append("Count: \(itemDescription) before overwrite checks.")
            }
        case let .message(message):
            lines.append("Count: \(message)")
        }

        if let filterDescription = summary.filterDescription {
            lines.append(filterDescription)
        }

        let appOwnedRule = snapshot.overwriteAppOwnedSameOrNewer
            ? "App-owned same/newer metadata will be overwritten."
            : "App-owned same/newer metadata will be preserved."
        let externalRule = snapshot.alwaysOverwriteExternalMetadata
            ? "Non-app metadata will be overwritten without prompts."
            : "Non-app metadata will still ask per item."
        lines.append("Overwrite: \(appOwnedRule) \(externalRule)")

        if !summary.confirmationReasons.isEmpty {
            lines.append("")
            lines.append(contentsOf: summary.confirmationReasons)
        }

        return lines.joined(separator: "\n")
    }

    private func emptyRunMessage(for options: RunOptions) -> String {
        var notes: [String] = []
        notes.append("The run started successfully, but Photos returned no eligible items for the current setup.")

        switch options.source {
        case .library:
            notes.append("Source: Whole Library")
        case let .album(id):
            if let album = albums.first(where: { $0.id == id }) {
                notes.append("Source: Album \"\(album.name)\"")
            } else {
                notes.append("Source: Album (currently unavailable)")
            }
        case let .picker(ids):
            notes.append("Source: Photos Picker (\(ids.count) selected)")
        case .captionWorkflow:
            notes.append("Source: \(AppPresentation.queuedAlbumsTitle)")
        }

        if let dateRange = options.optionalCaptureDateRange {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            notes.append(
                "Capture-date filter: \(formatter.string(from: dateRange.start)) to \(formatter.string(from: dateRange.end))"
            )
            notes.append("Try widening or turning off the capture-date filter, then run again.")
        } else {
            notes.append("Try switching source scope or reloading albums, then run again.")
        }

        return notes.joined(separator: "\n")
    }

    private func persistRunStateIfNeeded(pendingIDs: [String], force: Bool) async {
        guard let persistedRunOptionsForResume else { return }
        let shouldPersist: Bool
        if force || lastPersistedPendingCount == nil {
            shouldPersist = true
        } else {
            let previous = lastPersistedPendingCount ?? 0
            shouldPersist = abs(previous - pendingIDs.count) >= 25 || pendingIDs.count <= 200
        }
        guard shouldPersist else { return }

        let snapshot = PersistedRunState(
            savedAt: Date(),
            options: persistedRunOptionsForResume,
            pendingIDs: pendingIDs
        )
        await runResumeStore.save(snapshot)
        persistedRunState = snapshot
        lastPersistedPendingCount = pendingIDs.count
    }

    private func finalizePersistedRunState() async {
        if latestPendingIDs.isEmpty {
            await runResumeStore.clear()
            persistedRunState = nil
            resumablePendingCount = 0
            lastPersistedPendingCount = nil
            return
        }
        await persistRunStateIfNeeded(pendingIDs: latestPendingIDs, force: true)
    }

    private func loadCaptionWorkflowConfiguration() async {
        let configuration = await captionWorkflowConfigurationStore.load()
        applyCaptionWorkflowConfiguration(configuration)
    }

    func setCaptionWorkflowAlbumSelection(_ albumID: String?, at index: Int) async {
        guard captionWorkflowQueueRows.indices.contains(index) else { return }
        if let albumID,
           let album = albums.first(where: { $0.id == albumID })
        {
            captionWorkflowQueueRows[index].albumID = album.id
            captionWorkflowQueueRows[index].savedAlbumName = album.name
        } else {
            captionWorkflowQueueRows[index].albumID = nil
            captionWorkflowQueueRows[index].savedAlbumName = nil
        }
        await persistCaptionWorkflowConfiguration()
        refreshCaptionWorkflowStatus()
    }

    func addCaptionWorkflowQueueRow() async {
        captionWorkflowQueueRows.append(CaptionWorkflowQueueRowState())
        await persistCaptionWorkflowConfiguration()
        refreshCaptionWorkflowStatus()
    }

    func removeCaptionWorkflowQueueRow(at index: Int) async {
        guard captionWorkflowQueueRows.indices.contains(index) else { return }
        guard captionWorkflowQueueRows.count > CaptionWorkflowConfiguration.minimumQueueLength else { return }
        captionWorkflowQueueRows.remove(at: index)
        captionWorkflowQueueRows = normalizedCaptionWorkflowQueueRows(captionWorkflowQueueRows)
        await persistCaptionWorkflowConfiguration()
        refreshCaptionWorkflowStatus()
    }

    func moveCaptionWorkflowQueueRowUp(from index: Int) async {
        guard captionWorkflowQueueRows.indices.contains(index), index > 0 else { return }
        captionWorkflowQueueRows.swapAt(index, index - 1)
        await persistCaptionWorkflowConfiguration()
        refreshCaptionWorkflowStatus()
    }

    func moveCaptionWorkflowQueueRowDown(from index: Int) async {
        guard captionWorkflowQueueRows.indices.contains(index), index < captionWorkflowQueueRows.count - 1 else { return }
        captionWorkflowQueueRows.swapAt(index, index + 1)
        await persistCaptionWorkflowConfiguration()
        refreshCaptionWorkflowStatus()
    }

    private func applyCaptionWorkflowConfiguration(_ configuration: CaptionWorkflowConfiguration?) {
        captionWorkflowQueueRows = normalizedCaptionWorkflowQueueRows(
            (configuration?.queue ?? []).map(CaptionWorkflowQueueRowState.init(entry:))
        )
        refreshCaptionWorkflowStatus()
    }

    private func reconcileCaptionWorkflowSelections(persistChanges: Bool) async {
        let currentAlbumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        let priorSelections = captionWorkflowQueueRows
        captionWorkflowQueueRows = normalizedCaptionWorkflowQueueRows(
            captionWorkflowQueueRows.map { row in
                guard let albumID = row.albumID else {
                    return row
                }
                guard let album = currentAlbumsByID[albumID] else {
                    return row
                }
                return CaptionWorkflowQueueRowState(
                    id: row.id,
                    albumID: album.id,
                    savedAlbumName: album.name
                )
            }
        )
        refreshCaptionWorkflowStatus()

        if persistChanges, priorSelections != captionWorkflowQueueRows {
            await persistCaptionWorkflowConfiguration()
        }
    }

    private func persistCaptionWorkflowConfiguration() async {
        guard let configuration = makeCaptionWorkflowConfiguration() else {
            await captionWorkflowConfigurationStore.clear()
            return
        }
        await captionWorkflowConfigurationStore.save(configuration)
    }

    private func makeCaptionWorkflowConfiguration() -> CaptionWorkflowConfiguration? {
        let currentAlbumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        let queue = normalizedCaptionWorkflowQueueRows(captionWorkflowQueueRows).map { row in
            if let albumID = row.albumID,
               let album = currentAlbumsByID[albumID]
            {
                return CaptionWorkflowQueueEntry(albumID: album.id, albumName: album.name)
            }
            return row.persistedEntry
        }
        let onlyBlankMinimumRows = queue.count == CaptionWorkflowConfiguration.minimumQueueLength
            && queue.allSatisfy { $0.albumID == nil && $0.albumName == nil }
        if onlyBlankMinimumRows {
            return nil
        }
        return CaptionWorkflowConfiguration(queue: queue)
    }

    private func refreshCaptionWorkflowStatus() {
        let currentAlbumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
        let queueConfiguration = CaptionWorkflowConfiguration(
            queue: normalizedCaptionWorkflowQueueRows(captionWorkflowQueueRows).map(\.persistedEntry)
        )
        let duplicateQueueItems = duplicateCaptionWorkflowQueueItemLabels(configuration: queueConfiguration)

        if !duplicateQueueItems.isEmpty {
            captionWorkflowStatusMessage = "Select a different album for each queue item. Duplicate selections: \(duplicateQueueItems.joined(separator: ", "))."
            return
        }

        let repairDescriptions = captionWorkflowRepairDescriptions(
            configuration: queueConfiguration,
            currentAlbumsByID: currentAlbumsByID
        )
        if !repairDescriptions.isEmpty {
            captionWorkflowStatusMessage = "Needs repair before run: \(repairDescriptions.joined(separator: "; "))."
            return
        }

        captionWorkflowStatusMessage = "\(AppPresentation.queuedAlbumsTitle) is configured with \(queueConfiguration.queue.count) albums."
    }

    private func normalizedCaptionWorkflowQueueRows(
        _ rows: [CaptionWorkflowQueueRowState]
    ) -> [CaptionWorkflowQueueRowState] {
        var normalizedRows = rows
        while normalizedRows.count < CaptionWorkflowConfiguration.minimumQueueLength {
            normalizedRows.append(CaptionWorkflowQueueRowState())
        }
        return normalizedRows
    }

    private func duplicateCaptionWorkflowQueueItemLabels(
        configuration: CaptionWorkflowConfiguration
    ) -> [String] {
        var indicesByAlbumID: [String: [Int]] = [:]
        for (index, entry) in configuration.queue.enumerated() {
            guard let albumID = entry.albumID else {
                continue
            }
            indicesByAlbumID[albumID, default: []].append(index)
        }

        let duplicateIndices = indicesByAlbumID.values
            .filter { $0.count > 1 }
            .flatMap { $0 }
            .sorted()
        return duplicateIndices.map(captionWorkflowQueueItemLabel)
    }

    private func captionWorkflowRepairDescriptions(
        configuration: CaptionWorkflowConfiguration,
        currentAlbumsByID: [String: AlbumSummary]
    ) -> [String] {
        configuration.queue.enumerated().compactMap { index, entry in
            let label = captionWorkflowQueueItemLabel(index)
            guard let albumID = entry.albumID else {
                return "choose an album for \(label)"
            }
            guard let album = currentAlbumsByID[albumID] else {
                let savedAlbumName = entry.albumName ?? "Unknown Album"
                return "repair \(label) (saved selection: \"\(savedAlbumName)\")"
            }
            guard entry.isConfigured else {
                return "repair \(label) (saved selection: \"\(album.name)\")"
            }
            return nil
        }
    }

    private func captionWorkflowQueueItemLabel(_ index: Int) -> String {
        "queue item \(index + 1)"
    }

    private func makeRunOptions() -> RunOptions? {
        let source: ScopeSource
        let captionWorkflowConfiguration: CaptionWorkflowConfiguration?

        switch sourceSelection {
        case .library:
            source = .library
            captionWorkflowConfiguration = nil
        case .album:
            guard let selectedAlbumID, !selectedAlbumID.isEmpty else {
                showMessage(title: "Album Required", message: "Select an album before starting the run.")
                return nil
            }
            source = .album(id: selectedAlbumID)
            captionWorkflowConfiguration = nil
        case .picker:
            guard case .supported = capabilities.pickerCapability else {
                showMessage(title: "Picker Unavailable", message: pickerUnavailableReason)
                return nil
            }
            guard !pickerIDs.isEmpty else {
                showMessage(
                    title: "Picker Selection Required",
                    message: "Select at least one photo or video in picker mode."
                )
                return nil
            }
            source = .picker(ids: pickerIDs)
            captionWorkflowConfiguration = nil
        case .captionWorkflow:
            let currentAlbumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
            let queueConfiguration = CaptionWorkflowConfiguration(
                queue: normalizedCaptionWorkflowQueueRows(captionWorkflowQueueRows).map(\.persistedEntry)
            )

            guard queueConfiguration.queue.count >= CaptionWorkflowConfiguration.minimumQueueLength else {
                showMessage(
                    title: "\(AppPresentation.queuedAlbumsTitle) Needs Repair",
                    message: "\(AppPresentation.queuedAlbumsTitle) needs at least \(CaptionWorkflowConfiguration.minimumQueueLength) queue items."
                )
                return nil
            }

            let repairDescriptions = captionWorkflowRepairDescriptions(
                configuration: queueConfiguration,
                currentAlbumsByID: currentAlbumsByID
            )
            if !repairDescriptions.isEmpty {
                showMessage(
                    title: "\(AppPresentation.queuedAlbumsTitle) Needs Repair",
                    message: "Assign a valid album to each queue item before starting the run: \(repairDescriptions.joined(separator: "; "))."
                )
                return nil
            }

            let duplicateQueueItems = duplicateCaptionWorkflowQueueItemLabels(configuration: queueConfiguration)
            if !duplicateQueueItems.isEmpty {
                showMessage(
                    title: "\(AppPresentation.queuedAlbumsTitle) Needs Repair",
                    message: "Each queue item must point to a different album. Duplicate selections: \(duplicateQueueItems.joined(separator: ", "))."
                )
                return nil
            }

            source = .captionWorkflow
            captionWorkflowConfiguration = queueConfiguration
        }

        let dateRange: CaptureDateRange? = useDateFilter
            ? CaptureDateRange(start: startDate, end: endDate)
            : nil

        return RunOptions(
            source: source,
            optionalCaptureDateRange: dateRange,
            traversalOrder: traversalOrder,
            overwriteAppOwnedSameOrNewer: overwriteAppOwnedSameOrNewer,
            alwaysOverwriteExternalMetadata: alwaysOverwriteExternalMetadata,
            captionWorkflowConfiguration: captionWorkflowConfiguration
        )
    }

    private func requestConflictDecision(asset: MediaAsset, existing: ExistingMetadataState) async -> Bool {
        dismissImmersiveIfNeededForPrompt()
        pendingConflictPrompt = ConflictPromptData(asset: asset, existing: existing)
        return await withCheckedContinuation { continuation in
            conflictContinuation = continuation
        }
    }

    private func requestConfirmation(
        title: String,
        message: String,
        confirmLabel: String,
        cancelLabel: String
    ) async -> Bool {
        dismissImmersiveIfNeededForPrompt()
        activeAlert = .confirmation(
            ConfirmationPrompt(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel
            )
        )
        return await withCheckedContinuation { continuation in
            confirmationContinuation = continuation
        }
    }

    private func showMessage(title: String, message: String) {
        dismissImmersiveIfNeededForPrompt()
        activeAlert = .message(
            MessagePrompt(
                title: title,
                message: message
            )
        )
    }

    private func dismissImmersiveIfNeededForPrompt() {
        if isImmersivePreviewPresented {
            closeImmersivePreview()
        }
    }

    private func revealInFinder(_ url: URL) {
        let targetURL: URL
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: url.path) {
            targetURL = url
        } else {
            targetURL = url.deletingLastPathComponent()
        }

        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
    }

    var pickerSupported: Bool {
        if case .supported = capabilities.pickerCapability {
            return true
        }
        return false
    }

    var pickerUnavailableReason: String {
        if case let .unsupported(reason) = capabilities.pickerCapability {
            return reason
        }
        return "Picker is not available on this setup."
    }

    var canRetryFailedItems: Bool {
        !isRunning && !isPreparingModel && !lastFailedAssetIDs.isEmpty
    }

    var canResumeSavedRun: Bool {
        !isRunning && !isPreparingModel && resumablePendingCount > 0
    }
}

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("main.summaryPaneVisible") private var showsSummaryPane = true
    @SceneStorage("main.compactSummaryExpanded") private var compactSummaryExpanded = true
    @SceneStorage("main.compactProgressExpanded") private var compactProgressExpanded = false
    @State private var window: NSWindow?
    @State private var hasScheduledWindowClamp = false

    var body: some View {
        GeometryReader { geometry in
            let layoutMode = MainWorkbenchLayoutMode(size: geometry.size, showsSummaryPane: showsSummaryPane)

            Group {
                if layoutMode == .compact {
                    compactWorkbench
                } else {
                    wideWorkbench
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(mainBackground.ignoresSafeArea())
        .background(
            WindowReferenceReader { resolvedWindow in
                if window !== resolvedWindow {
                    window = resolvedWindow
                    hasScheduledWindowClamp = false
                }
                scheduleMainWindowClampIfNeeded()
            }
        )
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Reload Setup") {
                    Task {
                        await viewModel.loadInitialData()
                    }
                }
                .disabled(viewModel.isRunning || viewModel.isPreparingModel)

                if viewModel.canResumeSavedRun {
                    Button("Resume") {
                        Task {
                            await viewModel.resumeSavedRun()
                        }
                    }
                }

                if viewModel.canRetryFailedItems {
                    Button("Retry Failed") {
                        Task {
                            await viewModel.retryFailedItems()
                        }
                    }
                }

                Button(viewModel.isRunning ? (viewModel.isCancelRequested ? "Canceling" : "Cancel Run") : "Start Run") {
                    if viewModel.isRunning {
                        viewModel.cancelRun()
                    } else {
                        Task {
                            await viewModel.startRun()
                        }
                    }
                }
                .disabled(viewModel.isRunning ? viewModel.isCancelRequested : !viewModel.canStartRun)
            }

            ToolbarItemGroup(placement: .secondaryAction) {
                Button(showsSummaryPane ? "Hide Summary" : "Show Summary") {
                    showsSummaryPane.toggle()
                }

                Button("Preview") {
                    openPreviewWindow()
                }
                .disabled(!viewModel.canOpenPreviewWindow)
            }
        }
        .task {
            await viewModel.loadInitialData()
        }
        .task(id: viewModel.runPreflightRefreshToken) {
            await viewModel.refreshRunPreflightCount()
        }
        .sheet(item: $viewModel.pendingConflictPrompt) { prompt in
            ConflictPromptView(prompt: prompt) { overwrite in
                viewModel.resolveConflictPrompt(overwrite: overwrite)
            }
        }
        .alert(item: $viewModel.activeAlert) { active in
            switch active {
            case let .confirmation(prompt):
                Alert(
                    title: Text(prompt.title),
                    message: Text(prompt.message),
                    primaryButton: .default(Text(prompt.confirmLabel)) {
                        viewModel.resolveConfirmationPrompt(confirmed: true)
                    },
                    secondaryButton: .cancel(Text(prompt.cancelLabel)) {
                        viewModel.resolveConfirmationPrompt(confirmed: false)
                    }
                )
            case let .message(prompt):
                Alert(
                    title: Text(prompt.title),
                    message: Text(prompt.message),
                    dismissButton: .default(Text("OK")) {
                        viewModel.clearMessagePrompt()
                    }
                )
            }
        }
    }

    private var wideWorkbench: some View {
        VStack(spacing: 0) {
            statusOverview(compactLayout: false)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

            HSplitView {
                ScrollView {
                    setupWorkbenchContent(compactLayout: false)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(minWidth: 620, idealWidth: 760, maxWidth: .infinity)

                if showsSummaryPane {
                    ScrollView {
                        summaryWorkbenchContent(compactLayout: false, showsCards: true)
                            .padding(.trailing, 18)
                            .padding(.bottom, 18)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minWidth: 320, idealWidth: 390, maxWidth: 480)
                }
            }
        }
    }

    private var compactWorkbench: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusOverview(compactLayout: true)

                setupWorkbenchContent(compactLayout: true)

                if showsSummaryPane {
                    compactSummarySections
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func setupWorkbenchContent(compactLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: compactLayout ? 12 : 14) {
            if viewModel.shouldShowOllamaSetupCard {
                OllamaSetupCardView(
                    isBusy: viewModel.isRunning || viewModel.isPreparingModel,
                    compactLayout: compactLayout,
                    onOpenDownloadPage: {
                        Task {
                            await viewModel.confirmAndOpenOllamaDownloadPage()
                        }
                    },
                    onRecheckSetup: {
                        Task {
                            await viewModel.recheckOllamaSetup()
                        }
                    }
                )
            }

            RunSetupView(
                sourceSelection: $viewModel.sourceSelection,
                selectedAlbumID: $viewModel.selectedAlbumID,
                albums: viewModel.albums,
                albumLoadState: viewModel.albumLoadState,
                captionWorkflowQueueRows: viewModel.captionWorkflowQueueRows,
                captionWorkflowStatusMessage: viewModel.captionWorkflowStatusMessage,
                useDateFilter: $viewModel.useDateFilter,
                startDate: $viewModel.startDate,
                endDate: $viewModel.endDate,
                traversalOrder: $viewModel.traversalOrder,
                overwriteAppOwnedSameOrNewer: $viewModel.overwriteAppOwnedSameOrNewer,
                alwaysOverwriteExternalMetadata: $viewModel.alwaysOverwriteExternalMetadata,
                pickerSupported: viewModel.pickerSupported,
                pickerUnsupportedReason: viewModel.pickerUnavailableReason,
                pickerIDs: $viewModel.pickerIDs,
                onCaptionWorkflowAlbumSelectionChanged: { index, albumID in
                    Task {
                        await viewModel.setCaptionWorkflowAlbumSelection(albumID, at: index)
                    }
                },
                onAddCaptionWorkflowQueueRow: {
                    Task {
                        await viewModel.addCaptionWorkflowQueueRow()
                    }
                },
                onRemoveCaptionWorkflowQueueRow: { index in
                    Task {
                        await viewModel.removeCaptionWorkflowQueueRow(at: index)
                    }
                },
                onMoveCaptionWorkflowQueueRowUp: { index in
                    Task {
                        await viewModel.moveCaptionWorkflowQueueRowUp(from: index)
                    }
                },
                onMoveCaptionWorkflowQueueRowDown: { index in
                    Task {
                        await viewModel.moveCaptionWorkflowQueueRowDown(from: index)
                    }
                },
                compactLayout: compactLayout
            )
        }
    }

    private func summaryWorkbenchContent(compactLayout: Bool, showsCards: Bool) -> some View {
        VStack(alignment: .leading, spacing: compactLayout ? 12 : 14) {
            RunPreflightPanelView(
                summary: viewModel.runPreflightSummary,
                compactLayout: compactLayout,
                showsCard: showsCards
            )

            ProcessingProgressView(
                progress: viewModel.progress,
                performance: viewModel.performance,
                isRunning: viewModel.isRunning,
                isOpeningImmersivePreview: viewModel.isOpeningImmersivePreview,
                statusMessage: viewModel.runStatusMessage,
                summary: viewModel.lastSummary,
                liveErrors: viewModel.recentRunErrors,
                lastCompletedItemPreview: viewModel.lastCompletedItemPreview,
                compactLayout: compactLayout,
                showsCard: showsCards,
                onOpenImmersivePreview: viewModel.canOpenPreviewWindow ? {
                    openPreviewWindow()
                } : nil
            )
        }
    }

    private var compactSummarySections: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkbenchCard(
                title: "Run Summary",
                subtitle: "Current scope, filters, overwrite behavior, and start warnings.",
                compact: true
            ) {
                DisclosureGroup(isExpanded: $compactSummaryExpanded) {
                    RunPreflightPanelView(
                        summary: viewModel.runPreflightSummary,
                        compactLayout: true,
                        showsCard: false
                    )
                    .padding(.top, 8)
                } label: {
                    Text("Show the current scope and confirmation warnings before you start.")
                        .font(.footnote)
                        .foregroundStyle(WorkbenchPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            WorkbenchCard(
                title: "Progress & Preview",
                subtitle: "Latest completed item, run progress, and recent errors.",
                compact: true
            ) {
                DisclosureGroup(isExpanded: $compactProgressExpanded) {
                    ProcessingProgressView(
                        progress: viewModel.progress,
                        performance: viewModel.performance,
                        isRunning: viewModel.isRunning,
                        isOpeningImmersivePreview: viewModel.isOpeningImmersivePreview,
                        statusMessage: viewModel.runStatusMessage,
                        summary: viewModel.lastSummary,
                        liveErrors: viewModel.recentRunErrors,
                        lastCompletedItemPreview: viewModel.lastCompletedItemPreview,
                        compactLayout: true,
                        showsCard: false,
                        onOpenImmersivePreview: viewModel.canOpenPreviewWindow ? {
                            openPreviewWindow()
                        } : nil
                    )
                    .padding(.top, 8)
                } label: {
                    Text("Show the latest completed item, progress, and diagnostics in this smaller layout.")
                        .font(.footnote)
                        .foregroundStyle(WorkbenchPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var mainBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func scheduleMainWindowClampIfNeeded() {
        guard let window else { return }
        guard !hasScheduledWindowClamp else {
            clampMainWindowFrame(window)
            return
        }

        hasScheduledWindowClamp = true
        clampMainWindowFrame(window)

        DispatchQueue.main.async {
            clampMainWindowFrame(window)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            clampMainWindowFrame(window)
        }
    }

    private func clampMainWindowFrame(_ window: NSWindow) {
        if window.minSize != MainWorkbenchWindowLayout.minimumSize {
            window.minSize = MainWorkbenchWindowLayout.minimumSize
        }

        guard let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        else {
            return
        }

        let fittedFrame = MainWorkbenchWindowLayout.fittedFrame(for: window.frame, in: visibleFrame)
        guard fittedFrame != window.frame else { return }

        window.setFrame(fittedFrame, display: true, animate: false)
    }

    private func statusOverview(compactLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: compactLayout ? 10 : 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: compactLayout ? 12 : 16) {
                    titleBlock(compactLayout: compactLayout)
                    Spacer(minLength: 0)
                    capabilityBadgeGrid(compactLayout: compactLayout)
                }

                VStack(alignment: .leading, spacing: compactLayout ? 10 : 12) {
                    titleBlock(compactLayout: compactLayout)
                    capabilityBadgeGrid(compactLayout: compactLayout)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    detailBadge(VersionDisplay.appVersionLine, compactLayout: compactLayout)
                    detailBadge(VersionDisplay.logicVersionLine, compactLayout: compactLayout)
                }

                VStack(alignment: .leading, spacing: 6) {
                    detailBadge(VersionDisplay.appVersionLine, compactLayout: compactLayout)
                    detailBadge(VersionDisplay.logicVersionLine, compactLayout: compactLayout)
                }
            }

            VStack(alignment: .leading, spacing: compactLayout ? 4 : 6) {
                statusLine(text: viewModel.ollamaStatusMessage, isBusy: viewModel.isPreparingModel)

                if let benchmarkStatusMessage = viewModel.benchmarkStatusMessage {
                    statusLine(text: benchmarkStatusMessage, isBusy: viewModel.isRunningScanBenchmark)
                }

                if let identityProbeStatusMessage = viewModel.identityProbeStatusMessage {
                    statusLine(text: identityProbeStatusMessage, isBusy: viewModel.isRunningIdentityWriteProbe)
                }

                if let runStatusMessage = viewModel.runStatusMessage, viewModel.isRunning {
                    statusLine(text: runStatusMessage, isBusy: true)
                }
            }
        }
        .padding(compactLayout ? 16 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: compactLayout ? 18 : 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compactLayout ? 18 : 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func titleBlock(compactLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: compactLayout ? 4 : 6) {
            Text(AppPresentation.appName)
                .font((compactLayout ? Font.title2 : .largeTitle).weight(.bold))

            Text("Local-first captions and keywords for Apple Photos, with separate Mac windows for setup, diagnostics, storage, and preview.")
                .font(compactLayout ? .footnote : .callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func capabilityBadgeGrid(compactLayout: Bool) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: compactLayout ? 128 : 150), spacing: 8)],
            alignment: .trailing,
            spacing: 8
        ) {
            capabilityBadge("Automation", available: viewModel.capabilities.photosAutomationAvailable, compactLayout: compactLayout)
            capabilityBadge("Qwen 2.5VL 7B", available: viewModel.capabilities.qwenModelAvailable, compactLayout: compactLayout)
            capabilityBadge("Picker", available: viewModel.pickerSupported, compactLayout: compactLayout)
        }
        .frame(maxWidth: compactLayout ? .infinity : 460, alignment: .trailing)
    }

    @ViewBuilder
    private func capabilityBadge(_ title: String, available: Bool, compactLayout: Bool) -> some View {
        Text("\(title): \(available ? "Available" : "Unavailable")")
            .font(.caption.weight(.semibold))
            .foregroundStyle(available ? Color.accentColor : .orange)
            .padding(.horizontal, compactLayout ? 10 : 12)
            .padding(.vertical, compactLayout ? 5 : 6)
            .background(available ? Color.accentColor.opacity(0.12) : Color.orange.opacity(0.18))
            .clipShape(Capsule())
    }

    private func detailBadge(_ text: String, compactLayout: Bool) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, compactLayout ? 8 : 10)
            .padding(.vertical, compactLayout ? 5 : 6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(Capsule())
    }

    private func statusLine(text: String, isBusy: Bool) -> some View {
        HStack(spacing: 8) {
            if isBusy {
                SwiftUI.ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openPreviewWindow() {
        viewModel.openImmersivePreview()
        openWindow(id: AppSceneID.preview)
    }
}

private enum MainWorkbenchLayoutMode {
    case wide
    case compact

    init(size: CGSize, showsSummaryPane: Bool) {
        let compactForHeight = size.height < 660
        let compactForWidth = showsSummaryPane ? size.width < 1200 : size.width < 980
        self = (compactForHeight || compactForWidth) ? .compact : .wide
    }
}

struct DiagnosticCommands: Commands {
    @ObservedObject var viewModel: AppViewModel

    var body: some Commands {
        CommandMenu("Diagnostics") {
            Button(viewModel.isRunningScanBenchmark ? "Running Scan Benchmark..." : "Run Scan Benchmark") {
                Task {
                    await viewModel.runScanBenchmarkFromMenu()
                }
            }
            .disabled(viewModel.isRunning || viewModel.isPreparingModel || viewModel.isRunningScanBenchmark || viewModel.isRunningIdentityWriteProbe)

            Button(viewModel.isRunningIdentityWriteProbe ? "Running Identity Write Probe..." : "Run Identity Write Probe") {
                Task {
                    await viewModel.runIdentityWriteProbeFromMenu()
                }
            }
            .disabled(viewModel.isRunning || viewModel.isPreparingModel || viewModel.isRunningScanBenchmark || viewModel.isRunningIdentityWriteProbe)

            Button("Use Latest Benchmark IDs For Write Probe") {
                viewModel.prefillIdentityProbeFromLatestBenchmark()
            }
            .disabled(viewModel.isRunning || viewModel.isPreparingModel || viewModel.isRunningScanBenchmark || viewModel.isRunningIdentityWriteProbe)
        }
    }
}
