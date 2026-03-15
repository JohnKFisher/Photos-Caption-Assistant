import Foundation

public struct OllamaBootstrapResult: Sendable, Equatable {
    public let ready: Bool
    public let message: String

    public init(ready: Bool, message: String) {
        self.ready = ready
        self.message = message
    }
}

public actor OllamaManager {
    private let modelName: String
    private let tagsURL: URL
    private let generateURL: URL
    private let keepAliveDuration = "30m"
    // 1x1 transparent PNG so warmup exercises vision input path too.
    private static let warmupImageBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO3Zx0YAAAAASUVORK5CYII="
    private var managedServeProcess: Process?
    private var lastWarmupAt: Date?
    private let ollamaEnvironmentOverrides: [String: String] = [
        "OLLAMA_NUM_PARALLEL": "1",
        "OLLAMA_MAX_LOADED_MODELS": "1",
        "OLLAMA_MAX_QUEUE": "64",
        "OLLAMA_KEEP_ALIVE": "30m",
        "OLLAMA_CONTEXT_LENGTH": "8192",
        "OLLAMA_FLASH_ATTENTION": "1",
        "OLLAMA_KV_CACHE_TYPE": "q8_0",
        "OLLAMA_GPU_OVERHEAD": "1073741824"
    ]

    public init(modelName: String = "qwen2.5vl:7b", baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.modelName = modelName
        self.tagsURL = baseURL.appendingPathComponent("api/tags")
        self.generateURL = baseURL.appendingPathComponent("api/generate")
    }

    public func isModelAvailable() async -> Bool {
        guard let tags = try? await fetchTags(timeout: 4) else {
            return false
        }
        return tags.models.contains { model in
            model.name.lowercased().hasPrefix(modelName.lowercased())
        }
    }

    public func ensureModelReady(
        status: @escaping @Sendable (String) -> Void
    ) async -> OllamaBootstrapResult {
        status("Checking Ollama service...")
        let serviceReachable = await isServiceReachable()

        if !serviceReachable {
            status("Starting Ollama service...")
            do {
                try startManagedServeIfNeeded()
            } catch {
                return OllamaBootstrapResult(
                    ready: false,
                    message: "Unable to start Ollama: \(error.localizedDescription)"
                )
            }

            guard await waitForServiceStartup(timeoutSeconds: 20) else {
                return OllamaBootstrapResult(
                    ready: false,
                    message: "Ollama service did not become ready on localhost:11434."
                )
            }
        }

        if await isModelAvailable() {
            let message = await warmModelIfNeeded(status: status)
            return OllamaBootstrapResult(ready: true, message: message)
        }

        status("Downloading \(modelName) (first run may take several minutes)...")
        do {
            try runPullModel()
        } catch {
            return OllamaBootstrapResult(
                ready: false,
                message: "Model download failed: \(error.localizedDescription)"
            )
        }

        guard await isModelAvailable() else {
            return OllamaBootstrapResult(
                ready: false,
                message: "Model pull completed, but '\(modelName)' was not found."
            )
        }

        let message = await warmModelIfNeeded(status: status)
        return OllamaBootstrapResult(ready: true, message: message)
    }

    private func isServiceReachable() async -> Bool {
        (try? await fetchTags(timeout: 2)) != nil
    }

    private func fetchTags(timeout: TimeInterval) async throws -> OllamaTagsResponse {
        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw OllamaManagerError.serviceUnavailable
        }

        return try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
    }

    private func startManagedServeIfNeeded() throws {
        if let managedServeProcess, managedServeProcess.isRunning {
            return
        }

        guard let executablePath = resolveOllamaExecutablePath() else {
            throw OllamaManagerError.ollamaNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["serve"]
        process.environment = makeProcessEnvironment()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        managedServeProcess = process
    }

    private func waitForServiceStartup(timeoutSeconds: Int) async -> Bool {
        let attempts = max(1, timeoutSeconds * 2)
        for _ in 0..<attempts {
            if await isServiceReachable() {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func runPullModel() throws {
        guard let executablePath = resolveOllamaExecutablePath() else {
            throw OllamaManagerError.ollamaNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["pull", modelName]
        process.environment = makeProcessEnvironment()
        // Avoid pipe back-pressure deadlocks for long pull output.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw OllamaManagerError.modelPullFailed
        }
    }

    private func warmModelIfNeeded(status: @escaping @Sendable (String) -> Void) async -> String {
        if let lastWarmupAt, Date().timeIntervalSince(lastWarmupAt) < 300 {
            let message = "\(modelName) is warm and ready."
            status(message)
            return message
        }

        status("Warming \(modelName)...")
        let success = await sendWarmupRequest(timeout: 90)
        if success {
            lastWarmupAt = Date()
            let message = "\(modelName) is warm and ready."
            status(message)
            return message
        }

        let message = "\(modelName) is ready."
        status(message)
        return message
    }

    private func sendWarmupRequest(timeout: TimeInterval) async -> Bool {
        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OllamaWarmupRequest(
            model: modelName,
            prompt: "Reply with ok.",
            images: [Self.warmupImageBase64],
            stream: false,
            keepAlive: keepAliveDuration,
            options: [
                "temperature": 0.0,
                "num_predict": 1
            ]
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else {
                return false
            }

            if let decoded = try? JSONDecoder().decode(OllamaWarmupResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty
            {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private func resolveOllamaExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama"
        ]

        let fileManager = FileManager.default
        return candidates.first { path in
            fileManager.isExecutableFile(atPath: path)
        }
    }

    private func makeProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in ollamaEnvironmentOverrides {
            environment[key] = value
        }
        return environment
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String
}

private struct OllamaWarmupRequest: Encodable {
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

private struct OllamaWarmupResponse: Decodable {
    let error: String?
}

public enum OllamaManagerError: Error, LocalizedError {
    case ollamaNotInstalled
    case serviceUnavailable
    case modelPullFailed

    public var errorDescription: String? {
        switch self {
        case .ollamaNotInstalled:
            return "Ollama is not installed (expected in /opt/homebrew/bin/ollama or /usr/local/bin/ollama)."
        case .serviceUnavailable:
            return "Ollama service is unavailable."
        case .modelPullFailed:
            return "Ollama could not pull the requested model."
        }
    }
}
