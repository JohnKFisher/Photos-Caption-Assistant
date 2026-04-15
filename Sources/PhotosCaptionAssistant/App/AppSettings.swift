import Foundation

enum PreviewOpenBehavior: String, CaseIterable, Identifiable {
    case windowed
    case fullScreenOnOpen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowed:
            return "Open In Window"
        case .fullScreenOnOpen:
            return "Open Full Screen"
        }
    }

    var summary: String {
        switch self {
        case .windowed:
            return "Preview opens in its own window and can enter full screen on demand."
        case .fullScreenOnOpen:
            return "Preview opens in its own window and enters full screen immediately."
        }
    }
}

struct AppSettingsSnapshot: Equatable {
    let defaultSourceSelection: SourceSelection
    let defaultTraversalOrder: RunTraversalOrder
    let defaultOverwriteAppOwnedSameOrNewer: Bool
    let defaultAlwaysOverwriteExternalMetadata: Bool
    let previewOpenBehavior: PreviewOpenBehavior

    static let `default` = AppSettingsSnapshot(
        defaultSourceSelection: .album,
        defaultTraversalOrder: .photosOrderFast,
        defaultOverwriteAppOwnedSameOrNewer: false,
        defaultAlwaysOverwriteExternalMetadata: false,
        previewOpenBehavior: .windowed
    )
}

enum AppSettings {
    enum Keys {
        static let defaultSourceSelection = "settings.defaultSourceSelection"
        static let defaultTraversalOrder = "settings.defaultTraversalOrder"
        static let defaultOverwriteAppOwnedSameOrNewer = "settings.defaultOverwriteAppOwnedSameOrNewer"
        static let defaultAlwaysOverwriteExternalMetadata = "settings.defaultAlwaysOverwriteExternalMetadata"
        static let previewOpenBehavior = "settings.previewOpenBehavior"
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettingsSnapshot {
        let fallback = AppSettingsSnapshot.default

        let sourceSelection = SourceSelection(
            rawValue: defaults.string(forKey: Keys.defaultSourceSelection) ?? ""
        ) ?? fallback.defaultSourceSelection

        let traversalOrder = RunTraversalOrder(
            rawValue: defaults.string(forKey: Keys.defaultTraversalOrder) ?? ""
        ) ?? fallback.defaultTraversalOrder

        let previewOpenBehavior = PreviewOpenBehavior(
            rawValue: defaults.string(forKey: Keys.previewOpenBehavior) ?? ""
        ) ?? fallback.previewOpenBehavior

        return AppSettingsSnapshot(
            defaultSourceSelection: sourceSelection,
            defaultTraversalOrder: traversalOrder,
            defaultOverwriteAppOwnedSameOrNewer: defaults.object(forKey: Keys.defaultOverwriteAppOwnedSameOrNewer) as? Bool
                ?? fallback.defaultOverwriteAppOwnedSameOrNewer,
            defaultAlwaysOverwriteExternalMetadata: defaults.object(forKey: Keys.defaultAlwaysOverwriteExternalMetadata) as? Bool
                ?? fallback.defaultAlwaysOverwriteExternalMetadata,
            previewOpenBehavior: previewOpenBehavior
        )
    }
}
