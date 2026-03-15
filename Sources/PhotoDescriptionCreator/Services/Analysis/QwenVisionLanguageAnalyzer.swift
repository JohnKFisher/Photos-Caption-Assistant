import AppKit
import CoreGraphics
import Foundation

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

    // Keep the current prompt logic in source so packaged builds do not depend on loose workspace files.
    static let photoPrompt = """
    You are generating Apple Photos metadata for one photo.


    Return exactly one JSON object and nothing else.
    The response must start with { and end with }.
    Use exactly these two keys and no others:
    {"caption":"<caption>","keywords":["k1","k2","k3"]}

    Rules:

    Caption
    - Caption must be a short factual fragment, 3–20 words, plain language, with no ending punctuation.
    - Prefer a present participle phrase for visible actions, e.g., "two girls biking in a park". If the scene is static or action is unclear, use a short factual noun phrase instead.
    - Do not use auxiliary verbs such as is, are, or was.
    - Do not use commas, semicolons, colons, em dashes, quotation marks, or parentheses.
    - Do not end the caption with punctuation.
    - Prefer this order when it fits naturally: count or article + subject or role + action or state + setting + up to two distinctive visible details. Do not force this structure if a simpler factual caption is better.
    - Describe only what is clearly visible. Do not guess names, relationships, identity, intent, mood, or backstory. If uncertain, choose the broader visible term.
    - If the image is a screenshot, start the caption with "screenshot showing" and include keyword "screenshot".
    - If the image is mainly a document or whiteboard, start with "document page showing" or "whiteboard showing" and include the matching keyword.
    - If the photo mainly shows a TV monitor or phone screen, start with "screen showing".
    - If the photo mainly shows a drawing or painting, start with "drawing showing" or "painting showing".
    - If 1 person, use the most-specific clearly visible category that is visually unambiguous (for example girl, boy, man, woman, baby, bride). If that specificity is uncertain, use person.
    - If 2–5 people, use a visible count plus the clearest accurate category, for example "two men" or "four people".
    - If 6 or more people, use "group" or "crowd" unless a more useful broad label is obvious.
    - If ages or categories are mixed or uncertain, use "people".
    - Do not describe attractiveness, personality, emotion, or other subjective traits unless directly and plainly visible from expression or action.
    - Do not infer: health status, disability, pregnancy, religion, ethnicity, nationality, sexuality, political affiliation.
    - Do not read quote or transcribe license plates, addresses, emails, phone numbers, or other personal contact details. You may still describe the object generically, such as car, sign, or building.
    - Include a character brand team or franchise name only when it is clearly visible from readable text logos or unmistakable imagery.
    - Only include specific terms like Star Trek or Mickey Mouse when clearly visible from logos, readable text, or unmistakable imagery.
    - Name a specific location building landmark or business only when confidence is high from clear signage readable text or unmistakable visual cues. Otherwise use a broader place term.
    - Use role-based nouns such as bride groom graduate firefighter police officer or soldier only when visually unambiguous from clothing uniform props or setting. Otherwise use generic terms such as person man woman boy girl baby group.
    - If uncertain between a specific label and a broader label, choose the broader label.
    - Include up to two distinctive visible details that improve search, prioritizing unusual objects and distinctive clothing accessories or colors. Prefer details that help distinguish this image from similar ones. If needed to stay within 20 words, drop less important setting words before dropping strong distinctive details.
    - When clearly visible, include useful event cues such as birthday graduation wedding concert or soccer, and include specific animal or vehicle types when clear.


    Keywords
    - Keywords must contain 6 to 12 unique lowercase search-friendly items
    - Each keyword may contain only lowercase letters numbers and spaces. Remove punctuation rather than replacing it with symbols.
    - Do not include numeric counts as keywords (counts belong in the caption).
    - Keywords should usually be 1 to 3 words, but 4 words are allowed for strong searchable names or place phrases.
    - Use singular nouns when that still sounds natural and search-friendly.
    - Include specific differentiators such as character names distinctive objects or recognizable places only when clearly visible.
    - Prefer specific searchable nouns when evidence is clear. If confidence is not high, use broader terms.
    - When a role noun is used in the caption, include it as a keyword (e.g., bride, soldier, wedding).
    - When visible, try to cover several of these keyword types:
    	- subject
    	- action
    	- setting
    	- notable object
    	- time, lighting, or weather
    	- one or two distinctive details
    	- normalized public text when clearly readable
    - If a category is not evident (e.g., no clear action), replace it with another strong, visible noun (object/scene/text).
    - Do not invent actions; if no clear action, use an object/scene keyword instead of an action keyword
    - Do not include generic filler words like: photo, image, picture, thing, stuff.
    - Do not include reserved/internal tags or prefixes (for example __pdc*_).

    Output
    - Output exactly one JSON object. Do not output markdown code fences, prose, labels, notes, or extra keys. The response must be parseable by a strict JSON parser.
    - Before finalizing, verify all of the following:
    	- response starts with { and ends with }
    	- exactly two keys: "caption" and "keywords"
    	- caption is a string
    	- keywords is an array of strings
    	- no trailing commas
    	- caption is 3 to 20 words
    	- caption has no ending punctuation
    	- keywords contains 6 to 12 unique lowercase items
    	- each keyword uses only letters numbers and spaces
    - If you cannot confidently produce all fields, still output valid JSON using the broadest accurate caption and keywords rather than any explanatory text.
    - If your first draft would not be valid JSON, silently correct it and output only the corrected JSON.

    Example output:
    {"caption":"two girls wearing green scout vests smiling on playground equipment at dusk","keywords":["girl","scout","playground","smile","outdoor","dusk","park","swing"]}

    Final instruction:
    Output exactly one JSON object and nothing else.
    Do not output markdown.
    Do not output explanations.
    Do not output code fences.
    The response must be valid strict JSON parseable by a standard JSON parser.
    """

    static let videoPrompt = """
    You are generating Apple Photos metadata for one video.
    The provided images are key frames from the same video in chronological order.

    Return exactly one JSON object and nothing else.
    The response must start with { and end with }.
    Use exactly these two keys and no others:
    {"caption":"<caption>","keywords":["k1","k2","k3"]}

    Rules:

    Caption
    - Caption must be a short factual fragment, 3–20 words, plain language, with no ending punctuation.
    - Prefer a present participle phrase for visible actions, e.g., "two girls biking in a park". If the scene is static or action is unclear, use a short factual noun phrase instead.
    - Do not use auxiliary verbs such as is, are, or was.
    - Do not use commas, semicolons, colons, em dashes, quotation marks, or parentheses.
    - Do not end the caption with punctuation.
    - Prefer this order when it fits naturally: count or article + subject or role + action or state + setting + up to two distinctive visible details. Do not force this structure if a simpler factual caption is better.
    - Describe only what is clearly visible. Do not guess names, relationships, identity, intent, mood, or backstory. If uncertain, choose the broader visible term.
    - If the image is a screenshot, start the caption with "screenshot showing" and include keyword "screenshot".
    - If the image is mainly a document or whiteboard, start with "document page showing" or "whiteboard showing" and include the matching keyword.
    - If the photo mainly shows a TV monitor or phone screen, start with "screen showing".
    - If the photo mainly shows a drawing or painting, start with "drawing showing" or "painting showing".
    - If 1 person, use the most-specific clearly visible category that is visually unambiguous (for example girl, boy, man, woman, baby, bride). If that specificity is uncertain, use person.
    - If 2–5 people, use a visible count plus the clearest accurate category, for example "two men" or "four people".
    - If 6 or more people, use "group" or "crowd" unless a more useful broad label is obvious.
    - If ages or categories are mixed or uncertain, use "people".
    - Do not describe attractiveness, personality, emotion, or other subjective traits unless directly and plainly visible from expression or action.
    - Do not infer: health status, disability, pregnancy, religion, ethnicity, nationality, sexuality, political affiliation.
    - Do not read quote or transcribe license plates, addresses, emails, phone numbers, or other personal contact details. You may still describe the object generically, such as car, sign, or building.
    - Include a character brand team or franchise name only when it is clearly visible from readable text logos or unmistakable imagery.
    - Only include specific terms like Star Trek or Mickey Mouse when clearly visible from logos, readable text, or unmistakable imagery.
    - Name a specific location building landmark or business only when confidence is high from clear signage readable text or unmistakable visual cues. Otherwise use a broader place term.
    - Use role-based nouns such as bride groom graduate firefighter police officer or soldier only when visually unambiguous from clothing uniform props or setting. Otherwise use generic terms such as person man woman boy girl baby group.
    - If uncertain between a specific label and a broader label, choose the broader label.
    - Include up to two distinctive visible details that improve search, prioritizing unusual objects and distinctive clothing accessories or colors. Prefer details that help distinguish this image from similar ones. If needed to stay within 20 words, drop less important setting words before dropping strong distinctive details.
    - When clearly visible, include useful event cues such as birthday graduation wedding concert or soccer, and include specific animal or vehicle types when clear.
    - Describe the primary visible action or event across the sequence, not just one isolated frame. If the action changes, summarize the dominant action visible for most of the clip.



    Keywords
    - Keywords must contain 6 to 12 unique lowercase search-friendly items
    - Each keyword may contain only lowercase letters numbers and spaces. Remove punctuation rather than replacing it with symbols.
    - Do not include numeric counts as keywords (counts belong in the caption).
    - Keywords should usually be 1 to 3 words, but 4 words are allowed for strong searchable names or place phrases.
    - Use singular nouns when that still sounds natural and search-friendly.
    - Include specific differentiators such as character names distinctive objects or recognizable places only when clearly visible.
    - Prefer specific searchable nouns when evidence is clear. If confidence is not high, use broader terms.
    - When a role noun is used in the caption, include it as a keyword (e.g., bride, soldier, wedding).
    - When visible, try to cover several of these keyword types:
    	- subject
    	- action
    	- setting
    	- notable object
    	- time, lighting, or weather
    	- one or two distinctive details
    	- normalized public text when clearly readable
    - If a category is not evident (e.g., no clear action), replace it with another strong, visible noun (object/scene/text).
    - Do not invent actions; if no clear action, use an object/scene keyword instead of an action keyword
    - Do not include generic filler words like: photo, image, picture, thing, stuff.
    - Do not include reserved/internal tags or prefixes (for example __pdc*_).
    - For video keywords, prioritize recurring subjects actions and settings over brief transient details.

    Output
    - Output exactly one JSON object. Do not output markdown code fences, prose, labels, notes, or extra keys. The response must be parseable by a strict JSON parser.
    - Before finalizing, verify all of the following:
    	- response starts with { and ends with }
    	- exactly two keys: "caption" and "keywords"
    	- caption is a string
    	- keywords is an array of strings
    	- no trailing commas
    	- caption is 3 to 20 words
    	- caption has no ending punctuation
    	- keywords contains 6 to 12 unique lowercase items
    	- each keyword uses only letters numbers and spaces
    - If you cannot confidently produce all fields, still output valid JSON using the broadest accurate caption and keywords rather than any explanatory text.
    - If your first draft would not be valid JSON, silently correct it and output only the corrected JSON.

    Example output:
    {"caption":"two girls wearing green scout vests smiling on playground equipment at dusk","keywords":["girl","scout","playground","smile","outdoor","dusk","park","swing"]}

    Final instruction:
    Output exactly one JSON object and nothing else.
    Do not output markdown.
    Do not output explanations.
    Do not output code fences.
    The response must be valid strict JSON parseable by a standard JSON parser.
    """

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

    public func analyze(mediaURL: URL, kind: MediaKind) async throws -> GeneratedMetadata {
        let preparedPayload = try await prepareAnalysis(mediaURL: mediaURL, kind: kind)
        return try await analyze(preparedPayload: preparedPayload)
    }

    public func prepareAnalysis(mediaURL: URL, kind: MediaKind) async throws -> PreparedAnalysisPayload {
        let imageData: [Data]
        let prompt: String

        switch kind {
        case .photo:
            imageData = [try jpegData(from: mediaURL)]
            prompt = Self.photoPrompt
        case .video:
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
                "Ollama API request failed. Ensure Ollama is running on localhost:11434. \(responseText)"
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
            return .ollamaUnavailable("Unable to reach Ollama at localhost:11434 (\(error.localizedDescription)).")
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

    private func jpegData(from imageURL: URL) throws -> Data {
        if let image = NSImage(contentsOf: imageURL),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            return try encodeJPEG(from: cgImage)
        }

        let rawData = try Data(contentsOf: imageURL)
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
