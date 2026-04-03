import Foundation

public enum SkipReason: Sendable, Equatable {
    case alreadyOwnedSameOrNewer
}

public enum WriteReason: Sendable, Equatable {
    case emptyMetadata
    case userConfirmedExternalOverwrite
    case ownedOlderLogicVersion
    case ownedDifferentEngine
    case ownedSameOrNewerForced
}

public enum OverwriteDecision: Sendable, Equatable {
    case write(reason: WriteReason)
    case requiresPerPhotoConfirmation
    case skip(reason: SkipReason)
}

public struct OverwriteContext: Sendable, Equatable {
    public let existing: ExistingMetadataState
    public let targetLogicVersion: LogicVersion
    public let targetEngine: EngineTier
    public let overwriteAppOwnedSameOrNewer: Bool

    public init(
        existing: ExistingMetadataState,
        targetLogicVersion: LogicVersion,
        targetEngine: EngineTier,
        overwriteAppOwnedSameOrNewer: Bool
    ) {
        self.existing = existing
        self.targetLogicVersion = targetLogicVersion
        self.targetEngine = targetEngine
        self.overwriteAppOwnedSameOrNewer = overwriteAppOwnedSameOrNewer
    }
}

public enum OverwritePolicy {
    public static func decide(context: OverwriteContext) -> OverwriteDecision {
        let hasCaption = !(context.existing.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let userKeywords = OwnershipTagCodec.removeOwnedTags(from: context.existing.keywords)
        let hasUserKeywords = !userKeywords.isEmpty
        let hasAnyMetadata = hasCaption || hasUserKeywords

        guard hasAnyMetadata else {
            return .write(reason: .emptyMetadata)
        }

        guard let tag = context.existing.ownershipTag else {
            return .requiresPerPhotoConfirmation
        }

        if isOlderMajorMinor(tag.logicVersion, than: context.targetLogicVersion) {
            return .write(reason: .ownedOlderLogicVersion)
        }

        if tag.engineTier != context.targetEngine {
            return .write(reason: .ownedDifferentEngine)
        }

        if context.overwriteAppOwnedSameOrNewer {
            return .write(reason: .ownedSameOrNewerForced)
        }

        return .skip(reason: .alreadyOwnedSameOrNewer)
    }

    private static func isOlderMajorMinor(_ existing: LogicVersion, than target: LogicVersion) -> Bool {
        if existing.major != target.major {
            return existing.major < target.major
        }
        return existing.minor < target.minor
    }
}
