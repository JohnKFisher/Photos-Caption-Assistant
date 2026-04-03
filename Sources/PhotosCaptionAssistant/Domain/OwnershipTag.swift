import Foundation

public enum OwnershipTagCodec {
    public static let logicPrefix = "__pdc_logic_"
    public static let enginePrefix = "__pdc_engine_"

    public static func extract(from keywords: [String]) -> OwnershipTag? {
        var parsedVersion: LogicVersion?
        var parsedEngine: EngineTier?
        var sawEngineKeyword = false

        for keyword in keywords {
            if keyword.hasPrefix(logicPrefix), let version = parseVersion(keyword) {
                parsedVersion = version
            } else if keyword.hasPrefix(enginePrefix) {
                sawEngineKeyword = true
                if let engine = parseEngine(keyword) {
                    parsedEngine = engine
                }
            }
        }

        guard let parsedVersion else {
            return nil
        }
        if sawEngineKeyword, parsedEngine == nil {
            return nil
        }
        return OwnershipTag(logicVersion: parsedVersion, engineTier: parsedEngine ?? .qwen25vl7b)
    }

    public static func tags(for tag: OwnershipTag) -> [String] {
        [
            "\(logicPrefix)\(tag.logicVersion.major)_\(tag.logicVersion.minor)_\(tag.logicVersion.patch)"
        ]
    }

    public static func removeOwnedTags(from keywords: [String]) -> [String] {
        keywords.filter { keyword in
            !keyword.hasPrefix(logicPrefix) && !keyword.hasPrefix(enginePrefix)
        }
    }

    public static func appendTags(_ tag: OwnershipTag, to keywords: [String]) -> [String] {
        let base = removeOwnedTags(from: keywords)
        var seen = Set<String>()
        let orderedBase = base.filter { seen.insert($0).inserted }
        return orderedBase + tags(for: tag)
    }

    private static func parseVersion(_ keyword: String) -> LogicVersion? {
        let payload = keyword.replacingOccurrences(of: logicPrefix, with: "")
        let components = payload.split(separator: "_").compactMap { Int($0) }
        guard components.count == 3 else {
            return nil
        }
        return LogicVersion(major: components[0], minor: components[1], patch: components[2])
    }

    private static func parseEngine(_ keyword: String) -> EngineTier? {
        let payload = keyword.replacingOccurrences(of: enginePrefix, with: "")
        return EngineTier(rawValue: payload)
    }
}
