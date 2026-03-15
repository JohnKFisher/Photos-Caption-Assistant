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
    public var onItemCompleted: (CompletedItemPreview) -> Void
    public var onPendingIDsUpdated: ([String]) -> Void
    public var onError: (String) -> Void
    public var confirmExternalOverwrite: (MediaAsset, ExistingMetadataState) async -> Bool
    public var confirmContinueAfterCheckpoint: (Int) async -> Bool
    public var confirmSafetyPause: (RunSafetyPausePrompt) async -> Bool

    public init(
        onProgress: @escaping (RunProgress) -> Void = { _ in },
        onPreparationProgress: @escaping (Int, Int) -> Void = { _, _ in },
        onItemCompleted: @escaping (CompletedItemPreview) -> Void = { _ in },
        onPendingIDsUpdated: @escaping ([String]) -> Void = { _ in },
        onError: @escaping (String) -> Void = { _ in },
        confirmExternalOverwrite: @escaping (MediaAsset, ExistingMetadataState) async -> Bool = { _, _ in false },
        confirmContinueAfterCheckpoint: @escaping (Int) async -> Bool = { _ in true },
        confirmSafetyPause: @escaping (RunSafetyPausePrompt) async -> Bool = { _ in true }
    ) {
        self.onProgress = onProgress
        self.onPreparationProgress = onPreparationProgress
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

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

protocol PreviewRendering: Sendable {
    func persistPreviewFile(from inputURL: URL, fallbackFilename: String, kind: MediaKind) async -> URL?
}

actor DefaultPreviewRenderer: PreviewRendering {
    private let videoFrameSampler: VideoFrameSampler
    private var lastPreviewFileURL: URL?

    init(videoFrameSampler: VideoFrameSampler) {
        self.videoFrameSampler = videoFrameSampler
    }

    func persistPreviewFile(from inputURL: URL, fallbackFilename: String, kind: MediaKind) async -> URL? {
        let fileManager = FileManager.default
        let previewRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoDescriptionCreatorLastCompleted", isDirectory: true)

        do {
            try fileManager.createDirectory(at: previewRoot, withIntermediateDirectories: true)
            if let lastPreviewFileURL {
                try? fileManager.removeItem(at: lastPreviewFileURL)
            }

            if kind == .video,
               let extractedFrameDestination = await persistVideoPreviewFrame(
                   from: inputURL,
                   previewRoot: previewRoot
               )
            {
                lastPreviewFileURL = extractedFrameDestination
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
            lastPreviewFileURL = destination
            return destination
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
    private struct AnalysisJobResult: Sendable {
        let asset: MediaAsset
        let inputURL: URL?
        let generated: GeneratedMetadata?
        let errorMessage: String?
    }

    private struct PreparationJobResult: Sendable {
        let index: Int
        let asset: MediaAsset
        let inputURL: URL?
        let preparedPayload: PreparedAnalysisPayload?
        let errorMessage: String?
    }

    private struct PendingWrite: Sendable {
        let asset: MediaAsset
        let inputURL: URL
        let generated: GeneratedMetadata
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
    private static let metadataPrefetchWindowSize = 32
    private static let slowOrderWarningThreshold = 5_000
    private static let maxRetainedErrors = 500
    private static let maxRetainedFailedAssets = 2000
    private static let maxPendingPreviewTasks = 2
    private nonisolated static let photoPreviewMaxPixelSize = 2048

    private let photosWriter: PhotosWriter
    private let analyzer: Analyzer
    private let videoFrameSampler: VideoFrameSampler
    private let previewRenderer: any PreviewRendering
    private let logicVersion: LogicVersion
    private let checkpointInterval: Int
    private let photosRefreshPromptInterval: Int
    private let photosMemoryCheckInterval: Int
    private let photosMemoryWarningBytes: UInt64
    private let analysisConcurrency: Int
    private let prepareAheadLimit: Int
    private let writeBatchSize: Int

    private var isCancelled = false

    public convenience init(
        photosWriter: PhotosWriter,
        analyzer: Analyzer,
        videoFrameSampler: VideoFrameSampler = VideoFrameSampler(),
        logicVersion: LogicVersion = .current,
        checkpointInterval: Int = 1000,
        photosRefreshPromptInterval: Int = 500,
        photosMemoryCheckInterval: Int = 40,
        photosMemoryWarningBytes: UInt64 = 20 * 1024 * 1024 * 1024,
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
        checkpointInterval: Int = 1000,
        photosRefreshPromptInterval: Int = 500,
        photosMemoryCheckInterval: Int = 40,
        photosMemoryWarningBytes: UInt64 = 20 * 1024 * 1024 * 1024,
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
        self.checkpointInterval = max(1, checkpointInterval)
        self.photosRefreshPromptInterval = max(1, photosRefreshPromptInterval)
        self.photosMemoryCheckInterval = max(1, photosMemoryCheckInterval)
        self.photosMemoryWarningBytes = max(1, photosMemoryWarningBytes)
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
        defer {
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - runStartedNanoseconds
            Task {
                let summary = await timingRecorder.summary(totalWallNanoseconds: elapsedNs)
                print(summary)
            }
        }

        var progress = RunProgress()
        var errors: [String] = []
        var failedAssets: [MediaAsset] = []
        var nextPhotosRefreshPromptAtChanged = photosRefreshPromptInterval
        var nextPhotosMemoryCheckAtChanged = photosMemoryCheckInterval

        var queuedAssetIDs: [String] = []
        var processedAssetIDs = Set<String>()
        var queueCursor = 0
        var processedSincePendingUpdate = 0

        let targetEngine: EngineTier = .qwen25vl7b

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

        func handlePostChangePromptsIfNeeded() async {
            if progress.changed > 0 && progress.changed.isMultiple(of: checkpointInterval) {
                let shouldContinue = await callbacks.confirmContinueAfterCheckpoint(progress.changed)
                if !shouldContinue {
                    isCancelled = true
                }
            }

            if !isCancelled, progress.changed >= nextPhotosRefreshPromptAtChanged {
                let prompt = RunSafetyPausePrompt(
                    title: "Refresh Photos Before Continuing?",
                    message: "\(progress.changed) items have been changed. To reduce memory pressure, close and reopen Photos now, then click Continue.",
                    confirmLabel: "Continue",
                    cancelLabel: "Stop"
                )
                let shouldContinue = await callbacks.confirmSafetyPause(prompt)
                if !shouldContinue {
                    isCancelled = true
                } else if !(await verifyPhotosStillRunning()) {
                    isCancelled = true
                }
                repeat {
                    nextPhotosRefreshPromptAtChanged += photosRefreshPromptInterval
                } while nextPhotosRefreshPromptAtChanged <= progress.changed
            }

            if !isCancelled, progress.changed >= nextPhotosMemoryCheckAtChanged {
                nextPhotosMemoryCheckAtChanged = progress.changed + photosMemoryCheckInterval
                if let monitor = photosWriter as? PhotosProcessMonitoring,
                   let photosMemoryBytes = await monitor.photosResidentMemoryBytes(),
                   photosMemoryBytes >= photosMemoryWarningBytes
                {
                    let currentGiB = Double(photosMemoryBytes) / Double(1024 * 1024 * 1024)
                    let thresholdGiB = Double(photosMemoryWarningBytes) / Double(1024 * 1024 * 1024)
                    let prompt = RunSafetyPausePrompt(
                        title: "Photos Memory Is High",
                        message: String(
                            format: "Photos is using about %.1f GB (threshold %.1f GB). Close and reopen Photos now, then click Continue.",
                            currentGiB,
                            thresholdGiB
                        ),
                        confirmLabel: "Continue",
                        cancelLabel: "Stop"
                    )
                    let shouldContinue = await callbacks.confirmSafetyPause(prompt)
                    if !shouldContinue {
                        isCancelled = true
                    } else if !(await verifyPhotosStillRunning()) {
                        isCancelled = true
                    }
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

        func enqueuePreview(for write: PendingWrite) async {
            await drainCompletedPreviewTasks()
            let priorTask = pendingPreviewTasks.last
            let previewRenderer = self.previewRenderer

            let task = Task(priority: .utility) { [timingRecorder] in
                _ = await priorTask?.value

                let previewStart = DispatchTime.now().uptimeNanoseconds
                let previewFileURL = await previewRenderer.persistPreviewFile(
                    from: write.inputURL,
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
                        kind: write.asset.kind,
                        previewFileURL: previewFileURL,
                        caption: write.generated.caption,
                        keywords: write.generated.keywords
                    )
                )

                Self.cleanupTemporaryInput(at: write.inputURL)
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
                    await handlePostChangePromptsIfNeeded()
                } else {
                    progress.processed += 1
                    progress.failed += 1
                    let message = writeResult.errorMessage ?? "Metadata write failed."
                    recordError("\(write.asset.filename): \(message)")
                    recordFailedAsset(write.asset)
                    callbacks.onProgress(progress)
                    markAssetProcessed(write.asset.id)
                    Self.cleanupTemporaryInput(at: write.inputURL)
                }
            }
        }

        func runAnalysisJobs(
            for assets: [MediaAsset],
            onOrderedResult: @escaping (AnalysisJobResult) async -> Void
        ) async {
            guard !assets.isEmpty else { return }
            let writer = photosWriter
            let analysisEngine = analyzer
            let pipelineDepth = max(1, analysisConcurrency + prepareAheadLimit)
            let preparedInputs = PreparedInputChannel()
            let analyzedResults = AnalysisResultChannel()

            let producerTask = Task(priority: .userInitiated) {
                await Self.producePreparedInputs(
                    from: assets,
                    photosWriter: writer,
                    preparedAnalyzer: preparedAnalyzer,
                    timingRecorder: timingRecorder,
                    maxInFlight: pipelineDepth,
                    channel: preparedInputs
                )
            }

            let analysisTask = Task(priority: .userInitiated) {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<analysisConcurrency {
                        group.addTask(priority: .userInitiated) {
                            while let prepared = await preparedInputs.receive() {
                                let analyzed = await Self.analyzePreparedInput(
                                    prepared,
                                    analyzer: analysisEngine,
                                    preparedAnalyzer: preparedAnalyzer,
                                    timingRecorder: timingRecorder
                                )
                                await analyzedResults.send(analyzed)
                            }
                        }
                    }
                }
                await analyzedResults.finish()
            }

            var bufferedResults: [Int: AnalysisJobResult] = [:]
            var nextIndexToEmit = 0
            while let (index, result) = await analyzedResults.receive() {
                bufferedResults[index] = result
                while let readyResult = bufferedResults.removeValue(forKey: nextIndexToEmit) {
                    await onOrderedResult(readyResult)
                    nextIndexToEmit += 1
                    if nextIndexToEmit >= assets.count {
                        break
                    }
                }
            }

            _ = await producerTask.result
            _ = await analysisTask.result
        }

        func processAssets(_ assets: ArraySlice<MediaAsset>) async {
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
                var assetsToAnalyze: [MediaAsset] = []
                assetsToAnalyze.reserveCapacity(windowAssets.count)

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
                            assetsToAnalyze.append(asset)
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

                guard !assetsToAnalyze.isEmpty else { return }

                var pendingWrites: [PendingWrite] = []
                pendingWrites.reserveCapacity(analysisConcurrency + prepareAheadLimit + 1)

                func nextWriteChunkSize(for readyCount: Int) -> Int {
                    let untilCheckpoint: Int = {
                        let remainder = progress.changed % checkpointInterval
                        return remainder == 0 ? checkpointInterval : (checkpointInterval - remainder)
                    }()
                    let untilRefresh = max(1, nextPhotosRefreshPromptAtChanged - progress.changed)
                    let untilMemory = max(1, nextPhotosMemoryCheckAtChanged - progress.changed)
                    let safeChunkSize = max(1, min(writeBatchSize, untilCheckpoint, untilRefresh, untilMemory))
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

                await runAnalysisJobs(for: assetsToAnalyze) { result in
                    if let generated = result.generated,
                       let inputURL = result.inputURL
                    {
                        pendingWrites.append(
                            PendingWrite(
                                asset: result.asset,
                                inputURL: inputURL,
                                generated: generated
                            )
                        )
                        await flushPendingWrites()
                    } else {
                        if let inputURL = result.inputURL {
                            Self.cleanupTemporaryInput(at: inputURL)
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
            }

            var windowStart = 0
            let firstWindowEnd = min(
                windowStart + Self.metadataPrefetchWindowSize,
                assetArray.count
            )
            var currentWindowAssets = Array(assetArray[windowStart..<firstWindowEnd])
            var currentPrefetchedMetadata = await prefetchMetadata(for: currentWindowAssets)

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

                if isCancelled {
                    break
                }

                windowStart = nextWindowStart
                currentWindowAssets = nextWindowAssets
                currentPrefetchedMetadata = await nextPrefetchTask?.value ?? [:]
            }
        }

        func processAssetsInBatches(_ assets: [MediaAsset]) async {
            guard !assets.isEmpty else { return }

            var start = assets.startIndex
            while start < assets.endIndex && !isCancelled {
                let end = assets.index(
                    start,
                    offsetBy: Self.processingBatchSize,
                    limitedBy: assets.endIndex
                ) ?? assets.endIndex
                await processAssets(assets[start..<end])
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
                        await processAssets(batch[batch.startIndex..<batch.endIndex])
                    }
                } else {
                    let totalCount = try await incrementalWriter.count(scope: options.source)
                    progress.totalDiscovered = totalCount
                    callbacks.onProgress(progress)

                    if !(await promptForSlowOrderedRunIfNeeded(totalCount: totalCount)) {
                        return RunSummary(progress: progress, errors: errors, failedAssets: failedAssets)
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
                    await processAssetsInBatches(ordered)
                }
            } catch {
                return RunSummary(progress: .init(), errors: ["Failed to enumerate assets: \(error.localizedDescription)"])
            }
        } else {
            if !isFastTraversal,
               let incrementalWriter = photosWriter as? IncrementalPhotosWriter,
               let totalCount = try? await incrementalWriter.count(scope: options.source),
               !(await promptForSlowOrderedRunIfNeeded(totalCount: totalCount)) {
                return RunSummary(progress: progress, errors: errors, failedAssets: failedAssets)
            }

            let assets: [MediaAsset]
            do {
                assets = try await photosWriter.enumerate(scope: options.source, dateRange: options.optionalCaptureDateRange)
            } catch {
                return RunSummary(progress: .init(), errors: ["Failed to enumerate assets: \(error.localizedDescription)"])
            }

            progress.totalDiscovered = assets.count
            callbacks.onProgress(progress)
            if isFastTraversal {
                appendPendingAssets(assets)
                await processAssetsInBatches(assets)
            } else {
                let ordered = orderedAssets(assets, by: options.traversalOrder)
                appendPendingAssets(ordered)
                await processAssetsInBatches(ordered)
            }
        }

        await drainCompletedPreviewTasks(forceWaitForAll: true)
        return RunSummary(progress: progress, errors: errors, failedAssets: failedAssets)
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

    private nonisolated static func cleanupTemporaryInput(at exportURL: URL) {
        let parent = exportURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }

    private nonisolated static func producePreparedInputs(
        from assets: [MediaAsset],
        photosWriter: PhotosWriter,
        preparedAnalyzer: (any PreparedInputAnalyzer)?,
        timingRecorder: RunTimingRecorder,
        maxInFlight: Int,
        channel: PreparedInputChannel
    ) async {
        await withTaskGroup(of: PreparationJobResult.self) { group in
            var nextIndex = 0

            func schedulePreparation(_ index: Int) {
                let asset = assets[index]
                group.addTask(priority: .userInitiated) {
                    await Self.prepareAnalysisInput(
                        index: index,
                        asset: asset,
                        photosWriter: photosWriter,
                        preparedAnalyzer: preparedAnalyzer,
                        timingRecorder: timingRecorder
                    )
                }
            }

            let initialCount = min(maxInFlight, assets.count)
            for _ in 0..<initialCount {
                schedulePreparation(nextIndex)
                nextIndex += 1
            }

            while let prepared = await group.next() {
                await channel.send(prepared)
                if nextIndex < assets.count {
                    schedulePreparation(nextIndex)
                    nextIndex += 1
                }
            }
        }

        await channel.finish()
    }

    private nonisolated static func prepareAnalysisInput(
        index: Int,
        asset: MediaAsset,
        photosWriter: PhotosWriter,
        preparedAnalyzer: (any PreparedInputAnalyzer)?,
        timingRecorder: RunTimingRecorder
    ) async -> PreparationJobResult {
        var inputURL: URL?
        var preparedPayload: PreparedAnalysisPayload?

        do {
            inputURL = try await measureStage(.assetAcquire, recorder: timingRecorder) {
                try await acquireAnalysisInputURL(for: asset, photosWriter: photosWriter)
            }
            if let preparedAnalyzer, let inputURL {
                preparedPayload = try await measureStage(.analysisPrepare, recorder: timingRecorder) {
                    try await preparedAnalyzer.prepareAnalysis(mediaURL: inputURL, kind: asset.kind)
                }
            }
            return PreparationJobResult(
                index: index,
                asset: asset,
                inputURL: inputURL,
                preparedPayload: preparedPayload,
                errorMessage: nil
            )
        } catch {
            return PreparationJobResult(
                index: index,
                asset: asset,
                inputURL: inputURL,
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
        guard let inputURL = prepared.inputURL else {
            let result = AnalysisJobResult(
                asset: prepared.asset,
                inputURL: nil,
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
                    try await analyzer.analyze(mediaURL: inputURL, kind: prepared.asset.kind)
                }
            }
            let result = AnalysisJobResult(
                asset: prepared.asset,
                inputURL: inputURL,
                generated: generated,
                errorMessage: nil
            )
            return (prepared.index, result)
        } catch {
            let result = AnalysisJobResult(
                asset: prepared.asset,
                inputURL: inputURL,
                generated: nil,
                errorMessage: error.localizedDescription
            )
            return (prepared.index, result)
        }
    }

    private nonisolated static func acquireAnalysisInputURL(
        for asset: MediaAsset,
        photosWriter: PhotosWriter
    ) async throws -> URL {
        if asset.kind == .photo,
           let previewSource = photosWriter as? PhotoPreviewSource,
           let previewURL = try? await previewSource.photoPreviewToTemporaryURL(
               id: asset.id,
               maxPixelSize: Self.photoPreviewMaxPixelSize
           )
        {
            return previewURL
        }

        return try await photosWriter.exportAssetToTemporaryURL(id: asset.id)
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
