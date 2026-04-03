import XCTest
@testable import PhotosCaptionAssistant

private struct StubOllamaProbe: OllamaAvailabilityProbing {
    let availability: OllamaAvailability

    func probeAvailability() async -> OllamaAvailability {
        availability
    }
}

final class CapabilityProbeTests: XCTestCase {
    func testDetectedAvailabilityMarksMissingInstall() {
        XCTAssertEqual(
            OllamaAvailability.detected(isInstalled: false, serviceReachable: false, modelAvailable: false),
            .notInstalled
        )
        XCTAssertTrue(OllamaAvailability.notInstalled.requiresInstallBeforeRun)
    }

    func testDetectedAvailabilityMarksInstalledButStoppedService() {
        XCTAssertEqual(
            OllamaAvailability.detected(isInstalled: true, serviceReachable: false, modelAvailable: false),
            .installedNotRunning
        )
        XCTAssertFalse(OllamaAvailability.installedNotRunning.requiresInstallBeforeRun)
    }

    func testDetectedAvailabilityMarksRunningServiceWithoutModel() {
        XCTAssertEqual(
            OllamaAvailability.detected(isInstalled: true, serviceReachable: true, modelAvailable: false),
            .installedRunningModelMissing
        )
    }

    func testDetectedAvailabilityMarksReadyWhenModelIsAvailable() {
        XCTAssertEqual(
            OllamaAvailability.detected(isInstalled: true, serviceReachable: true, modelAvailable: true),
            .ready
        )
    }

    func testCapabilityProbeReportsNotInstalledState() async {
        let probe = CapabilityProbe(
            verifyAutomationAccess: { true },
            ollamaProbe: StubOllamaProbe(availability: .notInstalled)
        )

        let capabilities = await probe.probe()

        XCTAssertEqual(capabilities.ollamaAvailability, .notInstalled)
        XCTAssertFalse(capabilities.ollamaInstalled)
        XCTAssertFalse(capabilities.ollamaServiceReachable)
        XCTAssertFalse(capabilities.qwenModelAvailable)
        XCTAssertEqual(capabilities.pickerCapability, .supported)
    }

    func testCapabilityProbeReportsModelMissingState() async {
        let probe = CapabilityProbe(
            verifyAutomationAccess: { false },
            ollamaProbe: StubOllamaProbe(availability: .installedRunningModelMissing)
        )

        let capabilities = await probe.probe()

        XCTAssertEqual(capabilities.ollamaAvailability, .installedRunningModelMissing)
        XCTAssertTrue(capabilities.ollamaInstalled)
        XCTAssertTrue(capabilities.ollamaServiceReachable)
        XCTAssertFalse(capabilities.qwenModelAvailable)
        XCTAssertEqual(
            capabilities.pickerCapability,
            .unsupported(reason: "Photos automation is unavailable, so picker IDs cannot be resolved safely.")
        )
    }
}
