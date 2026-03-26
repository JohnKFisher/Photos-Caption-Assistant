import AppKit
import AVFoundation
import CoreGraphics
import Foundation

public struct RunSafetyPausePrompt: Sendable, Equatable {
    public let title: String
    public let message: String
    public let confirmLabel: String
    public let cancelLabel: String

    public init(title: String, message: String, confirmLabel: String, cancelLabel: String) {
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
    }
}

public struct RunCallbacks {
    public var onProgress: (RunProgress) -> Void
    public var onPreparationProgress: (Int, Int) -> Void
    public var onStatusChanged: (String?) -> Void
    public var onItemCompleted: (CompletedItemPreview) -> Void
    public var onPendingIDsUpdated: ([String]) -> Void
    public var onError: (String) -> Void
    public var confirmExternalOverwrite: (MediaAsset, ExistingMetadataState) async -> Bool
    public var confirmContinueAfterCheckpoint: (Int) async -> Bool
    public var confirmSafetyPause: (RunSafetyPausePrompt) async -> Bool

    public init(
        onProgress: @escaping (RunProgress) -> Void = { _ in },
        onPreparationProgress: @escaping (Int, Int) -> Void = { _, _ in },
        onStatusChanged: @escaping (String?) -> Void = { _ in },
        onItemCompleted: @escaping (CompletedItemPreview) -> Void = { _ in },
        onPendingIDsUpdated: @escaping ([String]) -> Void = { _ in },
        onError: @escaping (String) -> Void = { _ in },
        confirmExternalOverwrite: @escaping (MediaAsset, ExistingMetadataState) async -> Bool = { _, _ in false },
        confirmContinueAfterCheckpoint: @escaping (Int) async -> Bool = { _ in true },
        confirmSafetyPause: @escaping (RunSafetyPausePrompt) async -> Bool = { _ in true }
    ) {
        self.onProgress = onProgress
        self.onPreparationProgress = onPreparationProgress
        self.onStatusChanged = onStatusChanged
        self.onItemCompleted = onItemCompleted
        self.onPendingIDsUpdated = onPendingIDsUpdated
        self.onError = onError
        self.confirmExternalOverwrite = confirmExternalOverwrite
        self.confirmContinueAfterCheckpoint = confirmContinueAfterCheckpoint
        self.confirmSafetyPause = confirmSafetyPause
    }
}

private enum RunTimingStage: String, CaseIterable, Hashable, Sendable {
    case metadataRead = "metadata-read"
    case assetAcquire = "asset-acquire"
    case analysisPrepare = "analysis-prepare"
    case analyze = "analyze"
    case write = "write"
    case preview = "preview"
}

private enum CaptionWorkflowRunError: LocalizedError {
    case albumListingUnavailable
    case incompleteConfiguration([String])
    case duplicateConfiguredAlbums([String])
    case missingConfiguredAlbum(queueItem: Int, savedAlbumName: String)
    case noEligibleItems(filtered: Bool, albumNames: [String])

    var errorDescription: String? {
        switch self {
        case .albumListingUnavailable:
            return "Caption Workflow requires a Photos client that can list user albums."
        case let .incompleteConfiguration(queueItems):
            return "Caption Workflow is missing configured albums for: \(queueItems.joined(separator: ", ")). Repair the queue before starting the run."
        case let .duplicateConfiguredAlbums(queueItems):
            return "Caption Workflow queue items must use different albums. Duplicate selections were found for: \(queueItems.joined(separator: ", "))."
        case let .missingConfiguredAlbum(queueItem, savedAlbumName):
            return "Caption Workflow could not find the configured album for queue item \(queueItem). Saved selection: \"\(savedAlbumName)\". Repair the queue before starting the run."
        case let .noEligibleItems(filtered, albumNames):
            let scopeText = filtered ? " after the current capture-date filter" : ""
            let albumList = albumNames.joined(separator: "\", \"")
            return "Caption Workflow found no eligible items\(scopeText) in \"\(albumList)\"."
        }
    }
}

