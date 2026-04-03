import AppKit
import Foundation
import SwiftUI

enum ImmersiveLayoutMode: Equatable {
    case overlay
    case bottomShelf
}

enum ImmersiveMediaSizingMode: Equatable {
    case aspectFill
    case aspectFit

    var contentMode: ContentMode {
        switch self {
        case .aspectFill:
            return .fill
        case .aspectFit:
            return .fit
        }
    }
}

struct ImmersivePreviewChromeMetrics: Equatable {
    let topBarHeight: CGFloat
    let topBarHorizontalPadding: CGFloat
    let topBarVerticalPadding: CGFloat
    let bottomPanelHeight: CGFloat
    let bottomPanelHorizontalPadding: CGFloat
    let bottomPanelVerticalPadding: CGFloat
    let sectionSpacing: CGFloat
    let utilityWidth: CGFloat
    let captionWidth: CGFloat
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
        max(72, bottomPanelHeight - (bottomPanelVerticalPadding * 2) - 12)
    }

    func withBottomPanelHeight(_ height: CGFloat) -> ImmersivePreviewChromeMetrics {
        ImmersivePreviewChromeMetrics(
            topBarHeight: topBarHeight,
            topBarHorizontalPadding: topBarHorizontalPadding,
            topBarVerticalPadding: topBarVerticalPadding,
            bottomPanelHeight: height,
            bottomPanelHorizontalPadding: bottomPanelHorizontalPadding,
            bottomPanelVerticalPadding: bottomPanelVerticalPadding,
            sectionSpacing: sectionSpacing,
            utilityWidth: utilityWidth,
            captionWidth: captionWidth,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            sectionLabelFontSize: sectionLabelFontSize,
            captionFontSize: captionFontSize,
            compactCaptionFontSize: compactCaptionFontSize,
            minimumCaptionFontSize: minimumCaptionFontSize,
            fullProgressCardWidth: fullProgressCardWidth,
            compactProgressCardWidth: compactProgressCardWidth,
            keywordStyle: keywordStyle
        )
    }
}

struct ImmersivePreviewLayout: Equatable {
    let safeViewportRect: CGRect
    let mediaContainerRect: CGRect
    let mediaRect: CGRect
    let layoutMode: ImmersiveLayoutMode
    let mediaSizingMode: ImmersiveMediaSizingMode
    let topBarRect: CGRect
    let bottomPanelRect: CGRect
    let metrics: ImmersivePreviewChromeMetrics
}

enum ImmersivePreviewLayoutCalculator {
    private enum Constants {
        static let horizontalInsetRange: ClosedRange<CGFloat> = 20...32
        static let verticalInsetRange: ClosedRange<CGFloat> = 24...40
        static let overlayPanelInset: CGFloat = 18
        static let overlayVerticalGap: CGFloat = 28
        static let overlayMinMediaWidth: CGFloat = 980
        static let overlayMinMediaHeight: CGFloat = 520
        static let overlayMinCaptionWidth: CGFloat = 420
        static let overlayMinUtilityWidth: CGFloat = 280
        static let overlayLandscapeAspectThreshold: CGFloat = 1.1
        static let overlayFillPreservationThreshold: CGFloat = 0.88
        static let shelfVerticalGap: CGFloat = 18
        static let minShelfMediaHeight: CGFloat = 220
        static let rectTolerance: CGFloat = 0.5
    }

