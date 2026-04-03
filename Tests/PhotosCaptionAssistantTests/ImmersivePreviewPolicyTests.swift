import XCTest
@testable import PhotosCaptionAssistant

final class ImmersivePreviewPolicyTests: XCTestCase {
    func testDisplaySecondsUsesTieredCadenceAcrossBacklogRanges() {
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 0), 20)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 2), 20)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 3), 18)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 6), 18)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 7), 16)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 12), 16)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 13), 14)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 20), 14)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 21), 12)
        XCTAssertEqual(ImmersivePreviewPolicy.displaySeconds(for: 40), 12)
    }

    func testRetainedIndicesKeepAllItemsWithinRetainedLimit() {
        XCTAssertEqual(
            ImmersivePreviewPolicy.retainedIndices(for: ImmersivePreviewPolicy.sampledRetainedPreviewCount),
            Array(0..<ImmersivePreviewPolicy.sampledRetainedPreviewCount)
        )
    }

    func testRetainedIndicesKeepsFirstAndLastDuringEmergencySampling() {
        let backlogCount = ImmersivePreviewPolicy.emergencySamplingThreshold + 1
        let indices = ImmersivePreviewPolicy.retainedIndices(for: backlogCount)

        XCTAssertEqual(indices.count, ImmersivePreviewPolicy.sampledRetainedPreviewCount)
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, backlogCount - 1)
        XCTAssertEqual(indices, Array(Set(indices)).sorted())
    }

    func testLagDisplayValueShowsLiveAndCapsLargeCounts() {
        XCTAssertEqual(ImmersivePreviewPolicy.lagDisplayValue(for: 0), "Live")
        XCTAssertEqual(ImmersivePreviewPolicy.lagDisplayValue(for: 4), "4")
        XCTAssertEqual(ImmersivePreviewPolicy.lagDisplayValue(for: 99), "99")
        XCTAssertEqual(ImmersivePreviewPolicy.lagDisplayValue(for: 100), "99+")
        XCTAssertEqual(ImmersivePreviewPolicy.lagDisplayValue(for: 155), "99+")
    }
}

final class ImmersivePlaybackStateTests: XCTestCase {
    func testOpenStartsLiveAndQueuedCompletionsIncreaseLag() async {
        let viewModel = await MainActor.run { AppViewModel() }
        let first = Self.makePreview(named: "first")
        let second = Self.makePreview(named: "second")
        let third = Self.makePreview(named: "third")

        await MainActor.run {
            viewModel.lastCompletedItemPreview = first
            viewModel.openImmersivePreview()

            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview, first)
            XCTAssertEqual(viewModel.immersiveLagCount, 0)

            viewModel.receiveCompletedItemPreview(second, scheduleAdvance: false)
            XCTAssertEqual(viewModel.immersiveLagCount, 1)

            viewModel.receiveCompletedItemPreview(third, scheduleAdvance: false)
            XCTAssertEqual(viewModel.immersiveLagCount, 2)

            XCTAssertTrue(viewModel.advanceImmersivePreviewNowIfPossible())
            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview, second)
            XCTAssertEqual(viewModel.immersiveLagCount, 1)

            viewModel.isImmersivePreviewPresented = false
            viewModel.handleImmersivePresentationChange(false)
            XCTAssertEqual(viewModel.immersiveLagCount, 0)
            XCTAssertNil(viewModel.immersiveDisplayedItemPreview)
        }
    }

    func testEmergencySamplingPreservesExactLagUntilImmersiveCatchesUp() async {
        let viewModel = await MainActor.run { AppViewModel() }
        let current = Self.makePreview(named: "current")
        let backlogCount = ImmersivePreviewPolicy.emergencySamplingThreshold + 1

        await MainActor.run {
            viewModel.lastCompletedItemPreview = current
            viewModel.openImmersivePreview()

            for index in 1...backlogCount {
                viewModel.receiveCompletedItemPreview(
                    Self.makePreview(named: "queued-\(index)"),
                    scheduleAdvance: false
                )
            }

            XCTAssertEqual(viewModel.immersiveLagCount, backlogCount)

            var advances = 0
            while viewModel.advanceImmersivePreviewNowIfPossible() {
                advances += 1
            }

            XCTAssertEqual(advances, ImmersivePreviewPolicy.sampledRetainedPreviewCount)
            XCTAssertEqual(viewModel.immersiveLagCount, 0)
            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview?.filename, "queued-\(backlogCount).jpg")

            viewModel.isImmersivePreviewPresented = false
            viewModel.handleImmersivePresentationChange(false)
        }
    }

    private static func makePreview(named name: String) -> CompletedItemPreview {
        CompletedItemPreview(
            filename: "\(name).jpg",
            sourceContext: "Whole Library",
            captureDate: nil,
            kind: .photo,
            previewFileURL: nil,
            caption: "Caption for \(name)",
            keywords: [name]
        )
    }
}
