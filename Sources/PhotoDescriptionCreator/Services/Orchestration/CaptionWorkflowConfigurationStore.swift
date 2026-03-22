import Foundation

actor CaptionWorkflowConfigurationStore {
    private let fileManager: FileManager
    private let stateFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.stateFileURL = appSupport
            .appendingPathComponent("PhotoDescriptionCreator", isDirectory: true)
            .appendingPathComponent("caption_workflow_configuration.json", isDirectory: false)
    }

    func load() -> CaptionWorkflowConfiguration? {
        guard let data = try? Data(contentsOf: stateFileURL) else {
            return nil
        }
        return try? decoder.decode(CaptionWorkflowConfiguration.self, from: data)
    }

    func save(_ configuration: CaptionWorkflowConfiguration) {
        do {
            let parent = stateFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try encoder.encode(configuration)
            try data.write(to: stateFileURL, options: [.atomic])
        } catch {
            return
        }
    }

    func clear() {
        try? fileManager.removeItem(at: stateFileURL)
    }
}
