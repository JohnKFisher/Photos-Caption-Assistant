import AppKit
import SwiftUI

struct ScrollablePanelWindow<Content: View>: View {
    let scrollAxes: Axis.Set
    let minWidth: CGFloat
    let minHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(scrollAxes) {
            content()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: minWidth, minHeight: minHeight, alignment: .topLeading)
    }
}

struct AboutPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppPresentation.appName)
                        .font(.title2.bold())

                    Text(VersionDisplay.appVersionLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(VersionDisplay.logicVersionLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text(AppPresentation.aboutSummary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Copyright")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Copyright © \(AppPresentation.ownerName)")

                Text("GitHub")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Link(destination: AppPresentation.repositoryURL) {
                    Text(AppPresentation.repositoryURL.absoluteString)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct AboutWindowView: View {
    var body: some View {
        ScrollablePanelWindow(scrollAxes: .vertical, minWidth: 420, minHeight: 280) {
            AboutPanelView()
        }
    }
}

struct OllamaSetupCardView: View {
    let isBusy: Bool
    let onOpenDownloadPage: () -> Void
    let onRecheckSetup: () -> Void

    var body: some View {
        WorkbenchCard(
            title: "Ollama Setup",
            subtitle: "Runs stay local-first, and third-party installation remains explicit."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The app does not download or install third-party software automatically. When you choose to continue, it opens the official Ollama macOS download page in your browser so you can install it yourself.")
                    .font(.footnote)
                    .foregroundStyle(WorkbenchPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                WorkbenchNotice("1. Open the official download page.\n2. Install Ollama.\n3. Return here and click Re-check Setup.")

                HStack {
                    Button("Open Ollama Download Page", action: onOpenDownloadPage)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)

                    Button("Re-check Setup", action: onRecheckSetup)
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }

                Text("Installing Ollama and downloading the qwen2.5vl:7b model are separate steps. The model download stays opt-in and is confirmed later.")
                    .font(.caption)
                    .foregroundStyle(WorkbenchPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RunPreflightPanelView: View {
    let summary: RunPreflightSummary

    var body: some View {
        WorkbenchCard(
            title: "Run Summary"
        ) {
            VStack(alignment: .leading, spacing: 9) {
                Text(summary.sourceTitle)
                    .font(.headline)
                    .foregroundStyle(WorkbenchPalette.text)

                if !summary.sourceDetails.isEmpty {
                    ForEach(summary.sourceDetails, id: \.self) { detail in
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(WorkbenchPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                labeledRow("Count", text: summary.countDescription, showSpinner: summary.countIsLoading)

                if let filterDescription = summary.filterDescription {
                    labeledRow("Filter", text: filterDescription)
                }

                labeledRow("Writes", text: summary.writeDescription)

                ForEach(Array(summary.overwriteDescriptions.enumerated()), id: \.offset) { _, description in
                    labeledRow("Overwrite", text: description)
                }

                labeledRow("Model", text: summary.modelDescription)
                labeledRow("Ollama", text: summary.serviceDescription)

                if !summary.blockingReasons.isEmpty {
                    Divider()
                    ForEach(summary.blockingReasons, id: \.self) { reason in
                        callout(
                            text: reason,
                            fill: WorkbenchPalette.warningFill,
                            textColor: WorkbenchPalette.warningText
                        )
                    }
                } else if !summary.confirmationReasons.isEmpty {
                    Divider()
                    ForEach(summary.confirmationReasons, id: \.self) { reason in
                        callout(
                            text: reason,
                            fill: WorkbenchPalette.warningFill,
                            textColor: WorkbenchPalette.warningText
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func labeledRow(_ title: String, text: String, showSpinner: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchPalette.muted)
                .frame(width: 72, alignment: .leading)

            HStack(alignment: .top, spacing: 8) {
                if showSpinner {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                        .padding(.top, 2)
                }
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(WorkbenchPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func callout(text: String, fill: Color, textColor: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DataStoragePanelView: View {
    let storagePaths: AppStoragePaths
    let resumablePendingCount: Int
    let isBusy: Bool
    let onOpenDataFolder: () -> Void
    let onClearSavedRunState: () -> Void

    var body: some View {
        GroupBox("Data & Storage") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Persistent state lives in Application Support. Temporary previews, exports, and diagnostics reports live under the current temporary directory.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Those temporary files stay local to this Mac and may be cleared between runs or after cleanup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                pathRow("Data Folder", storagePaths.applicationSupportDirectory.path)
                pathRow("Resume State", storagePaths.runResumeStateFile.path)
                pathRow("Queued Albums Config", storagePaths.captionWorkflowConfigurationFile.path)
                pathRow("Temp Reports", storagePaths.benchmarkTempRoot.path)
                pathRow("Temp Previews", storagePaths.previewTempRoot.path)

                Text(resumablePendingCount > 0
                    ? "Saved run state currently tracks \(resumablePendingCount) pending item(s)."
                    : "No saved run state is currently stored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Open Data Folder", action: onOpenDataFolder)
                        .buttonStyle(.bordered)

                    Button("Clear Saved Run State", action: onClearSavedRunState)
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }

                Text("Clearing saved run state removes only the resumable pending-ID snapshot. It does not remove your saved \(AppPresentation.queuedAlbumsTitle) configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func pathRow(_ title: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DataStorageWindowView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollablePanelWindow(scrollAxes: [.vertical, .horizontal], minWidth: 560, minHeight: 340) {
            DataStoragePanelView(
                storagePaths: viewModel.currentStoragePaths,
                resumablePendingCount: viewModel.resumablePendingCount,
                isBusy: viewModel.isRunning || viewModel.isPreparingModel,
                onOpenDataFolder: {
                    viewModel.openDataFolder()
                },
                onClearSavedRunState: {
                    Task {
                        await viewModel.clearSavedRunState()
                    }
                }
            )
        }
    }
}

struct DiagnosticsPanelView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        GroupBox("Diagnostics") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Benchmark album override is optional. The identity write probe needs explicit sacrificial/control asset IDs and will prompt before writing anything.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Use the Diagnostics menu to run the scan benchmark and identity write probe after updating the fields below. Reports stay local on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Benchmark Album ID")
                            .font(.caption.weight(.semibold))
                        TextField("Optional AppleScript album ID", text: $viewModel.benchmarkAlbumOverrideID)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Benchmark Album Name")
                            .font(.caption.weight(.semibold))
                        TextField("Optional album label", text: $viewModel.benchmarkAlbumOverrideName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sacrificial Asset ID")
                            .font(.caption.weight(.semibold))
                        TextField("Required for write probe", text: $viewModel.identityProbeSacrificialAssetID)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Control Asset ID")
                            .font(.caption.weight(.semibold))
                        TextField("Required for write probe", text: $viewModel.identityProbeControlAssetID)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Smart Album ID")
                            .font(.caption.weight(.semibold))
                        TextField("Optional expected-removal smart album", text: $viewModel.identityProbeSmartAlbumID)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Smart Album Name")
                            .font(.caption.weight(.semibold))
                        TextField("Optional label", text: $viewModel.identityProbeSmartAlbumName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if let benchmarkSampleIDsText = viewModel.benchmarkSampleIDsText {
                    HStack {
                        Text("Latest Benchmark Sample IDs")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("Use First Two For Write Probe") {
                            viewModel.prefillIdentityProbeFromLatestBenchmark()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isRunningScanBenchmark || viewModel.isRunningIdentityWriteProbe)
                    }

                    ScrollView {
                        Text(benchmarkSampleIDsText)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Run the scan benchmark once and the latest sampled IDs will appear here for copy/paste.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DiagnosticsWindowView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollablePanelWindow(scrollAxes: [.vertical, .horizontal], minWidth: 760, minHeight: 420) {
            DiagnosticsPanelView(viewModel: viewModel)
        }
    }
}
