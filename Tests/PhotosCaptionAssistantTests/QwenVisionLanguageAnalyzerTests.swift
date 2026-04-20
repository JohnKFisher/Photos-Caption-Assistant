import AppKit
import AVFoundation
import XCTest
@testable import PhotosCaptionAssistant

final class QwenVisionLanguageAnalyzerTests: XCTestCase {
    func testPhotoPromptMatchesCurrentPromptFile() throws {
        let prompt = QwenVisionLanguageAnalyzer.photoPrompt
        let promptFile = try loadPromptFile(named: "photoprompt.txt")

        XCTAssertEqual(prompt, promptFile)
        XCTAssertTrue(prompt.hasPrefix("You are generating Apple Photos metadata for one photo."))
        XCTAssertTrue(prompt.contains("Return exactly one JSON object and nothing else."))
        XCTAssertTrue(prompt.contains("Use exactly these two keys and no others"))
        XCTAssertTrue(prompt.contains("Write the caption in English only."))
        XCTAssertTrue(prompt.contains("Write keywords in English only"))
    }

    func testVideoPromptMatchesCurrentPromptFile() throws {
        let prompt = QwenVisionLanguageAnalyzer.videoPrompt
        let promptFile = try loadPromptFile(named: "videoprompt.txt")

        XCTAssertEqual(prompt, promptFile)
        XCTAssertTrue(prompt.hasPrefix("You are generating Apple Photos metadata for one video."))
        XCTAssertTrue(prompt.contains("The provided images are key frames from the same video in chronological order."))
        XCTAssertTrue(prompt.contains("Describe the primary visible action or event across the sequence"))
        XCTAssertTrue(prompt.contains("Write the caption in English only."))
        XCTAssertTrue(prompt.contains("Write keywords in English only"))
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

    func testDecodeGeneratedMetadataRepairsSmartQuotesAndTrailingCommas() throws {
        let analyzer = QwenVisionLanguageAnalyzer()
        let raw = """
        Here is the JSON:
        ```json
        {“caption”:“person standing near a bright window indoors”,“keywords”:[“person”,“window”,“indoor”,“light”,“wall”,“room”,],}
        ```
        """

        let decoded = try analyzer.decodeGeneratedMetadata(from: raw)

        XCTAssertEqual(decoded.caption, "person standing near a bright window indoors")
        XCTAssertEqual(decoded.keywords, ["person", "window", "indoor", "light", "wall", "room"])
    }

    func testDecodeGeneratedMetadataRecoversLaterValidJSONObjectAfterCorruptedPrefix() throws {
        let analyzer = QwenVisionLanguageAnalyzer()
        let raw = """
        {
          "caption": "child building snowman with adult in snowy yard",
          "keywords": ["child", "snowman", "adult", "snow", "yard", "winter", "play", "out
        <|im_start|><|endoftext|> addCriterion
        Sure, here is the JSON object with the provided caption and keywords:

        ```json
        {
          "caption": "child building snowman with adult in snowy yard",
          "keywords": ["child", "snowman", "adult", "snow", "yard", "winter", "play", "outdoor", "fun"]
        }
        ```
        """

        let decoded = try analyzer.decodeGeneratedMetadata(from: raw)

        XCTAssertEqual(decoded.caption, "child building snowman with adult in snowy yard")
        XCTAssertEqual(decoded.keywords, ["child", "snowman", "adult", "snow", "yard", "winter", "play", "outdoor", "fun"])
    }

    func testDecodeGeneratedMetadataPrefersLaterValidJSONObject() throws {
        let analyzer = QwenVisionLanguageAnalyzer()
        let raw = """
        ```json
        {
          "caption": "earlier caption that should be ignored",
          "keywords": ["earlier", "caption"]
        }
        ```

        ```json
        {
          "caption": "later caption that should be used",
          "keywords": ["later", "caption", "preferred"]
        }
        ```
        """

        let decoded = try analyzer.decodeGeneratedMetadata(from: raw)

        XCTAssertEqual(decoded.caption, "later caption that should be used")
        XCTAssertEqual(decoded.keywords, ["later", "caption", "preferred"])
    }

    func testDecodeGeneratedMetadataStillRejectsBrokenAddCriterionOutput() {
        let analyzer = QwenVisionLanguageAnalyzer()
        let raw = """
        {
          "caption": "family taking selfie in forest with heart-shaped sunglasses",
          "keywords": ["family", "selfie", "forest", "heart-shaped", "sunglasses", "nature", "out
        <|im_start|><|im_start|><|im_start|><|im_start|>
         addCriterion("family", "selfie", "forest", "heart-shaped", "sunglasses", "nature", "outdoor", "people", "smile", "outdoor"]
        """

        XCTAssertThrowsError(try analyzer.decodeGeneratedMetadata(from: raw)) { error in
            guard case let QwenAnalyzerError.invalidResponse(message) = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
            XCTAssertEqual(message, "Qwen output was not valid JSON.")
        }
    }

    func testInvalidResponseSavesLocalDiagnosticArtifact() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let analyzer = QwenVisionLanguageAnalyzer(diagnosticsRootURL: root)
        let enriched = analyzer.enrichInvalidResponseError(
            .invalidResponse("Qwen output was not valid JSON."),
            rawResponse: "caption: definitely not json"
        )

        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)

        let payload = try String(contentsOf: files[0], encoding: .utf8)
        XCTAssertTrue(payload.contains("caption: definitely not json"))
        XCTAssertTrue(payload.contains("Qwen output was not valid JSON."))

        guard case let .invalidResponse(message) = enriched else {
            return XCTFail("Expected invalidResponse error")
        }
        XCTAssertTrue(message.contains("Saved raw response to"))
        XCTAssertTrue(message.contains(root.path))
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

    private func loadPromptFile(named filename: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return try String(contentsOf: url.appendingPathComponent("Prompts/\(filename)"), encoding: .utf8)
    }

    private func makeTemporaryDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        return root
    }
}
