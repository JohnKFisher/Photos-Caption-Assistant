import AVFoundation
import CoreGraphics
import Foundation

public enum VideoFrameSamplerError: Error {
    case noFramesExtracted
}

struct SampledVideoFrame: @unchecked Sendable {
    let image: CGImage
    let requestedTime: CMTime
    let actualTime: CMTime
    let requestedProgress: Double
    let actualProgress: Double
}

public struct VideoFrameSampler: Sendable {
    public init() {}

    static func evenlySpacedProgresses(count: Int) -> [Double] {
        let frameCount = max(1, count)
        return (0..<frameCount).map { index in
            if frameCount == 1 {
                return 0.5
            }
            return Double(index + 1) / Double(frameCount + 1)
        }
    }

    public func sampleFrames(from videoURL: URL, count: Int = 5) async throws -> [CGImage] {
        let sampledFrames = try await sampledFrames(from: videoURL, count: count)
        return sampledFrames.map(\.image)
    }

    func sampledFrames(from videoURL: URL, count: Int = 5) async throws -> [SampledVideoFrame] {
        try await sampledFrames(from: videoURL, progresses: Self.evenlySpacedProgresses(count: count))
    }

    func sampledFrames(from videoURL: URL, progresses: [Double]) async throws -> [SampledVideoFrame] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw VideoFrameSamplerError.noFramesExtracted
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let requestedFrames = sanitizedProgresses(progresses).map { progress in
            RequestedVideoFrame(
                requestedTime: CMTime(seconds: durationSeconds * progress, preferredTimescale: 600),
                requestedProgress: progress
            )
        }
        let images = try await generateFrames(
            generator: generator,
            requests: requestedFrames,
            durationSeconds: durationSeconds
        )

        guard !images.isEmpty else {
            throw VideoFrameSamplerError.noFramesExtracted
        }

        return images.sorted { lhs, rhs in
            if lhs.actualProgress != rhs.actualProgress {
                return lhs.actualProgress < rhs.actualProgress
            }
            return lhs.requestedProgress < rhs.requestedProgress
        }
    }

    private func sanitizedProgresses(_ progresses: [Double]) -> [Double] {
        let unclamped = progresses.isEmpty ? [0.5] : progresses
        return unclamped.map { min(max($0, 0.001), 0.999) }
    }

    private func generateFrames(
        generator: AVAssetImageGenerator,
        requests: [RequestedVideoFrame],
        durationSeconds: Double
    ) async throws -> [SampledVideoFrame] {
        if requests.isEmpty {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let accumulator = FrameAccumulator(
                requests: requests,
                durationSeconds: durationSeconds
            )
            let timeValues = requests.map { NSValue(time: $0.requestedTime) }

            generator.generateCGImagesAsynchronously(forTimes: timeValues) { requestedTime, image, actualTime, result, _ in
                if let completion = accumulator.record(
                    requestedTime: requestedTime,
                    actualTime: actualTime,
                    result: result,
                    image: image
                ) {
                    switch completion {
                    case let .success(images):
                        continuation.resume(returning: images)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

private struct RequestedVideoFrame {
    let requestedTime: CMTime
    let requestedProgress: Double
}

private struct FrameTimeKey: Hashable {
    let value: CMTimeValue
    let timescale: CMTimeScale
    let epoch: Int64

    init(_ time: CMTime) {
        value = time.value
        timescale = time.timescale
        epoch = time.epoch
    }
}

private enum FrameGenerationCompletion {
    case success([SampledVideoFrame])
    case failure(Error)
}

private final class FrameAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let requestsByTime: [FrameTimeKey: RequestedVideoFrame]
    private let durationSeconds: Double
    private var pending: Int
    private var images: [SampledVideoFrame] = []
    private var completed = false

    init(requests: [RequestedVideoFrame], durationSeconds: Double) {
        requestsByTime = Dictionary(
            uniqueKeysWithValues: requests.map { (FrameTimeKey($0.requestedTime), $0) }
        )
        self.durationSeconds = durationSeconds
        pending = requests.count
    }

    func record(
        requestedTime: CMTime,
        actualTime: CMTime,
        result: AVAssetImageGenerator.Result,
        image: CGImage?
    ) -> FrameGenerationCompletion? {
        lock.lock()
        defer { lock.unlock() }

        guard !completed else { return nil }

        if result == .succeeded,
           let image,
           let request = requestsByTime[FrameTimeKey(requestedTime)]
        {
            images.append(
                SampledVideoFrame(
                    image: image,
                    requestedTime: request.requestedTime,
                    actualTime: actualTime,
                    requestedProgress: request.requestedProgress,
                    actualProgress: normalizedProgress(for: actualTime, fallback: request.requestedProgress)
                )
            )
        }

        pending -= 1
        guard pending == 0 else {
            return nil
        }

        completed = true
        if images.isEmpty {
            return .failure(VideoFrameSamplerError.noFramesExtracted)
        }
        return .success(images)
    }

    private func normalizedProgress(for time: CMTime, fallback: Double) -> Double {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, durationSeconds > 0 else {
            return fallback
        }
        return min(max(seconds / durationSeconds, 0), 1)
    }
}
