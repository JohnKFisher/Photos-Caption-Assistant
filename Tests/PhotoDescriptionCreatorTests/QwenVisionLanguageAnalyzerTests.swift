import AppKit
import AVFoundation
import XCTest
@testable import PhotoDescriptionCreator

final class QwenVisionLanguageAnalyzerTests: XCTestCase {
    func testPhotoPromptUsesV3Template() {
        let prompt = QwenVisionLanguageAnalyzer.photoPromptV3

        XCTAssertTrue(prompt.hasPrefix("You are generating Apple Photos metadata for one photo."))
        XCTAssertTrue(prompt.contains("Use a present participle phrase with no auxiliary verbs"))
        XCTAssertTrue(prompt.contains("Before output, verify:"))
        XCTAssertFalse(prompt.contains("Return ONLY strict JSON"))
    }

    func testVideoPromptUsesV3Template() {
        let prompt = QwenVisionLanguageAnalyzer.videoPromptV3

        XCTAssertTrue(prompt.hasPrefix("You are generating Apple Photos metadata for one video."))
        XCTAssertTrue(prompt.contains("The provided images are key frames from the same video in time order."))
        XCTAssertTrue(prompt.contains("Describe motion/action, not just a single frame snapshot."))
        XCTAssertFalse(prompt.contains("Return ONLY strict JSON"))
    }

    func testVideoKeyFrameSelectionKeepsChronologicalCoverageAcrossThirds() {
        let selected = QwenVisionLanguageAnalyzer.selectVideoKeyFrames(from: [
            makeFrame(progress: 0.1, color: .white),
            makeFrame(progress: 0.2, color: .white),
            makeFrame(progress: 0.3, color: .black),
            makeFrame(progress: 0.4, color: .white),
            makeFrame(progress: 0.5, color: .white),
            makeFrame(progress: 0.6, color: .systemBlue),
            makeFrame(progress: 0.7, color: .white),
            makeFrame(progress: 0.8, color: .white),
            makeFrame(progress: 0.9, color: .systemGreen)
        ])

        let progresses = selected.map(\.actualProgress)
        XCTAssertEqual(progresses.count, 3)
        XCTAssertTrue(progresses[0] < progresses[1] && progresses[1] < progresses[2])
        XCTAssertTrue(progresses[0] < 0.35)
        XCTAssertTrue(progresses[1] >= 0.35 && progresses[1] < 0.65)
        XCTAssertTrue(progresses[2] >= 0.65)
    }

    func testVideoKeyFrameSelectionPrefersDistinctFramesNearAnchors() {
        let selected = QwenVisionLanguageAnalyzer.selectVideoKeyFrames(from: [
            makeFrame(progress: 0.1, color: .white),
            makeFrame(progress: 0.2, color: .white),
            makeFrame(progress: 0.3, color: .black),
            makeFrame(progress: 0.4, color: .white),
            makeFrame(progress: 0.5, color: .white),
            makeFrame(progress: 0.6, color: .systemRed),
            makeFrame(progress: 0.7, color: .white),
            makeFrame(progress: 0.8, color: .white),
            makeFrame(progress: 0.9, color: .systemBlue)
        ])

        let progresses = selected.map(\.actualProgress)
        XCTAssertEqual(progresses.count, 3)
        XCTAssertEqual(progresses[0], 0.3, accuracy: 0.001)
        XCTAssertEqual(progresses[1], 0.6, accuracy: 0.001)
        XCTAssertEqual(progresses[2], 0.9, accuracy: 0.001)
    }

    private func makeFrame(progress: Double, color: NSColor) -> SampledVideoFrame {
        let time = CMTime(seconds: progress * 10.0, preferredTimescale: 600)
        return SampledVideoFrame(
            image: solidColorImage(color: color),
            requestedTime: time,
            actualTime: time,
            requestedProgress: progress,
            actualProgress: progress
        )
    }

    private func solidColorImage(color: NSColor) -> CGImage {
        let width = 24
        let height = 24
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Failed to create test image context.")
        }

        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            fatalError("Failed to render test image.")
        }
        return image
    }
}