    static func calculate(
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets,
        mediaSize: CGSize?
    ) -> ImmersivePreviewLayout {
        let safeViewportRect = safeViewportRect(
            viewportSize: viewportSize,
            safeAreaInsets: safeAreaInsets
        )
        let normalizedMediaSize = normalizedMediaSize(mediaSize)
        let horizontalInset = clamped(
            safeViewportRect.width * 0.02,
            to: Constants.horizontalInsetRange
        )
        let verticalInset = clamped(
            safeViewportRect.height * 0.03,
            to: Constants.verticalInsetRange
        )
        let chromeSafeRect = safeViewportRect.insetBy(dx: horizontalInset, dy: verticalInset)

        let overlayContainerRect = chromeSafeRect
        let overlaySizingMode = preferredOverlaySizingMode(
            mediaSize: normalizedMediaSize,
            containerRect: overlayContainerRect
        )
        let overlayMediaRect = mediaRect(
            mediaSize: normalizedMediaSize,
            in: overlayContainerRect,
            sizingMode: overlaySizingMode
        )
        let overlayChromeContainer = overlayMediaRect.intersection(safeViewportRect)

        let overlayPanelWidth = max(
            240,
            overlayMediaRect.width - (Constants.overlayPanelInset * 2)
        )
        let overlayMetrics = chromeMetrics(
            panelWidth: overlayPanelWidth,
            viewportHeight: safeViewportRect.height,
            layoutMode: .overlay
        )
        let overlayTopBarRect = clampedRect(
            CGRect(
                x: overlayMediaRect.minX + Constants.overlayPanelInset,
                y: overlayMediaRect.minY + Constants.overlayPanelInset,
                width: overlayPanelWidth,
                height: overlayMetrics.topBarHeight
            ),
            inside: overlayChromeContainer
        )
        let overlayBottomPanelRect = clampedRect(
            CGRect(
                x: overlayMediaRect.minX + Constants.overlayPanelInset,
                y: overlayMediaRect.maxY - Constants.overlayPanelInset - overlayMetrics.bottomPanelHeight,
                width: overlayPanelWidth,
                height: overlayMetrics.bottomPanelHeight
            ),
            inside: overlayChromeContainer
        )

        if canUseOverlay(
            safeViewportRect: safeViewportRect,
            mediaRect: overlayMediaRect,
            topBarRect: overlayTopBarRect,
            bottomPanelRect: overlayBottomPanelRect,
            metrics: overlayMetrics
        ) {
            return ImmersivePreviewLayout(
                safeViewportRect: safeViewportRect,
                mediaContainerRect: overlayContainerRect,
                mediaRect: overlayMediaRect,
                layoutMode: .overlay,
                mediaSizingMode: overlaySizingMode,
                topBarRect: overlayTopBarRect,
                bottomPanelRect: overlayBottomPanelRect,
                metrics: overlayMetrics
            )
        }

        let shelfUsableRect = chromeSafeRect
        var shelfMetrics = chromeMetrics(
            panelWidth: shelfUsableRect.width,
            viewportHeight: safeViewportRect.height,
            layoutMode: .bottomShelf
        )
        let maxShelfHeight = max(
            140,
            shelfUsableRect.height
                - shelfMetrics.topBarHeight
                - (Constants.shelfVerticalGap * 2)
                - Constants.minShelfMediaHeight
        )
        shelfMetrics = shelfMetrics.withBottomPanelHeight(
            min(shelfMetrics.bottomPanelHeight, maxShelfHeight)
        )

        let shelfTopBarRect = clampedRect(
            CGRect(
                x: shelfUsableRect.minX,
                y: shelfUsableRect.minY,
                width: shelfUsableRect.width,
                height: shelfMetrics.topBarHeight
            ),
            inside: shelfUsableRect
        )
        let shelfBottomPanelRect = clampedRect(
            CGRect(
                x: shelfUsableRect.minX,
                y: shelfUsableRect.maxY - shelfMetrics.bottomPanelHeight,
                width: shelfUsableRect.width,
                height: shelfMetrics.bottomPanelHeight
            ),
            inside: shelfUsableRect
        )

        let mediaAreaMinY = shelfTopBarRect.maxY + Constants.shelfVerticalGap
        let mediaAreaMaxY = shelfBottomPanelRect.minY - Constants.shelfVerticalGap
        let mediaAreaRect = CGRect(
            x: shelfUsableRect.minX,
            y: mediaAreaMinY,
            width: shelfUsableRect.width,
            height: max(0, mediaAreaMaxY - mediaAreaMinY)
        )
        let shelfMediaRect = mediaRect(
            mediaSize: normalizedMediaSize,
            in: mediaAreaRect,
            sizingMode: .aspectFit
        )

        return ImmersivePreviewLayout(
            safeViewportRect: safeViewportRect,
            mediaContainerRect: mediaAreaRect,
            mediaRect: shelfMediaRect,
            layoutMode: .bottomShelf,
            mediaSizingMode: .aspectFit,
            topBarRect: shelfTopBarRect,
            bottomPanelRect: shelfBottomPanelRect,
            metrics: shelfMetrics
        )
    }

