import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Keys.defaultSourceSelection) private var defaultSourceSelectionRaw = AppSettingsSnapshot.default.defaultSourceSelection.rawValue
    @AppStorage(AppSettings.Keys.defaultTraversalOrder) private var defaultTraversalOrderRaw = AppSettingsSnapshot.default.defaultTraversalOrder.rawValue
    @AppStorage(AppSettings.Keys.defaultOverwriteAppOwnedSameOrNewer) private var defaultOverwriteAppOwnedSameOrNewer = AppSettingsSnapshot.default.defaultOverwriteAppOwnedSameOrNewer
    @AppStorage(AppSettings.Keys.defaultAlwaysOverwriteExternalMetadata) private var defaultAlwaysOverwriteExternalMetadata = AppSettingsSnapshot.default.defaultAlwaysOverwriteExternalMetadata
    @AppStorage(AppSettings.Keys.previewOpenBehavior) private var previewOpenBehaviorRaw = AppSettingsSnapshot.default.previewOpenBehavior.rawValue

    let onDefaultsChanged: () -> Void
    let onRevealDataFolder: () -> Void

    private var defaultSourceSelection: Binding<SourceSelection> {
        Binding(
            get: { SourceSelection(rawValue: defaultSourceSelectionRaw) ?? AppSettingsSnapshot.default.defaultSourceSelection },
            set: { value in
                defaultSourceSelectionRaw = value.rawValue
                onDefaultsChanged()
            }
        )
    }

    private var defaultTraversalOrder: Binding<RunTraversalOrder> {
        Binding(
            get: { RunTraversalOrder(rawValue: defaultTraversalOrderRaw) ?? AppSettingsSnapshot.default.defaultTraversalOrder },
            set: { value in
                defaultTraversalOrderRaw = value.rawValue
                onDefaultsChanged()
            }
        )
    }

    private var previewOpenBehavior: Binding<PreviewOpenBehavior> {
        Binding(
            get: { PreviewOpenBehavior(rawValue: previewOpenBehaviorRaw) ?? AppSettingsSnapshot.default.previewOpenBehavior },
            set: { value in
                previewOpenBehaviorRaw = value.rawValue
                onDefaultsChanged()
            }
        )
    }

    var body: some View {
        TabView {
            Form {
                Section("Run Defaults") {
                    Picker("Default Source", selection: defaultSourceSelection) {
                        ForEach(SourceSelection.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }

                    Picker("Default Order", selection: defaultTraversalOrder) {
                        Text(RunTraversalOrder.photosOrderFast.title).tag(RunTraversalOrder.photosOrderFast)
                        Text(RunTraversalOrder.oldestToNewest.title).tag(RunTraversalOrder.oldestToNewest)
                        Text(RunTraversalOrder.newestToOldest.title).tag(RunTraversalOrder.newestToOldest)
                        Text(RunTraversalOrder.random.title).tag(RunTraversalOrder.random)
                        Text(RunTraversalOrder.cycle.title).tag(RunTraversalOrder.cycle)
                    }

                    Toggle("Overwrite app-owned same/newer metadata by default", isOn: Binding(
                        get: { defaultOverwriteAppOwnedSameOrNewer },
                        set: { newValue in
                            defaultOverwriteAppOwnedSameOrNewer = newValue
                            onDefaultsChanged()
                        }
                    ))

                    Toggle("Default to overwriting non-app metadata without prompts", isOn: Binding(
                        get: { defaultAlwaysOverwriteExternalMetadata },
                        set: { newValue in
                            defaultAlwaysOverwriteExternalMetadata = newValue
                            onDefaultsChanged()
                        }
                    ))
                }

                Section("Preview") {
                    Picker("Open Preview", selection: previewOpenBehavior) {
                        ForEach(PreviewOpenBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }

                    Text((PreviewOpenBehavior(rawValue: previewOpenBehaviorRaw) ?? .windowed).summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Support") {
                    Button("Reveal App Data Folder", action: onRevealDataFolder)
                    Text("These defaults apply immediately when the app is idle and become the new startup defaults.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .frame(width: 560, height: 420, alignment: .topLeading)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
        }
    }
}
