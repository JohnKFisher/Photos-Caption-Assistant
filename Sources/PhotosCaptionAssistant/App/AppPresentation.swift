import Foundation

enum AppPresentation {
    static let appName = "Photos Caption Assistant"
    static let queuedAlbumsTitle = "Queued Albums"
    static let aboutSummary = "Generates captions and keywords for Apple Photos using a local Ollama model and writes them back to Photos."
    static let ownerName = "John Kenneth Fisher"
    static let repositoryURL = URL(string: "https://github.com/JohnKFisher/Photos-Caption-Assistant")!
}

enum AppSceneID {
    static let about = "about"
    static let preview = "preview"
    static let dataStorage = "data-storage"
    static let diagnostics = "diagnostics"
}

enum VersionDisplay {
    static var appVersionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let marketing = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return "App v\(marketing) (build \(build))"
    }

    static var logicVersionLine: String {
        let logic = LogicVersion.current
        return "DescriptionLogic v\(logic.major).\(logic.minor).\(logic.patch)"
    }
}
