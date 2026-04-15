import AppKit
import Foundation
import SwiftUI

struct ProcessingProgressView: View {
    let progress: RunProgress
    let performance: RunPerformanceStats
    let isRunning: Bool
    let isOpeningImmersivePreview: Bool
    let statusMessage: String?
    let summary: RunSummary?
    let liveErrors: [String]
    let lastCompletedItemPreview: CompletedItemPreview?
    var onOpenImmersivePreview: (() -> Void)? = nil

    private var completionFraction: Double {
        guard progress.totalDiscovered > 0 else { return 0 }
        return Double(progress.processed) / Double(progress.totalDiscovered)
    }

    private var displayedErrors: [String] {
        liveErrors.isEmpty ? (summary?.errors ?? []) : liveErrors
    }

    var body: some View {
        WorkbenchCard(
            title: "Last Completed Item"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lastCompletedItemPreview?.filename ?? "Waiting for a completed item")
                            .font(.headline)
                            .foregroundStyle(WorkbenchPalette.text)

                        Text(runStatusText)
                            .font(.footnote)
                            .foregroundStyle(WorkbenchPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if isRunning || lastCompletedItemPreview != nil {
                        Button {
                            onOpenImmersivePreview?()
                        } label: {
                            HStack(spacing: 6) {
                                if isOpeningImmersivePreview {
                                    SwiftUI.ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "macwindow")
                                }

                                Text(isOpeningImmersivePreview ? "Opening…" : "Preview Window")
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .disabled(onOpenImmersivePreview == nil || isOpeningImmersivePreview)
                    }
                }

                previewHero

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Run Progress")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WorkbenchPalette.text)
                        Spacer(minLength: 0)
                        Text(completionPercentText)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(WorkbenchPalette.muted)
                    }

                    SwiftUI.ProgressView(value: completionFraction)
                        .controlSize(.large)
                }

                metricsGrid

                if !displayedErrors.isEmpty {
                    errorPanel
                }

                if let diagnostics = summary?.diagnostics {
                    diagnosticsPanel(diagnostics)
                }
            }
        }
    }

    @ViewBuilder
    private var previewHero: some View {
        if let preview = lastCompletedItemPreview {
            Button {
                onOpenImmersivePreview?()
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    previewImage(preview)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        if !preview.sourceContext.isEmpty {
                            labeledText("Source", value: preview.sourceContext, lineLimit: 2)
                        }

                        labeledText("Caption", value: preview.caption.isEmpty ? "(empty caption)" : preview.caption, lineLimit: 3)
                        labeledText(
                            "Keywords",
                            value: preview.keywords.isEmpty ? "(none)" : preview.keywords.joined(separator: ", "),
                            lineLimit: 2
                        )
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkbenchPalette.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onOpenImmersivePreview == nil)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(WorkbenchPalette.accentSoft)
                    .frame(height: 190)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(WorkbenchPalette.accent)
                            Text("Start a run and the latest completed photo or video will appear here.")
                                .font(.footnote)
                                .foregroundStyle(WorkbenchPalette.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    )

                if isRunning {
                    WorkbenchNotice("The preview panel updates live as soon as the first item completes.")
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            metricTile("Discovered", value: "\(progress.totalDiscovered)")
            metricTile("Processed", value: "\(progress.processed)")
            metricTile("Changed", value: "\(progress.changed)")
            metricTile("Failed", value: "\(progress.failed)")
            metricTile("Elapsed", value: Self.formatDuration(seconds: performance.elapsedSeconds))
            metricTile("ETA", value: etaText)
        }
    }

    private var errorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Errors")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WorkbenchPalette.text)

            Text(Array(displayedErrors.suffix(5))
                .map { "• \($0)" }
                .joined(separator: "\n"))
                .font(.footnote.monospaced())
                .foregroundStyle(WorkbenchPalette.warningText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchPalette.warningFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func diagnosticsPanel(_ diagnostics: RunDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Run Timings")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WorkbenchPalette.text)

            Text(diagnosticsSummaryText(diagnostics))
                .font(.caption.monospaced())
                .foregroundStyle(WorkbenchPalette.muted)
                .textSelection(.enabled)

            let topStages = diagnostics.stageTimings
                .filter { $0.elapsedSeconds > 0.001 }
                .sorted { $0.elapsedSeconds > $1.elapsedSeconds }
                .prefix(3)

            if !topStages.isEmpty {
                ForEach(Array(topStages)) { stage in
                    HStack(spacing: 8) {
                        Text(stage.stage)
                            .font(.caption.monospaced())
                            .foregroundStyle(WorkbenchPalette.muted)
                            .frame(width: 110, alignment: .leading)
                        Text(formatSeconds(stage.elapsedSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(WorkbenchPalette.text)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchPalette.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func previewImage(_ preview: CompletedItemPreview) -> some View {
        if let image = makeThumbnail(for: preview) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(WorkbenchPalette.accentSoft)
                .frame(height: 190)
                .overlay(
                    Text("No Preview")
                        .font(.caption)
                        .foregroundStyle(WorkbenchPalette.muted)
                )
        }
    }

    private func makeThumbnail(for preview: CompletedItemPreview) -> NSImage? {
        guard let fileURL = preview.previewFileURL else {
            return nil
        }

        if let image = NSImage(contentsOf: fileURL) {
            return image
        }

        return NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    private func labeledText(_ title: String, value: String, lineLimit: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchPalette.muted)
            Text(value)
                .font(.footnote)
                .foregroundStyle(WorkbenchPalette.text)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchPalette.muted)
            Text(value)
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(WorkbenchPalette.text)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchPalette.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var runStatusText: String {
        if let statusMessage, isRunning {
            return statusMessage
        }
        if isRunning {
            return "Processing is running. You can still cancel between item boundaries."
        }
        if progress.processed > 0 {
            return "The latest completed item stays visible after the run finishes."
        }
        return "Start a run to preview the latest completed item here."
    }

    private var completionPercentText: String {
        "\(Int((completionFraction * 100).rounded()))%"
    }

    private var etaText: String {
        guard let etaSeconds = performance.etaSeconds else {
            return "calculating"
        }
        return Self.formatDuration(seconds: etaSeconds)
    }

    private func diagnosticsSummaryText(_ diagnostics: RunDiagnostics) -> String {
        "wall \(formatSeconds(diagnostics.wallSeconds))  |  analysis x\(diagnostics.analysisConcurrency)  |  prepare-ahead \(diagnostics.prepareAheadLimit)  |  write batch \(diagnostics.writeBatchSize)"
    }

    private func formatSeconds(_ seconds: Double) -> String {
        if seconds >= 10 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.2fs", seconds)
    }

    private static func formatDuration(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
