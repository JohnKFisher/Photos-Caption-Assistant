import AppKit
import CoreGraphics
import Foundation

public struct QwenVisionLanguageAnalyzer: Analyzer {
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

    // Keep V3 prompts in source so packaged builds do not depend on loose workspace files.
    static let photoPromptV3 = """
    You are generating Apple Photos metadata for one photo.
    Return ONLY valid JSON in exactly this shape:
    {"caption":"<one sentence factual description>","keywords":["k1","k2","k3"]}

    Rules:

    Caption
    - Caption must be one sentence fragment, <= 20 words, plain factual language.
    - Use a present participle phrase with no auxiliary verbs (no is/are/was), e.g., "two girls biking in a park".
    - No commas, semicolons, em dashes, or parentheses. No ending punctuation.
    - Prefer this structure when possible: count/article + subject (or role) + present participle + setting (if there is room) + up to two distinctive details.
    - Describe only what is clearly visible. Do not guess names, relationships, or private identity traits.
    - If screenshot, use caption starting "screenshot showing" and include keyword "screenshot".
    - If document/whiteboard, use caption "document page showing" or "whiteboard showing" and include keyword "document" or "whiteboard".
    - If photo of a screen (tv/monitor/phone), use caption "screen showing"
    - If photo of a drawing or painting, use caption "drawing showing" or "painting showing"
    - If 1 person, include most-specific visible category (e.g., "girl", "man", "bride", "baby").
    - If 2-5 people, include a count + most-specific visible category (e.g., "two men", "three girls", "four people").
    - If 6+ people, use "group" or "crowd".
    - If mixed categories (adults and children), use count + "people" unless one category clearly dominates.
    - Do not describe attractiveness or subjective traits.
    - Do not infer: health status, disability, pregnancy, religion, ethnicity, nationality, sexuality, political affiliation.
    - Do not read or quote license plates, addresses, emails, or phone numbers, even if visible (you may still say "car" or "street sign").
    - If clothing/signage/posters/text clearly indicate a known character/brand/team/franchise, include that term.
    - Only include specific terms like Star Trek or Mickey Mouse when clearly visible from logos, readable text, or unmistakable imagery.
    - You may name specific locations, buildings, landmarks, or businesses only when confidence is high from clear signage/text or unmistakable visual cues.
    - Role nouns allowed when visually unambiguous: You may use role-based nouns (e.g., bride, groom, wedding party, soldier, firefighter, police officer, graduate) only when clearly indicated by distinctive attire, uniforms, or context objects (e.g., wedding dress/veil/bouquet, military uniform/insignia, turnout gear, police uniform, cap and gown) - If role is not clearly indicated, use generic terms (man/woman/boy/girl/baby/person/group).
    - If uncertain, use broader terms (person, indoor, outdoor, crowd) instead of specific guesses.
    - Include up to two distinctive visible details that improve search, prioritizing unusual objects and distinctive clothing/accessories/colors (e.g., trombone, cowboy hat, orange hat, stroller, wheelchair, guitar). Prefer details that disambiguate similar photos. If needed to stay <= 20 words, drop setting before dropping distinctive details.
    - When visible, include event cues (birthday, graduation, wedding, concert, soccer) and animal/vehicle types (dog, cat, fire truck, airplane) in the caption.

    Keywords
    - Keywords must be 6-12 items, lowercase, unique, search-friendly.
    - Keywords must contain only letters/numbers/spaces (no punctuation). Normalize by removing punctuation.
    - Do not include numeric counts as keywords (counts belong in the caption).
    - Keywords may be 1-3 words max.
    - Use singular forms when possible.
    - Include specific differentiators (character names, distinctive objects, recognizable places/buildings) only when clearly visible.
    - Prefer specific, searchable nouns over generic ones when evidence is clear; if uncertain, use broader terms.
    - When a role noun is used in the caption, include it as a keyword (e.g., bride, soldier, wedding).
    - Aim to include, when visible:
      - 1-2 subjects (person/child/dog/etc.)
      - 1 activity/action (walking, eating, hugging, skating)
      - 1-2 setting/location type (kitchen, beach, stadium, classroom)
      - 1 notable object (balloon, stroller, guitar, laptop)
      - 1 lighting/time (day, night, sunset) or weather (snow, rain)
      - Include 1-2 distinctive details as keywords (notable object and a distinctive clothing/accessory/color phrase like "orange hat") when clearly visible.
      - If readable public text is present (store name, team name, event banner), include 1-2 normalized text keywords.
    - If a category is not evident (e.g., no clear action), replace it with another strong, visible noun (object/scene/text).
    - Do not invent actions; if no clear action, use an object/scene keyword instead of an action keyword
    - Do not include generic filler words like: photo, image, picture, thing, stuff.
    - Do not include reserved/internal tags or prefixes (for example __pdc*_).

    Output
    - Output JSON only. No markdown, no commentary, no extra keys.
    - Before output, verify: caption <= 20 words, one fragment with no ending punctuation, keywords 6-12, all lowercase, unique, no punctuation, no forbidden guesses. Conforms to JSON format.

    Example output:
    {"caption":"two girls wearing green scout vests smiling on playground equipment at dusk","keywords":["girl","scout","playground","smile","outdoor","dusk","park","swing"]}
    """

