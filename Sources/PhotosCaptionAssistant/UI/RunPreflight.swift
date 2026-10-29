import Foundation

enum RunSetupDefaults {
    static let sourceSelection: SourceSelection = AppSettingsSnapshot.default.defaultSourceSelection
    static let alwaysOverwriteExternalMetadata = AppSettingsSnapshot.default.defaultAlwaysOverwriteExternalMetadata
}

enum RunPreflightCountState: Equatable {
    case loading
    case exact(Int)
    case message(String)
}

struct RunSetupSnapshot: Equatable {
    let sourceSelection: SourceSelection
    let selectedAlbum: AlbumSummary?
    let pickerIDs: [String]
    let captionWorkflowConfiguration: CaptionWorkflowConfiguration
    let useDateFilter: Bool
    let dateRange: CaptureDateRange?
    let overwriteAppOwnedSameOrNewer: Bool
    let alwaysOverwriteExternalMetadata: Bool
}

struct RunPreflightSummary: Equatable {
    let sourceTitle: String
    let sourceDetails: [String]
    let countDescription: String
    let countIsLoading: Bool
    let filterDescription: String?
    let writeDescription: String
    let overwriteDescriptions: [String]
    let modelDescription: String
    let serviceDescription: String
    let blockingReasons: [String]
    let confirmationReasons: [String]
    let confirmationLabel: String?
}

enum RunPreflightSummaryBuilder {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func build(
        snapshot: RunSetupSnapshot,
        capabilities: AppCapabilities,
        countState: RunPreflightCountState
    ) -> RunPreflightSummary {
        let sourceTitle = makeSourceTitle(snapshot: snapshot)
        let sourceDetails = makeSourceDetails(snapshot: snapshot)
        let countDescription = makeCountDescription(snapshot: snapshot, countState: countState)
        let countIsLoading: Bool
        if case .loading = countState {
            countIsLoading = true
        } else {
            countIsLoading = false
        }

        let filterDescription = makeFilterDescription(snapshot: snapshot)
        let overwriteDescriptions = makeOverwriteDescriptions(snapshot: snapshot)
        let blockingReasons = makeBlockingReasons(snapshot: snapshot, capabilities: capabilities)
        let confirmationReasons = makeConfirmationReasons(snapshot: snapshot, capabilities: capabilities)
        let confirmationLabel = makeConfirmationLabel(confirmationReasons: confirmationReasons)

        return RunPreflightSummary(
            sourceTitle: sourceTitle,
            sourceDetails: sourceDetails,
            countDescription: countDescription,
            countIsLoading: countIsLoading,
            filterDescription: filterDescription,
            writeDescription: makeWriteDescription(capabilities: capabilities),
            overwriteDescriptions: overwriteDescriptions,
            modelDescription: makeModelDescription(capabilities: capabilities),
            serviceDescription: makeServiceDescription(capabilities: capabilities),
            blockingReasons: blockingReasons,
            confirmationReasons: confirmationReasons,
            confirmationLabel: confirmationLabel
        )
    }

    private static func makeSourceTitle(snapshot: RunSetupSnapshot) -> String {
        switch snapshot.sourceSelection {
        case .library:
            return "Whole Library"
        case .album:
            if let selectedAlbum = snapshot.selectedAlbum {
                return "Album: \(selectedAlbum.name)"
            }
            return "Album: not selected"
        case .picker:
            return "Photos Picker"
        case .captionWorkflow:
            return AppPresentation.queuedAlbumsTitle
        }
    }

    private static func makeSourceDetails(snapshot: RunSetupSnapshot) -> [String] {
        switch snapshot.sourceSelection {
        case .library:
            return ["Scope: every eligible item currently visible in the library."]
        case .album:
            return ["Scope: only items currently in the selected album."]
        case .picker:
            return [
                "Scope: only items currently selected in Photos Picker.",
                "Selected items: \(snapshot.pickerIDs.count)"
            ]
        case .captionWorkflow:
            let configuredNames = snapshot.captionWorkflowConfiguration.queue.enumerated().map { index, entry in
                let label = "Queue item \(index + 1)"
                let albumName = entry.albumName ?? "Not configured"
                return "\(label): \(albumName)"
            }
            return [
                "Scope: only the configured albums below, processed in queue order."
            ] + ["Queue length: \(snapshot.captionWorkflowConfiguration.queue.count)"] + configuredNames
        }
    }

    private static func makeCountDescription(snapshot: RunSetupSnapshot, countState: RunPreflightCountState) -> String {
        if case .captionWorkflow = snapshot.sourceSelection {
            return "Counts are resolved stage-by-stage during the run for \(AppPresentation.queuedAlbumsTitle), so the exact write scope is not precomputed up front."
        }

        switch countState {
        case .loading:
            return "Estimating the current scope. Final writes may still be lower after filters and overwrite checks."
        case let .exact(count):
            let itemDescription = itemCountDescription(count)
            if snapshot.useDateFilter, snapshot.sourceSelection != .picker {
                return "Exact scope count before capture-date filtering: \(itemDescription). Final writes may be lower after filtering and overwrite checks."
            }
            return "Exact current scope count before overwrite checks: \(itemDescription)."
        case let .message(message):
            return message
        }
    }

    private static func makeFilterDescription(snapshot: RunSetupSnapshot) -> String? {
        guard snapshot.useDateFilter, let dateRange = snapshot.dateRange else {
            return nil
        }
        return "Capture-date filter: \(dateFormatter.string(from: dateRange.start)) to \(dateFormatter.string(from: dateRange.end))."
    }

