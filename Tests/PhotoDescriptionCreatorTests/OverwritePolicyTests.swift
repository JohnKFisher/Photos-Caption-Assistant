import XCTest
@testable import PhotoDescriptionCreator

final class OverwritePolicyTests: XCTestCase {
    func testExternalMetadataRequiresPerPhotoConfirmation() {
        let existing = ExistingMetadataState(
            caption: "Existing user caption",
            keywords: ["family"],
            ownershipTag: nil,
            isExternal: true
        )

        let decision = OverwritePolicy.decide(
            context: OverwriteContext(
                existing: existing,
                targetLogicVersion: .current,
                targetEngine: .qwen25vl7b,
                overwriteAppOwnedSameOrNewer: false
            )
        )

        XCTAssertEqual(decision, .requiresPerPhotoConfirmation)
    }

    func testOwnedOlderLogicVersionAutoOverwrites() {
        let existing = ExistingMetadataState(
            caption: "Old",
            keywords: ["__pdc_logic_0_9_0", "__pdc_engine_qwen25vl7b"],
            ownershipTag: OwnershipTag(logicVersion: LogicVersion(major: 0, minor: 9, patch: 0), engineTier: .qwen25vl7b),
            isExternal: false
        )

        let decision = OverwritePolicy.decide(
            context: OverwriteContext(
                existing: existing,
                targetLogicVersion: .current,
                targetEngine: .qwen25vl7b,
                overwriteAppOwnedSameOrNewer: false
            )
        )

        XCTAssertEqual(decision, .write(reason: .ownedOlderLogicVersion))
    }

    func testOwnedOlderPatchVersionDoesNotAutoOverwrite() {
        let existingTagVersion = LogicVersion(
            major: LogicVersion.current.major,
            minor: LogicVersion.current.minor,
            patch: max(0, LogicVersion.current.patch - 1)
        )
        let existing = ExistingMetadataState(
            caption: "Old patch",
            keywords: OwnershipTagCodec.tags(
                for: OwnershipTag(logicVersion: existingTagVersion, engineTier: .qwen25vl7b)
            ),
            ownershipTag: OwnershipTag(logicVersion: existingTagVersion, engineTier: .qwen25vl7b),
            isExternal: false
        )

        let decision = OverwritePolicy.decide(
            context: OverwriteContext(
                existing: existing,
                targetLogicVersion: .current,
                targetEngine: .qwen25vl7b,
                overwriteAppOwnedSameOrNewer: false
            )
        )

        XCTAssertEqual(decision, .skip(reason: .alreadyOwnedSameOrNewer))
    }

    func testOwnedOlderMinorVersionAutoOverwrites() {
        let existingTagVersion = LogicVersion(major: 1, minor: 0, patch: 9)
        let existing = ExistingMetadataState(
            caption: "Old minor",
            keywords: ["__pdc_logic_1_0_9", "__pdc_engine_qwen25vl7b"],
            ownershipTag: OwnershipTag(logicVersion: existingTagVersion, engineTier: .qwen25vl7b),
            isExternal: false
        )

        let decision = OverwritePolicy.decide(
            context: OverwriteContext(
                existing: existing,
                targetLogicVersion: .current,
                targetEngine: .qwen25vl7b,
                overwriteAppOwnedSameOrNewer: false
            )
        )

        XCTAssertEqual(decision, .write(reason: .ownedOlderLogicVersion))
    }

    func testOwnedSameVersionSkipsByDefault() {
        let currentOwnership = OwnershipTag(logicVersion: .current, engineTier: .qwen25vl7b)
        let existing = ExistingMetadataState(
            caption: "Current",
            keywords: OwnershipTagCodec.tags(for: currentOwnership),
            ownershipTag: currentOwnership,
            isExternal: false
        )

        let decision = OverwritePolicy.decide(
            context: OverwriteContext(
                existing: existing,
                targetLogicVersion: .current,
                targetEngine: .qwen25vl7b,
                overwriteAppOwnedSameOrNewer: false
            )
        )

        XCTAssertEqual(decision, .skip(reason: .alreadyOwnedSameOrNewer))
    }

    func testOwnedSameVersionCanBeForcedToOverwrite() {
        let currentOwnership = OwnershipTag(logicVersion: .current, engineTier: .qwen25vl7b)
        let existing = ExistingMetadataState(
            caption: "Current",
            keywords: OwnershipTagCodec.tags(for: currentOwnership),
            ownershipTag: currentOwnership,
            isExternal: false
        )

        let decision = OverwritePolicy.decide(
            context: OverwriteContext(
                existing: existing,
                targetLogicVersion: .current,
                targetEngine: .qwen25vl7b,
                overwriteAppOwnedSameOrNewer: true
            )
        )

        XCTAssertEqual(decision, .write(reason: .ownedSameOrNewerForced))
    }

    func testOwnedDifferentEngineAutoOverwrites() {
        let existing = ExistingMetadataState(
            caption: "Vision output",
            keywords: ["__pdc_logic_1_0_0", "__pdc_engine_vision"],
            ownershipTag: OwnershipTag(logicVersion: .current, engineTier: .vision),
            isExternal: false
        )

        let decision = OverwritePolicy.decide(
            context: OverwriteContext(
                existing: existing,
                targetLogicVersion: .current,
                targetEngine: .qwen25vl7b,
                overwriteAppOwnedSameOrNewer: false
            )
        )

        XCTAssertEqual(decision, .write(reason: .ownedDifferentEngine))
    }
}
