import SwiftUI

@main
struct PhotosCaptionAssistantApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
        }
        .defaultSize(width: 1160, height: 860)
        .commands {
            AppInfoCommands()
            WindowAccessCommands()
            DiagnosticCommands(viewModel: viewModel)
        }

        Window("About \(AppPresentation.appName)", id: AppSceneID.about) {
            AboutWindowView()
        }
        .defaultSize(width: 460, height: 320)

        Window("Data & Storage", id: AppSceneID.dataStorage) {
            DataStorageWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 720, height: 420)

        Window("Diagnostics", id: AppSceneID.diagnostics) {
            DiagnosticsWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 860, height: 520)
    }
}

struct AppInfoCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppPresentation.appName)") {
                openWindow(id: AppSceneID.about)
            }
        }
    }
}

struct WindowAccessCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Data & Storage") {
                openWindow(id: AppSceneID.dataStorage)
            }

            Button("Diagnostics") {
                openWindow(id: AppSceneID.diagnostics)
            }
        }
    }
}
