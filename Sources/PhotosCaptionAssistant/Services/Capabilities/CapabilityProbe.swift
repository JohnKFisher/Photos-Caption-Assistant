import Foundation

public protocol OllamaAvailabilityProbing: Sendable {
    func probeAvailability() async -> OllamaAvailability
}

public struct CapabilityProbe: CapabilityProbing {
    private let verifyAutomationAccess: @Sendable () async -> Bool
    private let ollamaProbe: any OllamaAvailabilityProbing

    public init(photosClient: PhotosAppleScriptClient, ollamaManager: OllamaManager = OllamaManager()) {
        self.verifyAutomationAccess = {
            await photosClient.verifyAutomationAccess()
        }
        self.ollamaProbe = ollamaManager
    }

    init(
        verifyAutomationAccess: @escaping @Sendable () async -> Bool,
        ollamaProbe: any OllamaAvailabilityProbing
    ) {
        self.verifyAutomationAccess = verifyAutomationAccess
        self.ollamaProbe = ollamaProbe
    }

    public func probe() async -> AppCapabilities {
        let automationAvailable = await verifyAutomationAccess()
        let ollamaAvailability = await ollamaProbe.probeAvailability()
        let pickerCapability: PickerCapability = automationAvailable
            ? .supported
            : .unsupported(reason: "Photos automation is unavailable, so picker IDs cannot be resolved safely.")

        return AppCapabilities(
            photosAutomationAvailable: automationAvailable,
            ollamaAvailability: ollamaAvailability,
            pickerCapability: pickerCapability
        )
    }
}
