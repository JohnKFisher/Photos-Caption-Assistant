import AVFoundation
import CoreGraphics
import Foundation

public enum VideoFrameSamplerError: Error {
    case noFramesExtracted
}

public struct VideoFrameSampler: Sendable {
    public init() {}

    public func sampleFrames(from videoURL: URL, count: Int = 5) async throws -> [CGImage] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw VideoFrameSamplerError.noFramesExtracted
        }

        let frameCount = max(1, count)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let requestedTimes: [CMTime] = (0..<frameCount).map { index in
            if frameCount == 1 {
                return CMTime(seconds: durationSeconds / 2.0, preferredTimescale: 600)
            }
            let progress = Double(index + 1) / Double(frameCount + 1)
            return CMTime(seconds: durationSeconds * progress, preferredTimescale: 600)
        }
        let timeValues = requestedTimes.map { NSValue(time: $0) }

        let images = try await generateFrames(generator: generator, times: timeValues)

        guard !images.isEmpty else {
            throw VideoFrameSamplerError.noFramesExtracted
        }

        return images
    }

    private func generateFrames(
        generator: AVAssetImageGenerator,
        times: [NSValue]
    ) async throws -> [CGImage] {
        if times.isEmpty {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let accumulator = FrameAccumulator(total: times.count)

            generator.generateCGImagesAsynchronously(forTimes: times) { _, image, _, result, _ in
                if let completion = accumulator.record(result: result, image: image) {
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

private enum FrameGenerationCompletion {
    case success([CGImage])
    case failure(Error)
}

private final class FrameAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Int
    private var images: [CGImage] = []
    private var completed = false

    init(total: Int) {
        pending = total
    }

    func record(result: AVAssetImageGenerator.Result, image: CGImage?) -> FrameGenerationCompletion? {
        lock.lock()
        defer { lock.unlock() }

        guard !completed else { return nil }

        if result == .succeeded, let image {
            images.append(image)
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
}
