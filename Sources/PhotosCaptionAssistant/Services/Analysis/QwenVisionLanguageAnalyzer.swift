import AppKit
import CoreGraphics
import Foundation

private enum PromptCatalog {
    static let photoPrompt = loadRequiredPrompt(named: "photoprompt.txt")
    static let videoPrompt = loadRequiredPrompt(named: "videoprompt.txt")

    private static func loadRequiredPrompt(named filename: String) -> String {
        for url in candidateURLs(for: filename) {
            if let prompt = try? String(contentsOf: url, encoding: .utf8) {
                return prompt
            }
        }

        let searchedPaths = candidateURLs(for: filename)
            .map(\.path)
            .joined(separator: "\n - ")
        fatalError("Missing prompt file '\(filename)'. Searched:\n - \(searchedPaths)")
    }

    private static func candidateURLs(for filename: String) -> [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Prompts/\(filename)"))
        }

        var repoRootURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            repoRootURL.deleteLastPathComponent()
        }
        candidates.append(repoRootURL.appendingPathComponent("Prompts/\(filename)"))

        return candidates
    }
}

public struct QwenVisionLanguageAnalyzer: PreparedInputAnalyzer {
    private let frameSampler: VideoFrameSampler
    private let endpointURL: URL
    private let modelName: String
    private let requestTimeoutSeconds: TimeInterval
    private let requestRetryCount: Int
    private let maxImageDimension: CGFloat
    private let jpegCompression: CGFloat
    private let keepAliveDuration = "30m"
    private let generationOptions: [String: Double] = [
        "temperature": 0.2,
        "num_predict": 128
    ]
    static let videoKeyFrameCount = 3
    static let videoCandidateProgresses = VideoFrameSampler.evenlySpacedProgresses(count: 9)
    static let videoTargetProgresses = [0.2, 0.5, 0.8]
    static let photoPrompt = PromptCatalog.photoPrompt
    static let videoPrompt = PromptCatalog.videoPrompt

    public init(
        frameSampler: VideoFrameSampler = VideoFrameSampler(),
        endpointURL: URL = URL(string: "http://127.0.0.1:11434/api/generate")!,
        modelName: String = "qwen2.5vl:7b",
        requestTimeoutSeconds: TimeInterval = 420,
        requestRetryCount: Int = 0,
        maxImageDimension: CGFloat = 1024,
        jpegCompression: CGFloat = 0.82
    ) {
        self.frameSampler = frameSampler
        self.endpointURL = endpointURL
        self.modelName = modelName
        self.requestTimeoutSeconds = max(30, requestTimeoutSeconds)
        self.requestRetryCount = max(0, requestRetryCount)
        self.maxImageDimension = max(512, maxImageDimension)
        self.jpegCompression = min(max(jpegCompression, 0.5), 0.95)
    }

    public func analyze(input: AnalysisInput, kind: MediaKind) async throws -> GeneratedMetadata {
        let preparedPayload = try await prepareAnalysis(input: input, kind: kind)
        return try await analyze(preparedPayload: preparedPayload)
    }

    public func prepareAnalysis(input: AnalysisInput, kind: MediaKind) async throws -> PreparedAnalysisPayload {
        let imageData: [Data]
        let prompt: String

        switch kind {
        case .photo:
            imageData = [try jpegData(from: input)]
            prompt = Self.photoPrompt
        case .video:
            guard case let .fileURL(mediaURL) = input else {
                throw QwenAnalyzerError.invalidResponse("Video analysis requires a file-backed input.")
            }
            let candidateFrames = try await frameSampler.sampledFrames(
                from: mediaURL,
                progresses: Self.videoCandidateProgresses
            )
            let keyFrames = Self.selectVideoKeyFrames(from: candidateFrames)
            imageData = try keyFrames.map { try jpegData(from: $0.image) }
            prompt = Self.videoPrompt
        }

        return PreparedAnalysisPayload(prompt: prompt, images: imageData)
    }

    public func analyze(preparedPayload: PreparedAnalysisPayload) async throws -> GeneratedMetadata {
        let generatedText = try await request(
            prompt: preparedPayload.prompt,
            images: preparedPayload.images
        )
        return try decodeGeneratedMetadata(from: generatedText)
    }

    private func request(prompt: String, images: [Data]) async throws -> String {
        let payload = OllamaGenerateRequest(
            model: modelName,
            prompt: prompt,
            images: images.map { $0.base64EncodedString() },
            stream: false,
            keepAlive: keepAliveDuration,
            options: generationOptions
        )

        var latestTimeoutError: URLError?
        for attempt in 0...requestRetryCount {
            do {
                return try await requestOnce(payload: payload)
            } catch let urlError as URLError where urlError.code == .timedOut {
                latestTimeoutError = urlError
                if attempt < requestRetryCount {
                    let retryDelaySeconds = UInt64(attempt + 1)
                    try? await Task.sleep(nanoseconds: retryDelaySeconds * 1_000_000_000)
                    continue
                }
            } catch let urlError as URLError {
                throw mapNetworkError(urlError)
            }
        }

        if latestTimeoutError != nil {
            throw QwenAnalyzerError.ollamaUnavailable(
                "The request timed out after \(Int(requestTimeoutSeconds))s. Try again; first-run local inference can be slow."
            )
        }

        throw QwenAnalyzerError.ollamaUnavailable("Ollama request failed for an unknown reason.")
    }

