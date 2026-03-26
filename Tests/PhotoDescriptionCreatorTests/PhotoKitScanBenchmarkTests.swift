import Foundation
import Photos
import XCTest
@testable import PhotoDescriptionCreator

final class PhotoKitScanBenchmarkTests: XCTestCase {
    func testExperimentalPhotoKitReaderRejectsUnsupportedScopes() async {
        let reader = ExperimentalPhotoKitScanReader()

        do {
            _ = try await reader.count(scope: .picker(ids: ["one"]))
            XCTFail("Expected picker scope to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("picker"))
        }

        do {
            _ = try await reader.enumerate(scope: .captionWorkflow, offset: 0, limit: 1)
            XCTFail("Expected caption workflow scope to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("captionWorkflow"))
        }
    }

    func testExperimentalPhotoKitIdentifierCandidatesIncludeBaseIdentifier() {
        XCTAssertEqual(
            ExperimentalPhotoKitScanReader.identifierCandidates(from: "abc/def"),
            ["abc/def", "abc"]
        )
        XCTAssertEqual(
            ExperimentalPhotoKitScanReader.identifierCandidates(from: "abc"),
            ["abc"]
        )
    }

    func testExperimentalPhotoKitPageRangeClampsBounds() {
        XCTAssertEqual(ExperimentalPhotoKitScanReader.pageRange(totalCount: 10, offset: 2, limit: 3), 2..<5)
        XCTAssertEqual(ExperimentalPhotoKitScanReader.pageRange(totalCount: 10, offset: 9, limit: 5), 9..<10)
        XCTAssertNil(ExperimentalPhotoKitScanReader.pageRange(totalCount: 0, offset: 0, limit: 1))
        XCTAssertNil(ExperimentalPhotoKitScanReader.pageRange(totalCount: 5, offset: 5, limit: 1))
    }

    func testGenerateLocalParityAndSpeedReportWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PDC_RUN_PHOTOS_SCAN_BENCHMARK"] == "1" else {
            throw XCTSkip("Set PDC_RUN_PHOTOS_SCAN_BENCHMARK=1 to run the local Photos parity benchmark.")
        }

        let configuration = PhotoLibraryScanBenchmarkConfiguration.fromEnvironment(
            ProcessInfo.processInfo.environment
        )
        let runner = PhotoLibraryScanBenchmarkRunner(appleScriptClient: PhotosAppleScriptClient())
        let outcome = try await runner.run(configuration: configuration)

        switch outcome {
        case let .completed(run):
            print("[PhotoKitScanBenchmarkTests] wrote report to \(run.reportURL.path)")
            for scope in run.report.scopes {
                print(scope.summaryLine)
            }
            XCTAssertFalse(run.report.scopes.isEmpty)
        case let .skipped(reason):
            throw XCTSkip(reason)
        }
    }
}