    private static func safeViewportRect(
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> CGRect {
        CGRect(
            x: safeAreaInsets.leading,
            y: safeAreaInsets.top,
            width: max(0, viewportSize.width - safeAreaInsets.leading - safeAreaInsets.trailing),
            height: max(0, viewportSize.height - safeAreaInsets.top - safeAreaInsets.bottom)
        )
    }

    private static func normalizedMediaSize(_ mediaSize: CGSize?) -> CGSize {
        guard let mediaSize,
              mediaSize.width.isFinite,
              mediaSize.height.isFinite,
              mediaSize.width > 1,
              mediaSize.height > 1
        else {
            return CGSize(width: 1600, height: 1200)
        }
        return mediaSize
    }

    private static func preferredOverlaySizingMode(
        mediaSize: CGSize,
        containerRect: CGRect
    ) -> ImmersiveMediaSizingMode {
        let mediaAspectRatio = mediaSize.width / mediaSize.height
        guard mediaAspectRatio >= Constants.overlayLandscapeAspectThreshold,
              containerRect.width > 0,
              containerRect.height > 0
        else {
            return .aspectFit
        }

        let containerAspectRatio = containerRect.width / containerRect.height
        let widthFraction: CGFloat
        let heightFraction: CGFloat

        if mediaAspectRatio >= containerAspectRatio {
            widthFraction = containerAspectRatio / mediaAspectRatio
            heightFraction = 1
        } else {
            widthFraction = 1
            heightFraction = mediaAspectRatio / containerAspectRatio
        }

        if widthFraction >= Constants.overlayFillPreservationThreshold,
           heightFraction >= Constants.overlayFillPreservationThreshold
        {
            return .aspectFill
        }

        return .aspectFit
    }

    private static func mediaRect(
        mediaSize: CGSize,
        in containerRect: CGRect,
        sizingMode: ImmersiveMediaSizingMode
    ) -> CGRect {
        guard containerRect.width > 0,
              containerRect.height > 0
        else {
            return .zero
        }

        switch sizingMode {
        case .aspectFill:
            return containerRect
        case .aspectFit:
            let scale = min(
                containerRect.width / mediaSize.width,
                containerRect.height / mediaSize.height
            )
            let width = mediaSize.width * scale
            let height = mediaSize.height * scale
            return CGRect(
                x: containerRect.midX - (width / 2),
                y: containerRect.midY - (height / 2),
                width: width,
                height: height
            )
        }
    }

    private static func chromeMetrics(
        panelWidth: CGFloat,
        viewportHeight: CGFloat,
        layoutMode: ImmersiveLayoutMode
    ) -> ImmersivePreviewChromeMetrics {
        let isOverlay = layoutMode == .overlay
        let topBarHeight = clamped(
            viewportHeight * (isOverlay ? 0.075 : 0.07),
            to: (isOverlay ? 58...72 : 56...68)
        )
        let bottomPanelHeight = clamped(
            viewportHeight * (isOverlay ? 0.19 : 0.23),
            to: (isOverlay ? 156...186 : 180...226)
        )
        let topBarHorizontalPadding: CGFloat = isOverlay ? 22 : 20
        let topBarVerticalPadding: CGFloat = isOverlay ? 12 : 11
        let bottomPanelHorizontalPadding: CGFloat = isOverlay ? 24 : 24
        let bottomPanelVerticalPadding: CGFloat = isOverlay ? 16 : 18
        let sectionSpacing: CGFloat = isOverlay ? 20 : 22
        let utilityWidth = min(
            max(panelWidth * (isOverlay ? 0.30 : 0.28), isOverlay ? 280 : 260),
            isOverlay ? 420 : 360
        )
        let captionAvailableWidth = panelWidth
            - (bottomPanelHorizontalPadding * 2)
            - sectionSpacing
            - 1
            - utilityWidth
        let captionWidth = max(CGFloat.zero, captionAvailableWidth)
        let keywordStyle = ImmersiveKeywordChipLayout.Style.immersiveCompact

        return ImmersivePreviewChromeMetrics(
            topBarHeight: topBarHeight,
            topBarHorizontalPadding: topBarHorizontalPadding,
            topBarVerticalPadding: topBarVerticalPadding,
            bottomPanelHeight: bottomPanelHeight,
            bottomPanelHorizontalPadding: bottomPanelHorizontalPadding,
            bottomPanelVerticalPadding: bottomPanelVerticalPadding,
            sectionSpacing: sectionSpacing,
            utilityWidth: utilityWidth,
            captionWidth: captionWidth,
            titleFontSize: isOverlay ? 20 : 18,
            subtitleFontSize: isOverlay ? 13 : 12,
            sectionLabelFontSize: 11,
            captionFontSize: isOverlay ? 40 : 34,
            compactCaptionFontSize: isOverlay ? 34 : 30,
            minimumCaptionFontSize: 26,
            fullProgressCardWidth: isOverlay ? 78 : 72,
            compactProgressCardWidth: isOverlay ? 64 : 60,
            keywordStyle: keywordStyle
        )
    }

    private static func canUseOverlay(
        safeViewportRect: CGRect,
        mediaRect: CGRect,
        topBarRect: CGRect,
        bottomPanelRect: CGRect,
        metrics: ImmersivePreviewChromeMetrics
    ) -> Bool {
        guard mediaRect.width >= Constants.overlayMinMediaWidth,
              mediaRect.height >= Constants.overlayMinMediaHeight,
              metrics.utilityWidth >= Constants.overlayMinUtilityWidth,
              metrics.captionWidth >= Constants.overlayMinCaptionWidth
        else {
            return false
        }

        let chromeGap = bottomPanelRect.minY - topBarRect.maxY
        guard chromeGap >= Constants.overlayVerticalGap else {
            return false
        }

        return rect(topBarRect, fitsInside: safeViewportRect)
            && rect(bottomPanelRect, fitsInside: safeViewportRect)
            && rect(topBarRect, fitsInside: mediaRect)
            && rect(bottomPanelRect, fitsInside: mediaRect)
    }

    private static func rect(_ rect: CGRect, fitsInside container: CGRect) -> Bool {
        rect.minX >= container.minX - Constants.rectTolerance
            && rect.maxX <= container.maxX + Constants.rectTolerance
            && rect.minY >= container.minY - Constants.rectTolerance
            && rect.maxY <= container.maxY + Constants.rectTolerance
    }

    private static func clampedRect(
        _ rect: CGRect,
        inside container: CGRect
    ) -> CGRect {
        guard container.width > 0,
              container.height > 0
        else {
            return .zero
        }

        let width = min(rect.width, container.width)
        let height = min(rect.height, container.height)
        let x = min(max(rect.minX, container.minX), container.maxX - width)
        let y = min(max(rect.minY, container.minY), container.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func clamped(
        _ value: CGFloat,
        to range: ClosedRange<CGFloat>
    ) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct ImmersivePreviewView: View {
    private static let captureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private struct ProgressCardDisplay: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    private struct ResolvedMedia {
        let image: NSImage?
        let size: CGSize
    }

    let preview: CompletedItemPreview?
    let progress: RunProgress
    let performance: RunPerformanceStats
    let isRunning: Bool
    let lagCount: Int
    @Binding var isPresented: Bool

    private var previewIdentity: String {
        let filePart = preview?.previewFileURL?.path ?? "no-file"
        let namePart = preview?.filename ?? "no-name"
        return "\(filePart)|\(namePart)"
    }

    var body: some View {
        GeometryReader { proxy in
            let safeAreaInsets = proxy.safeAreaInsets
            let resolvedMedia = preview.map(Self.resolveMedia(for:))
            let layout = ImmersivePreviewLayoutCalculator.calculate(
                viewportSize: proxy.size,
                safeAreaInsets: safeAreaInsets,
                mediaSize: resolvedMedia?.size
            )

            ZStack(alignment: .topLeading) {
                Color.black
                    .ignoresSafeArea()

                if let resolvedMedia {
                    mediaLayer(resolvedMedia, layout: layout)
                } else {
                    fallbackBackground
                        .ignoresSafeArea()
                }

                if let preview {
                    previewForeground(preview: preview, layout: layout)
                        .transition(.opacity)
                } else {
                    emptyStateForeground
                    closeButtonLayer(safeAreaInsets: safeAreaInsets)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .onExitCommand {
            isPresented = false
        }
        .animation(.easeInOut(duration: 0.3), value: previewIdentity)
    }

    private var fallbackBackground: some View {
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

    private func mediaLayer(
        _ resolvedMedia: ResolvedMedia,
        layout: ImmersivePreviewLayout
    ) -> some View {
        ZStack {
            if let image = resolvedMedia.image {
                if showsAmbientMatte(for: layout) {
                    ambientMatteLayer(image: image, layout: layout)
                }

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: layout.mediaSizingMode.contentMode)
                    .frame(width: layout.mediaRect.width, height: layout.mediaRect.height)
                    .clipped()
                    .position(x: layout.mediaRect.midX, y: layout.mediaRect.midY)
            } else {
                fallbackBackground
                    .frame(width: layout.mediaContainerRect.width, height: layout.mediaContainerRect.height)
                    .position(x: layout.mediaContainerRect.midX, y: layout.mediaContainerRect.midY)
            }
        }
    }

    private func previewForeground(
        preview: CompletedItemPreview,
        layout: ImmersivePreviewLayout
    ) -> some View {
        ZStack(alignment: .topLeading) {
            topBar(preview: preview, layout: layout)
            bottomPanel(preview: preview, layout: layout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyStateForeground: some View {
        VStack(spacing: 12) {
            Text("No Completed Item Yet")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Start a run and this view will update live as items complete.")
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.74))
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func topBar(
        preview: CompletedItemPreview,
        layout: ImmersivePreviewLayout
    ) -> some View {
        topHUD(preview: preview, metrics: layout.metrics)
            .frame(width: layout.topBarRect.width, height: layout.topBarRect.height)
            .position(x: layout.topBarRect.midX, y: layout.topBarRect.midY)
    }

    private func bottomPanel(
        preview: CompletedItemPreview,
        layout: ImmersivePreviewLayout
    ) -> some View {
        bottomDock(preview: preview, layout: layout)
            .frame(width: layout.bottomPanelRect.width, height: layout.bottomPanelRect.height)
            .position(x: layout.bottomPanelRect.midX, y: layout.bottomPanelRect.midY)
    }

    private func topHUD(
        preview: CompletedItemPreview,
        metrics: ImmersivePreviewChromeMetrics
    ) -> some View {
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
        .padding(.horizontal, metrics.topBarHorizontalPadding)
        .padding(.vertical, metrics.topBarVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(panelBackground(cornerRadius: 24, fillOpacity: 0.92))
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 8)
    }

    private func bottomDock(
        preview: CompletedItemPreview,
        layout: ImmersivePreviewLayout
    ) -> some View {
        let metrics = layout.metrics

        return HStack(alignment: .top, spacing: metrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Caption", size: metrics.sectionLabelFontSize)
                captionText(preview.caption, metrics: metrics)
            }
            .frame(width: metrics.captionWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(Self.dividerColor.opacity(0.45))
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                if showsRunPerformance {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Run Pace", size: metrics.sectionLabelFontSize)
                        pacePillsRow()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Keywords", size: metrics.sectionLabelFontSize)
                    keywordsView(
                        preview.keywords,
                        utilityWidth: metrics.utilityWidth,
                        style: metrics.keywordStyle
                    )
                }
            }
            .frame(width: metrics.utilityWidth, alignment: .topLeading)
        }
        .padding(.horizontal, metrics.bottomPanelHorizontalPadding)
        .padding(.vertical, metrics.bottomPanelVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            panelBackground(
                cornerRadius: layout.layoutMode == .overlay ? 28 : 24,
                fillOpacity: layout.layoutMode == .overlay ? 0.89 : 0.96
            )
        )
        .shadow(
            color: Color.black.opacity(layout.layoutMode == .overlay ? 0.26 : 0.18),
            radius: layout.layoutMode == .overlay ? 22 : 14,
            y: layout.layoutMode == .overlay ? 10 : 6
        )
    }

    private func captionText(
        _ caption: String,
        metrics: ImmersivePreviewChromeMetrics
    ) -> some View {
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
    private func keywordsView(
        _ keywords: [String],
        utilityWidth: CGFloat,
        style: ImmersiveKeywordChipLayout.Style
    ) -> some View {
        let rows = ImmersiveKeywordChipLayout.rows(
            for: keywords,
            maxWidth: max(120, utilityWidth - 6),
            style: style
        )

        if rows.isEmpty {
            Text("(none)")
                .font(.system(size: style.fontSize, weight: .semibold))
                .foregroundStyle(Self.secondaryTextColor)
        } else {
            VStack(alignment: .leading, spacing: style.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: style.itemSpacing) {
                        ForEach(Array(row.chips.enumerated()), id: \.offset) { _, chip in
                            keywordChip(chip, style: style)
                        }
                    }
                }
            }
        }
    }

    private func keywordChip(
        _ chip: ImmersiveKeywordChipLayout.Chip,
        style: ImmersiveKeywordChipLayout.Style
    ) -> some View {
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
                compactPacePill(title: "Lag", value: lagText)
            }

            HStack(spacing: 6) {
                compactPacePill(title: "Rate", value: rateText, ultraCompact: true)
                compactPacePill(title: "Elapsed", value: Self.formatDuration(seconds: performance.elapsedSeconds), ultraCompact: true)
                compactPacePill(title: "ETA", value: etaText, ultraCompact: true)
                compactPacePill(title: "Lag", value: lagText, ultraCompact: true)
            }
        }
    }

    private func compactPacePill(
        title: String,
        value: String,
        ultraCompact: Bool = false
    ) -> some View {
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

    private func ambientMatteLayer(
        image: NSImage,
        layout: ImmersivePreviewLayout
    ) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: layout.mediaContainerRect.width,
                    height: layout.mediaContainerRect.height
                )
                .saturation(0.92)
                .brightness(-0.08)
                .scaleEffect(1.08)
                .blur(radius: 34)
                .clipped()

            Rectangle()
                .fill(Color.black.opacity(0.34))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.black.opacity(0.26)
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(layout.mediaContainerRect.width, layout.mediaContainerRect.height) * 0.72
            )
        }
        .frame(
            width: layout.mediaContainerRect.width,
            height: layout.mediaContainerRect.height
        )
        .clipped()
        .position(
            x: layout.mediaContainerRect.midX,
            y: layout.mediaContainerRect.midY
        )
    }

    private func showsAmbientMatte(for layout: ImmersivePreviewLayout) -> Bool {
        guard layout.mediaSizingMode == .aspectFit else {
            return false
        }

        return abs(layout.mediaContainerRect.width - layout.mediaRect.width) > 1
            || abs(layout.mediaContainerRect.height - layout.mediaRect.height) > 1
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

    private func closeButtonLayer(safeAreaInsets: EdgeInsets) -> some View {
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
                .padding(.top, safeAreaInsets.top + 24)
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

    private static func resolveMedia(for preview: CompletedItemPreview) -> ResolvedMedia {
        let fallbackSize: CGSize = preview.kind == .video
            ? CGSize(width: 1920, height: 1080)
            : CGSize(width: 1600, height: 1200)

        if let fileURL = preview.previewFileURL,
           let image = NSImage(contentsOf: fileURL),
           image.size.width > 1,
           image.size.height > 1
        {
            return ResolvedMedia(image: image, size: image.size)
        }

        if let fileURL = preview.previewFileURL {
            return ResolvedMedia(
                image: NSWorkspace.shared.icon(forFile: fileURL.path),
                size: fallbackSize
            )
        }

        return ResolvedMedia(image: nil, size: fallbackSize)
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

    private var lagText: String {
        ImmersivePreviewPolicy.lagDisplayValue(for: lagCount)
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

    private static func truncatedKeyword(
        _ keyword: String,
        maxWidth: CGFloat,
        style: Style
    ) -> String {
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