    private func requestOnce(payload: OllamaGenerateRequest) async throws -> String {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let responseText = String(data: data, encoding: .utf8) ?? ""
            throw QwenAnalyzerError.ollamaUnavailable(
                "Ollama API request failed. Ensure Ollama is installed and reachable on localhost:11434. \(responseText)"
            )
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        if let apiError = decoded.error, !apiError.isEmpty {
            throw QwenAnalyzerError.ollamaUnavailable(apiError)
        }

        guard let content = decoded.response?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            let reason = decoded.doneReason ?? "unknown"
            throw QwenAnalyzerError.invalidResponse(
                "Ollama returned an empty response (done_reason=\(reason))."
            )
        }

        return content
    }

    private func mapNetworkError(_ error: URLError) -> QwenAnalyzerError {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return .ollamaUnavailable("Unable to reach Ollama at localhost:11434 (\(error.localizedDescription)). If Ollama is not installed yet, install it first from the official download page.")
        default:
            return .ollamaUnavailable("Network error talking to Ollama: \(error.localizedDescription)")
        }
    }

    private func decodeGeneratedMetadata(from text: String) throws -> GeneratedMetadata {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded: QwenOutput

        if let directData = trimmed.data(using: .utf8),
           let direct = try? JSONDecoder().decode(QwenOutput.self, from: directData)
        {
            decoded = direct
        } else if let jsonString = extractJSONObject(from: trimmed),
                  let jsonData = jsonString.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(QwenOutput.self, from: jsonData)
        {
            decoded = parsed
        } else {
            throw QwenAnalyzerError.invalidResponse("Qwen output was not valid JSON.")
        }

        let normalizedCaption = decoded.caption
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var seen = Set<String>()
        let normalizedKeywords = decoded.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { keyword in
                guard !keyword.isEmpty else { return false }
                guard !keyword.hasPrefix(OwnershipTagCodec.logicPrefix),
                      !keyword.hasPrefix(OwnershipTagCodec.enginePrefix)
                else {
                    return false
                }
                return seen.insert(keyword).inserted
            }
            .prefix(10)

        guard !normalizedCaption.isEmpty else {
            throw QwenAnalyzerError.invalidResponse("Qwen output omitted caption text.")
        }

        return GeneratedMetadata(
            caption: normalizedCaption,
            keywords: Array(normalizedKeywords)
        )
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return nil
        }
        guard start <= end else { return nil }
        return String(text[start...end])
    }

    static func selectVideoKeyFrames(from candidates: [SampledVideoFrame]) -> [SampledVideoFrame] {
        let orderedCandidates = candidates.sorted { lhs, rhs in
            if lhs.actualProgress != rhs.actualProgress {
                return lhs.actualProgress < rhs.actualProgress
            }
            return lhs.requestedProgress < rhs.requestedProgress
        }

        guard !orderedCandidates.isEmpty else { return [] }
        guard orderedCandidates.count > videoKeyFrameCount else {
            return Array(orderedCandidates.prefix(videoKeyFrameCount))
        }

        let signatures = orderedCandidates.map { makeLumaSignature(for: $0.image) }
        let boundaries = bucketBoundaries(for: videoTargetProgresses)
        var selectedIndices: [Int] = []
        var usedIndices = Set<Int>()

        for (targetBucketIndex, targetProgress) in videoTargetProgresses.enumerated() {
            let bucketCandidates = orderedCandidates.indices.filter { index in
                !usedIndices.contains(index) &&
                bucketIndex(for: orderedCandidates[index].actualProgress, boundaries: boundaries) == targetBucketIndex
            }

            let candidateIndices = bucketCandidates.isEmpty
                ? orderedCandidates.indices.filter { !usedIndices.contains($0) }
                : bucketCandidates

            guard let bestIndex = bestFrameIndex(
                among: Array(candidateIndices),
                orderedCandidates: orderedCandidates,
                signatures: signatures,
                targetProgress: targetProgress
            ) else {
                continue
            }

            selectedIndices.append(bestIndex)
            usedIndices.insert(bestIndex)
        }

        return selectedIndices
            .sorted { orderedCandidates[$0].actualProgress < orderedCandidates[$1].actualProgress }
            .map { orderedCandidates[$0] }
    }

    private static func bucketBoundaries(for targetProgresses: [Double]) -> [Double] {
        zip(targetProgresses, targetProgresses.dropFirst()).map { ($0 + $1) / 2.0 }
    }

    private static func bucketIndex(for progress: Double, boundaries: [Double]) -> Int {
        boundaries.firstIndex(where: { progress < $0 }) ?? boundaries.count
    }

    private static func bestFrameIndex(
        among candidateIndices: [Int],
        orderedCandidates: [SampledVideoFrame],
        signatures: [[UInt8]?],
        targetProgress: Double
    ) -> Int? {
        candidateIndices.max { lhs, rhs in
            let lhsScore = selectionScore(
                for: lhs,
                orderedCandidates: orderedCandidates,
                signatures: signatures,
                targetProgress: targetProgress
            )
            let rhsScore = selectionScore(
                for: rhs,
                orderedCandidates: orderedCandidates,
                signatures: signatures,
                targetProgress: targetProgress
            )

            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }

            let lhsDistance = abs(orderedCandidates[lhs].actualProgress - targetProgress)
            let rhsDistance = abs(orderedCandidates[rhs].actualProgress - targetProgress)
            if lhsDistance != rhsDistance {
                return lhsDistance > rhsDistance
            }

            return orderedCandidates[lhs].actualProgress > orderedCandidates[rhs].actualProgress
        }
    }

    private static func selectionScore(
        for index: Int,
        orderedCandidates: [SampledVideoFrame],
        signatures: [[UInt8]?],
        targetProgress: Double
    ) -> Double {
        let novelty = noveltyScore(for: index, signatures: signatures)
        let anchorDistance = abs(orderedCandidates[index].actualProgress - targetProgress)
        let anchorScore = 1 - min(1, anchorDistance / 0.25)
        return (novelty * 0.7) + (anchorScore * 0.3)
    }

    private static func noveltyScore(for index: Int, signatures: [[UInt8]?]) -> Double {
        guard let signature = signatures[index] else { return 0 }

        var differences: [Double] = []
        if index > 0, let previous = signatures[index - 1] {
            differences.append(signatureDifference(signature, previous))
        }
        if index + 1 < signatures.count, let next = signatures[index + 1] {
            differences.append(signatureDifference(signature, next))
        }

        guard !differences.isEmpty else { return 0 }
        if differences.count == 1 {
            return differences[0]
        }
        return differences.min() ?? 0
    }

    private static func makeLumaSignature(for image: CGImage, size: Int = 16) -> [UInt8]? {
        let clampedSize = max(4, size)
        var pixels = [UInt8](repeating: 0, count: clampedSize * clampedSize)
        let didRender = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: clampedSize,
                    height: clampedSize,
                    bitsPerComponent: 8,
                    bytesPerRow: clampedSize,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: clampedSize, height: clampedSize))
            return true
        }

        return didRender ? pixels : nil
    }

    private static func signatureDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }

        let totalDifference = zip(lhs.prefix(count), rhs.prefix(count)).reduce(0.0) { partialResult, pair in
            partialResult + abs(Double(pair.0) - Double(pair.1))
        }
        return totalDifference / (Double(count) * 255.0)
    }

    private func jpegData(from input: AnalysisInput) throws -> Data {
        switch input {
        case let .fileURL(imageURL):
            return try jpegData(from: imageURL)
        case let .photoPreviewJPEGData(data):
            return try jpegData(fromImageData: data)
        }
    }

    private func jpegData(from imageURL: URL) throws -> Data {
        if let image = NSImage(contentsOf: imageURL),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            return try encodeJPEG(from: cgImage)
        }

        let rawData = try Data(contentsOf: imageURL)
        return try jpegData(fromImageData: rawData)
    }

    private func jpegData(fromImageData rawData: Data) throws -> Data {
        if let bitmap = NSBitmapImageRep(data: rawData), let cgImage = bitmap.cgImage
        {
            return try encodeJPEG(from: cgImage)
        }

        return rawData
    }

    private func jpegData(from cgImage: CGImage) throws -> Data {
        try encodeJPEG(from: cgImage)
    }

    private func encodeJPEG(from cgImage: CGImage) throws -> Data {
        let resizedImage = resizeIfNeeded(cgImage: cgImage)
        let bitmap = NSBitmapImageRep(cgImage: resizedImage)
        guard
            let jpegData = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: jpegCompression]
            )
        else {
            throw QwenAnalyzerError.invalidResponse("Failed to encode video frame for model input.")
        }
        return jpegData
    }

    private func resizeIfNeeded(cgImage: CGImage) -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        let largestSide = max(width, height)
        guard largestSide > 0 else { return cgImage }

        let scale = min(1, maxImageDimension / CGFloat(largestSide))
        guard scale < 0.999 else { return cgImage }

        let targetWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let targetHeight = max(1, Int((CGFloat(height) * scale).rounded()))

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return cgImage
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? cgImage
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let images: [String]
    let stream: Bool
    let keepAlive: String
    let options: [String: Double]

    private enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case images
        case stream
        case keepAlive = "keep_alive"
        case options
    }
}

private struct OllamaGenerateResponse: Decodable {
    let response: String?
    let error: String?
    let doneReason: String?

    private enum CodingKeys: String, CodingKey {
        case response
        case error
        case doneReason = "done_reason"
    }
}

private struct QwenOutput: Decodable {
    let caption: String
    let keywords: [String]
}

public enum QwenAnalyzerError: Error, LocalizedError {
    case ollamaUnavailable(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .ollamaUnavailable(message):
            return "Qwen/Ollama unavailable: \(message)"
        case let .invalidResponse(message):
            return "Qwen response parsing failed: \(message)"
        }
    }
}
