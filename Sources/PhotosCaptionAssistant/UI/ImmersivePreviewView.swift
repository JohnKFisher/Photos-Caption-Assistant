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

    private struct OverlayMetrics {
        let outerInset: CGFloat
        let hudHeight: CGFloat
        let hudHorizontalPadding: CGFloat
        let hudVerticalPadding: CGFloat
        let dockBottomInset: CGFloat
        let dockHeight: CGFloat
        let dockHorizontalPadding: CGFloat
        let dockVerticalPadding: CGFloat
        let dockSectionSpacing: CGFloat
        let utilityWidth: CGFloat
        let utilitySectionSpacing: CGFloat
        let titleFontSize: CGFloat
        let subtitleFontSize: CGFloat
        let sectionLabelFontSize: CGFloat
        let captionFontSize: CGFloat
        let compactCaptionFontSize: CGFloat
        let minimumCaptionFontSize: CGFloat
        let fullProgressCardWidth: CGFloat
        let compactProgressCardWidth: CGFloat
        let keywordStyle: ImmersiveKeywordChipLayout.Style

        var captionRegionHeight: CGFloat {
            max(72, dockHeight - (dockVerticalPadding * 2) - 12)
        }
    }

    private struct ProgressCardDisplay: Identifiable {
        let id: String
        let title: String
        let value: String
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
            let overlayMetrics = Self.overlayMetrics(for: proxy.size)

            ZStack {
                Color.black
                backgroundLayer

                if let preview {
                    previewForeground(preview: preview, metrics: overlayMetrics)
                        .transition(.opacity)
                } else {
                    emptyStateForeground
                    closeButtonLayer
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .ignoresSafeArea()
        .onExitCommand {
            isPresented = false
        }
        .animation(.easeInOut(duration: 0.3), value: previewIdentity)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let preview,
           let image = makeDisplayImage(for: preview)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .transition(.opacity)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.20),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
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

    private func previewForeground(preview: CompletedItemPreview, metrics: OverlayMetrics) -> some View {
        VStack(spacing: 0) {
            topHUD(preview: preview, metrics: metrics)
                .padding(.top, metrics.outerInset)
                .padding(.horizontal, metrics.outerInset)

            Spacer(minLength: 0)

            bottomDock(preview: preview, metrics: metrics)
                .padding(.horizontal, metrics.outerInset)
                .padding(.bottom, metrics.dockBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateForeground: some View {
        VStack(spacing: 12) {
            Text("No Completed Item Yet")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Start a run and this view will update live as items complete.")
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.74))

            if showsRunPerformance {
                VStack(alignment: .leading, spacing: 12) {
                    progressStatsGrid

                    HStack(spacing: 12) {
                        legacyPacePill(title: "Rate", value: rateText)
                        legacyPacePill(title: "Elapsed", value: Self.formatDuration(seconds: performance.elapsedSeconds))
                        legacyPacePill(title: "ETA", value: etaText)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
    }

    private func topHUD(preview: CompletedItemPreview, metrics: OverlayMetrics) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(preview.filename)
                    .font(.system(size: metrics.titleFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                let subtitle = overlaySubtitle(for: preview)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: metrics.subtitleFontSize, weight: .semibold))
                        .foregroundStyle(Self.secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsRunPerformance {
                ViewThatFits(in: .horizontal) {
                    progressCards(compact: false, cardWidth: metrics.fullProgressCardWidth)
                    progressCards(compact: true, cardWidth: metrics.compactProgressCardWidth)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            integratedCloseButton
        }
        .padding(.horizontal, metrics.hudHorizontalPadding)
        .padding(.vertical, metrics.hudVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.hudHeight, alignment: .leading)
        .background(panelBackground(cornerRadius: 24, fillOpacity: 0.92))
    }

    private func bottomDock(preview: CompletedItemPreview, metrics: OverlayMetrics) -> some View {
        HStack(alignment: .top, spacing: metrics.dockSectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Caption", size: metrics.sectionLabelFontSize)
                captionText(preview.caption, metrics: metrics)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(Self.dividerColor.opacity(0.45))
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: metrics.utilitySectionSpacing) {
                if showsRunPerformance {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Run Pace", size: metrics.sectionLabelFontSize)
                        pacePillsRow()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Keywords", size: metrics.sectionLabelFontSize)
                    keywordsView(preview.keywords, metrics: metrics)
                }
            }
            .frame(width: metrics.utilityWidth, alignment: .topLeading)
        }
        .padding(.horizontal, metrics.dockHorizontalPadding)
        .padding(.vertical, metrics.dockVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.dockHeight, maxHeight: metrics.dockHeight, alignment: .topLeading)
        .background(panelBackground(cornerRadius: 28, fillOpacity: 0.89))
    }

    private func captionText(_ caption: String, metrics: OverlayMetrics) -> some View {
        let displayCaption = caption.isEmpty ? "(empty caption)" : caption

        return ViewThatFits(in: .vertical) {
            captionCandidate(displayCaption, size: metrics.captionFontSize, lineLimit: 2)
            captionCandidate(displayCaption, size: metrics.compactCaptionFontSize, lineLimit: 2)
            captionCandidate(displayCaption, size: metrics.minimumCaptionFontSize, lineLimit: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: metrics.captionRegionHeight, alignment: .topLeading)
    }

    private func captionCandidate(_ caption: String, size: CGFloat, lineLimit: Int) -> some View {
        Text(caption)
            .font(.system(size: size, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func keywordsView(_ keywords: [String], metrics: OverlayMetrics) -> some View {
        let rows = ImmersiveKeywordChipLayout.rows(
            for: keywords,
            maxWidth: max(120, metrics.utilityWidth - 6),
            style: metrics.keywordStyle
        )

        if rows.isEmpty {
            Text("(none)")
                .font(.system(size: metrics.keywordStyle.fontSize, weight: .semibold))
                .foregroundStyle(Self.secondaryTextColor)
        } else {
            VStack(alignment: .leading, spacing: metrics.keywordStyle.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: metrics.keywordStyle.itemSpacing) {
                        ForEach(Array(row.chips.enumerated()), id: \.offset) { _, chip in
                            keywordChip(chip, style: metrics.keywordStyle)
                        }
                    }
                }
            }
        }
    }

    private func keywordChip(_ chip: ImmersiveKeywordChipLayout.Chip, style: ImmersiveKeywordChipLayout.Style) -> some View {
        Text(chip.text)
            .font(.system(size: style.fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .background(chip.isOverflow ? Self.chipFillColor.opacity(0.98) : Self.chipFillColor.opacity(0.9))
            .overlay(
                Capsule()
                    .stroke(Self.chipStrokeColor, lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func progressCards(compact: Bool, cardWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(progressCardDisplays(compact: compact)) { item in
                progressCard(title: item.title, value: item.value, minWidth: cardWidth)
            }
        }
    }

    private func progressCard(title: String, value: String, minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Self.secondaryTextColor)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: minWidth, alignment: .leading)
        .background(Self.metricFillColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Self.metricStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pacePillsRow() -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                compactPacePill(title: "Rate", value: rateText)
                compactPacePill(title: "Elapsed", value: Self.formatDuration(seconds: performance.elapsedSeconds))
                compactPacePill(title: "ETA", value: etaText)
            }

            HStack(spacing: 6) {
                compactPacePill(title: "Rate", value: rateText, ultraCompact: true)
                compactPacePill(title: "Elapsed", value: Self.formatDuration(seconds: performance.elapsedSeconds), ultraCompact: true)
                compactPacePill(title: "ETA", value: etaText, ultraCompact: true)
            }
        }
    }

    private func compactPacePill(title: String, value: String, ultraCompact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: ultraCompact ? 9 : 10, weight: .semibold))
                .foregroundStyle(Self.secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(value)
                .font(.system(size: ultraCompact ? 11 : 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, ultraCompact ? 8 : 10)
        .padding(.vertical, ultraCompact ? 5 : 6)
        .background(Self.metricFillColor)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Self.metricStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionLabel(_ text: String, size: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Self.secondaryTextColor)
            .tracking(0.8)
    }

    private func panelBackground(cornerRadius: CGFloat, fillOpacity: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Self.panelTopColor.opacity(fillOpacity),
                        Self.panelBottomColor.opacity(fillOpacity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Self.panelStrokeColor, lineWidth: 1)
            )
    }

    private var integratedCloseButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Self.metricFillColor)
                )
                .overlay(
                    Circle()
                        .stroke(Self.metricStrokeColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
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

    private func overlaySubtitle(for preview: CompletedItemPreview) -> String {
        [preview.sourceContext, captureDateText(preview.captureDate)]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func captureDateText(_ captureDate: Date?) -> String {
        guard let captureDate else {
            return ""
        }
        return Self.captureDateFormatter.string(from: captureDate)
    }

    private func progressCardDisplays(compact: Bool) -> [ProgressCardDisplay] {
        [
            ProgressCardDisplay(
                id: "discovered",
                title: compact ? "Disc" : "Discovered",
                value: "\(progress.totalDiscovered)"
            ),
            ProgressCardDisplay(
                id: "processed",
                title: compact ? "Proc" : "Processed",
                value: "\(progress.processed)"
            ),
            ProgressCardDisplay(
                id: "changed",
                title: compact ? "Changed" : "Changed",
                value: "\(progress.changed)"
            ),
            ProgressCardDisplay(
                id: "skipped",
                title: compact ? "Skip" : "Skipped",
                value: "\(progress.skipped)"
            ),
            ProgressCardDisplay(
                id: "failed",
                title: compact ? "Fail" : "Failed",
                value: "\(progress.failed)"
            )
        ]
    }

    private var progressStatsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 118), spacing: 10)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            legacyProgressStat(title: "Discovered", value: progress.totalDiscovered)
            legacyProgressStat(title: "Processed", value: progress.processed)
            legacyProgressStat(title: "Changed", value: progress.changed)
            legacyProgressStat(title: "Skipped", value: progress.skipped)
            legacyProgressStat(title: "Failed", value: progress.failed)
        }
    }

    private func legacyProgressStat(title: String, value: Int) -> some View {
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

    private func legacyPacePill(title: String, value: String) -> some View {
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

    private func makeDisplayImage(for preview: CompletedItemPreview) -> NSImage? {
        guard let fileURL = preview.previewFileURL else {
            return nil
        }

        if let image = NSImage(contentsOf: fileURL) {
            return image
        }

        return NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    private var showsRunPerformance: Bool {
        isRunning || progress.processed > 0
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

    private static func overlayMetrics(for size: CGSize) -> OverlayMetrics {
        let outerInset = min(max(size.width * 0.012, 12), 24)
        let hudHeight = min(max(size.height * 0.08, 58), 72)
        let hudHorizontalPadding = min(max(size.width * 0.018, 18), 24)
        let hudVerticalPadding = min(max(size.height * 0.015, 10), 14)

        let dockBottomInset = min(max(size.height * 0.016, 12), 22)
        let dockHeight = min(max(size.height * 0.19, 152), 186)
        let dockHorizontalPadding = min(max(size.width * 0.018, 18), 28)
        let dockVerticalPadding = min(max(size.height * 0.016, 14), 18)
        let dockSectionSpacing = min(max(size.width * 0.016, 16), 24)

        let dockWidth = max(size.width - (outerInset * 2), 360)
        var utilityWidth = min(max(dockWidth * 0.34, 300), 420)
        let minimumCaptionWidth = max(240, dockWidth * 0.36)
        let availableCaptionWidth = dockWidth - (dockHorizontalPadding * 2) - dockSectionSpacing - utilityWidth - 1
        if availableCaptionWidth < minimumCaptionWidth {
            utilityWidth = max(240, dockWidth - (dockHorizontalPadding * 2) - dockSectionSpacing - minimumCaptionWidth - 1)
        }

        let captionFontSize = min(max(size.height * 0.056, 34), 56)
        let compactCaptionFontSize = max(30, captionFontSize * 0.88)
        let minimumCaptionFontSize = max(26, captionFontSize * 0.76)

        return OverlayMetrics(
            outerInset: outerInset,
            hudHeight: hudHeight,
            hudHorizontalPadding: hudHorizontalPadding,
            hudVerticalPadding: hudVerticalPadding,
            dockBottomInset: dockBottomInset,
            dockHeight: dockHeight,
            dockHorizontalPadding: dockHorizontalPadding,
            dockVerticalPadding: dockVerticalPadding,
            dockSectionSpacing: dockSectionSpacing,
            utilityWidth: utilityWidth,
            utilitySectionSpacing: 8,
            titleFontSize: min(max(size.width * 0.014, 18), 22),
            subtitleFontSize: min(max(size.width * 0.009, 12), 15),
            sectionLabelFontSize: 11,
            captionFontSize: captionFontSize,
            compactCaptionFontSize: compactCaptionFontSize,
            minimumCaptionFontSize: minimumCaptionFontSize,
            fullProgressCardWidth: 78,
            compactProgressCardWidth: 64,
            keywordStyle: .immersiveCompact
        )
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

    private static let panelTopColor = Color(red: 0.05, green: 0.09, blue: 0.13)
    private static let panelBottomColor = Color(red: 0.06, green: 0.11, blue: 0.16)
    private static let panelStrokeColor = Color(red: 0.31, green: 0.47, blue: 0.58).opacity(0.72)
    private static let metricFillColor = Color(red: 0.09, green: 0.16, blue: 0.23).opacity(0.94)
    private static let metricStrokeColor = Color(red: 0.33, green: 0.52, blue: 0.64).opacity(0.78)
    private static let chipFillColor = Color(red: 0.10, green: 0.18, blue: 0.26)
    private static let chipStrokeColor = Color(red: 0.34, green: 0.54, blue: 0.67).opacity(0.82)
    private static let secondaryTextColor = Color.white.opacity(0.76)
    private static let dividerColor = Color(red: 0.28, green: 0.43, blue: 0.53)
}

struct ImmersiveKeywordChipLayout {
    struct Style: Equatable {
        let fontSize: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let itemSpacing: CGFloat
        let rowSpacing: CGFloat
        let maxRows: Int
        let maxChipWidthFraction: CGFloat
        let absoluteMaxChipWidth: CGFloat

        static let immersiveCompact = Style(
            fontSize: 11,
            horizontalPadding: 9,
            verticalPadding: 5,
            itemSpacing: 6,
            rowSpacing: 6,
            maxRows: 2,
            maxChipWidthFraction: 0.40,
            absoluteMaxChipWidth: 132
        )
    }

    struct Chip: Equatable {
        let text: String
        let isOverflow: Bool
    }

    struct Row: Equatable {
        let chips: [Chip]
    }

    private struct ChipPlacement {
        let chip: Chip
        let width: CGFloat
    }

    static func rows(
        for keywords: [String],
        maxWidth: CGFloat,
        style: Style = .immersiveCompact
    ) -> [Row] {
        let normalized = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty, maxWidth > 0 else {
            return []
        }

        var rows: [[ChipPlacement]] = [[]]
        var rowWidths: [CGFloat] = [0]
        var index = 0

        while index < normalized.count {
            let chipText = truncatedKeyword(
                normalized[index],
                maxWidth: effectiveMaxChipWidth(for: maxWidth, style: style),
                style: style
            )
            let chipWidth = measuredChipWidth(for: chipText, style: style)
            let lastRowIndex = rows.count - 1

            if canFit(
                chipWidth: chipWidth,
                inRowWidth: rowWidths[lastRowIndex],
                itemCount: rows[lastRowIndex].count,
                maxWidth: maxWidth,
                style: style
            ) {
                append(
                    Chip(text: chipText, isOverflow: false),
                    width: chipWidth,
                    to: &rows[lastRowIndex],
                    rowWidth: &rowWidths[lastRowIndex],
                    style: style
                )
                index += 1
                continue
            }

            if rows.count < style.maxRows {
                rows.append([])
                rowWidths.append(0)
                continue
            }

            addOverflowChip(
                hiddenCount: normalized.count - index,
                to: &rows[lastRowIndex],
                rowWidth: &rowWidths[lastRowIndex],
                maxWidth: maxWidth,
                style: style
            )
            break
        }

        return rows
            .filter { !$0.isEmpty }
            .map { Row(chips: $0.map(\.chip)) }
    }

    private static func effectiveMaxChipWidth(for maxWidth: CGFloat, style: Style) -> CGFloat {
        min(style.absoluteMaxChipWidth, maxWidth * style.maxChipWidthFraction)
    }

    private static func canFit(
        chipWidth: CGFloat,
        inRowWidth rowWidth: CGFloat,
        itemCount: Int,
        maxWidth: CGFloat,
        style: Style
    ) -> Bool {
        let proposedWidth = rowWidth + chipWidth + (itemCount > 0 ? style.itemSpacing : 0)
        return proposedWidth <= maxWidth
    }

    private static func append(
        _ chip: Chip,
        width: CGFloat,
        to row: inout [ChipPlacement],
        rowWidth: inout CGFloat,
        style: Style
    ) {
        if !row.isEmpty {
            rowWidth += style.itemSpacing
        }
        row.append(ChipPlacement(chip: chip, width: width))
        rowWidth += width
    }

    private static func addOverflowChip(
        hiddenCount: Int,
        to row: inout [ChipPlacement],
        rowWidth: inout CGFloat,
        maxWidth: CGFloat,
        style: Style
    ) {
        var remainingHidden = hiddenCount

        while remainingHidden > 0 {
            let overflowText = "+\(remainingHidden) more"
            let overflowWidth = measuredChipWidth(for: overflowText, style: style)

            if row.isEmpty || canFit(
                chipWidth: overflowWidth,
                inRowWidth: rowWidth,
                itemCount: row.count,
                maxWidth: maxWidth,
                style: style
            ) {
                append(
                    Chip(text: overflowText, isOverflow: true),
                    width: overflowWidth,
                    to: &row,
                    rowWidth: &rowWidth,
                    style: style
                )
                return
            }

            let hadMultipleItems = row.count > 1
            guard let removed = row.popLast() else {
                return
            }
            rowWidth -= removed.width
            if hadMultipleItems {
                rowWidth -= style.itemSpacing
            }
            remainingHidden += 1
        }
    }

    private static func truncatedKeyword(_ keyword: String, maxWidth: CGFloat, style: Style) -> String {
        if measuredChipWidth(for: keyword, style: style) <= maxWidth {
            return keyword
        }

        let ellipsis = "..."
        var candidate = keyword
        while !candidate.isEmpty {
            candidate.removeLast()
            let text = candidate.isEmpty ? ellipsis : candidate + ellipsis
            if measuredChipWidth(for: text, style: style) <= maxWidth {
                return text
            }
        }

        return ellipsis
    }

    private static func measuredChipWidth(for text: String, style: Style) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)
        ]
        let measured = ceil((text as NSString).size(withAttributes: attributes).width)
        return measured + (style.horizontalPadding * 2)
    }
}
