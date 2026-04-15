import SwiftUI

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
    @ObservedObject var viewModel: AppViewModel

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Preview") {
                viewModel.openImmersivePreview()
                openWindow(id: AppSceneID.preview)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button("Data & Storage") {
                openWindow(id: AppSceneID.dataStorage)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Diagnostics") {
                openWindow(id: AppSceneID.diagnostics)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }
}

struct RunCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var viewModel: AppViewModel

    var body: some Commands {
        CommandMenu("Run") {
            Button("Start Run") {
                Task {
                    await viewModel.startRun()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!viewModel.canStartRun)

            Button(viewModel.isCancelRequested ? "Canceling Run" : "Cancel Run") {
                viewModel.cancelRun()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!viewModel.isRunning || viewModel.isCancelRequested)

            Divider()

            Button("Reload Setup") {
                Task {
                    await viewModel.loadInitialData()
                }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(viewModel.isRunning || viewModel.isPreparingModel)

            Button("Resume Previous Run") {
                Task {
                    await viewModel.resumeSavedRun()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!viewModel.canResumeSavedRun)

            Button("Retry Failed Items") {
                Task {
                    await viewModel.retryFailedItems()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!viewModel.canRetryFailedItems)

            Divider()

            Button("Open Preview Window") {
                viewModel.openImmersivePreview()
                openWindow(id: AppSceneID.preview)
            }
            .disabled(!viewModel.canOpenPreviewWindow)
        }
    }
}