    static let videoPromptV3 = """
    You are generating Apple Photos metadata for one video.
    The provided images are key frames from the same video in time order.

    Return ONLY valid JSON in exactly this shape:
    {"caption":"<one sentence factual description>","keywords":["k1","k2","k3"]}

    Rules:

    Caption
    - Caption must be one sentence fragment, <= 20 words, plain factual language.
    - Use a present participle phrase with no auxiliary verbs (no is/are/was), e.g., "two girls biking in a park".
    - No commas, semicolons, em dashes, or parentheses. No ending punctuation.
    - Prefer this structure when possible: count/article + subject (or role) + present participle + setting (if there is room) + up to two distinctive details.
    - Describe only what is clearly visible. Do not guess names, relationships, or private identity traits.
    - If screenshot, use caption starting "screenshot showing" and include keyword "screenshot".
    - If document/whiteboard, use caption "document page showing" or "whiteboard showing" and include keyword "document" or "whiteboard".
    - If photo of a screen (tv/monitor/phone), use caption "screen showing"
    - If photo of a drawing or painting, use caption "drawing showing" or "painting showing"
    - If 1 person, include most-specific visible category (e.g., "girl", "man", "bride", "baby").
    - If 2-5 people, include a count + most-specific visible category (e.g., "two men", "three girls", "four people").
    - If 6+ people, use "group" or "crowd".
    - If mixed categories (adults and children), use count + "people" unless one category clearly dominates.
    - Do not describe attractiveness or subjective traits.
    - Do not infer: health status, disability, pregnancy, religion, ethnicity, nationality, sexuality, political affiliation.
    - Do not read or quote license plates, addresses, emails, or phone numbers, even if visible (you may still say "car" or "street sign").
    - If clothing/signage/posters/text clearly indicate a known character/brand/team/franchise, include that term.
    - Only include specific terms like Star Trek or Mickey Mouse when clearly visible from logos, readable text, or unmistakable imagery.
    - You may name specific locations, buildings, landmarks, or businesses only when confidence is high from clear signage/text or unmistakable visual cues.
    - Role nouns allowed when visually unambiguous: You may use role-based nouns (e.g., bride, groom, wedding party, soldier, firefighter, police officer, graduate) only when clearly indicated by distinctive attire, uniforms, or context objects (e.g., wedding dress/veil/bouquet, military uniform/insignia, turnout gear, police uniform, cap and gown) - If role is not clearly indicated, use generic terms (man/woman/boy/girl/baby/person/group).
    - If uncertain, use broader terms (person, indoor, outdoor, crowd) instead of specific guesses.
    - Include up to two distinctive visible details that improve search, prioritizing unusual objects and distinctive clothing/accessories/colors (e.g., trombone, cowboy hat, orange hat, stroller, wheelchair, guitar). Prefer details that disambiguate similar photos. If needed to stay <= 20 words, drop setting before dropping distinctive details.
    - When visible, include event cues (birthday, graduation, wedding, concert, soccer) and animal/vehicle types (dog, cat, fire truck, airplane) in the caption.
    - Describe motion/action, not just a single frame snapshot.

    Keywords
    - Keywords must be 6-12 items, lowercase, unique, search-friendly.
    - Keywords must contain only letters/numbers/spaces (no punctuation). Normalize by removing punctuation.
    - Do not include numeric counts as keywords (counts belong in the caption).
    - Keywords may be 1-3 words max.
    - Use singular forms when possible.
    - Include specific differentiators (character names, distinctive objects, recognizable places/buildings) only when clearly visible.
    - Prefer specific, searchable nouns over generic ones when evidence is clear; if uncertain, use broader terms.
    - When a role noun is used in the caption, include it as a keyword (e.g., bride, soldier, wedding).
    - Aim to include, when visible:
      - 1-2 subjects (person/child/dog/etc.)
      - 1 activity/action (walking, eating, hugging, skating)
      - 1-2 setting/location type (kitchen, beach, stadium, classroom)
      - 1 notable object (balloon, stroller, guitar, laptop)
      - 1 lighting/time (day, night, sunset) or weather (snow, rain)
      - Include 1-2 distinctive details as keywords (notable object and a distinctive clothing/accessory/color phrase like "orange hat") when clearly visible.
      - If readable public text is present (store name, team name, event banner), include 1-2 normalized text keywords.
    - If a category is not evident (e.g., no clear action), replace it with another strong, visible noun (object/scene/text).
    - Do not invent actions; if no clear action, use an object/scene keyword instead of an action keyword
    - Do not include generic filler words like: photo, image, picture, thing, stuff.
    - Do not include reserved/internal tags or prefixes (for example __pdc*_).

    Output
    - Output JSON only. No markdown, no commentary, no extra keys.
    - Before output, verify: caption <= 20 words, one fragment with no ending punctuation, keywords 6-12, all lowercase, unique, no punctuation, no forbidden guesses. Conforms to JSON format.

    Example output:
    {"caption":"two girls wearing green scout vests smiling on playground equipment at dusk","keywords":["girl","scout","playground","smile","outdoor","dusk","park","swing"]}
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
        let imageData: [Data]
        let prompt: String

        switch kind {
        case .photo:
            imageData = [try jpegData(from: mediaURL)]
            prompt = Self.photoPromptV3
        case .video:
            let frames = try await frameSampler.sampleFrames(from: mediaURL, count: 5)
            let keyFrames = Array(frames.prefix(3))
            imageData = try keyFrames.map(jpegData(from:))
            prompt = Self.videoPromptV3
        }

        let generatedText = try await request(prompt: prompt, images: imageData)
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
