import AppKit
import Foundation
import SwiftUI

struct ImmersivePreviewView: View {
    private static let captureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private struct LayoutMetrics {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let columnSpacing: CGFloat
        let artworkWidth: CGFloat
        let artworkHeight: CGFloat
        let textColumnWidth: CGFloat
        let contentHeight: CGFloat
        let captionFontSize: CGFloat
    }

    let preview: CompletedItemPreview?
    let progress: RunProgress
    let performance: RunPerformanceStats
    let isRunning: Bool
    @Binding var isPresented: Bool

    private var previewIdentity: String {
        let filePart = preview?.previewFileURL?.path ?? "no-file"
        let namePart = preview?.filename ?? "no-name"
        return "\(filePart)|\(namePart)"
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = Self.layoutMetrics(for: proxy.size)

            ZStack {
                Color.black
                backgroundLayer(metrics: metrics)
                foregroundLayer(metrics: metrics)
                closeButtonLayer
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .ignoresSafeArea()
        .onExitCommand {
            isPresented = false
        }
        .animation(.easeInOut(duration: 0.3), value: previewIdentity)
    }

    private static func layoutMetrics(for size: CGSize) -> LayoutMetrics {
        let horizontalPadding = min(max(size.width * 0.05, 28), 72)
        let verticalPadding = min(max(size.height * 0.06, 24), 56)
        let columnSpacing = min(max(size.width * 0.03, 20), 44)

        let availableWidth = max(size.width - (horizontalPadding * 2) - columnSpacing, 360)
        let availableHeight = max(size.height - (verticalPadding * 2), 260)

        var artworkWidth = min(max(availableWidth * 0.58, 260), 860)
        let artworkHeight = min(max(availableHeight * 0.88, 240), 760)

        var textColumnWidth = max(availableWidth - artworkWidth, 220)
        textColumnWidth = min(textColumnWidth, 680)

        if textColumnWidth < 260 {
            let adjustedArtworkWidth = max(180, availableWidth - 260)
            artworkWidth = min(artworkWidth, adjustedArtworkWidth)
            textColumnWidth = max(availableWidth - artworkWidth, 220)
        }

        let captionFontSize = min(max(size.height * 0.055, 30), 52)

        return LayoutMetrics(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            columnSpacing: columnSpacing,
            artworkWidth: artworkWidth,
            artworkHeight: artworkHeight,
            textColumnWidth: textColumnWidth,
            contentHeight: availableHeight,
            captionFontSize: captionFontSize
        )
    }

    @ViewBuilder
    private func backgroundLayer(metrics _: LayoutMetrics) -> some View {
        if let preview,
           let image = makeDisplayImage(for: preview)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: 72)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.4),
                            Color.black.opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.92)
                .transition(.opacity)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.2),
                    Color(red: 0.05, green: 0.06, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 700
                )
            )
        }
    }

    @ViewBuilder
    private func foregroundLayer(metrics: LayoutMetrics) -> some View {
        if let preview {
            HStack(alignment: .top, spacing: metrics.columnSpacing) {
                artworkPanel(preview, width: metrics.artworkWidth, height: metrics.artworkHeight)
                detailsPanel(preview: preview, metrics: metrics)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .transition(.opacity)
        } else {
            VStack(spacing: 12) {
                Text("No Completed Item Yet")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Start a run and this view will update live as items complete.")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.74))
                if isRunning || progress.processed > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        progressStatsGrid

                        HStack(spacing: 12) {
                            pacePill(title: "Rate", value: rateText)
                            pacePill(title: "Elapsed", value: Self.formatDuration(seconds: performance.elapsedSeconds))
                            pacePill(title: "ETA", value: etaText)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(40)
        }
    }

    private func detailsPanel(preview: CompletedItemPreview, metrics: LayoutMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                Text(preview.filename)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                detailField(title: "Source", value: preview.sourceContext)
                detailField(title: "Captured", value: captureDateText(preview.captureDate))

                if isRunning || progress.processed > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Run Progress")
                            .font(.headline.smallCaps())
                            .foregroundStyle(Color.white.opacity(0.7))

                        progressStatsGrid

                        Text("Run Pace")
                            .font(.headline.smallCaps())
                            .foregroundStyle(Color.white.opacity(0.7))

                        HStack(spacing: 12) {
                            pacePill(title: "Rate", value: rateText)
                            pacePill(title: "Elapsed", value: Self.formatDuration(seconds: performance.elapsedSeconds))
                            pacePill(title: "ETA", value: etaText)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Caption")
                        .font(.headline.smallCaps())
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(preview.caption.isEmpty ? "(empty caption)" : preview.caption)
                        .font(.system(size: metrics.captionFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Keywords")
                        .font(.headline.smallCaps())
                        .foregroundStyle(Color.white.opacity(0.7))
                    keywordGrid(preview.keywords, textColumnWidth: metrics.textColumnWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
        }
        .frame(width: metrics.textColumnWidth, alignment: .topLeading)
        .frame(maxHeight: metrics.contentHeight, alignment: .topLeading)
        .clipped()
    }

    private var closeButtonLayer: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.92))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(.top, 24)
                .padding(.trailing, 24)
            }
            Spacer()
        }
    }

    private func artworkPanel(_ preview: CompletedItemPreview, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let image = makeDisplayImage(for: preview) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 54))
                    Text("No Preview")
                        .font(.headline)
                }
                .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 26, y: 14)
    }

    private func detailField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.smallCaps())
                .foregroundStyle(Color.white.opacity(0.7))
            Text(value.isEmpty ? "(not available)" : value)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func captureDateText(_ captureDate: Date?) -> String {
        guard let captureDate else {
            return ""
        }
        return Self.captureDateFormatter.string(from: captureDate)
    }

    private var progressStatsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 118), spacing: 10)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            progressStat(title: "Discovered", value: progress.totalDiscovered)
            progressStat(title: "Processed", value: progress.processed)
            progressStat(title: "Changed", value: progress.changed)
            progressStat(title: "Skipped", value: progress.skipped)
            progressStat(title: "Failed", value: progress.failed)
        }
    }

    private func progressStat(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))
            Text("\(value)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func keywordGrid(_ keywords: [String], textColumnWidth: CGFloat) -> some View {
        if keywords.isEmpty {
            Text("(none)")
                .font(.title2)
                .foregroundStyle(Color.white.opacity(0.74))
        } else {
            let minimumChipWidth = max(96, min(150, textColumnWidth * 0.34))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minimumChipWidth), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(keywords, id: \.self) { keyword in
                    Text(keyword)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func makeDisplayImage(for preview: CompletedItemPreview) -> NSImage? {
        guard let fileURL = preview.previewFileURL else {
            return nil
        }

        if let image = NSImage(contentsOf: fileURL) {
            return image
        }

        return NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    private func pacePill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
