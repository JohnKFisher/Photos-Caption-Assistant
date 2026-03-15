import Foundation

public struct CapabilityProbe: CapabilityProbing {
    private let photosClient: PhotosAppleScriptClient
    private let ollamaManager: OllamaManager

    public init(photosClient: PhotosAppleScriptClient, ollamaManager: OllamaManager = OllamaManager()) {
        self.photosClient = photosClient
        self.ollamaManager = ollamaManager
    }

    public func probe() async -> AppCapabilities {
        let automationAvailable = await photosClient.verifyAutomationAccess()
        let qwenAvailable = await ollamaManager.isModelAvailable()
        let pickerCapability: PickerCapability = automationAvailable
            ? .supported
            : .unsupported(reason: "Photos automation is unavailable, so picker IDs cannot be resolved safely.")

        return AppCapabilities(
            photosAutomationAvailable: automationAvailable,
            qwenModelAvailable: qwenAvailable,
            pickerCapability: pickerCapability
        )
    }
}
