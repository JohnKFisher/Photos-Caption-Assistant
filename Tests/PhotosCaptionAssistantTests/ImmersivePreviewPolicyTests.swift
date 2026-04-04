import XCTest
@testable import PhotosCaptionAssistant

final class ImmersivePlaybackCadenceTests: XCTestCase {
    func testLearnedIntervalMatchesStableRecentMean() {
        var cadence = ImmersivePlaybackCadence()
        var timestamp = Date(timeIntervalSinceReferenceDate: 0)

        cadence.recordCompletion(at: timestamp)
        for _ in 0..<10 {
            timestamp = timestamp.addingTimeInterval(40)
            cadence.recordCompletion(at: timestamp)
        }

        XCTAssertEqual(cadence.learnedInterval ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(cadence.recentIntervalCount, 10)
    }

    func testLearnedIntervalUsesRollingMeanOfMostRecentThirtyIntervals() {
        var cadence = ImmersivePlaybackCadence()
        var timestamp = Date(timeIntervalSinceReferenceDate: 0)

        cadence.recordCompletion(at: timestamp)
        for _ in 0..<30 {
            timestamp = timestamp.addingTimeInterval(10)
            cadence.recordCompletion(at: timestamp)
        }
        for _ in 0..<15 {
            timestamp = timestamp.addingTimeInterval(20)
            cadence.recordCompletion(at: timestamp)
        }

        XCTAssertEqual(cadence.recentIntervalCount, 30)
        XCTAssertEqual(cadence.learnedInterval ?? -1, 15, accuracy: 0.001)
    }

    func testOlderIntervalsFallOffAfterThirtyNewerIntervals() {
        var cadence = ImmersivePlaybackCadence()
        var timestamp = Date(timeIntervalSinceReferenceDate: 0)

        cadence.recordCompletion(at: timestamp)
        for _ in 0..<30 {
            timestamp = timestamp.addingTimeInterval(10)
            cadence.recordCompletion(at: timestamp)
        }
        for _ in 0..<30 {
            timestamp = timestamp.addingTimeInterval(20)
            cadence.recordCompletion(at: timestamp)
        }

        XCTAssertEqual(cadence.recentIntervalCount, 30)
        XCTAssertEqual(cadence.learnedInterval ?? -1, 20, accuracy: 0.001)
    }

    func testMidRunRegimeChangeRelearnsGradually() {
        var cadence = ImmersivePlaybackCadence()
        var timestamp = Date(timeIntervalSinceReferenceDate: 0)

        cadence.recordCompletion(at: timestamp)
        for _ in 0..<30 {
            timestamp = timestamp.addingTimeInterval(120)
            cadence.recordCompletion(at: timestamp)
        }
        for _ in 0..<15 {
            timestamp = timestamp.addingTimeInterval(30)
            cadence.recordCompletion(at: timestamp)
        }

        XCTAssertEqual(cadence.learnedInterval ?? -1, 75, accuracy: 0.001)
    }

    func testSlowRunsCanLearnLongIntervals() {
        var cadence = ImmersivePlaybackCadence()
        var timestamp = Date(timeIntervalSinceReferenceDate: 0)

        cadence.recordCompletion(at: timestamp)
        for _ in 0..<5 {
            timestamp = timestamp.addingTimeInterval(120)
            cadence.recordCompletion(at: timestamp)
        }

        XCTAssertEqual(cadence.learnedInterval ?? -1, 120, accuracy: 0.001)
    }

    func testDisplayIntervalShortensWhenDriftExceedsUpperBound() {
        var cadence = Self.makeCadence(withIntervals: [40, 40, 40])
        let displayedCompletionAt = Date(timeIntervalSinceReferenceDate: 0)

        let nextInterval = cadence.updateCurrentDisplayInterval(
            displayedCompletionAt: displayedCompletionAt,
            hasBacklog: true
        )

        XCTAssertEqual(nextInterval ?? -1, 38, accuracy: 0.001)
    }

    func testDisplayIntervalLengthensWhenDriftIsBelowLowerBound() {
        var cadence = Self.makeCadence(withIntervals: [40, 40, 40])
        let displayedCompletionAt = Date(timeIntervalSinceReferenceDate: 80)

        let nextInterval = cadence.updateCurrentDisplayInterval(
            displayedCompletionAt: displayedCompletionAt,
            hasBacklog: true
        )

        XCTAssertEqual(nextInterval ?? -1, 42, accuracy: 0.001)
    }

    func testDisplayIntervalReturnsTowardLearnedInsideDeadband() {
        var cadence = Self.makeCadence(withIntervals: [40, 40, 40])

        _ = cadence.updateCurrentDisplayInterval(
            displayedCompletionAt: Date(timeIntervalSinceReferenceDate: 0),
            hasBacklog: true
        )

        let nextInterval = cadence.updateCurrentDisplayInterval(
            displayedCompletionAt: Date(timeIntervalSinceReferenceDate: 40),
            hasBacklog: true
        )

        XCTAssertEqual(nextInterval ?? -1, 38.1, accuracy: 0.001)
    }

    private static func makeCadence(withIntervals intervals: [TimeInterval]) -> ImmersivePlaybackCadence {
        var cadence = ImmersivePlaybackCadence()
        var timestamp = Date(timeIntervalSinceReferenceDate: 0)

        cadence.recordCompletion(at: timestamp)
        for interval in intervals {
            timestamp = timestamp.addingTimeInterval(interval)
            cadence.recordCompletion(at: timestamp)
        }

        return cadence
    }
}

final class ImmersivePreviewPolicyTests: XCTestCase {
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
    func testImmediateOpenLearnsCadenceFromRecentCompletions() async {
        let viewModel = await MainActor.run { AppViewModel() }
        let start = Date(timeIntervalSinceReferenceDate: 0)

        await MainActor.run {
            viewModel.receiveCompletedItemPreview(
                Self.makePreview(named: "first"),
                completedAt: start,
                scheduleAdvance: false
            )
            viewModel.openImmersivePreview()

            XCTAssertNil(viewModel.immersiveLearnedInterval)

            viewModel.receiveCompletedItemPreview(
                Self.makePreview(named: "second"),
                completedAt: start.addingTimeInterval(40),
                scheduleAdvance: false
            )

            XCTAssertEqual(viewModel.immersiveLearnedInterval ?? -1, 40, accuracy: 0.001)
            XCTAssertEqual(viewModel.immersiveCurrentDisplayInterval ?? -1, 42, accuracy: 0.001)

            viewModel.receiveCompletedItemPreview(
                Self.makePreview(named: "third"),
                completedAt: start.addingTimeInterval(80),
                scheduleAdvance: false
            )

            XCTAssertEqual(viewModel.immersiveLearnedInterval ?? -1, 40, accuracy: 0.001)
            XCTAssertEqual(viewModel.immersiveCurrentDisplayInterval ?? -1, 41.9, accuracy: 0.001)

            viewModel.isImmersivePreviewPresented = false
            viewModel.handleImmersivePresentationChange(false)
        }
    }