    private static func makeOverwriteDescriptions(snapshot: RunSetupSnapshot) -> [String] {
        var descriptions: [String] = []
        if snapshot.overwriteAppOwnedSameOrNewer {
            descriptions.append("Metadata already tagged as app-owned at the same or newer logic version will be overwritten.")
        } else {
            descriptions.append("Metadata already tagged as app-owned at the same or newer logic version will be preserved.")
        }

        if snapshot.alwaysOverwriteExternalMetadata {
            descriptions.append("Metadata not tagged as app-owned will be overwritten without per-item prompts.")
        } else {
            descriptions.append("Metadata not tagged as app-owned will require per-item confirmation before overwrite.")
        }

        return descriptions
    }

    private static func makeModelDescription(capabilities: AppCapabilities) -> String {
        switch capabilities.ollamaAvailability {
        case .notInstalled:
            return "Model status: qwen2.5vl:7b cannot be checked until Ollama is installed locally."
        case .installedNotRunning:
            return "Model status: qwen2.5vl:7b will be checked after local Ollama starts."
        case .installedRunningModelMissing:
            return "Model status: qwen2.5vl:7b is not installed locally yet."
        case .ready:
            return "Model status: qwen2.5vl:7b is installed and ready to warm locally."
        case let .failure(reason, _, _):
            return "Model status: \(reason)"
        }
    }

    private static func makeServiceDescription(capabilities: AppCapabilities) -> String {
        switch capabilities.ollamaAvailability {
        case .notInstalled:
            return "Ollama service: not available because Ollama is not installed yet."
        case .installedNotRunning:
            return "Ollama service: not currently reachable; the app may start Ollama locally."
        case .installedRunningModelMissing, .ready:
            return "Ollama service: reachable on http://127.0.0.1:11434."
        case let .failure(reason, _, _):
            return "Ollama service: \(reason)"
        }
    }

    private static func makeBlockingReasons(snapshot: RunSetupSnapshot, capabilities: AppCapabilities) -> [String] {
        var reasons: [String] = []

        if !capabilities.photosIntegrationAvailable {
            switch capabilities.photosAccessState {
            case .limited:
                reasons.append("Allow full Photos library access before starting a write run.")
            case .denied:
                if capabilities.photosRequiresAppleEventsAutomation {
                    reasons.append("Grant Photos automation access before starting a write run.")
                } else {
                    reasons.append("Allow Photos library access in System Settings before starting a write run.")
                }
            case .restricted:
                reasons.append("Photos library access is restricted on this Mac.")
            case .notDetermined:
                if capabilities.photosRequiresAppleEventsAutomation {
                    reasons.append("Grant Photos automation access before starting a write run.")
                } else {
                    reasons.append("Allow Photos library access before starting a write run.")
                }
            case .available:
                if capabilities.photosRequiresAppleEventsAutomation {
                    reasons.append("Grant Photos automation access before starting a write run.")
                }
            }
        }

        if capabilities.ollamaAvailability.requiresInstallBeforeRun {
            reasons.append("Install Ollama locally before starting a run. Use the setup card to open the official download page, then click Re-check Setup.")
        }

        switch snapshot.sourceSelection {
        case .library:
            break
        case .album:
            if snapshot.selectedAlbum == nil {
                reasons.append("Select an album before starting a run.")
            }
        case .picker:
            if snapshot.pickerIDs.isEmpty {
                reasons.append("Select at least one item in Photos Picker mode before starting a run.")
            }
        case .captionWorkflow:
            if snapshot.captionWorkflowConfiguration.queue.count < CaptionWorkflowConfiguration.minimumQueueLength {
                reasons.append("\(AppPresentation.queuedAlbumsTitle) needs at least \(CaptionWorkflowConfiguration.minimumQueueLength) queue items.")
            }
            if !snapshot.captionWorkflowConfiguration.missingQueuePositions.isEmpty {
                reasons.append("Choose an album for each queue item in \(AppPresentation.queuedAlbumsTitle) before starting a run.")
            }
            if !snapshot.captionWorkflowConfiguration.duplicateAlbumIDs.isEmpty {
                reasons.append("Each queue item in \(AppPresentation.queuedAlbumsTitle) must use a different album.")
            }
        }

        return reasons
    }

    private static func makeWriteDescription(capabilities: AppCapabilities) -> String {
        let appRequirement = capabilities.photosRequiresPhotosApp
            ? "Photos.app must stay open during the run."
            : "Photos.app can remain closed during the run."
        let automationRequirement = capabilities.photosRequiresAppleEventsAutomation
            ? " The compatibility backend uses Apple Events automation."
            : " The active backend is native PhotoKit."
        let libraryTarget = capabilities.photosRequiresAppleEventsAutomation
            ? " AppleScript targets the library currently open in Photos.app."
            : " PhotoKit always targets the System Photo Library. Opening another library in Photos.app does not redirect it."
        return "This run will generate captions and keywords locally, then write captions, keywords, and app ownership tags through \(capabilities.photosBackendName). \(appRequirement)\(automationRequirement)\(libraryTarget)"
    }

    private static func makeConfirmationReasons(snapshot: RunSetupSnapshot, capabilities: AppCapabilities) -> [String] {
        var reasons: [String] = []

        if snapshot.sourceSelection == .library {
            let library = capabilities.photosRequiresAppleEventsAutomation
                ? "the library currently open in Photos.app"
                : "the System Photo Library"
            reasons.append("This run will target the whole of \(library), subject to the current filter and overwrite settings.")
        }

        if snapshot.alwaysOverwriteExternalMetadata {
            reasons.append("This run will overwrite metadata not tagged as app-owned without per-item confirmation.")
        }

        return reasons
    }

    private static func makeConfirmationLabel(confirmationReasons: [String]) -> String? {
        guard !confirmationReasons.isEmpty else {
            return nil
        }
        return "Start Run"
    }

    private static func itemCountDescription(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}
