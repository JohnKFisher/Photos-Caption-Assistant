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
            return AppPresentation.queuedAlbumsTitle
        }
    }

    var summary: String {
        switch self {
        case .library:
            return "Process the full library. Confirmation still appears before wider or heavier runs."
        case .album:
            return "Keep the run tightly scoped by picking a specific album here."
        case .picker:
            return "Hand-pick individual photos or videos with the system picker."
        case .captionWorkflow:
            return "Run a saved album queue from top to bottom with repair checks before start."
        }
    }
}

enum AlbumLoadState: Equatable {
    case loadingNames
    case loadingCounts
    case ready
    case failed(message: String)
}

extension RunTraversalOrder {
    var title: String {
        switch self {
        case .photosOrderFast:
            return "Photos order (recommended - fastest start)"
        case .oldestToNewest:
            return "Oldest to Newest"
        case .newestToOldest:
            return "Newest to Oldest"
        case .random:
            return "Random"
        case .cycle:
            return "Cycle (oldest,newest,random)"
        }
    }
}

enum WorkbenchPalette {
    static let text = Color.primary
    static let muted = Color.secondary
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.12)
    static let border = Color.primary.opacity(0.08)
    static let surface = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let surfaceAlt = Color(nsColor: .underPageBackgroundColor).opacity(0.92)
    static let warningFill = Color.orange.opacity(0.16)
    static let warningText = Color.orange
}

struct WorkbenchCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(WorkbenchPalette.text)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(WorkbenchPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WorkbenchPalette.border, lineWidth: 1)
        )
    }
}

struct WorkbenchNotice: View {
    let text: String
    let fill: Color
    let textColor: Color

    init(
        _ text: String,
        fill: Color = WorkbenchPalette.accentSoft,
        textColor: Color = WorkbenchPalette.muted
    ) {
        self.text = text
        self.fill = fill
        self.textColor = textColor
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension View {
    func workbenchFormControlAppearance() -> some View {
        self
            .tint(WorkbenchPalette.accent)
    }
}

struct RunSetupView: View {
    @Binding var sourceSelection: SourceSelection
    @Binding var selectedAlbumID: String?
    let albums: [AlbumSummary]
    let albumLoadState: AlbumLoadState
    let captionWorkflowQueueRows: [CaptionWorkflowQueueRowState]
    let captionWorkflowStatusMessage: String?

    @Binding var useDateFilter: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var traversalOrder: RunTraversalOrder

    @Binding var overwriteAppOwnedSameOrNewer: Bool
    @Binding var alwaysOverwriteExternalMetadata: Bool

    let pickerSupported: Bool
    let pickerUnsupportedReason: String?
    @Binding var pickerIDs: [String]
    let onCaptionWorkflowAlbumSelectionChanged: (Int, String?) -> Void
    let onAddCaptionWorkflowQueueRow: () -> Void
    let onRemoveCaptionWorkflowQueueRow: (Int) -> Void
    let onMoveCaptionWorkflowQueueRowUp: (Int) -> Void
    let onMoveCaptionWorkflowQueueRowDown: (Int) -> Void

    @State private var pickerItems: [PhotosPickerItem] = []

    private var isAlbumNamesLoading: Bool {
        if case .loadingNames = albumLoadState {
            return true
        }
        return false
    }

    private var isAlbumCountsLoading: Bool {
        if case .loadingCounts = albumLoadState {
            return true
        }
        return false
    }

    private var albumLoadFailureMessage: String? {
        if case let .failed(message) = albumLoadState {
            return message
        }
        return nil
    }

    private var hasUsableAlbumList: Bool {
        !albums.isEmpty
    }

    private var albumPickerPlaceholder: String {
        if isAlbumNamesLoading && !hasUsableAlbumList {
            return "Loading albums…"
        }
        if hasUsableAlbumList {
            return "Choose an album"
        }
        if albumLoadFailureMessage != nil {
            return "Albums unavailable"
        }
        return "No albums found"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sourceCard
            secondaryCards
        }
        .onChange(of: pickerItems, initial: false) { _, newItems in
            pickerIDs = newItems.compactMap(\.itemIdentifier)
        }
    }

    private var sourceCard: some View {
        WorkbenchCard(
            title: "Source",
            subtitle: sourceSelection.summary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                sourceSelectionOptions

                sourceConfiguration
            }
        }
    }

