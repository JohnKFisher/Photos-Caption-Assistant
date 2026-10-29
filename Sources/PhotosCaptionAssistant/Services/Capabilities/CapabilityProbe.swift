import Foundation

public protocol OllamaAvailabilityProbing: Sendable {
    func probeAvailability() async -> OllamaAvailability
}

public struct CapabilityProbe: CapabilityProbing {
    private let runtimeRequirements: (any PhotosRuntimeRequirements)?
    private let verifyAutomationAccess: (@Sendable () async -> Bool)?
    private let ollamaProbe: any OllamaAvailabilityProbing

    public init(photosClient: any PhotosIntegrationClient, ollamaManager: OllamaManager = OllamaManager()) {
        self.runtimeRequirements = photosClient
        self.verifyAutomationAccess = nil
        self.ollamaProbe = ollamaManager
    }

    init(
        verifyAutomationAccess: @escaping @Sendable () async -> Bool,
        ollamaProbe: any OllamaAvailabilityProbing
    ) {
        self.runtimeRequirements = nil
        self.verifyAutomationAccess = verifyAutomationAccess
        self.ollamaProbe = ollamaProbe
    }

    public func probe() async -> AppCapabilities {
        let ollamaAvailability = await ollamaProbe.probeAvailability()

        if let runtimeRequirements {
            let accessState = await runtimeRequirements.authorizationState()
            let available = accessState.permitsRunAdmission
            let pickerCapability: PickerCapability
            if runtimeRequirements.requiresAppleEventsAutomation && !available {
                pickerCapability = .unsupported(
                    reason: "Photos automation is unavailable, so picker IDs cannot be resolved safely."
                )
            } else {
                pickerCapability = .supported
            }

            return AppCapabilities(
                photosIntegrationAvailable: available,
                photosAccessState: accessState,
                photosBackendName: runtimeRequirements.backendName,
                photosRequiresPhotosApp: runtimeRequirements.requiresPhotosAppToBeOpen,
                photosRequiresAppleEventsAutomation: runtimeRequirements.requiresAppleEventsAutomation,
                ollamaAvailability: ollamaAvailability,
                pickerCapability: pickerCapability
            )
        }

        let automationAvailable = await verifyAutomationAccess?() ?? false
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
