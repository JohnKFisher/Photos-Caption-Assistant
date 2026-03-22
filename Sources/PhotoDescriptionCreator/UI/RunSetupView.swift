import PhotosUI
import SwiftUI

enum SourceSelection: String, CaseIterable, Identifiable {
    case library
    case album
    case picker
    case captionWorkflow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            return "Whole Library"
        case .album:
            return "Album"
        case .picker:
            return "Photos Picker"
        case .captionWorkflow:
            return "Caption Workflow"
        }
    }
}

private extension RunTraversalOrder {
    var title: String {
        switch self {
        case .photosOrderFast:
            return "Photos order (fast start)"
        case .oldestToNewest:
            return "Oldest to Newest"
        case .newestToOldest:
            return "Newest to Oldest"
        case .random:
            return "Random"
        case .cycle:
            return "Cycle"
        }
    }
}

struct RunSetupView: View {
    @Binding var sourceSelection: SourceSelection
    @Binding var selectedAlbumID: String?
    let albums: [AlbumSummary]
    let captionWorkflowStageAlbumIDs: [CaptionWorkflowAlbumStage: String]
    let captionWorkflowStatusMessage: String?
    let captionWorkflowCanAutoFill: Bool

    @Binding var useDateFilter: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var traversalOrder: RunTraversalOrder

    @Binding var overwriteAppOwnedSameOrNewer: Bool
    @Binding var alwaysOverwriteExternalMetadata: Bool

    let pickerSupported: Bool
    let pickerUnsupportedReason: String?
    @Binding var pickerIDs: [String]
    let onCaptionWorkflowAlbumSelectionChanged: (CaptionWorkflowAlbumStage, String?) -> Void
    let onAutoFillCaptionWorkflowAlbums: () -> Void

    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        Form {
            Section("Source") {
                Picker("Selection", selection: $sourceSelection) {
                    ForEach(SourceSelection.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                if sourceSelection == .album {
                    Picker("Album", selection: Binding(get: {
                        selectedAlbumID ?? ""
                    }, set: { value in
                        selectedAlbumID = value.isEmpty ? nil : value
                    })) {
                        Text("Choose an album").tag("")
                        ForEach(albums) { album in
                            Text(album.itemCount >= 0 ? "\(album.name) (\(album.itemCount))" : album.name)
                                .tag(album.id)
                        }
                    }
                }

                if sourceSelection == .picker {
                    if pickerSupported {
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: nil,
                            matching: .any(of: [.images, .videos]),
                            photoLibrary: .shared()
                        ) {
                            Text("Select Photos or Videos")
                        }
                        Text("Selected IDs: \(pickerIDs.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(pickerUnsupportedReason ?? "Picker mode is unavailable on this setup.")
                            .foregroundStyle(.secondary)
                    }
                }

                if sourceSelection == .captionWorkflow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Re-queries these configured albums in order and waits briefly if Photos needs time to update the next stage:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(CaptionWorkflowAlbumStage.allCases, id: \.rawValue) { stage in
                            Picker(stage.rawValue, selection: Binding(get: {
                                captionWorkflowStageAlbumIDs[stage] ?? ""
                            }, set: { value in
                                onCaptionWorkflowAlbumSelectionChanged(stage, value.isEmpty ? nil : value)
                            })) {
                                Text("Choose an album").tag("")
                                ForEach(albums) { album in
                                    Text(album.itemCount >= 0 ? "\(album.name) (\(album.itemCount))" : album.name)
                                        .tag(album.id)
                                }
                            }
                        }

                        if let captionWorkflowStatusMessage {
                            Text(captionWorkflowStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(captionWorkflowStatusMessage.contains("Needs repair") || captionWorkflowStatusMessage.contains("different album")
                                    ? .orange
                                    : .secondary)
                        }

                        Button("Auto-Fill By Stage Names") {
                            onAutoFillCaptionWorkflowAlbums()
                        }
                        .disabled(!captionWorkflowCanAutoFill)
                    }
                }
            }

            Section("Capture Date Filter") {
                Toggle("Limit by capture date", isOn: $useDateFilter)
                if useDateFilter {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                }
            }

            Section("Processing Order") {
                Picker("Order", selection: $traversalOrder) {
                    Text(RunTraversalOrder.photosOrderFast.title).tag(RunTraversalOrder.photosOrderFast)
                    Text(RunTraversalOrder.oldestToNewest.title).tag(RunTraversalOrder.oldestToNewest)
                    Text(RunTraversalOrder.newestToOldest.title).tag(RunTraversalOrder.newestToOldest)
                    Text(RunTraversalOrder.random.title).tag(RunTraversalOrder.random)
                    Text(RunTraversalOrder.cycle.title).tag(RunTraversalOrder.cycle)
                }
            }

            Section("Overwrite Behavior") {
                Toggle("Overwrite app-owned same/newer metadata", isOn: $overwriteAppOwnedSameOrNewer)
                Toggle("Always overwrite non-app metadata (no per-item prompts)", isOn: $alwaysOverwriteExternalMetadata)
            }
        }
        .onChange(of: pickerItems, initial: false) { _, newItems in
            pickerIDs = newItems.compactMap(\ .itemIdentifier)
        }
    }
}
