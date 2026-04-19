import SwiftUI

enum MainWorkbenchWindowLayout {
    static let preferredSize = CGSize(width: 1280, height: 760)
    static let idealSize = CGSize(width: 1400, height: 820)
    static let minimumSize = CGSize(width: 1040, height: 700)
    private static let horizontalInset: CGFloat = 48
    private static let verticalInset: CGFloat = 72

    static func fittedSize(for preferredSize: CGSize, in visibleRect: CGRect) -> CGSize {
        let maxWidth = max(visibleRect.width - horizontalInset, 0)
        let maxHeight = max(visibleRect.height - verticalInset, 0)
        let width = min(max(minimumSize.width, min(preferredSize.width, maxWidth)), visibleRect.width)
        let height = min(max(minimumSize.height, min(preferredSize.height, maxHeight)), visibleRect.height)
        return CGSize(width: width, height: height)
    }

    static func fittedFrame(for frame: CGRect, in visibleRect: CGRect) -> CGRect {
        let size = fittedSize(for: frame.size, in: visibleRect)
        let maxX = max(visibleRect.maxX - size.width, visibleRect.minX)
        let maxY = max(visibleRect.maxY - size.height, visibleRect.minY)
        let origin = CGPoint(
            x: min(max(frame.origin.x, visibleRect.minX), maxX),
            y: min(max(frame.origin.y, visibleRect.minY), maxY)
        )
        return CGRect(origin: origin, size: size)
    }
}

@main
struct PhotosCaptionAssistantApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
        }
        .defaultSize(
            width: MainWorkbenchWindowLayout.preferredSize.width,
            height: MainWorkbenchWindowLayout.preferredSize.height
        )
        .defaultWindowPlacement { _, context in
            // Keep the main workbench comfortably above the Dock and within the visible display.
            let size = MainWorkbenchWindowLayout.fittedSize(
                for: MainWorkbenchWindowLayout.preferredSize,
                in: context.defaultDisplay.visibleRect
            )
            return WindowPlacement(size: size)
        }
        .windowIdealPlacement { _, context in
            let size = MainWorkbenchWindowLayout.fittedSize(
                for: MainWorkbenchWindowLayout.idealSize,
                in: context.defaultDisplay.visibleRect
            )
            return WindowPlacement(size: size)
        }
        .commands {
            AppInfoCommands()
            WindowAccessCommands(viewModel: viewModel)
            RunCommands(viewModel: viewModel)
            DiagnosticCommands(viewModel: viewModel)
        }

        Window("Preview", id: AppSceneID.preview) {
            PreviewWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 1320, height: 860)
        .restorationBehavior(.disabled)

        Window("About \(AppPresentation.appName)", id: AppSceneID.about) {
            AboutWindowView()
        }
        .defaultSize(width: 460, height: 320)
        .restorationBehavior(.disabled)

        Window("Data & Storage", id: AppSceneID.dataStorage) {
            DataStorageWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 760, height: 460)
        .restorationBehavior(.disabled)

        Window("Diagnostics", id: AppSceneID.diagnostics) {
            DiagnosticsWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 920, height: 600)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(
                onDefaultsChanged: {
                    viewModel.applyAppDefaultsIfPossible()
                },
                onRevealDataFolder: {
                    viewModel.revealDataFolder()
                }
            )
        }
    }
}
