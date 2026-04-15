import AppKit
import SwiftUI

private struct WindowReferenceReader: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveWindow(for: nsView)
    }

    private func resolveWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onResolve(window)
        }
    }
}

struct PreviewWindowView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var window: NSWindow?
    @State private var hasAppliedInitialBehavior = false

    var body: some View {
        ImmersivePreviewView(
            preview: viewModel.immersiveDisplayedItemPreview,
            progress: viewModel.progress,
            performance: viewModel.performance,
            isRunning: viewModel.isRunning,
            lagCount: viewModel.immersiveLagCount,
            isPresented: Binding(
                get: { viewModel.isImmersivePreviewPresented },
                set: { isPresented in
                    guard !isPresented else { return }
                    closePreviewWindow()
                }
            )
        )
        .background(
            WindowReferenceReader { resolvedWindow in
                if window !== resolvedWindow {
                    window = resolvedWindow
                }
                applyInitialPresentationBehaviorIfNeeded()
            }
        )
        .toolbar {
            ToolbarItemGroup {
                Button("Full Screen") {
                    toggleFullScreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .control])

                Button("Close Preview") {
                    closePreviewWindow()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            viewModel.openImmersivePreview()
            applyInitialPresentationBehaviorIfNeeded()
        }
        .onDisappear {
            hasAppliedInitialBehavior = false
            if viewModel.isImmersivePreviewPresented {
                viewModel.closeImmersivePreview()
            }
        }
    }

    private func applyInitialPresentationBehaviorIfNeeded() {
        guard let window, !hasAppliedInitialBehavior else { return }
        hasAppliedInitialBehavior = true
        viewModel.markImmersivePreviewOpened()

        guard viewModel.previewOpenBehavior == .fullScreenOnOpen,
              !window.styleMask.contains(.fullScreen)
        else {
            return
        }

        DispatchQueue.main.async {
            guard viewModel.isImmersivePreviewPresented else { return }
            window.toggleFullScreen(nil)
        }
    }

    private func toggleFullScreen() {
        guard let window else { return }
        window.toggleFullScreen(nil)
    }

    private func closePreviewWindow() {
        viewModel.closeImmersivePreview()
        if let window {
            window.close()
        } else {
            NSApp.keyWindow?.close()
        }
    }
}