    @ViewBuilder
    private var sourceSelectionOptions: some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 140), spacing: 10),
                    GridItem(.flexible(minimum: 140), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                sourceSelectionOptionButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                sourceSelectionOptionButtons
            }
        }
    }

    private var sourceSelectionOptionButtons: some View {
        ForEach(SourceSelection.allCases) { source in
            Button {
                sourceSelection = source
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WorkbenchPalette.text)
                            .multilineTextAlignment(.leading)

                        Text(source.summary)
                            .font(.footnote)
                            .foregroundStyle(WorkbenchPalette.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: sourceSelection == source ? "largecircle.fill.circle" : "circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(
                            sourceSelection == source
                                ? WorkbenchPalette.accent
                                : WorkbenchPalette.muted.opacity(0.65)
                        )
                        .padding(.top, 2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(sourceSelection == source ? WorkbenchPalette.accentSoft : WorkbenchPalette.surfaceAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            sourceSelection == source ? WorkbenchPalette.accent : WorkbenchPalette.border,
                            lineWidth: sourceSelection == source ? 1.5 : 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var secondaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                captureDateCard
                runRulesCard
            }

            VStack(alignment: .leading, spacing: 16) {
                captureDateCard
                runRulesCard
            }
        }
    }

    private var captureDateCard: some View {
        WorkbenchCard(
            title: "Capture Date Filter",
            subtitle: "Optional scope guardrail before model preparation starts."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Limit by capture date", isOn: $useDateFilter)
                    .workbenchFormControlAppearance()

                if useDateFilter {
                    HStack(alignment: .top, spacing: 14) {
                        dateField(title: "Start", selection: $startDate)
                        dateField(title: "End", selection: $endDate)
                    }
                } else {
                    WorkbenchNotice("All capture dates in the current source remain eligible.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var runRulesCard: some View {
        WorkbenchCard(
            title: "Run Rules"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Processing Order")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WorkbenchPalette.muted)

                    Picker("Order", selection: $traversalOrder) {
                        Text(RunTraversalOrder.photosOrderFast.title).tag(RunTraversalOrder.photosOrderFast)
                        Text(RunTraversalOrder.oldestToNewest.title).tag(RunTraversalOrder.oldestToNewest)
                        Text(RunTraversalOrder.newestToOldest.title).tag(RunTraversalOrder.newestToOldest)
                        Text(RunTraversalOrder.random.title).tag(RunTraversalOrder.random)
                        Text(RunTraversalOrder.cycle.title).tag(RunTraversalOrder.cycle)
                    }
                    .labelsHidden()
                    .workbenchFormControlAppearance()
                }

                Divider()

                Toggle("Overwrite app-owned same/newer metadata", isOn: $overwriteAppOwnedSameOrNewer)
                    .workbenchFormControlAppearance()
                Toggle("Always overwrite non-app metadata (no per-item prompts)", isOn: $alwaysOverwriteExternalMetadata)
                    .workbenchFormControlAppearance()

                WorkbenchNotice(
                    "External metadata stays protected unless you widen the overwrite rule and then confirm it at run start."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var sourceConfiguration: some View {
        switch sourceSelection {
        case .library:
            WorkbenchNotice("Whole-library estimates and confirmation messaging appear in the Run Summary panel.")
        case .album:
            albumSelectionSection
        case .picker:
            if pickerSupported {
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: nil,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        Label("Select Photos or Videos", systemImage: "photo.on.rectangle.angled")
                    }

                    WorkbenchNotice(
                        pickerIDs.isEmpty
                            ? "No picker items selected yet."
                            : "\(pickerIDs.count) photo or video item(s) selected."
                    )
                }
            } else {
                WorkbenchNotice(
                    pickerUnsupportedReason ?? "Picker mode is unavailable on this setup.",
                    fill: WorkbenchPalette.warningFill,
                    textColor: WorkbenchPalette.warningText
                )
            }
        case .captionWorkflow:
            captionWorkflowConfiguration
        }
    }

    private var captionWorkflowConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkbenchNotice("Runs the configured albums in order and validates duplicate or missing selections before start.")

            if let notice = albumLoadingNotice {
                albumLoadingNoticeView(
                    text: notice.text,
                    isWarning: notice.isWarning,
                    showSpinner: notice.showSpinner
                )
            }

            ForEach(Array(captionWorkflowQueueRows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .center, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(WorkbenchPalette.muted)
                        .frame(width: 24, height: 24)
                        .background(WorkbenchPalette.accentSoft)
                        .clipShape(Circle())

                    Picker("", selection: Binding(get: {
                        row.albumID ?? ""
                    }, set: { value in
                        onCaptionWorkflowAlbumSelectionChanged(index, value.isEmpty ? nil : value)
                    })) {
                        if let albumID = row.albumID,
                           !albumID.isEmpty,
                           !albums.contains(where: { $0.id == albumID })
                        {
                            Text("Missing: \(row.savedAlbumName ?? "Unknown Album")")
                                .tag(albumID)
                        }

                        Text(albumPickerPlaceholder).tag("")
                        ForEach(albums) { album in
                            Text(albumLabel(for: album))
                                .tag(album.id)
                        }
                    }
                    .labelsHidden()
                    .workbenchFormControlAppearance()
                    .disabled(!hasUsableAlbumList)

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        queueButton(systemName: "arrow.up", disabled: index == 0) {
                            onMoveCaptionWorkflowQueueRowUp(index)
                        }

                        queueButton(systemName: "arrow.down", disabled: index == captionWorkflowQueueRows.count - 1) {
                            onMoveCaptionWorkflowQueueRowDown(index)
                        }

                        queueButton(
                            systemName: "minus.circle",
                            disabled: captionWorkflowQueueRows.count <= CaptionWorkflowConfiguration.minimumQueueLength
                        ) {
                            onRemoveCaptionWorkflowQueueRow(index)
                        }
                    }
                }
                .padding(12)
                .background(WorkbenchPalette.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack {
                Button("Add Album To Queue", action: onAddCaptionWorkflowQueueRow)
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }

            if let captionWorkflowStatusMessage {
                WorkbenchNotice(
                    captionWorkflowStatusMessage,
                    fill: captionWorkflowStatusMessage.contains("Needs repair") || captionWorkflowStatusMessage.contains("different album")
                        ? WorkbenchPalette.warningFill
                        : WorkbenchPalette.accentSoft,
                    textColor: captionWorkflowStatusMessage.contains("Needs repair") || captionWorkflowStatusMessage.contains("different album")
                        ? WorkbenchPalette.warningText
                        : WorkbenchPalette.muted
                )
            }
        }
    }

    @ViewBuilder
    private func dateField(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchPalette.muted)

            DatePicker(title, selection: selection, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .workbenchFormControlAppearance()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func queueButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .frame(width: 28, height: 28)
    }

    private var albumSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Album")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkbenchPalette.muted)

                if isAlbumNamesLoading || isAlbumCountsLoading {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                }
            }

            Picker("Album", selection: Binding(get: {
                selectedAlbumID ?? ""
            }, set: { value in
                selectedAlbumID = value.isEmpty ? nil : value
            })) {
                Text(albumPickerPlaceholder).tag("")
                ForEach(albums) { album in
                    Text(albumLabel(for: album))
                        .tag(album.id)
                }
            }
            .labelsHidden()
            .workbenchFormControlAppearance()
            .disabled(!hasUsableAlbumList)

            if let notice = albumLoadingNotice {
                albumLoadingNoticeView(
                    text: notice.text,
                    isWarning: notice.isWarning,
                    showSpinner: notice.showSpinner
                )
            }
        }
    }

    private var albumLoadingNotice: (text: String, isWarning: Bool, showSpinner: Bool)? {
        if isAlbumNamesLoading && !hasUsableAlbumList {
            return (
                "Loading album names from Photos. The picker will unlock as soon as names arrive.",
                false,
                true
            )
        }

        if isAlbumCountsLoading && hasUsableAlbumList {
            return (
                "Album names are ready. Finishing counts in the background.",
                false,
                true
            )
        }

        if let message = albumLoadFailureMessage {
            if hasUsableAlbumList {
                return (
                    "Album names are available, but refreshed counts could not be loaded. \(message)",
                    true,
                    false
                )
            }
            return ("Album loading failed. \(message)", true, false)
        }

        if !hasUsableAlbumList {
            return (
                "No albums are available yet. Reload if Photos just opened.",
                true,
                false
            )
        }

        return nil
    }

    private func albumLoadingNoticeView(
        text: String,
        isWarning: Bool,
        showSpinner: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if showSpinner {
                SwiftUI.ProgressView()
                    .controlSize(.small)
            } else if isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(WorkbenchPalette.warningText)
            }

            Text(text)
                .font(.footnote)
                .foregroundStyle(isWarning ? WorkbenchPalette.warningText : WorkbenchPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isWarning ? WorkbenchPalette.warningFill : WorkbenchPalette.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func albumLabel(for album: AlbumSummary) -> String {
        album.itemCount >= 0 ? "\(album.name) (\(album.itemCount))" : album.name
    }
}
