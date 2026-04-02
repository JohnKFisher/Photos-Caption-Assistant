import AppKit
import Photos
import SwiftUI

private enum VersionDisplay {
    static var appVersionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let marketing = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return "App v\(marketing) (build \(build))"
    }

    static var logicVersionLine: String {
        let logic = LogicVersion.current
        return "DescriptionLogic v\(logic.major).\(logic.minor).\(logic.patch)"
    }
}

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
    static let regularDisplaySeconds: TimeInterval = 30
    static let catchUpDisplaySeconds: TimeInterval = 10
    static let catchUpThreshold = 20
    static let emergencySamplingThreshold = 60
    static let sampledRetainedPreviewCount = 30

    static func displaySeconds(for backlogCount: Int) -> TimeInterval {
        backlogCount > catchUpThreshold
            ? catchUpDisplaySeconds
            : regularDisplaySeconds
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
    private struct ImmersivePreviewQueue {
        private var storage: [CompletedItemPreview] = []
        private var headIndex = 0

        var count: Int {
            storage.count - headIndex
        }

        var isEmpty: Bool {
            count == 0
        }

        var previews: [CompletedItemPreview] {
            guard headIndex < storage.count else { return [] }
            return Array(storage[headIndex...])
        }

        var previewFileURLs: [URL] {
            previews.compactMap(\.previewFileURL)
        }

        mutating func append(_ preview: CompletedItemPreview) {
            storage.append(preview)
        }

        mutating func popFirst() -> CompletedItemPreview? {
            guard headIndex < storage.count else { return nil }
            let preview = storage[headIndex]
            headIndex += 1

            if headIndex >= 32 && headIndex * 2 >= storage.count {
                storage.removeFirst(headIndex)
                headIndex = 0
            }

            return preview
        }

        @discardableResult
        mutating func sampleDown(toRetainedCount retainedCount: Int) -> [CompletedItemPreview] {
            let activePreviews = previews
            let retainedIndices = Set(
                ImmersivePreviewPolicy.retainedIndices(
                    for: activePreviews.count,
                    targetRetainedCount: retainedCount
                )
            )
            guard retainedIndices.count < activePreviews.count else {
                return []
            }

            var kept: [CompletedItemPreview] = []
            var dropped: [CompletedItemPreview] = []
            kept.reserveCapacity(retainedIndices.count)
            dropped.reserveCapacity(activePreviews.count - retainedIndices.count)

            for (index, preview) in activePreviews.enumerated() {
                if retainedIndices.contains(index) {
                    kept.append(preview)
                } else {
                    dropped.append(preview)
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
    }

    private static let previewDirectoryName = "PhotoDescriptionCreatorLastCompleted"

    @Published var capabilities = AppCapabilities(
        photosAutomationAvailable: false,
        qwenModelAvailable: false,
        pickerCapability: .unsupported(reason: "Capabilities not loaded yet.")
    )

    @Published var sourceSelection: SourceSelection = .library
    @Published var selectedAlbumID: String?
    @Published var pickerIDs: [String] = []
    @Published var albums: [AlbumSummary] = []
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
    @Published var traversalOrder: RunTraversalOrder = .photosOrderFast

    @Published var overwriteAppOwnedSameOrNewer = false
    @Published var alwaysOverwriteExternalMetadata = true

    @Published var isRunning = false
    @Published var isCancelRequested = false
    @Published var isPreparingModel = false
    @Published var progress = RunProgress()
    @Published var performance = RunPerformanceStats()
    @Published var runStatusMessage: String?
    @Published var lastSummary: RunSummary?
    @Published var lastCompletedItemPreview: CompletedItemPreview?
    @Published var immersiveDisplayedItemPreview: CompletedItemPreview?
    @Published var recentRunErrors: [String] = []
    @Published var isImmersivePreviewPresented = false
    @Published var ollamaStatusMessage = "Checking Qwen 2.5VL 7B availability..."
    @Published var benchmarkStatusMessage: String?
    @Published var identityProbeStatusMessage: String?
    @Published var resumablePendingCount = 0

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
    private var retainedPreviewFileURLs: Set<URL> = []
    private var lastScanBenchmarkReport: PhotoKitScanBenchmarkReport?

    private let photosClient = PhotosAppleScriptClient()
    private let photoKitIncrementalScanSource = ExperimentalPhotoKitScanReader()
    private let ollamaManager = OllamaManager()
    private let runResumeStore = RunResumeStore()
    private let captionWorkflowConfigurationStore = CaptionWorkflowConfigurationStore()
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

    func loadInitialData() async {
        capabilities = await capabilityProbe.probe()
        if capabilities.photosAutomationAvailable {
            hasShownStartupAutomationAlert = false
        } else if !hasShownStartupAutomationAlert {
            hasShownStartupAutomationAlert = true
            showMessage(
                title: "Automation Permission Needed",
                message: "Photos automation is not available yet. Grant Apple Events permission now so caption updates and automatic Photos restarts can run unattended later."
            )
        }
        ollamaStatusMessage = capabilities.qwenModelAvailable
            ? "Qwen 2.5VL 7B is ready."
            : "Qwen 2.5VL 7B not ready. The app will start/install it when you run."
        await loadCaptionWorkflowConfiguration()
        await refreshAlbums()
        await loadPersistedRunState()
    }

    func refreshAlbums() async {
        do {
            let listedAlbums = try await photosClient.listUserAlbums()
            albums = await photoKitIncrementalScanSource.withResolvedPlainAlbumCounts(listedAlbums)
            await reconcileCaptionWorkflowSelections(persistChanges: true)
        } catch {
            showMessage(title: "Album Load Failed", message: error.localizedDescription)
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

        let restoredBaseOptions = persistedRunState.options.toRunOptions()
        let resumeOptions = RunOptions(
            source: .picker(ids: persistedRunState.pendingIDs),
            optionalCaptureDateRange: nil,
            traversalOrder: restoredBaseOptions.traversalOrder,
            overwriteAppOwnedSameOrNewer: restoredBaseOptions.overwriteAppOwnedSameOrNewer,
            alwaysOverwriteExternalMetadata: restoredBaseOptions.alwaysOverwriteExternalMetadata
        )
        await run(options: resumeOptions, persistedOptionsOverride: persistedRunState.options)
    }

    private func run(options: RunOptions, persistedOptionsOverride: PersistedRunOptions? = nil) async {
        isPreparingModel = true
        let bootstrap = await ollamaManager.ensureModelReady { [weak self] statusMessage in
            Task { @MainActor in
                self?.ollamaStatusMessage = statusMessage
            }
        }
        isPreparingModel = false
        capabilities = await capabilityProbe.probe()

        guard bootstrap.ready else {
            showMessage(title: "Qwen Model Required", message: bootstrap.message)
            return
        }
        ollamaStatusMessage = bootstrap.message

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
                    self?.handleCompletedItemPreview(preview)
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
                message: "Run the scan benchmark first, then use the sampled IDs listed in the Diagnostics section."
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
                message: "Enter a sacrificial asset ID and a different control asset ID in the Diagnostics section before running the write probe."
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

    fileprivate var benchmarkSampleIDsText: String? {
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
        immersiveDisplayedItemPreview = lastCompletedItemPreview
        queuedImmersivePreviews.removeAll()
        immersiveLastPreviewPresentedAt = immersiveDisplayedItemPreview == nil ? nil : Date()
        synchronizeRetainedPreviewFiles()
        isImmersivePreviewPresented = true
    }

    func handleImmersivePresentationChange(_ isPresented: Bool) {
        if isPresented {
            scheduleImmersivePreviewAdvanceIfNeeded()
        } else {
            immersivePreviewTask?.cancel()
            immersivePreviewTask = nil
            queuedImmersivePreviews.removeAll()
            immersiveDisplayedItemPreview = nil
            immersiveLastPreviewPresentedAt = nil
            synchronizeRetainedPreviewFiles()
        }
    }

    private func handleCompletedItemPreview(_ preview: CompletedItemPreview) {
        lastCompletedItemPreview = preview

        guard isImmersivePreviewPresented else {
            immersiveDisplayedItemPreview = nil
            immersiveLastPreviewPresentedAt = nil
            synchronizeRetainedPreviewFiles()
            return
        }

        if immersiveDisplayedItemPreview == nil {
            immersiveDisplayedItemPreview = preview
            immersiveLastPreviewPresentedAt = Date()
            synchronizeRetainedPreviewFiles()
            return
        }

        queuedImmersivePreviews.append(preview)
        if queuedImmersivePreviews.count > ImmersivePreviewPolicy.emergencySamplingThreshold {
            queuedImmersivePreviews.sampleDown(
                toRetainedCount: ImmersivePreviewPolicy.sampledRetainedPreviewCount
            )
        }
        synchronizeRetainedPreviewFiles()
        scheduleImmersivePreviewAdvanceIfNeeded()
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
                    let targetDelay = ImmersivePreviewPolicy.displaySeconds(
                        for: self.queuedImmersivePreviews.count
                    )
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
                guard let nextPreview = self.queuedImmersivePreviews.popFirst() else { break }
                self.immersiveDisplayedItemPreview = nextPreview
                self.immersiveLastPreviewPresentedAt = Date()
                self.synchronizeRetainedPreviewFiles()
            }

            self.immersivePreviewTask = nil
            if self.isImmersivePreviewPresented, !self.queuedImmersivePreviews.isEmpty {
                self.scheduleImmersivePreviewAdvanceIfNeeded()
            }
        }
    }

    private func resetImmersivePreviewState() {
        immersivePreviewTask?.cancel()
        immersivePreviewTask = nil
        immersiveDisplayedItemPreview = nil
        queuedImmersivePreviews.removeAll()
        immersiveLastPreviewPresentedAt = nil
        synchronizeRetainedPreviewFiles()
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
        guard fileURL.deletingLastPathComponent().lastPathComponent == previewDirectoryName else {
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

    private func loadPersistedRunState() async {
        let loaded = await runResumeStore.load()
        persistedRunState = loaded
        resumablePendingCount = loaded?.pendingIDs.count ?? 0
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

        captionWorkflowStatusMessage = "Caption Workflow queue is configured with \(queueConfiguration.queue.count) albums."
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
                    title: "Caption Workflow Needs Repair",
                    message: "Caption Workflow needs at least \(CaptionWorkflowConfiguration.minimumQueueLength) queue items."
                )
                return nil
            }

            let repairDescriptions = captionWorkflowRepairDescriptions(
                configuration: queueConfiguration,
                currentAlbumsByID: currentAlbumsByID
            )
            if !repairDescriptions.isEmpty {
                showMessage(
                    title: "Caption Workflow Needs Repair",
                    message: "Assign a valid album to each queue item before starting the run: \(repairDescriptions.joined(separator: "; "))."
                )
                return nil
            }

            let duplicateQueueItems = duplicateCaptionWorkflowQueueItemLabels(configuration: queueConfiguration)
            if !duplicateQueueItems.isEmpty {
                showMessage(
                    title: "Caption Workflow Needs Repair",
                    message: "Each caption workflow queue item must point to a different album. Duplicate selections: \(duplicateQueueItems.joined(separator: ", "))."
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
            isImmersivePreviewPresented = false
        }
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
    @State private var immersiveAutoEnteredFullScreen = false
    @State private var isDiagnosticsExpanded = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                header

                RunSetupView(
                    sourceSelection: $viewModel.sourceSelection,
                    selectedAlbumID: $viewModel.selectedAlbumID,
                    albums: viewModel.albums,
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
                    }
                )
                .frame(maxHeight: 330)

                diagnosticsConfigurationView

                ProcessingProgressView(
                    progress: viewModel.progress,
                    performance: viewModel.performance,
                    isRunning: viewModel.isRunning,
                    statusMessage: viewModel.runStatusMessage,
                    summary: viewModel.lastSummary,
                    liveErrors: viewModel.recentRunErrors,
                    lastCompletedItemPreview: viewModel.lastCompletedItemPreview,
                    onOpenImmersivePreview: {
                        viewModel.openImmersivePreview()
                    }
                )

                HStack {
                    Button("Reload Capabilities") {
                        Task {
                            await viewModel.loadInitialData()
                        }
                    }

                    Spacer()

                    if viewModel.isRunning {
                        Button(viewModel.isCancelRequested ? "Canceling" : "Cancel Run") {
                            viewModel.cancelRun()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isCancelRequested)
                    } else {
                        if viewModel.canResumeSavedRun {
                            Button("Resume Previous Run (\(viewModel.resumablePendingCount) pending)") {
                                Task {
                                    await viewModel.resumeSavedRun()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isPreparingModel)
                        }

                        if viewModel.canRetryFailedItems {
                            Button("Retry Failed Items") {
                                Task {
                                    await viewModel.retryFailedItems()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isPreparingModel)
                        }

                        Button("Start Run") {
                            Task {
                                await viewModel.startRun()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isPreparingModel)
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 900, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(!viewModel.isImmersivePreviewPresented)
            .environment(\.controlActiveState, viewModel.isImmersivePreviewPresented ? .inactive : .key)
            .zIndex(0)

            if viewModel.isImmersivePreviewPresented {
                ImmersivePreviewView(
                    preview: viewModel.immersiveDisplayedItemPreview,
                    progress: viewModel.progress,
                    performance: viewModel.performance,
                    isRunning: viewModel.isRunning,
                    isPresented: $viewModel.isImmersivePreviewPresented
                )
                .transition(.opacity)
                .zIndex(5)
            }
        }
        .task {
            await viewModel.loadInitialData()
        }
        .onChange(of: viewModel.isImmersivePreviewPresented) { _, isPresented in
            viewModel.handleImmersivePresentationChange(isPresented)
            handleImmersivePresentationChange(isPresented)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo Description Creator")
                .font(.largeTitle.bold())

            HStack(spacing: 12) {
                Text(VersionDisplay.appVersionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(VersionDisplay.logicVersionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                capabilityBadge("Automation", available: viewModel.capabilities.photosAutomationAvailable)
                capabilityBadge("Qwen 2.5VL 7B", available: viewModel.capabilities.qwenModelAvailable)
                capabilityBadge("Picker", available: viewModel.pickerSupported)
            }

            HStack(spacing: 8) {
                if viewModel.isPreparingModel {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.ollamaStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let benchmarkStatusMessage = viewModel.benchmarkStatusMessage {
                HStack(spacing: 8) {
                    if viewModel.isRunningScanBenchmark {
                        SwiftUI.ProgressView()
                            .controlSize(.small)
                    }
                    Text(benchmarkStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let identityProbeStatusMessage = viewModel.identityProbeStatusMessage {
                HStack(spacing: 8) {
                    if viewModel.isRunningIdentityWriteProbe {
                        SwiftUI.ProgressView()
                            .controlSize(.small)
                    }
                    Text(identityProbeStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var diagnosticsConfigurationView: some View {
        GroupBox {
            DisclosureGroup("Diagnostics", isExpanded: $isDiagnosticsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Benchmark album override is optional. The identity write probe needs explicit sacrificial/control asset IDs and will prompt before writing anything.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Benchmark Album ID")
                                .font(.caption.weight(.semibold))
                            TextField("Optional AppleScript album ID", text: $viewModel.benchmarkAlbumOverrideID)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Benchmark Album Name")
                                .font(.caption.weight(.semibold))
                            TextField("Optional album label", text: $viewModel.benchmarkAlbumOverrideName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sacrificial Asset ID")
                                .font(.caption.weight(.semibold))
                            TextField("Required for write probe", text: $viewModel.identityProbeSacrificialAssetID)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Control Asset ID")
                                .font(.caption.weight(.semibold))
                            TextField("Required for write probe", text: $viewModel.identityProbeControlAssetID)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Smart Album ID")
                                .font(.caption.weight(.semibold))
                            TextField("Optional expected-removal smart album", text: $viewModel.identityProbeSmartAlbumID)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Smart Album Name")
                                .font(.caption.weight(.semibold))
                            TextField("Optional label", text: $viewModel.identityProbeSmartAlbumName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let benchmarkSampleIDsText = viewModel.benchmarkSampleIDsText {
                        HStack {
                            Text("Latest Benchmark Sample IDs")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Use First Two For Write Probe") {
                                viewModel.prefillIdentityProbeFromLatestBenchmark()
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isRunningScanBenchmark || viewModel.isRunningIdentityWriteProbe)
                        }

                        ScrollView {
                            Text(benchmarkSampleIDsText)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 120, maxHeight: 180)
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("Run the scan benchmark once and the latest sampled IDs will appear here for copy/paste.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)
            }
            .animation(.default, value: isDiagnosticsExpanded)
        }
    }

    @ViewBuilder
    private func capabilityBadge(_ title: String, available: Bool) -> some View {
        Text("\(title): \(available ? "Available" : "Unavailable")")
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(available ? Color.green.opacity(0.18) : Color.orange.opacity(0.2))
            .clipShape(Capsule())
    }

    private func handleImmersivePresentationChange(_ isPresented: Bool) {
        guard let window = currentWindow() else { return }

        if isPresented {
            window.makeFirstResponder(nil)
            if !window.styleMask.contains(.fullScreen) {
                immersiveAutoEnteredFullScreen = true
                window.toggleFullScreen(nil)
            } else {
                immersiveAutoEnteredFullScreen = false
            }
            return
        }

        guard immersiveAutoEnteredFullScreen else { return }
        immersiveAutoEnteredFullScreen = false

        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    private func currentWindow() -> NSWindow? {
        if let key = NSApp.keyWindow {
            return key
        }
        if let main = NSApp.mainWindow {
            return main
        }
        return NSApp.windows.first(where: { $0.isVisible })
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