private actor RunTimingRecorder {
    private var totals: [RunTimingStage: UInt64] = [:]

    func record(stage: RunTimingStage, nanoseconds: UInt64) {
        guard nanoseconds > 0 else { return }
        totals[stage, default: 0] += nanoseconds
    }

    func summary(totalWallNanoseconds: UInt64) -> String {
        let wallSeconds = Double(totalWallNanoseconds) / 1_000_000_000
        let entries = RunTimingStage.allCases.map { stage -> String in
            let elapsedNs = totals[stage, default: 0]
            let elapsedSeconds = Double(elapsedNs) / 1_000_000_000
            let pct = totalWallNanoseconds > 0
                ? (Double(elapsedNs) / Double(totalWallNanoseconds)) * 100.0
                : 0.0
            let pctText = String(format: "%.1f", pct)
            return "\(stage.rawValue)=\(Self.formatSeconds(elapsedSeconds))s (\(pctText)%)"
        }
        return "[RunCoordinator] stage timings wall=\(Self.formatSeconds(wallSeconds))s " + entries.joined(separator: ", ")
    }

    func diagnostics(
        totalWallNanoseconds: UInt64,
        analysisConcurrency: Int,
        prepareAheadLimit: Int,
        writeBatchSize: Int
    ) -> RunDiagnostics {
        let stageTimings = RunTimingStage.allCases.map { stage in
            RunStageTiming(
                stage: stage.rawValue,
                elapsedSeconds: Double(totals[stage, default: 0]) / 1_000_000_000
            )
        }
        return RunDiagnostics(
            wallSeconds: Double(totalWallNanoseconds) / 1_000_000_000,
            analysisConcurrency: analysisConcurrency,
            prepareAheadLimit: prepareAheadLimit,
            writeBatchSize: writeBatchSize,
            stageTimings: stageTimings
        )
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

protocol PreviewRendering: Sendable {
    func persistPreviewFile(
        from input: AnalysisInput,
        assetID: String,
        fallbackFilename: String,
        kind: MediaKind
    ) async -> URL?
}

actor DefaultPreviewRenderer: PreviewRendering {
    private let videoFrameSampler: VideoFrameSampler

    init(videoFrameSampler: VideoFrameSampler) {
        self.videoFrameSampler = videoFrameSampler
    }

    func persistPreviewFile(
        from input: AnalysisInput,
        assetID _: String,
        fallbackFilename: String,
        kind: MediaKind
    ) async -> URL? {
        let fileManager = FileManager.default
        let previewRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoDescriptionCreatorLastCompleted", isDirectory: true)

        do {
            try fileManager.createDirectory(at: previewRoot, withIntermediateDirectories: true)

            switch input {
            case let .fileURL(inputURL):
                if kind == .video,
                   let extractedFrameDestination = await persistVideoPreviewFrame(
                       from: inputURL,
                       previewRoot: previewRoot
                   )
                {
                    return extractedFrameDestination
                }

                let inputExtension = inputURL.pathExtension
                let fallbackExtension = (fallbackFilename as NSString).pathExtension
                let pathExtension = inputExtension.isEmpty ? fallbackExtension : inputExtension
                let filename = pathExtension.isEmpty
                    ? "last-completed-\(UUID().uuidString)"
                    : "last-completed-\(UUID().uuidString).\(pathExtension)"
                let destination = previewRoot.appendingPathComponent(filename)

                try fileManager.copyItem(at: inputURL, to: destination)
                return destination
            case let .photoPreviewJPEGData(data):
                let destination = previewRoot.appendingPathComponent("last-completed-\(UUID().uuidString).jpg")
                try data.write(to: destination, options: [.atomic])
                return destination
            }
        } catch {
            return nil
        }
    }

    private func persistVideoPreviewFrame(from videoURL: URL, previewRoot: URL) async -> URL? {
        guard let frameImage = await representativeVideoPreviewFrame(from: videoURL) else {
            return nil
        }
        guard let jpegData = jpegData(from: frameImage) else {
            return nil
        }

        let destination = previewRoot.appendingPathComponent("last-completed-\(UUID().uuidString).jpg")
        do {
            try jpegData.write(to: destination, options: [.atomic])
            return destination
        } catch {
            return nil
        }
    }

    private func representativeVideoPreviewFrame(from videoURL: URL) async -> CGImage? {
        let asset = AVURLAsset(url: videoURL)
        if let duration = try? await asset.load(.duration) {
            let durationSeconds = max(0, CMTimeGetSeconds(duration))
            let targetTime = durationSeconds > 0
                ? CMTime(seconds: durationSeconds * 0.5, preferredTimescale: 600)
                : .zero
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            if let cgImage = await generatePreviewFrame(generator: generator, at: targetTime) {
                return cgImage
            }
        }

        guard let frames = try? await videoFrameSampler.sampleFrames(from: videoURL, count: 3),
              !frames.isEmpty
        else {
            return nil
        }
        return frames[min(1, frames.count - 1)]
    }

    private func generatePreviewFrame(
        generator: AVAssetImageGenerator,
        at time: CMTime
    ) async -> CGImage? {
        final class ResumeState: @unchecked Sendable {
            var resumed = false
        }

        return await withCheckedContinuation { continuation in
            let times = [NSValue(time: time)]
            let lock = NSLock()
            let state = ResumeState()

            generator.generateCGImagesAsynchronously(forTimes: times) { _, image, _, result, _ in
                lock.lock()
                guard !state.resumed else {
                    lock.unlock()
                    return
                }

                let outputImage: CGImage?
                if result == .succeeded, let image {
                    outputImage = image
                } else if result == .failed || result == .cancelled {
                    outputImage = nil
                } else {
                    lock.unlock()
                    return
                }

                state.resumed = true
                lock.unlock()
                continuation.resume(returning: outputImage)
            }
        }
    }

    private func jpegData(from image: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}

@MainActor
public final class RunCoordinator {
    private struct ResolvedCaptionWorkflowQueueItem: Sendable {
        let queueIndex: Int
        let albumID: String
        let configuredAlbumName: String
        let currentAlbumName: String

        var queueLabel: String {
            "queue item \(queueIndex + 1)"
        }

        var displayName: String {
            "\"\(currentAlbumName)\" (\(queueLabel))"
        }
    }

    private struct AnalysisJobResult: Sendable {
        let asset: MediaAsset
        let input: AnalysisInput?
        let generated: GeneratedMetadata?
        let errorMessage: String?
    }

    private struct PreparationJobResult: Sendable {
        let index: Int
        let asset: MediaAsset
        let input: AnalysisInput?
        let preparedPayload: PreparedAnalysisPayload?
        let errorMessage: String?
    }

    private struct PendingWrite: Sendable {
        let asset: MediaAsset
        let sourceContext: String
        let input: AnalysisInput
        let generated: GeneratedMetadata
    }

    private actor AsyncSemaphore {
        private var permits: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(permits: Int) {
            self.permits = max(1, permits)
        }

        func acquire() async {
            if permits > 0 {
                permits -= 1
                return
            }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            if let waiter = waiters.first {
                waiters.removeFirst()
                waiter.resume(returning: ())
            } else {
                permits += 1
            }
        }
    }

    private actor PreparedInputChannel {
        private var buffer: [PreparationJobResult] = []
        private var waiters: [CheckedContinuation<PreparationJobResult?, Never>] = []
        private var finished = false

        func send(_ result: PreparationJobResult) {
            if let waiter = waiters.first {
                waiters.removeFirst()
                waiter.resume(returning: result)
            } else {
                buffer.append(result)
            }
        }

        func finish() {
            finished = true
            let pendingWaiters = waiters
            waiters.removeAll(keepingCapacity: false)
            pendingWaiters.forEach { $0.resume(returning: nil) }
        }

        func receive() async -> PreparationJobResult? {
            if !buffer.isEmpty {
                return buffer.removeFirst()
            }
            if finished {
                return nil
            }
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    private actor AnalysisResultChannel {
        private var buffer: [(Int, AnalysisJobResult)] = []
        private var waiters: [CheckedContinuation<(Int, AnalysisJobResult)?, Never>] = []
        private var finished = false

        func send(_ result: (Int, AnalysisJobResult)) {
            if let waiter = waiters.first {
                waiters.removeFirst()
                waiter.resume(returning: result)
            } else {
                buffer.append(result)
            }
        }

        func finish() {
            finished = true
            let pendingWaiters = waiters
            waiters.removeAll(keepingCapacity: false)
            pendingWaiters.forEach { $0.resume(returning: nil) }
        }

        func receive() async -> (Int, AnalysisJobResult)? {
            if !buffer.isEmpty {
                return buffer.removeFirst()
            }
            if finished {
                return nil
            }
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    private static let enumerationPageSize = 250
    private static let processingBatchSize = 250
    private static let captionWorkflowChunkTarget = 500
    private static let metadataPrefetchWindowSize = 32
    private static let slowOrderWarningThreshold = 5_000
    private static let maxRetainedErrors = 500
    private static let maxRetainedFailedAssets = 2000
    private static let maxPendingPreviewTasks = 2
    private static let captionWorkflowStageLoadMaxAttempts = 3
    private static let captionWorkflowEmptyConfirmationAttempts = 2
    private static let captionWorkflowRetryDelayNanoseconds: UInt64 = 1_000_000_000
    private nonisolated static let photoPreviewMaxPixelSize = 2048

    private let photosWriter: PhotosWriter
    private let analyzer: Analyzer
    private let videoFrameSampler: VideoFrameSampler
    private let previewRenderer: any PreviewRendering
    private let logicVersion: LogicVersion
    private let photosRestartInterval: Int
    private let photosMemoryCheckInterval: Int
    private let photosMemoryWarningBytes: UInt64
    private let photosRestartCooldownSeconds: TimeInterval
    private let photosRestartLaunchTimeoutSeconds: TimeInterval
    private let analysisConcurrency: Int
    private let prepareAheadLimit: Int
    private let writeBatchSize: Int

    private var isCancelled = false

    public convenience init(
        photosWriter: PhotosWriter,
        analyzer: Analyzer,
        videoFrameSampler: VideoFrameSampler = VideoFrameSampler(),
        logicVersion: LogicVersion = .current,
        checkpointInterval: Int = 500,
        photosRefreshPromptInterval: Int = 500,
        photosMemoryCheckInterval: Int = 40,
        photosMemoryWarningBytes: UInt64 = 20 * 1024 * 1024 * 1024,
        photosRestartCooldownSeconds: TimeInterval = 60,
        photosRestartLaunchTimeoutSeconds: TimeInterval = 30,
        analysisConcurrency: Int = 1,
        prepareAheadLimit: Int = 1,
        writeBatchSize: Int = 16
    ) {
        self.init(
            photosWriter: photosWriter,
            analyzer: analyzer,
            videoFrameSampler: videoFrameSampler,
            logicVersion: logicVersion,
            checkpointInterval: checkpointInterval,
            photosRefreshPromptInterval: photosRefreshPromptInterval,
            photosMemoryCheckInterval: photosMemoryCheckInterval,
            photosMemoryWarningBytes: photosMemoryWarningBytes,
            photosRestartCooldownSeconds: photosRestartCooldownSeconds,
            photosRestartLaunchTimeoutSeconds: photosRestartLaunchTimeoutSeconds,
            analysisConcurrency: analysisConcurrency,
            prepareAheadLimit: prepareAheadLimit,
            writeBatchSize: writeBatchSize,
            previewRenderer: DefaultPreviewRenderer(videoFrameSampler: videoFrameSampler)
        )
    }

    init(
        photosWriter: PhotosWriter,
        analyzer: Analyzer,
        videoFrameSampler: VideoFrameSampler = VideoFrameSampler(),
        logicVersion: LogicVersion = .current,
        checkpointInterval: Int = 500,
        photosRefreshPromptInterval: Int = 500,
        photosMemoryCheckInterval: Int = 40,
        photosMemoryWarningBytes: UInt64 = 20 * 1024 * 1024 * 1024,
        photosRestartCooldownSeconds: TimeInterval = 60,
        photosRestartLaunchTimeoutSeconds: TimeInterval = 30,
        analysisConcurrency: Int = 1,
        prepareAheadLimit: Int = 1,
        writeBatchSize: Int = 16,
        previewRenderer: any PreviewRendering
    ) {
        self.photosWriter = photosWriter
        self.analyzer = analyzer
        self.videoFrameSampler = videoFrameSampler
        self.previewRenderer = previewRenderer
        self.logicVersion = logicVersion
        self.photosRestartInterval = max(1, checkpointInterval)
        self.photosMemoryCheckInterval = max(1, photosMemoryCheckInterval)
        self.photosMemoryWarningBytes = max(1, photosMemoryWarningBytes)
        self.photosRestartCooldownSeconds = max(0, photosRestartCooldownSeconds)
        self.photosRestartLaunchTimeoutSeconds = max(1, photosRestartLaunchTimeoutSeconds)
        self.analysisConcurrency = max(1, analysisConcurrency)
        self.prepareAheadLimit = max(0, prepareAheadLimit)
        self.writeBatchSize = max(1, writeBatchSize)
    }

    public func cancel() {
        isCancelled = true
    }

    public func run(
        options: RunOptions,
        capabilities: AppCapabilities,
        callbacks: RunCallbacks
    ) async -> RunSummary {
        isCancelled = false

        if case .picker = options.source,
           case let .unsupported(reason) = capabilities.pickerCapability {
            return RunSummary(progress: .init(), errors: [reason])
        }

        let photosRunning = await photosWriter.isPhotosAppRunning()
        guard photosRunning else {
            return RunSummary(progress: .init(), errors: ["Photos.app must be open before starting a write run."])
        }

        guard capabilities.qwenModelAvailable else {
            return RunSummary(
                progress: .init(),
                errors: ["Qwen 2.5VL 7B is unavailable. Start Ollama and ensure model 'qwen2.5vl:7b' is installed."]
            )
        }

        let timingRecorder = RunTimingRecorder()
        let runStartedNanoseconds = DispatchTime.now().uptimeNanoseconds

        var progress = RunProgress()
        var errors: [String] = []
        var failedAssets: [MediaAsset] = []
        var nextPhotosRestartAtChanged = photosRestartInterval
        var nextPhotosMemoryCheckAtChanged = photosMemoryCheckInterval
        var photosRestartRequested = false

        var queuedAssetIDs: [String] = []
        var processedAssetIDs = Set<String>()
        var queueCursor = 0
        var processedSincePendingUpdate = 0

        let targetEngine: EngineTier = .qwen25vl7b
        let lifecycleController = photosWriter as? PhotosLifecycleControlling
        let albumListingSource = photosWriter as? AlbumListingPhotosSource
        var cachedAlbumNamesByID: [String: String] = [:]

        func currentRunDiagnostics() async -> RunDiagnostics {
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - runStartedNanoseconds
            return await timingRecorder.diagnostics(
                totalWallNanoseconds: elapsedNs,
                analysisConcurrency: analysisConcurrency,
                prepareAheadLimit: prepareAheadLimit,
                writeBatchSize: writeBatchSize
            )
        }

        func makeSummary() async -> RunSummary {
            let diagnostics = await currentRunDiagnostics()
            let timingSummary = await timingRecorder.summary(
                totalWallNanoseconds: UInt64((diagnostics.wallSeconds * 1_000_000_000).rounded())
            )
            print(timingSummary)
            return RunSummary(
                progress: progress,
                errors: errors,
                failedAssets: failedAssets,
                diagnostics: diagnostics
            )
        }

        func snapshotPendingIDs() -> [String] {
            while queueCursor < queuedAssetIDs.count && processedAssetIDs.contains(queuedAssetIDs[queueCursor]) {
                queueCursor += 1
            }
            guard queueCursor < queuedAssetIDs.count else {
                return []
            }
            return Array(queuedAssetIDs[queueCursor...])
        }

        func emitPendingIDs(force: Bool = false) {
            guard force || processedSincePendingUpdate >= 25 else {
                return
            }
            processedSincePendingUpdate = 0
            callbacks.onPendingIDsUpdated(snapshotPendingIDs())
        }

        func appendPendingAssets(_ assets: [MediaAsset]) {
            guard !assets.isEmpty else { return }
            queuedAssetIDs.append(contentsOf: assets.map(\.id))
            callbacks.onPendingIDsUpdated(snapshotPendingIDs())
        }

        func markAssetProcessed(_ assetID: String) {
            let inserted = processedAssetIDs.insert(assetID).inserted
            guard inserted else { return }
            processedSincePendingUpdate += 1
            emitPendingIDs()
        }

        callbacks.onPendingIDsUpdated([])
        defer {
            emitPendingIDs(force: true)
            callbacks.onStatusChanged(nil)
        }

        func recordError(_ message: String) {
            if errors.count < Self.maxRetainedErrors {
                errors.append(message)
            }
            callbacks.onError(message)
        }

        func recordFailedAsset(_ asset: MediaAsset) {
            if failedAssets.count < Self.maxRetainedFailedAssets {
                failedAssets.append(asset)
            }
        }

        func measureOnMain<T>(
            _ stage: RunTimingStage,
            operation: () async throws -> T
        ) async throws -> T {
            let start = DispatchTime.now().uptimeNanoseconds
            do {
                let value = try await operation()
                await timingRecorder.record(
                    stage: stage,
                    nanoseconds: DispatchTime.now().uptimeNanoseconds - start
                )
                return value
            } catch {
                await timingRecorder.record(
                    stage: stage,
                    nanoseconds: DispatchTime.now().uptimeNanoseconds - start
                )
                throw error
            }
        }

        func verifyPhotosStillRunning() async -> Bool {
            let photosRunningNow = await photosWriter.isPhotosAppRunning()
            if photosRunningNow {
                return true
            }
            recordError("Photos.app was closed during run. Reopen Photos and start again.")
            return false
        }

        func requestPhotosRestartIfNeeded() {
            guard !photosRestartRequested else { return }
            photosRestartRequested = true
            callbacks.onStatusChanged("Pausing for Photos restart")
        }

        func waitForRestartCooldown() async -> Bool {
            let deadline = Date().addingTimeInterval(photosRestartCooldownSeconds)
            while true {
                if isCancelled {
                    return false
                }

                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 {
                    return true
                }

                let delaySeconds = min(0.5, remaining)
                let delayNanoseconds = UInt64((delaySeconds * 1_000_000_000).rounded())
                try? await Task.sleep(nanoseconds: max(1, delayNanoseconds))
            }
        }

        func relaunchPhotosAfterCancellationIfNeeded(_ lifecycleController: PhotosLifecycleControlling?) async {
            guard let lifecycleController else { return }
            try? await lifecycleController.launchPhotosApp()
        }

        func performRequestedPhotosRestartIfNeeded() async -> Bool {
            guard photosRestartRequested else {
                return false
            }

            photosRestartRequested = false

            guard let lifecycleController else {
                callbacks.onStatusChanged(nil)
                recordError("Automatic Photos restart is unavailable for this Photos client.")
                return false
            }

            guard !isCancelled else {
                callbacks.onStatusChanged(nil)
                return false
            }

            callbacks.onStatusChanged("Pausing for Photos restart")
            let didQuitPhotos = await lifecycleController.quitPhotosAppGracefully()
            guard didQuitPhotos else {
                callbacks.onStatusChanged(nil)
                recordError("Photos restart was skipped because Photos did not quit cleanly.")
                return false
            }

            callbacks.onStatusChanged("Waiting 60s before relaunch")
            let completedCooldown = await waitForRestartCooldown()
            guard completedCooldown else {
                callbacks.onStatusChanged(nil)
                await relaunchPhotosAfterCancellationIfNeeded(lifecycleController)
                return false
            }

            do {
                try await lifecycleController.launchPhotosApp()
            } catch {
                callbacks.onStatusChanged(nil)
                recordError("Photos restart failed while relaunching: \(error.localizedDescription)")
                isCancelled = true
                return false
            }

            guard !isCancelled else {
                callbacks.onStatusChanged(nil)
                return false
            }

            callbacks.onStatusChanged("Waiting for Photos to become ready")
            let photosReady = await lifecycleController.waitForPhotosReady(
                timeoutSeconds: photosRestartLaunchTimeoutSeconds
            )
            callbacks.onStatusChanged(nil)

            guard photosReady else {
                if isCancelled {
                    return false
                }
                recordError(
                    "Photos did not become automation-ready within \(Int(photosRestartLaunchTimeoutSeconds.rounded()))s after relaunch."
                )
                isCancelled = true
                return false
            }

            return true
        }

        func handlePostChangeMaintenanceIfNeeded() async {
            if !isCancelled, progress.changed >= nextPhotosRestartAtChanged {
                requestPhotosRestartIfNeeded()
                repeat {
                    nextPhotosRestartAtChanged += photosRestartInterval
                } while nextPhotosRestartAtChanged <= progress.changed
            }

            if !isCancelled, progress.changed >= nextPhotosMemoryCheckAtChanged {
                nextPhotosMemoryCheckAtChanged = progress.changed + photosMemoryCheckInterval
                if let monitor = photosWriter as? PhotosProcessMonitoring,
                   let photosMemoryBytes = await monitor.photosResidentMemoryBytes(),
                   photosMemoryBytes >= photosMemoryWarningBytes
                {
                    requestPhotosRestartIfNeeded()
                }
            }
        }

        let batchWriter = photosWriter as? BatchWritePhotosWriter
        let preparedAnalyzer = analyzer as? any PreparedInputAnalyzer
        var pendingPreviewTasks: [Task<Void, Never>] = []

        func drainCompletedPreviewTasks(forceWaitForAll: Bool = false) async {
            while let firstTask = pendingPreviewTasks.first,
                  forceWaitForAll || pendingPreviewTasks.count >= Self.maxPendingPreviewTasks
            {
                await firstTask.value
                pendingPreviewTasks.removeFirst()
            }
        }

        func completeRun() async -> RunSummary {
            await drainCompletedPreviewTasks(forceWaitForAll: true)
            return await makeSummary()
        }

        func resolveSourceContext(for source: ScopeSource) async -> String {
            switch source {
            case .library:
                return "Whole Library"
            case let .picker(ids):
                return ids.isEmpty ? "Photos Picker" : "Photos Picker"
            case let .album(id):
                if let cachedName = cachedAlbumNamesByID[id] {
                    return cachedName
                }
                guard let albumListingSource else {
                    return "Selected Album"
                }
                if let albumName = try? await albumListingSource
                    .listUserAlbums()
                    .first(where: { $0.id == id })?
                    .name
                {
                    cachedAlbumNamesByID[id] = albumName
                    return albumName
                }
                return "Selected Album"
            case .captionWorkflow:
                return "Caption Workflow"
            }
        }

        func enqueuePreview(for write: PendingWrite) async {
            await drainCompletedPreviewTasks()
            let priorTask = pendingPreviewTasks.last
            let previewRenderer = self.previewRenderer

            let task = Task(priority: .utility) { [timingRecorder] in
                _ = await priorTask?.value

                let previewStart = DispatchTime.now().uptimeNanoseconds
                let previewFileURL = await previewRenderer.persistPreviewFile(
                    from: write.input,
                    assetID: write.asset.id,
                    fallbackFilename: write.asset.filename,
                    kind: write.asset.kind
                )
                await timingRecorder.record(
                    stage: .preview,
                    nanoseconds: DispatchTime.now().uptimeNanoseconds - previewStart
                )

                callbacks.onItemCompleted(
                    CompletedItemPreview(
                        filename: write.asset.filename,
                        sourceContext: write.sourceContext,
                        kind: write.asset.kind,
                        previewFileURL: previewFileURL,
                        caption: write.generated.caption,
                        keywords: write.generated.keywords
                    )
                )

                Self.cleanupAnalysisInput(write.input)
            }

            pendingPreviewTasks.append(task)
        }

        func writeChunk(_ writes: [PendingWrite]) async {
            guard !writes.isEmpty else { return }

            let payloads = writes.map { write in
                MetadataWritePayload(
                    id: write.asset.id,
                    caption: write.generated.caption,
                    keywords: OwnershipTagCodec.appendTags(
                        OwnershipTag(logicVersion: logicVersion, engineTier: targetEngine),
                        to: write.generated.keywords
                    )
                )
            }

            var resultsByID: [String: MetadataWriteResult] = [:]
            if let batchWriter {
                do {
                    let batchResults = try await measureOnMain(.write) {
                        try await batchWriter.writeMetadata(batch: payloads)
                    }
                    resultsByID.reserveCapacity(batchResults.count)
                    for result in batchResults where resultsByID[result.id] == nil {
                        resultsByID[result.id] = result
                    }
                } catch {
                    resultsByID.removeAll(keepingCapacity: true)
                }
            }

            if resultsByID.isEmpty {
                for (index, write) in writes.enumerated() {
                    do {
                        try await measureOnMain(.write) {
                            try await photosWriter.writeMetadata(
                                id: write.asset.id,
                                caption: payloads[index].caption,
                                keywords: payloads[index].keywords
                            )
                        }
                        resultsByID[write.asset.id] = MetadataWriteResult(id: write.asset.id, success: true)
                    } catch {
                        resultsByID[write.asset.id] = MetadataWriteResult(
                            id: write.asset.id,
                            success: false,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }

            for write in writes {
                let writeResult = resultsByID[write.asset.id] ?? MetadataWriteResult(
                    id: write.asset.id,
                    success: false,
                    errorMessage: "Write operation did not return a result."
                )

                if writeResult.success {
                        progress.processed += 1
                        progress.changed += 1
                        callbacks.onProgress(progress)
                        markAssetProcessed(write.asset.id)
                        await enqueuePreview(for: write)
                        await handlePostChangeMaintenanceIfNeeded()
                } else {
                    progress.processed += 1
                    progress.failed += 1
                    let message = writeResult.errorMessage ?? "Metadata write failed."
                    recordError("\(write.asset.filename): \(message)")
                    recordFailedAsset(write.asset)
                    callbacks.onProgress(progress)
                    markAssetProcessed(write.asset.id)
                    Self.cleanupAnalysisInput(write.input)
                }
            }
        }

        func processAssets(
            _ assets: ArraySlice<MediaAsset>,
            sourceContext: String
        ) async {
            guard !assets.isEmpty else { return }
            let assetArray = Array(assets)
            let batchReader = photosWriter as? BatchMetadataPhotosWriter

            func prefetchMetadata(for windowAssets: [MediaAsset]) async -> [String: ExistingMetadataState] {
                guard let batchReader, !windowAssets.isEmpty else {
                    return [:]
                }

                let ids = windowAssets.map(\.id)
                do {
                    return try await measureOnMain(.metadataRead) {
                        try await batchReader.readMetadata(ids: ids)
                    }
                } catch {
                    return [:]
                }
            }

            func processWindow(
                _ windowAssets: [MediaAsset],
                prefetchedMetadata: [String: ExistingMetadataState]
            ) async {
                var pendingWrites: [PendingWrite] = []
                pendingWrites.reserveCapacity(analysisConcurrency + prepareAheadLimit + 1)
                let pipelineDepth = max(1, analysisConcurrency + prepareAheadLimit)
                let preparationSemaphore = AsyncSemaphore(permits: pipelineDepth)
                let analysisSemaphore = AsyncSemaphore(permits: analysisConcurrency)
                let analyzedResults = AnalysisResultChannel()
                let writer = photosWriter
                let analysisEngine = analyzer
                let preparedAnalysisEngine = preparedAnalyzer
                let recorder = timingRecorder
                var nextAnalysisIndex = 0

                func nextWriteChunkSize(for readyCount: Int) -> Int {
                    let untilRestart = max(1, nextPhotosRestartAtChanged - progress.changed)
                    let untilMemory = max(1, nextPhotosMemoryCheckAtChanged - progress.changed)
                    let safeChunkSize = max(1, min(writeBatchSize, untilRestart, untilMemory))
                    return max(1, min(readyCount, safeChunkSize))
                }

                func flushPendingWrites() async {
                    while !pendingWrites.isEmpty && !isCancelled {
                        let chunkSize = nextWriteChunkSize(for: pendingWrites.count)
                        let chunk = Array(pendingWrites.prefix(chunkSize))
                        pendingWrites.removeFirst(chunkSize)
                        await writeChunk(chunk)
                    }
                }

                func handleOrderedResult(_ result: AnalysisJobResult) async {
                    if let generated = result.generated,
                       let input = result.input
                    {
                        pendingWrites.append(
                            PendingWrite(
                                asset: result.asset,
                                sourceContext: sourceContext,
                                input: input,
                                generated: generated
                            )
                        )
                        await flushPendingWrites()
                    } else {
                        if let input = result.input {
                            Self.cleanupAnalysisInput(input)
                        }
                        progress.processed += 1
                        progress.failed += 1
                        let message = result.errorMessage ?? "Analysis failed."
                        recordError("\(result.asset.filename): \(message)")
                        recordFailedAsset(result.asset)
                        callbacks.onProgress(progress)
                        markAssetProcessed(result.asset.id)
                    }
                }

                let consumerTask = Task { @MainActor in
                    var bufferedResults: [Int: AnalysisJobResult] = [:]
                    var nextIndexToEmit = 0

                    while let completed = await analyzedResults.receive() {
                        bufferedResults[completed.0] = completed.1

                        while let readyResult = bufferedResults.removeValue(forKey: nextIndexToEmit) {
                            await handleOrderedResult(readyResult)
                            nextIndexToEmit += 1
                        }
                    }

                    await flushPendingWrites()
                }

                await withTaskGroup(of: Void.self) { group in
                    func scheduleAnalysis(for asset: MediaAsset) {
                        let index = nextAnalysisIndex
                        nextAnalysisIndex += 1

                        group.addTask(priority: .userInitiated) {
                            await preparationSemaphore.acquire()
                            let prepared = await Self.prepareAnalysisInput(
                                index: index,
                                asset: asset,
                                photosWriter: writer,
                                preparedAnalyzer: preparedAnalysisEngine,
                                timingRecorder: recorder
                            )
                            await preparationSemaphore.release()
                            await analysisSemaphore.acquire()
                            let analyzed = await Self.analyzePreparedInput(
                                prepared,
                                analyzer: analysisEngine,
                                preparedAnalyzer: preparedAnalysisEngine,
                                timingRecorder: recorder
                            )
                            await analysisSemaphore.release()
                            await analyzedResults.send(analyzed)
                        }
                    }

                    for asset in windowAssets {
                        if isCancelled {
                            break
                        }

                        do {
                            let existing: ExistingMetadataState
                            if let prefetched = prefetchedMetadata[asset.id] {
                                existing = prefetched
                            } else {
                                existing = try await measureOnMain(.metadataRead) {
                                    try await photosWriter.readMetadata(id: asset.id)
                                }
                            }

                            let decision = OverwritePolicy.decide(
                                context: OverwriteContext(
                                    existing: existing,
                                    targetLogicVersion: logicVersion,
                                    targetEngine: targetEngine,
                                    overwriteAppOwnedSameOrNewer: options.overwriteAppOwnedSameOrNewer
                                )
                            )

                            let shouldWrite: Bool
                            switch decision {
                            case .write:
                                shouldWrite = true
                            case .requiresPerPhotoConfirmation:
                                if options.alwaysOverwriteExternalMetadata {
                                    shouldWrite = true
                                } else {
                                    shouldWrite = await callbacks.confirmExternalOverwrite(asset, existing)
                                }
                            case .skip:
                                shouldWrite = false
                            }

                            if shouldWrite {
                                scheduleAnalysis(for: asset)
                            } else {
                                progress.processed += 1
                                progress.skipped += 1
                                callbacks.onProgress(progress)
                                markAssetProcessed(asset.id)
                            }
                        } catch {
                            progress.processed += 1
                            progress.failed += 1
                            recordError("\(asset.filename): \(error.localizedDescription)")
                            recordFailedAsset(asset)
                            callbacks.onProgress(progress)
                            markAssetProcessed(asset.id)
                        }
                    }
                }

                await analyzedResults.finish()
                _ = await consumerTask.value
            }

            var windowStart = 0
            let firstWindowEnd = min(
                windowStart + Self.metadataPrefetchWindowSize,
                assetArray.count
            )
            var currentWindowAssets = Array(assetArray[windowStart..<firstWindowEnd])
            // Keep the active window streaming by reading overwrite metadata on demand.
            // Later windows still use the existing batch prefetch path off the critical path.
            var currentPrefetchedMetadata: [String: ExistingMetadataState] = [:]

            while !isCancelled && !currentWindowAssets.isEmpty {
                let nextWindowStart = windowStart + currentWindowAssets.count
                var nextWindowAssets: [MediaAsset] = []
                var nextPrefetchTask: Task<[String: ExistingMetadataState], Never>?
                if nextWindowStart < assetArray.count {
                    let nextWindowEnd = min(
                        nextWindowStart + Self.metadataPrefetchWindowSize,
                        assetArray.count
                    )
                    nextWindowAssets = Array(assetArray[nextWindowStart..<nextWindowEnd])
                    let prefetchedWindowAssets = nextWindowAssets
                    nextPrefetchTask = Task(priority: .userInitiated) {
                        await prefetchMetadata(for: prefetchedWindowAssets)
                    }
                }

                await processWindow(
                    currentWindowAssets,
                    prefetchedMetadata: currentPrefetchedMetadata
                )

                let nextPrefetchedMetadata = await nextPrefetchTask?.value ?? [:]

                if isCancelled {
                    break
                }

                let didRestartPhotos = await performRequestedPhotosRestartIfNeeded()
                if isCancelled {
                    break
                }

                windowStart = nextWindowStart
                currentWindowAssets = nextWindowAssets
                currentPrefetchedMetadata = didRestartPhotos
                    ? [:]
                    : nextPrefetchedMetadata
            }
        }

        func processAssetsInBatches(
            _ assets: [MediaAsset],
            sourceContext: String
        ) async {
            guard !assets.isEmpty else { return }

            var start = assets.startIndex
            while start < assets.endIndex && !isCancelled {
                let end = assets.index(
                    start,
                    offsetBy: Self.processingBatchSize,
                    limitedBy: assets.endIndex
                ) ?? assets.endIndex
                await processAssets(
                    assets[start..<end],
                    sourceContext: sourceContext
                )
                start = end
            }
        }

        func promptForSlowOrderedRunIfNeeded(totalCount: Int) async -> Bool {
            guard totalCount >= Self.slowOrderWarningThreshold else {
                return true
            }
            let prompt = RunSafetyPausePrompt(
                title: "Slow Ordered Run",
                message: "\(totalCount) items are selected. This order mode pre-scans the selection before processing starts and may take a long time. Continue?",
                confirmLabel: "Continue",
                cancelLabel: "Cancel"
            )
            let shouldContinue = await callbacks.confirmSafetyPause(prompt)
            if !shouldContinue {
                isCancelled = true
                return false
            }
            return await verifyPhotosStillRunning()
        }

        func waitForCaptionWorkflowRetryDelay() async -> Bool {
            guard !isCancelled else {
                return false
            }
            try? await Task.sleep(nanoseconds: Self.captionWorkflowRetryDelayNanoseconds)
            return !isCancelled
        }

        func resolveCaptionWorkflowQueue(
            from albums: [AlbumSummary]
        ) throws -> [ResolvedCaptionWorkflowQueueItem] {
            guard let configuration = options.captionWorkflowConfiguration else {
                let queueItems = (1...CaptionWorkflowConfiguration.minimumQueueLength).map { "queue item \($0)" }
                throw CaptionWorkflowRunError.incompleteConfiguration(queueItems)
            }

            guard configuration.queue.count >= CaptionWorkflowConfiguration.minimumQueueLength else {
                let queueItems = (configuration.queue.count + 1...CaptionWorkflowConfiguration.minimumQueueLength)
                    .map { "queue item \($0)" }
                throw CaptionWorkflowRunError.incompleteConfiguration(queueItems)
            }

            let missingQueueItems = configuration.queue.enumerated().compactMap { index, entry -> String? in
                entry.isConfigured ? nil : "queue item \(index + 1)"
            }
            if !missingQueueItems.isEmpty {
                throw CaptionWorkflowRunError.incompleteConfiguration(missingQueueItems)
            }

            let duplicateQueueItems = Dictionary(grouping: configuration.queue.enumerated().compactMap { index, entry in
                entry.albumID.map { ($0, index) }
            }, by: { $0.0 })
                .values
                .filter { $0.count > 1 }
                .flatMap { duplicates in
                    duplicates.map { _, index in
                        "queue item \(index + 1)"
                    }
                }
            if !duplicateQueueItems.isEmpty {
                throw CaptionWorkflowRunError.duplicateConfiguredAlbums(duplicateQueueItems)
            }

            let albumsByID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
            return try configuration.queue.enumerated().map { index, entry in
                guard let albumID = entry.albumID,
                      let configuredAlbumName = entry.albumName
                else {
                    throw CaptionWorkflowRunError.incompleteConfiguration(["queue item \(index + 1)"])
                }
                guard let currentAlbum = albumsByID[albumID] else {
                    throw CaptionWorkflowRunError.missingConfiguredAlbum(
                        queueItem: index + 1,
                        savedAlbumName: configuredAlbumName
                    )
                }
                return ResolvedCaptionWorkflowQueueItem(
                    queueIndex: index,
                    albumID: currentAlbum.id,
                    configuredAlbumName: configuredAlbumName,
                    currentAlbumName: currentAlbum.name
                )
            }
        }

        func enumerateCaptionWorkflowSnapshot(
            albumID: String
        ) async throws -> [MediaAsset] {
            do {
                return try await photosWriter.enumerate(
                    scope: .album(id: albumID),
                    dateRange: options.optionalCaptureDateRange
                )
            } catch {
                guard let incrementalWriter = photosWriter as? IncrementalPhotosWriter else {
                    throw error
                }

                var offset = 0
                var assets: [MediaAsset] = []
                while !isCancelled {
                    let batch = try await enumeratePageResilient(
                        incrementalWriter: incrementalWriter,
                        scope: .album(id: albumID),
                        offset: offset,
                        preferredLimit: Self.enumerationPageSize
                    )
                    if batch.isEmpty {
                        break
                    }
                    offset += batch.count
                    assets.append(contentsOf: batch)
                }

                if let dateRange = options.optionalCaptureDateRange {
                    return assets.filter { dateRange.contains($0.captureDate) }
                }
                return assets
            }
        }

        func isCaptionWorkflowAssetEligible(_ asset: MediaAsset) -> Bool {
            guard !processedAssetIDs.contains(asset.id) else {
                return false
            }
            guard let dateRange = options.optionalCaptureDateRange else {
                return true
            }
            return dateRange.contains(asset.captureDate)
        }

        func captionWorkflowQueueItem(
            at index: Int,
            from queue: [ResolvedCaptionWorkflowQueueItem]
        ) -> ResolvedCaptionWorkflowQueueItem? {
            guard queue.indices.contains(index) else {
                return nil
            }
            return queue[index]
        }

        func captionWorkflowChunkCollectionStatus(
            queueItem: ResolvedCaptionWorkflowQueueItem,
            discovered: Int,
            target: Int
        ) -> String {
            "Caption Workflow: collecting next chunk for \(queueItem.displayName) (\(min(discovered, target))/\(target) discovered)."
        }

        func enumerateCaptionWorkflowChunk(
            albumID: String,
            queueItem: ResolvedCaptionWorkflowQueueItem,
            incrementalWriter: IncrementalPhotosWriter,
            targetCount: Int
        ) async throws -> [MediaAsset] {
            // Smart albums can shrink as writes complete, so each chunk must come from a fresh offset-0 pass.
            var offset = 0
            var assets: [MediaAsset] = []
            assets.reserveCapacity(targetCount)
            var seenAssetIDs = Set<String>()

            callbacks.onStatusChanged(
                captionWorkflowChunkCollectionStatus(
                    queueItem: queueItem,
                    discovered: 0,
                    target: targetCount
                )
            )

            while !isCancelled && assets.count < targetCount {
                let batch = try await enumeratePageResilient(
                    incrementalWriter: incrementalWriter,
                    scope: .album(id: albumID),
                    offset: offset,
                    preferredLimit: Self.enumerationPageSize
                )
                if batch.isEmpty {
                    break
                }

                offset += batch.count

                for asset in batch where seenAssetIDs.insert(asset.id).inserted {
                    guard isCaptionWorkflowAssetEligible(asset) else {
                        continue
                    }
                    assets.append(asset)
                    if assets.count >= targetCount {
                        break
                    }
                }

                callbacks.onStatusChanged(
                    captionWorkflowChunkCollectionStatus(
                        queueItem: queueItem,
                        discovered: assets.count,
                        target: targetCount
                    )
                )
            }

            guard !isCancelled else {
                return []
            }

            return assets
        }

        func loadCaptionWorkflowQueueSnapshot(
            queueItemPlan: ResolvedCaptionWorkflowQueueItem,
            preflightQueue: [ResolvedCaptionWorkflowQueueItem],
            confirmEmptyAfterWrites: Bool
        ) async throws -> (ResolvedCaptionWorkflowQueueItem, [MediaAsset]) {
            let emptyConfirmationLimit = confirmEmptyAfterWrites
                ? min(Self.captionWorkflowStageLoadMaxAttempts, Self.captionWorkflowEmptyConfirmationAttempts)
                : 1
            var lastError: Error?

            for attempt in 1...Self.captionWorkflowStageLoadMaxAttempts {
                if attempt > 1 {
                    callbacks.onStatusChanged(
                        "Caption Workflow: retrying \(queueItemPlan.displayName) (attempt \(attempt) of \(Self.captionWorkflowStageLoadMaxAttempts))."
                    )
                }

                do {
                    let albums = try await albumListingSource!.listUserAlbums()
                    let refreshedQueue = try resolveCaptionWorkflowQueue(from: albums)
                    guard let refreshedQueueItem = captionWorkflowQueueItem(at: queueItemPlan.queueIndex, from: refreshedQueue)
                        ?? captionWorkflowQueueItem(at: queueItemPlan.queueIndex, from: preflightQueue)
                    else {
                        throw CaptionWorkflowRunError.missingConfiguredAlbum(
                            queueItem: queueItemPlan.queueIndex + 1,
                            savedAlbumName: queueItemPlan.configuredAlbumName
                        )
                    }
                    let snapshot = try await enumerateCaptionWorkflowSnapshot(albumID: refreshedQueueItem.albumID)
                    if snapshot.isEmpty, attempt < emptyConfirmationLimit {
                        callbacks.onStatusChanged(
                            "Caption Workflow: waiting for Photos to refresh \(refreshedQueueItem.displayName) before deciding it is empty."
                        )
                        guard await waitForCaptionWorkflowRetryDelay() else {
                            return (refreshedQueueItem, [])
                        }
                        continue
                    }
                    return (refreshedQueueItem, snapshot)
                } catch {
                    lastError = error
                    guard attempt < Self.captionWorkflowStageLoadMaxAttempts else {
                        throw error
                    }
                    callbacks.onStatusChanged(
                        "Caption Workflow: stage handoff for \(queueItemPlan.displayName) failed (\(error.localizedDescription)). Waiting briefly and retrying."
                    )
                    guard await waitForCaptionWorkflowRetryDelay() else {
                        break
                    }
                }
            }

            throw lastError ?? PhotosAppleScriptError.scriptFailed(
                message: "Caption Workflow failed while loading \(queueItemPlan.displayName)."
            )
        }

        func loadCaptionWorkflowQueueChunk(
            queueItemPlan: ResolvedCaptionWorkflowQueueItem,
            preflightQueue: [ResolvedCaptionWorkflowQueueItem],
            incrementalWriter: IncrementalPhotosWriter,
            targetCount: Int,
            confirmEmptyAfterWrites: Bool
        ) async throws -> (ResolvedCaptionWorkflowQueueItem, [MediaAsset]) {
            let emptyConfirmationLimit = confirmEmptyAfterWrites
                ? min(Self.captionWorkflowStageLoadMaxAttempts, Self.captionWorkflowEmptyConfirmationAttempts)
                : 1
            var lastError: Error?

            for attempt in 1...Self.captionWorkflowStageLoadMaxAttempts {
                if attempt > 1 {
                    callbacks.onStatusChanged(
                        "Caption Workflow: retrying \(queueItemPlan.displayName) (attempt \(attempt) of \(Self.captionWorkflowStageLoadMaxAttempts))."
                    )
                }

                do {
                    let albums = try await albumListingSource!.listUserAlbums()
                    let refreshedQueue = try resolveCaptionWorkflowQueue(from: albums)
                    guard let refreshedQueueItem = captionWorkflowQueueItem(at: queueItemPlan.queueIndex, from: refreshedQueue)
                        ?? captionWorkflowQueueItem(at: queueItemPlan.queueIndex, from: preflightQueue)
                    else {
                        throw CaptionWorkflowRunError.missingConfiguredAlbum(
                            queueItem: queueItemPlan.queueIndex + 1,
                            savedAlbumName: queueItemPlan.configuredAlbumName
                        )
                    }

                    let chunk = try await enumerateCaptionWorkflowChunk(
                        albumID: refreshedQueueItem.albumID,
                        queueItem: refreshedQueueItem,
                        incrementalWriter: incrementalWriter,
                        targetCount: targetCount
                    )

                    if chunk.isEmpty, attempt < emptyConfirmationLimit {
                        callbacks.onStatusChanged(
                            "Caption Workflow: waiting for Photos to refresh \(refreshedQueueItem.displayName) before deciding it is empty."
                        )
                        guard await waitForCaptionWorkflowRetryDelay() else {
                            return (refreshedQueueItem, [])
                        }
                        continue
                    }

                    return (refreshedQueueItem, chunk)
                } catch {
                    lastError = error
                    guard attempt < Self.captionWorkflowStageLoadMaxAttempts else {
                        throw error
                    }
                    callbacks.onStatusChanged(
                        "Caption Workflow: stage handoff for \(queueItemPlan.displayName) failed (\(error.localizedDescription)). Waiting briefly and retrying."
                    )
                    guard await waitForCaptionWorkflowRetryDelay() else {
                        break
                    }
                }
            }

            throw lastError ?? PhotosAppleScriptError.scriptFailed(
                message: "Caption Workflow failed while loading \(queueItemPlan.displayName)."
            )
        }

        func captionWorkflowSkipStatus(
            queueItem: ResolvedCaptionWorkflowQueueItem,
            filtered: Bool
        ) -> String {
            let suffix = filtered ? " after the capture-date filter" : ""
            return "Caption Workflow: \(queueItem.displayName) has no eligible items\(suffix)."
        }

        func captionWorkflowProcessingStatus(
            queueItem: ResolvedCaptionWorkflowQueueItem,
            itemCount: Int,
            skippedQueueItems: [String]
        ) -> String {
            let prefix: String
            if skippedQueueItems.isEmpty {
                prefix = "Caption Workflow: processing"
            } else {
                let skippedNames = skippedQueueItems.joined(separator: ", ")
                prefix = "Caption Workflow: \(skippedNames) had no eligible items, now processing"
            }
            return "\(prefix) \(queueItem.displayName) (\(itemCount) items)."
        }

        func runCaptionWorkflow() async -> RunSummary {
            guard albumListingSource != nil else {
                errors.append(CaptionWorkflowRunError.albumListingUnavailable.localizedDescription)
                return await completeRun()
            }

            let preflightAlbums: [AlbumSummary]
            do {
                preflightAlbums = try await albumListingSource!.listUserAlbums()
            } catch {
                errors.append("Caption Workflow failed while refreshing albums: \(error.localizedDescription)")
                return await completeRun()
            }

            let preflightQueue: [ResolvedCaptionWorkflowQueueItem]
            do {
                preflightQueue = try resolveCaptionWorkflowQueue(from: preflightAlbums)
            } catch {
                errors.append(error.localizedDescription)
                return await completeRun()
            }

            let isFastTraversal = options.traversalOrder == .photosOrderFast
            let chunkedFastTraversalWriter = isFastTraversal
                ? (photosWriter as? IncrementalPhotosWriter)
                : nil
            let filtered = options.optionalCaptureDateRange != nil
            var skippedQueueItems: [String] = []
            var foundEligibleAssets = false

            for queueItem in preflightQueue {
                guard !isCancelled else {
                    return await completeRun()
                }

                callbacks.onStatusChanged("Caption Workflow: refreshing \(queueItem.displayName).")

                if let chunkedFastTraversalWriter {
                    var processedChunkForQueueItem = false

                    while !isCancelled {
                        let refreshedQueueItem: ResolvedCaptionWorkflowQueueItem
                        let chunk: [MediaAsset]
                        do {
                            let loaded = try await loadCaptionWorkflowQueueChunk(
                                queueItemPlan: queueItem,
                                preflightQueue: preflightQueue,
                                incrementalWriter: chunkedFastTraversalWriter,
                                targetCount: Self.captionWorkflowChunkTarget,
                                confirmEmptyAfterWrites: progress.changed > 0
                            )
                            refreshedQueueItem = loaded.0
                            chunk = loaded.1
                        } catch {
                            errors.append("Caption Workflow failed while loading \(queueItem.displayName): \(error.localizedDescription)")
                            return await completeRun()
                        }

                        if isCancelled {
                            return await completeRun()
                        }

                        guard !chunk.isEmpty else {
                            if !processedChunkForQueueItem {
                                callbacks.onStatusChanged(
                                    captionWorkflowSkipStatus(
                                        queueItem: refreshedQueueItem,
                                        filtered: filtered
                                    )
                                )
                                skippedQueueItems.append(refreshedQueueItem.displayName)
                            }
                            break
                        }

                        processedChunkForQueueItem = true
                        foundEligibleAssets = true
                        progress.totalDiscovered += chunk.count
                        callbacks.onProgress(progress)

                        callbacks.onStatusChanged(
                            captionWorkflowProcessingStatus(
                                queueItem: refreshedQueueItem,
                                itemCount: chunk.count,
                                skippedQueueItems: skippedQueueItems
                            )
                        )

                        appendPendingAssets(chunk)
                        await processAssetsInBatches(
                            chunk,
                            sourceContext: refreshedQueueItem.currentAlbumName
                        )
                    }
                } else {
                    let refreshedQueueItem: ResolvedCaptionWorkflowQueueItem
                    let snapshot: [MediaAsset]
                    do {
                        let loaded = try await loadCaptionWorkflowQueueSnapshot(
                            queueItemPlan: queueItem,
                            preflightQueue: preflightQueue,
                            confirmEmptyAfterWrites: progress.changed > 0
                        )
                        refreshedQueueItem = loaded.0
                        snapshot = loaded.1
                    } catch {
                        errors.append("Caption Workflow failed while loading \(queueItem.displayName): \(error.localizedDescription)")
                        return await completeRun()
                    }

                    let remainingAssets = snapshot.filter(isCaptionWorkflowAssetEligible)
                    guard !remainingAssets.isEmpty else {
                        callbacks.onStatusChanged(
                            captionWorkflowSkipStatus(
                                queueItem: refreshedQueueItem,
                                filtered: filtered
                            )
                        )
                        skippedQueueItems.append(refreshedQueueItem.displayName)
                        continue
                    }

                    foundEligibleAssets = true
                    progress.totalDiscovered += remainingAssets.count
                    callbacks.onProgress(progress)

                    if !isFastTraversal,
                       !(await promptForSlowOrderedRunIfNeeded(totalCount: remainingAssets.count)) {
                        return await completeRun()
                    }

                    callbacks.onStatusChanged(
                        captionWorkflowProcessingStatus(
                            queueItem: refreshedQueueItem,
                            itemCount: remainingAssets.count,
                            skippedQueueItems: skippedQueueItems
                        )
                    )

                    let orderedRemainingAssets = orderedAssets(remainingAssets, by: options.traversalOrder)
                    appendPendingAssets(orderedRemainingAssets)
                    await processAssetsInBatches(
                        orderedRemainingAssets,
                        sourceContext: refreshedQueueItem.currentAlbumName
                    )
                }
            }

            if !foundEligibleAssets, !isCancelled {
                errors.append(
                    CaptionWorkflowRunError.noEligibleItems(
                        filtered: filtered,
                        albumNames: preflightQueue.map(\.currentAlbumName)
                    ).localizedDescription
                )
            }

            return await completeRun()
        }

        func isEnumeratePageTimeout(_ error: Error) -> Bool {
            if case let PhotosAppleScriptError.scriptTimedOut(operation, _) = error {
                return operation.localizedCaseInsensitiveContains("enumerate page")
            }
            return error.localizedDescription
                .localizedLowercase
                .contains("enumerate page timed out")
        }

        func enumeratePageResilient(
            incrementalWriter: IncrementalPhotosWriter,
            scope: ScopeSource,
            offset: Int,
            preferredLimit: Int
        ) async throws -> [MediaAsset] {
            let candidates = [preferredLimit, min(preferredLimit, 128), 64, 32]
            var triedLimits = Set<Int>()
            var lastTimeoutError: Error?

            for limit in candidates where limit > 0 && triedLimits.insert(limit).inserted {
                do {
                    return try await incrementalWriter.enumerate(
                        scope: scope,
                        offset: offset,
                        limit: limit
                    )
                } catch {
                    guard isEnumeratePageTimeout(error) else {
                        throw error
                    }
                    lastTimeoutError = error
                    print(
                        "[RunCoordinator] enumerate page timed out at offset \(offset) with page size \(limit); retrying with smaller page size."
                    )
                }
            }

            throw lastTimeoutError ?? PhotosAppleScriptError.scriptTimedOut(
                operation: "enumerate page",
                timeoutSeconds: 45
            )
        }

        if options.source == .captionWorkflow {
            return await runCaptionWorkflow()
        }

        let defaultSourceContext = await resolveSourceContext(for: options.source)

        let isFastTraversal = options.traversalOrder == .photosOrderFast

        if options.optionalCaptureDateRange == nil,
           let incrementalWriter = photosWriter as? IncrementalPhotosWriter {
            do {
                if isFastTraversal {
                    var offset = 0
                    while !isCancelled {
                        let batch = try await enumeratePageResilient(
                            incrementalWriter: incrementalWriter,
                            scope: options.source,
                            offset: offset,
                            preferredLimit: Self.enumerationPageSize
                        )
                        if batch.isEmpty {
                            break
                        }
                        offset += batch.count
                        progress.totalDiscovered += batch.count
                        callbacks.onProgress(progress)
                        appendPendingAssets(batch)
                        await processAssets(
                            batch[batch.startIndex..<batch.endIndex],
                            sourceContext: defaultSourceContext
                        )
                    }
                } else {
                    let totalCount = try await incrementalWriter.count(scope: options.source)
                    progress.totalDiscovered = totalCount
                    callbacks.onProgress(progress)

                    if !(await promptForSlowOrderedRunIfNeeded(totalCount: totalCount)) {
                        return await makeSummary()
                    }

                    callbacks.onPreparationProgress(0, totalCount)

                    var offset = 0
                    var allAssets: [MediaAsset] = []
                    allAssets.reserveCapacity(totalCount)
                    while offset < totalCount && !isCancelled {
                        let batch = try await enumeratePageResilient(
                            incrementalWriter: incrementalWriter,
                            scope: options.source,
                            offset: offset,
                            preferredLimit: Self.enumerationPageSize
                        )
                        if batch.isEmpty {
                            break
                        }
                        offset += batch.count
                        allAssets.append(contentsOf: batch)
                        callbacks.onPreparationProgress(min(offset, totalCount), totalCount)
                    }

                    progress.totalDiscovered = allAssets.count
                    callbacks.onProgress(progress)
                    let ordered = orderedAssets(allAssets, by: options.traversalOrder)
                    appendPendingAssets(ordered)
                    await processAssetsInBatches(
                        ordered,
                        sourceContext: defaultSourceContext
                    )
                }
            } catch {
                errors.append("Failed to enumerate assets: \(error.localizedDescription)")
                progress = .init()
                failedAssets = []
                return await makeSummary()
            }
        } else {
            if !isFastTraversal,
               let incrementalWriter = photosWriter as? IncrementalPhotosWriter,
               let totalCount = try? await incrementalWriter.count(scope: options.source),
               !(await promptForSlowOrderedRunIfNeeded(totalCount: totalCount)) {
                return await makeSummary()
            }

            let assets: [MediaAsset]
            do {
                assets = try await photosWriter.enumerate(scope: options.source, dateRange: options.optionalCaptureDateRange)
            } catch {
                errors.append("Failed to enumerate assets: \(error.localizedDescription)")
                progress = .init()
                failedAssets = []
                return await makeSummary()
            }

            progress.totalDiscovered = assets.count
            callbacks.onProgress(progress)
            if isFastTraversal {
                appendPendingAssets(assets)
                await processAssetsInBatches(
                    assets,
                    sourceContext: defaultSourceContext
                )
            } else {
                let ordered = orderedAssets(assets, by: options.traversalOrder)
                appendPendingAssets(ordered)
                await processAssetsInBatches(
                    ordered,
                    sourceContext: defaultSourceContext
                )
            }
        }

        return await completeRun()
    }

    private func orderedAssets(_ assets: [MediaAsset], by traversalOrder: RunTraversalOrder) -> [MediaAsset] {
        switch traversalOrder {
        case .photosOrderFast:
            return assets
        case .random:
            var shuffled = assets
            shuffled.shuffle()
            return shuffled
        case .cycle:
            return cycleOrderedAssets(assets)
        case .oldestToNewest:
            return assets.sorted { lhs, rhs in
                compareAsset(lhs, rhs, newestFirst: false)
            }
        case .newestToOldest:
            return assets.sorted { lhs, rhs in
                compareAsset(lhs, rhs, newestFirst: true)
            }
        }
    }

    private func cycleOrderedAssets(_ assets: [MediaAsset]) -> [MediaAsset] {
        var remaining = assets.sorted { lhs, rhs in
            compareAsset(lhs, rhs, newestFirst: false)
        }
        var cycled: [MediaAsset] = []
        cycled.reserveCapacity(remaining.count)
        var phase = 0

        while !remaining.isEmpty {
            switch phase {
            case 0:
                cycled.append(remaining.removeFirst())
            case 1:
                cycled.append(remaining.removeLast())
            default:
                let randomIndex = Int.random(in: 0..<remaining.count)
                cycled.append(remaining.remove(at: randomIndex))
            }
            phase = (phase + 1) % 3
        }

        return cycled
    }

    private func compareAsset(_ lhs: MediaAsset, _ rhs: MediaAsset, newestFirst: Bool) -> Bool {
        switch (lhs.captureDate, rhs.captureDate) {
        case let (leftDate?, rightDate?):
            if leftDate != rightDate {
                return newestFirst ? (leftDate > rightDate) : (leftDate < rightDate)
            }
            return tieBreakAssets(lhs, rhs)
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return tieBreakAssets(lhs, rhs)
        }
    }

    private func tieBreakAssets(_ lhs: MediaAsset, _ rhs: MediaAsset) -> Bool {
        let filenameOrder = lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
        if filenameOrder != .orderedSame {
            return filenameOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private nonisolated static func cleanupAnalysisInput(_ input: AnalysisInput) {
        guard case let .fileURL(exportURL) = input else {
            return
        }
        let parent = exportURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }

    private nonisolated static func prepareAnalysisInput(
        index: Int,
        asset: MediaAsset,
        photosWriter: PhotosWriter,
        preparedAnalyzer: (any PreparedInputAnalyzer)?,
        timingRecorder: RunTimingRecorder
    ) async -> PreparationJobResult {
        var input: AnalysisInput?
        var preparedPayload: PreparedAnalysisPayload?

        do {
            input = try await measureStage(.assetAcquire, recorder: timingRecorder) {
                try await acquireAnalysisInput(for: asset, photosWriter: photosWriter)
            }
            if let preparedAnalyzer, let input {
                preparedPayload = try await measureStage(.analysisPrepare, recorder: timingRecorder) {
                    try await preparedAnalyzer.prepareAnalysis(input: input, kind: asset.kind)
                }
            }
            return PreparationJobResult(
                index: index,
                asset: asset,
                input: input,
                preparedPayload: preparedPayload,
                errorMessage: nil
            )
        } catch {
            return PreparationJobResult(
                index: index,
                asset: asset,
                input: input,
                preparedPayload: preparedPayload,
                errorMessage: error.localizedDescription
            )
        }
    }

    private nonisolated static func analyzePreparedInput(
        _ prepared: PreparationJobResult,
        analyzer: Analyzer,
        preparedAnalyzer: (any PreparedInputAnalyzer)?,
        timingRecorder: RunTimingRecorder
    ) async -> (Int, AnalysisJobResult) {
        guard let input = prepared.input else {
            let result = AnalysisJobResult(
                asset: prepared.asset,
                input: nil,
                generated: nil,
                errorMessage: prepared.errorMessage ?? "Analysis input was unavailable."
            )
            return (prepared.index, result)
        }

        do {
            let generated: GeneratedMetadata
            if let preparedPayload = prepared.preparedPayload,
               let preparedAnalyzer
            {
                generated = try await measureStage(.analyze, recorder: timingRecorder) {
                    try await preparedAnalyzer.analyze(preparedPayload: preparedPayload)
                }
            } else {
                generated = try await measureStage(.analyze, recorder: timingRecorder) {
                    try await analyzer.analyze(input: input, kind: prepared.asset.kind)
                }
            }
            let result = AnalysisJobResult(
                asset: prepared.asset,
                input: input,
                generated: generated,
                errorMessage: nil
            )
            return (prepared.index, result)
        } catch {
            let result = AnalysisJobResult(
                asset: prepared.asset,
                input: input,
                generated: nil,
                errorMessage: error.localizedDescription
            )
            return (prepared.index, result)
        }
    }

    private nonisolated static func acquireAnalysisInput(
        for asset: MediaAsset,
        photosWriter: PhotosWriter
    ) async throws -> AnalysisInput {
        if asset.kind == .photo,
           let previewDataSource = photosWriter as? PhotoPreviewDataSource
        {
            if let previewData = try? await previewDataSource.photoPreviewJPEGData(
                id: asset.id,
                maxPixelSize: Self.photoPreviewMaxPixelSize
            ) {
                return .photoPreviewJPEGData(previewData)
            }
        } else if asset.kind == .photo,
                  let previewSource = photosWriter as? PhotoPreviewSource,
                  let previewURL = try? await previewSource.photoPreviewToTemporaryURL(
                      id: asset.id,
                      maxPixelSize: Self.photoPreviewMaxPixelSize
                  )
        {
            return .fileURL(previewURL)
        }

        let exportURL = try await photosWriter.exportAssetToTemporaryURL(id: asset.id, kind: asset.kind)
        return .fileURL(exportURL)
    }

    private nonisolated static func measureStage<T>(
        _ stage: RunTimingStage,
        recorder: RunTimingRecorder,
        operation: () async throws -> T
    ) async throws -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let value = try await operation()
            await recorder.record(
                stage: stage,
                nanoseconds: DispatchTime.now().uptimeNanoseconds - start
            )
            return value
        } catch {
            await recorder.record(
                stage: stage,
                nanoseconds: DispatchTime.now().uptimeNanoseconds - start
            )
            throw error
        }
    }
}
