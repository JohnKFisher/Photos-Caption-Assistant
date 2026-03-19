import AppKit
import Foundation
import SwiftUI

struct ProcessingProgressView: View {
    let progress: RunProgress
    let performance: RunPerformanceStats
    let isRunning: Bool
    let statusMessage: String?
    let summary: RunSummary?
    let liveErrors: [String]
    let lastCompletedItemPreview: CompletedItemPreview?
    var onOpenImmersivePreview: (() -> Void)? = nil

    private var completionFraction: Double {
        guard progress.totalDiscovered > 0 else { return 0 }
        return Double(progress.processed) / Double(progress.totalDiscovered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Progress")
                .font(.headline)

            SwiftUI.ProgressView(value: completionFraction)

            HStack(spacing: 18) {
                stat("Discovered", value: progress.totalDiscovered)
                stat("Processed", value: progress.processed)
                stat("Changed", value: progress.changed)
                stat("Skipped", value: progress.skipped)
                stat("Failed", value: progress.failed)
            }

            if isRunning || progress.processed > 0 {
                HStack(spacing: 18) {
                    metric("Rate", value: rateText)
                    metric("Elapsed", value: Self.formatDuration(seconds: performance.elapsedSeconds))
                    metric("ETA", value: etaText)
                }
            }

            if isRunning {
                if let statusMessage {
                    HStack(spacing: 8) {
                        SwiftUI.ProgressView()
                            .controlSize(.small)
                        Text(statusMessage)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Processing is running. You can cancel between item boundaries.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isRunning || lastCompletedItemPreview != nil {
                if let onOpenImmersivePreview {
                    Button {
                        onOpenImmersivePreview()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text(lastCompletedItemPreview == nil ? "Open immersive view (waiting for first completed item)" : "Open immersive view")
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            let displayedErrors = liveErrors.isEmpty ? (summary?.errors ?? []) : liveErrors
            if !displayedErrors.isEmpty {
                let errorText = Array(displayedErrors.suffix(8))
                    .map { "• \($0)" }
                    .joined(separator: "\n")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Errors")
                        .font(.subheadline.bold())
                    ScrollView {
                        Text(errorText)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 130)
                }
            }

            if let preview = lastCompletedItemPreview {
                Divider()
                Button {
                    onOpenImmersivePreview?()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("Last Completed Item")
                                .font(.subheadline.bold())
                            Text("Click to enlarge")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            previewThumbnail(preview)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(preview.filename)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Text("Caption")
                                    .font(.caption.bold())
                                Text(preview.caption)
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("Keywords")
                                    .font(.caption.bold())
                                Text(preview.keywords.isEmpty ? "(none)" : preview.keywords.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(onOpenImmersivePreview == nil)
            }

            if let diagnostics = summary?.diagnostics {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last Run Timings")
                        .font(.subheadline.bold())

                    Text(diagnosticsSummaryText(diagnostics))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    let topStages = diagnostics.stageTimings
                        .filter { $0.elapsedSeconds > 0.001 }
                        .sorted { lhs, rhs in lhs.elapsedSeconds > rhs.elapsedSeconds }
                        .prefix(4)

                    if !topStages.isEmpty {
                        ForEach(Array(topStages)) { stage in
                            HStack(spacing: 8) {
                                Text(stage.stage)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Text(formatSeconds(stage.elapsedSeconds))
                                    .font(.caption.monospacedDigit())
                            }
                        }

                        Text("Stage totals can exceed wall time because prepare, analyze, write, and preview overlap.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func stat(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.monospacedDigit())
        }
    }

    @ViewBuilder
    private func previewThumbnail(_ preview: CompletedItemPreview) -> some View {
        if let image = makeThumbnail(for: preview) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 132, height: 132)
                .overlay(
                    Text("No Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }

    private var rateText: String {
        guard let itemsPerMinute = performance.itemsPerMinute, itemsPerMinute.isFinite else {
            return "calculating"
        }
        if itemsPerMinute < 1 {
            return String(format: "%.2f items/min", itemsPerMinute)
        }
        return String(format: "%.1f items/min", itemsPerMinute)
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
