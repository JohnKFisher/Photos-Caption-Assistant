import Foundation

struct AppStoragePaths: Sendable, Equatable {
    static let applicationSupportDirectoryName = "PhotosCaptionAssistant"
    static let legacyApplicationSupportDirectoryName = "PhotoDescriptionCreator"
    static let benchmarkTempDirectoryName = "PhotosCaptionAssistantBenchmarks"
    static let previewTempDirectoryName = "PhotosCaptionAssistantLastCompleted"
    static let photoExportTempDirectoryName = "PhotosCaptionAssistantExports"
    static let videoExportTempDirectoryName = "PhotosCaptionAssistantVideoExports"
    static let photoPreviewTempDirectoryName = "PhotosCaptionAssistantPreviews"
    static let qwenResponseDiagnosticsTempDirectoryName = "PhotosCaptionAssistantQwenDiagnostics"

    let applicationSupportDirectory: URL
    let legacyApplicationSupportDirectory: URL
    let runResumeStateFile: URL
    let legacyRunResumeStateFile: URL
    let captionWorkflowConfigurationFile: URL
    let legacyCaptionWorkflowConfigurationFile: URL
    let benchmarkTempRoot: URL
    let previewTempRoot: URL
    let photoExportTempRoot: URL
    let videoExportTempRoot: URL
    let photoPreviewTempRoot: URL
    let qwenResponseDiagnosticsTempRoot: URL

    static func make(
        fileManager: FileManager = .default,
        applicationSupportBase: URL? = nil,
        temporaryDirectory: URL? = nil
    ) -> AppStoragePaths {
        let baseApplicationSupport = applicationSupportBase ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let applicationSupportDirectory = baseApplicationSupport
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
        let legacyApplicationSupportDirectory = baseApplicationSupport
            .appendingPathComponent(legacyApplicationSupportDirectoryName, isDirectory: true)
        let temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory

        return AppStoragePaths(
            applicationSupportDirectory: applicationSupportDirectory,
            legacyApplicationSupportDirectory: legacyApplicationSupportDirectory,
            runResumeStateFile: applicationSupportDirectory.appendingPathComponent("run_resume_state.json", isDirectory: false),
            legacyRunResumeStateFile: legacyApplicationSupportDirectory.appendingPathComponent("run_resume_state.json", isDirectory: false),
            captionWorkflowConfigurationFile: applicationSupportDirectory.appendingPathComponent(
                "caption_workflow_configuration.json",
                isDirectory: false
            ),
            legacyCaptionWorkflowConfigurationFile: legacyApplicationSupportDirectory.appendingPathComponent(
                "caption_workflow_configuration.json",
                isDirectory: false
            ),
            benchmarkTempRoot: temporaryDirectory.appendingPathComponent(benchmarkTempDirectoryName, isDirectory: true),
            previewTempRoot: temporaryDirectory.appendingPathComponent(previewTempDirectoryName, isDirectory: true),
            photoExportTempRoot: temporaryDirectory.appendingPathComponent(photoExportTempDirectoryName, isDirectory: true),
            videoExportTempRoot: temporaryDirectory.appendingPathComponent(videoExportTempDirectoryName, isDirectory: true),
            photoPreviewTempRoot: temporaryDirectory.appendingPathComponent(photoPreviewTempDirectoryName, isDirectory: true),
            qwenResponseDiagnosticsTempRoot: temporaryDirectory.appendingPathComponent(
                qwenResponseDiagnosticsTempDirectoryName,
                isDirectory: true
            )
        )
    }

    static func contains(_ candidate: URL, within root: URL) -> Bool {
        let normalizedCandidate = candidate.standardizedFileURL.path
        let normalizedRoot = root.standardizedFileURL.path
        return normalizedCandidate == normalizedRoot || normalizedCandidate.hasPrefix(normalizedRoot + "/")
    }
}