    func testClosedImmersiveBuffersCompletedItemsAndOpensWithBacklog() async {
        let viewModel = await MainActor.run { AppViewModel() }
        let first = Self.makePreview(named: "first")
        let second = Self.makePreview(named: "second")
        let third = Self.makePreview(named: "third")

        await MainActor.run {
            viewModel.receiveCompletedItemPreview(first, scheduleAdvance: false)
            viewModel.receiveCompletedItemPreview(second, scheduleAdvance: false)
            viewModel.receiveCompletedItemPreview(third, scheduleAdvance: false)

            viewModel.openImmersivePreview()

            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview, first)
            XCTAssertEqual(viewModel.immersiveLagCount, 2)

            XCTAssertTrue(viewModel.advanceImmersivePreviewNowIfPossible())
            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview, second)
            XCTAssertEqual(viewModel.immersiveLagCount, 1)

            XCTAssertTrue(viewModel.advanceImmersivePreviewNowIfPossible())
            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview, third)
            XCTAssertEqual(viewModel.immersiveLagCount, 0)

            viewModel.isImmersivePreviewPresented = false
            viewModel.handleImmersivePresentationChange(false)
        }
    }

    func testReopeningImmersiveResumesPendingBacklogWithoutReplayingShownItem() async {
        let viewModel = await MainActor.run { AppViewModel() }
        let first = Self.makePreview(named: "first")
        let second = Self.makePreview(named: "second")
        let third = Self.makePreview(named: "third")

        await MainActor.run {
            viewModel.receiveCompletedItemPreview(first, scheduleAdvance: false)
            viewModel.receiveCompletedItemPreview(second, scheduleAdvance: false)
            viewModel.receiveCompletedItemPreview(third, scheduleAdvance: false)

            viewModel.openImmersivePreview()
            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview, first)
            XCTAssertEqual(viewModel.immersiveLagCount, 2)

            viewModel.isImmersivePreviewPresented = false
            viewModel.handleImmersivePresentationChange(false)

            viewModel.openImmersivePreview()
            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview, second)
            XCTAssertEqual(viewModel.immersiveLagCount, 1)

            viewModel.isImmersivePreviewPresented = false
            viewModel.handleImmersivePresentationChange(false)
        }
    }

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

    func testNoOrdinarySkippingBeforeEmergencySamplingThreshold() async {
        let viewModel = await MainActor.run { AppViewModel() }
        let current = Self.makePreview(named: "current")
        let backlogCount = ImmersivePreviewPolicy.emergencySamplingThreshold

        await MainActor.run {
            viewModel.lastCompletedItemPreview = current
            viewModel.openImmersivePreview()

            for index in 1...backlogCount {
                viewModel.receiveCompletedItemPreview(
                    Self.makePreview(named: "queued-\(index)"),
                    completedAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                    scheduleAdvance: false
                )
            }

            var advances = 0
            while viewModel.advanceImmersivePreviewNowIfPossible() {
                advances += 1
            }

            XCTAssertEqual(advances, backlogCount)
            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview?.filename, "queued-\(backlogCount).jpg")

            viewModel.isImmersivePreviewPresented = false
            viewModel.handleImmersivePresentationChange(false)
        }
    }

    func testDuplicateCompletedPreviewDoesNotQueueSameAssetTwice() async {
        let viewModel = await MainActor.run { AppViewModel() }
        let first = Self.makePreview(named: "first", assetID: "asset-1")
        let duplicate = Self.makePreview(named: "first-duplicate", assetID: "asset-1")
        let second = Self.makePreview(named: "second", assetID: "asset-2")

        await MainActor.run {
            viewModel.receiveCompletedItemPreview(first, scheduleAdvance: false)
            viewModel.receiveCompletedItemPreview(duplicate, scheduleAdvance: false)
            viewModel.receiveCompletedItemPreview(second, scheduleAdvance: false)

            viewModel.openImmersivePreview()

            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview?.assetID, "asset-1")
            XCTAssertEqual(viewModel.immersiveLagCount, 1)
            XCTAssertTrue(viewModel.advanceImmersivePreviewNowIfPossible())
            XCTAssertEqual(viewModel.immersiveDisplayedItemPreview?.assetID, "asset-2")
            XCTAssertEqual(viewModel.immersiveLagCount, 0)

            viewModel.isImmersivePreviewPresented = false
            viewModel.handleImmersivePresentationChange(false)
        }
    }

    private static func makePreview(named name: String, assetID: String? = nil) -> CompletedItemPreview {
        CompletedItemPreview(
            assetID: assetID ?? name,
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
