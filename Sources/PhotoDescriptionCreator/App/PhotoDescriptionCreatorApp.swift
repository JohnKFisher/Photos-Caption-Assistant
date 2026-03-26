import SwiftUI

@main
struct PhotoDescriptionCreatorApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .commands {
            DiagnosticCommands(viewModel: viewModel)
        }
    }
}
