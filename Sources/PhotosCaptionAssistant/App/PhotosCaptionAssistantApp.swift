import SwiftUI

@main
struct PhotosCaptionAssistantApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
        }
        .defaultSize(width: 1280, height: 880)
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
