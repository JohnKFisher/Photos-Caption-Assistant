@preconcurrency import AVFoundation
import AppKit
import Darwin
import Foundation
import Photos

public actor PhotosAppleScriptClient: PhotosWriter, PhotosProcessMonitoring, PhotosLifecycleControlling, PhotoPreviewSource, IncrementalPhotosWriter, BatchMetadataPhotosWriter, BatchWritePhotosWriter, AlbumListingPhotosSource {
    private struct UncheckedExportSession: @unchecked Sendable {
        let rawValue: AVAssetExportSession
    }

    private enum ScriptTimeout {
        static let enumerateLibrary: TimeInterval = 900
        static let enumerateNarrowScope: TimeInterval = 180
        static let countLibrary: TimeInterval = 180
        static let countNarrowScope: TimeInterval = 60
        static let enumeratePage: TimeInterval = 45
        static let readMetadata: TimeInterval = 30
        static let readMetadataBatchBase: TimeInterval = 20
        static let writeMetadata: TimeInterval = 45
        static let writeMetadataBatchBase: TimeInterval = 25
        static let exportPhotoAsset: TimeInterval = 120
        static let exportVideoAsset: TimeInterval = 300
        static let requestVideoAsset: TimeInterval = 900
        static let prepareVideoExportSession: TimeInterval = 60
        static let exportPreparedVideoAsset: TimeInterval = 300
        static let capabilityProbe: TimeInterval = 15
        static let listAlbums: TimeInterval = 120
        static let memoryProbe: TimeInterval = 5
        static let previewImageRequestGuard: TimeInterval = 3
        static let readMetadataBatchMaxIDs = 64
        static let readMetadataBatchMaxArgumentBytes = 12_000
        static let writeMetadataBatchMaxItems = 24
        static let writeMetadataBatchMaxArgumentBytes = 36_000
        static let maximumCommandArgumentBytes = 64_000
    }

    private enum PhotosLifecycle {
        static let appBundleIdentifier = "com.apple.Photos"
        static let quitTimeoutSeconds: TimeInterval = 15
        static let pollIntervalSeconds: TimeInterval = 0.5
    }

    private let fileManager: FileManager
    private let isoFormatter: ISO8601DateFormatter

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func enumerate(scope: ScopeSource, dateRange: CaptureDateRange?) async throws -> [MediaAsset] {
        if case .captionWorkflow = scope {
            throw PhotosAppleScriptError.scriptFailed(
                message: "Caption Workflow must be resolved stage-by-stage by RunCoordinator before direct enumeration."
            )
        }

        let script = makeEnumerationScript(scope: scope)
        let timeout: TimeInterval
        switch scope {
        case .library:
            timeout = ScriptTimeout.enumerateLibrary
        case .album, .picker:
            timeout = ScriptTimeout.enumerateNarrowScope
        case .captionWorkflow:
            timeout = ScriptTimeout.enumerateNarrowScope
        }
        let output = try runAppleScript(
            script,
            timeoutSeconds: timeout,
            operationName: "enumerate assets"
        )

        let assets = await parseEnumeratedAssets(from: output)

        guard let dateRange else {
            return assets
        }

        return assets.filter { dateRange.contains($0.captureDate) }
    }

    public func count(scope: ScopeSource) async throws -> Int {
        if case .captionWorkflow = scope {
            throw PhotosAppleScriptError.scriptFailed(
                message: "Caption Workflow must be resolved stage-by-stage by RunCoordinator before direct counting."
            )
        }

        let assignment = makeScopeTargetItemsAssignment(scope: scope)
        let script = """
        \(baseIdentifierHelperAppleScript)

        tell application \"Photos\"
            \(assignment)
            return (count of targetItems) as text
        end tell
        """

        let timeout: TimeInterval
        switch scope {
        case .library:
            timeout = ScriptTimeout.countLibrary
        case .album, .picker:
            timeout = ScriptTimeout.countNarrowScope
        case .captionWorkflow:
            timeout = ScriptTimeout.countNarrowScope
        }

        let output = try runAppleScript(
            script,
            timeoutSeconds: timeout,
            operationName: "count assets"
        )
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    public func enumerate(scope: ScopeSource, offset: Int, limit: Int) async throws -> [MediaAsset] {
        if case .captionWorkflow = scope {
            throw PhotosAppleScriptError.scriptFailed(
                message: "Caption Workflow must be resolved stage-by-stage by RunCoordinator before paged enumeration."
            )
        }

        let assignment = makeScopeTargetItemsAssignment(scope: scope)
        let script = """
        \(baseIdentifierHelperAppleScript)

        on run argv
            set startIndex to (item 1 of argv) as integer
            set pageLimit to (item 2 of argv) as integer

            if startIndex < 1 then set startIndex to 1
            if pageLimit < 1 then set pageLimit to 1

            tell application \"Photos\"
                \(assignment)
                set totalItems to count of targetItems
                if totalItems is 0 then return \"\"
                if startIndex > totalItems then return \"\"

                set endIndex to startIndex + pageLimit - 1
                if endIndex > totalItems then set endIndex to totalItems

                set pageItems to items startIndex thru endIndex of targetItems
                set rows to {}
                repeat with targetItem in pageItems
                    set itemID to id of targetItem
                    set itemFilename to filename of targetItem
                    set itemDate to date of targetItem
                    set itemDateText to ""
                    try
                        set itemDateText to itemDate as string
                    on error
                        set itemDateText to ""
                    end try
                    set end of rows to itemID & tab & itemFilename & tab & itemDateText
                end repeat

                set AppleScript's text item delimiters to linefeed
                set outputText to rows as text
                set AppleScript's text item delimiters to \"\"
                return outputText
            end tell
        end run
        """

        let output = try runAppleScript(
            script,
            arguments: [String(offset + 1), String(max(1, limit))],
            timeoutSeconds: ScriptTimeout.enumeratePage,
            operationName: "enumerate page"
        )

        return await parseEnumeratedAssets(from: output)
    }

    public func readMetadata(id: String) async throws -> ExistingMetadataState {
        let script = """
        \(mediaItemResolverAppleScript)

        on run argv
            set targetID to item 1 of argv
            set targetItem to my resolveMediaItem(targetID)
            tell application \"Photos\"
                set itemCaption to \"\"
                try
                    set itemCaption to description of targetItem
                on error
                    set itemCaption to \"\"
                end try
                if itemCaption is missing value then set itemCaption to \"\"

                set itemKeywords to {}
                try
                    set itemKeywords to keywords of targetItem
                on error
                    set itemKeywords to {}
                end try
                if itemKeywords is missing value then set itemKeywords to {}

                set normalizedKeywords to {}
                repeat with currentKeyword in itemKeywords
                    if currentKeyword is not missing value then
                        set end of normalizedKeywords to (currentKeyword as text)
                    end if
                end repeat

                set AppleScript's text item delimiters to (character id 31)
                set keywordBlob to normalizedKeywords as text
                set AppleScript's text item delimiters to \"\"
                return itemCaption & (character id 30) & keywordBlob
            end tell
        end run
        """

        let output = try runAppleScript(
            script,
            arguments: [id],
            timeoutSeconds: ScriptTimeout.readMetadata,
            operationName: "read metadata"
        )
        let components = output.split(separator: Character(UnicodeScalar(30)), omittingEmptySubsequences: false)
        let captionRaw = components.indices.contains(0) ? String(components[0]) : ""
        let keywordsRaw = components.indices.contains(1) ? String(components[1]) : ""
        return makeExistingMetadata(captionRaw: captionRaw, keywordsRaw: keywordsRaw)
    }

    public func readMetadata(ids: [String]) async throws -> [String: ExistingMetadataState] {
        guard !ids.isEmpty else { return [:] }

        var aggregated: [String: ExistingMetadataState] = [:]
        let chunks = Self.chunkedMetadataIDs(
            ids,
            maxIDs: ScriptTimeout.readMetadataBatchMaxIDs,
            maxArgumentBytes: ScriptTimeout.readMetadataBatchMaxArgumentBytes
        )
        for chunk in chunks {
            do {
                let chunkMetadata = try runReadMetadataBatch(ids: chunk)
                for (id, state) in chunkMetadata {
                    aggregated[id] = state
                }
            } catch {
                // Fall back to single-item reads for this chunk so one bad batch doesn't block the run.
                for id in chunk where aggregated[id] == nil {
                    if let single = try? await readMetadata(id: id) {
                        aggregated[id] = single
                    }
                }
            }
        }

        return aggregated
    }

    static func chunkedMetadataIDs(
        _ ids: [String],
        maxIDs: Int,
        maxArgumentBytes: Int
    ) -> [[String]] {
        guard !ids.isEmpty else { return [] }
        guard maxIDs > 0 else { return ids.map { [$0] } }
        guard maxArgumentBytes > 0 else { return ids.map { [$0] } }

        var chunks: [[String]] = []
        chunks.reserveCapacity((ids.count / maxIDs) + 1)
        var current: [String] = []
        current.reserveCapacity(min(ids.count, maxIDs))
        var currentBytes = 0

        for id in ids {
            let bytes = id.lengthOfBytes(using: .utf8) + 1
            let exceedsCount = current.count >= maxIDs
            let exceedsByteBudget = !current.isEmpty && (currentBytes + bytes > maxArgumentBytes)

            if exceedsCount || exceedsByteBudget {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
                currentBytes = 0
            }

            if bytes > maxArgumentBytes {
                chunks.append([id])
                continue
            }

            current.append(id)
            currentBytes += bytes
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    static func chunkedMetadataWrites(
        _ writes: [MetadataWritePayload],
        maxItems: Int,
        maxArgumentBytes: Int
    ) -> [[MetadataWritePayload]] {
        guard !writes.isEmpty else { return [] }
        guard maxItems > 0 else { return writes.map { [$0] } }
        guard maxArgumentBytes > 0 else { return writes.map { [$0] } }

        func writeArgumentBytes(_ write: MetadataWritePayload) -> Int {
            let keywordBlob = write.keywords.joined(separator: String(Character(UnicodeScalar(31))))
            return write.id.lengthOfBytes(using: .utf8)
                + write.caption.lengthOfBytes(using: .utf8)
                + keywordBlob.lengthOfBytes(using: .utf8)
                + 3
        }

        var chunks: [[MetadataWritePayload]] = []
        chunks.reserveCapacity((writes.count / maxItems) + 1)
        var current: [MetadataWritePayload] = []
        current.reserveCapacity(min(writes.count, maxItems))
        var currentBytes = 0

        for write in writes {
            let bytes = writeArgumentBytes(write)
            let exceedsCount = current.count >= maxItems
            let exceedsByteBudget = !current.isEmpty && (currentBytes + bytes > maxArgumentBytes)
            if exceedsCount || exceedsByteBudget {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
                currentBytes = 0
            }

            if bytes > maxArgumentBytes {
                chunks.append([write])
                continue
            }

            current.append(write)
            currentBytes += bytes
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private func runReadMetadataBatch(ids: [String]) throws -> [String: ExistingMetadataState] {
        let script = """
        \(mediaItemResolverAppleScript)

        on replaceText(findText, replaceWith, sourceText)
            set AppleScript's text item delimiters to findText
            set textParts to text items of sourceText
            set AppleScript's text item delimiters to replaceWith
            set rebuilt to textParts as text
            set AppleScript's text item delimiters to \"\"
            return rebuilt
        end replaceText

        on sanitizeText(inputText)
            set cleaned to inputText as text
            set cleaned to my replaceText((character id 29), \" \", cleaned)
            set cleaned to my replaceText((character id 30), \" \", cleaned)
            set cleaned to my replaceText(linefeed, \" \", cleaned)
            set cleaned to my replaceText(return, \" \", cleaned)
            return cleaned
        end sanitizeText

        on run argv
            set recordDelimiter to (character id 29)
            set fieldDelimiter to (character id 30)
            set keywordDelimiter to (character id 31)
            set rows to {}

            repeat with rawID in argv
                set targetID to rawID as text
                try
                    set targetItem to my resolveMediaItem(targetID)

                    tell application \"Photos\"
                        set itemCaption to \"\"
                        try
                            set itemCaption to description of targetItem
                        on error
                            set itemCaption to \"\"
                        end try
                        if itemCaption is missing value then set itemCaption to \"\"

                        set itemKeywords to {}
                        try
                            set itemKeywords to keywords of targetItem
                        on error
                            set itemKeywords to {}
                        end try
                        if itemKeywords is missing value then set itemKeywords to {}
                    end tell

                    set normalizedKeywords to {}
                    repeat with currentKeyword in itemKeywords
                        if currentKeyword is not missing value then
                            set end of normalizedKeywords to my sanitizeText(currentKeyword as text)
                        end if
                    end repeat

                    set AppleScript's text item delimiters to keywordDelimiter
                    set keywordBlob to normalizedKeywords as text
                    set AppleScript's text item delimiters to \"\"

                    set sanitizedCaption to my sanitizeText(itemCaption)
                    set end of rows to targetID & fieldDelimiter & sanitizedCaption & fieldDelimiter & keywordBlob
                end try
            end repeat

            set AppleScript's text item delimiters to recordDelimiter
            set outputText to rows as text
            set AppleScript's text item delimiters to \"\"
            return outputText
        end run
        """

        let timeout = min(
            240,
            max(
                ScriptTimeout.readMetadataBatchBase,
                Double(ids.count) * 0.9
            )
        )
        let output = try runAppleScript(
            script,
            arguments: ids,
            timeoutSeconds: timeout,
            operationName: "read metadata batch"
        )

        var byID: [String: ExistingMetadataState] = [:]
        let rowDelimiter = Character(UnicodeScalar(29))
        let fieldDelimiter = Character(UnicodeScalar(30))

        for row in output.split(separator: rowDelimiter, omittingEmptySubsequences: true) {
            let fields = row.split(separator: fieldDelimiter, omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let id = String(fields[0])
            let captionRaw = String(fields[1])
            let keywordsRaw = String(fields[2])
            byID[id] = makeExistingMetadata(captionRaw: captionRaw, keywordsRaw: keywordsRaw)
        }

        return byID
    }

    private func normalizedWriteParts(caption: String, keywords: [String]) -> (caption: String, keywordBlob: String) {
        let normalizedCaption = caption.replacingOccurrences(of: "\n", with: " ")
        let normalizedKeywords = keywords
            .map { keyword in
                keyword
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: String(Character(UnicodeScalar(31))), with: " ")
            }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("missing value") != .orderedSame }
        let keywordBlob = normalizedKeywords.joined(separator: String(Character(UnicodeScalar(31))))
        return (normalizedCaption, keywordBlob)
    }

    public func writeMetadata(batch writes: [MetadataWritePayload]) async throws -> [MetadataWriteResult] {
        guard !writes.isEmpty else { return [] }
        let chunks = Self.chunkedMetadataWrites(
            writes,
            maxItems: ScriptTimeout.writeMetadataBatchMaxItems,
            maxArgumentBytes: ScriptTimeout.writeMetadataBatchMaxArgumentBytes
        )

        var resultsByID: [String: MetadataWriteResult] = [:]
        for chunk in chunks {
            do {
                let chunkResults = try runWriteMetadataBatch(writes: chunk)
                for result in chunkResults where resultsByID[result.id] == nil {
                    resultsByID[result.id] = result
                }
            } catch {
                // Fall back to single-item writes for this chunk.
                for write in chunk where resultsByID[write.id] == nil {
                    do {
                        try await writeMetadata(id: write.id, caption: write.caption, keywords: write.keywords)
                        resultsByID[write.id] = MetadataWriteResult(id: write.id, success: true)
                    } catch {
                        resultsByID[write.id] = MetadataWriteResult(
                            id: write.id,
                            success: false,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }
        }

        return writes.map { write in
            resultsByID[write.id] ?? MetadataWriteResult(
                id: write.id,
                success: false,
                errorMessage: "Batch write did not return a result."
            )
        }
    }

    private func runWriteMetadataBatch(writes: [MetadataWritePayload]) throws -> [MetadataWriteResult] {
        guard !writes.isEmpty else { return [] }

        let script = """
        \(mediaItemResolverAppleScript)

        on replaceText(findText, replaceWith, sourceText)
            set AppleScript's text item delimiters to findText
            set textParts to text items of sourceText
            set AppleScript's text item delimiters to replaceWith
            set rebuilt to textParts as text
            set AppleScript's text item delimiters to \"\"
            return rebuilt
        end replaceText

        on sanitizeText(inputText)
            set cleaned to inputText as text
            set cleaned to my replaceText((character id 29), \" \", cleaned)
            set cleaned to my replaceText((character id 30), \" \", cleaned)
            set cleaned to my replaceText(linefeed, \" \", cleaned)
            set cleaned to my replaceText(return, \" \", cleaned)
            return cleaned
        end sanitizeText

        on run argv
            set recordDelimiter to (character id 29)
            set fieldDelimiter to (character id 30)
            set rows to {}
            set argvCount to count of argv
            set itemIndex to 1

            repeat while itemIndex <= argvCount
                set targetID to (item itemIndex of argv) as text
                set captionText to item (itemIndex + 1) of argv
                set keywordBlob to item (itemIndex + 2) of argv

                set keywordList to {}
                if keywordBlob is not \"\" then
                    set AppleScript's text item delimiters to (character id 31)
                    set keywordList to text items of keywordBlob
                    set AppleScript's text item delimiters to \"\"
                end if

                try
                    set targetItem to my resolveMediaItem(targetID)
                    tell application \"Photos\"
                        set description of targetItem to captionText
                        set keywords of targetItem to keywordList
                    end tell
                    set end of rows to targetID & fieldDelimiter & \"ok\" & fieldDelimiter & \"\"
                on error errorMessage
                    set safeMessage to my sanitizeText(errorMessage)
                    set end of rows to targetID & fieldDelimiter & \"error\" & fieldDelimiter & safeMessage
                end try

                set itemIndex to itemIndex + 3
            end repeat

            set AppleScript's text item delimiters to recordDelimiter
            set outputText to rows as text
            set AppleScript's text item delimiters to \"\"
            return outputText
        end run
        """

        var arguments: [String] = []
        arguments.reserveCapacity(writes.count * 3)
        for write in writes {
            let normalized = normalizedWriteParts(caption: write.caption, keywords: write.keywords)
            arguments.append(write.id)
            arguments.append(normalized.caption)
            arguments.append(normalized.keywordBlob)
        }

        let timeout = min(
            300,
            max(
                ScriptTimeout.writeMetadataBatchBase,
                Double(writes.count) * 1.2
            )
        )
        let output = try runAppleScript(
            script,
            arguments: arguments,
            timeoutSeconds: timeout,
            operationName: "write metadata batch"
        )

        let rowDelimiter = Character(UnicodeScalar(29))
        let fieldDelimiter = Character(UnicodeScalar(30))
        var parsedByID: [String: MetadataWriteResult] = [:]
        for row in output.split(separator: rowDelimiter, omittingEmptySubsequences: true) {
            let fields = row.split(separator: fieldDelimiter, omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            let id = String(fields[0])
            let status = String(fields[1])
            if status == "ok" {
                parsedByID[id] = MetadataWriteResult(id: id, success: true)
            } else {
                let message = fields.indices.contains(2) ? String(fields[2]) : "Metadata write failed."
                parsedByID[id] = MetadataWriteResult(id: id, success: false, errorMessage: message)
            }
        }

        return writes.map { write in
            parsedByID[write.id] ?? MetadataWriteResult(
                id: write.id,
                success: false,
                errorMessage: "No batch result was returned for this item."
            )
        }
    }

    public func writeMetadata(id: String, caption: String, keywords: [String]) async throws {
        let normalized = normalizedWriteParts(caption: caption, keywords: keywords)
        let script = """
        \(mediaItemResolverAppleScript)

        on run argv
            set targetID to item 1 of argv
            set captionText to item 2 of argv
            set keywordBlob to item 3 of argv

            set keywordList to {}
            if keywordBlob is not \"\" then
                set AppleScript's text item delimiters to (character id 31)
                set keywordList to text items of keywordBlob
                set AppleScript's text item delimiters to \"\"
            end if

            set targetItem to my resolveMediaItem(targetID)
            tell application \"Photos\"
                set description of targetItem to captionText
                set keywords of targetItem to keywordList
            end tell
            return \"ok\"
        end run
        """

        _ = try runAppleScript(
            script,
            arguments: [id, normalized.caption, normalized.keywordBlob],
            timeoutSeconds: ScriptTimeout.writeMetadata,
            operationName: "write metadata"
        )
    }

    public func exportAssetToTemporaryURL(id: String, kind: MediaKind) async throws -> URL {
        if kind == .video {
            do {
                return try await exportVideoAssetToTemporaryURLViaPhotosFramework(id: id)
            } catch {
                if !Self.shouldFallbackToAppleScriptAfterFrameworkVideoAcquireFailure(error) {
                    throw error
                }
            }
        }

        return try exportAssetToTemporaryURLViaAppleScript(id: id, kind: kind)
    }

    private func exportAssetToTemporaryURLViaAppleScript(id: String, kind: MediaKind) throws -> URL {
        let exportRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoDescriptionCreatorExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        let script = """
        \(mediaItemResolverAppleScript)

        on run argv
            set exportPath to item 1 of argv
            set targetID to item 2 of argv
            set exportFolder to POSIX file exportPath
            set targetItem to my resolveMediaItem(targetID)
            tell application \"Photos\"
                export {targetItem} to exportFolder
            end tell
            return \"ok\"
        end run
        """

        _ = try runAppleScript(
            script,
            arguments: [exportRoot.path, id],
            timeoutSeconds: Self.exportAssetTimeout(for: kind),
            operationName: "export asset"
        )

        guard let exportedFile = firstRegularFile(in: exportRoot) else {
            throw PhotosAppleScriptError.noExportedFileFound
        }

        return exportedFile
    }

    private func exportVideoAssetToTemporaryURLViaPhotosFramework(id: String) async throws -> URL {
        let identifiers = photoIdentifierCandidates(from: id)
        guard let asset = resolveAsset(identifierCandidates: identifiers, mediaType: .video) else {
            throw PhotosAppleScriptError.scriptFailed(message: "Photos video asset could not be resolved for id: \(id).")
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true

        let requestedAsset = try await requestVideoAsset(
            for: asset,
            options: options,
            timeoutSeconds: ScriptTimeout.requestVideoAsset
        )

        if let urlAsset = requestedAsset as? AVURLAsset,
           urlAsset.url.isFileURL,
           let stagedURL = try? stageVideoAssetFile(from: urlAsset.url, assetID: id)
        {
            return stagedURL
        }

        return try await exportRequestedVideoAsset(
            asset,
            options: options,
            assetID: id
        )
    }

    public func photoPreviewToTemporaryURL(id: String, maxPixelSize: Int) async throws -> URL? {
        let identifiers = photoIdentifierCandidates(from: id)
        guard let asset = resolveAsset(identifierCandidates: identifiers, mediaType: .image) else {
            return nil
        }
        guard asset.mediaType == .image else {
            return nil
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current

        let targetEdge = max(512, maxPixelSize)
        let targetSize = CGSize(width: targetEdge, height: targetEdge)

        guard let image = await requestImage(
            for: asset,
            targetSize: targetSize,
            options: options
        ) else {
            return nil
        }

        return writePreviewImageToTemporaryURL(image, assetID: id)
    }

    public func isPhotosAppRunning() async -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: PhotosLifecycle.appBundleIdentifier).isEmpty
    }

    public func quitPhotosAppGracefully() async -> Bool {
        guard await isPhotosAppRunning() else {
            return true
        }

        let script = """
        tell application "Photos"
            quit
        end tell
        """

        do {
            _ = try runAppleScript(
                script,
                timeoutSeconds: ScriptTimeout.capabilityProbe,
                operationName: "quit Photos"
            )
        } catch {
            return false
        }

        return await Self.waitForCondition(
            timeoutSeconds: PhotosLifecycle.quitTimeoutSeconds,
            pollIntervalSeconds: PhotosLifecycle.pollIntervalSeconds
        ) {
            !(await self.isPhotosAppRunning())
        }
    }

    public func launchPhotosApp() async throws {
        let appURL = try await MainActor.run { () throws -> URL in
            if let resolvedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: PhotosLifecycle.appBundleIdentifier) {
                return resolvedURL
            }
            throw PhotosAppleScriptError.scriptFailed(message: "Photos.app could not be located for relaunch.")
        }

        try await Self.awaitLaunch { completion in
            Task { @MainActor in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                    completion(error)
                }
            }
        }
    }

    public func waitForPhotosReady(timeoutSeconds: TimeInterval) async -> Bool {
        await Self.waitForCondition(
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: PhotosLifecycle.pollIntervalSeconds
        ) {
            guard await self.isPhotosAppRunning() else {
                return false
            }
            return await self.verifyAutomationAccess()
        }
    }

    public func photosResidentMemoryBytes() async -> UInt64? {
        guard
            let photosApp = NSRunningApplication.runningApplications(withBundleIdentifier: PhotosLifecycle.appBundleIdentifier).first
        else {
            return nil
        }

        let output: String
        do {
            output = try runCommand(
                executablePath: "/bin/ps",
                arguments: ["-o", "rss=", "-p", String(photosApp.processIdentifier)],
                timeoutSeconds: ScriptTimeout.memoryProbe
            )
        } catch {
            return nil
        }

        let kilobyteText = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .first ?? ""
        guard let kilobytes = UInt64(kilobyteText) else {
            return nil
        }

        return kilobytes * 1024
    }

    public func verifyAutomationAccess() async -> Bool {
        let script = """
        tell application \"Photos\"
            count media items
        end tell
        """

        do {
            _ = try runAppleScript(
                script,
                timeoutSeconds: ScriptTimeout.capabilityProbe,
                operationName: "verify automation access"
            )
            return true
        } catch {
            return false
        }
    }

    static func awaitLaunch(
        using launcher: @escaping (@escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            launcher { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    static func waitForCondition(
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let clampedTimeout = max(0, timeoutSeconds)
        let deadline = Date().addingTimeInterval(clampedTimeout)
        let clampedPollInterval = max(0.01, pollIntervalSeconds)

        while true {
            if Task.isCancelled {
                return false
            }
            if await condition() {
                return true
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                return false
            }

            let delaySeconds = min(clampedPollInterval, remaining)
            let delayNanoseconds = UInt64((delaySeconds * 1_000_000_000).rounded())
            await sleep(max(1, delayNanoseconds))
        }
    }

    public func listUserAlbums() async throws -> [AlbumSummary] {
        let script = """
        tell application \"Photos\"
            set rows to {}
            repeat with targetAlbum in albums
                set albumID to id of targetAlbum
                set albumName to name of targetAlbum
                set end of rows to albumID & tab & albumName
            end repeat
            set AppleScript's text item delimiters to linefeed
            set outputText to rows as text
            set AppleScript's text item delimiters to \"\"
            return outputText
        end tell
        """

        let output = try runAppleScript(
            script,
            timeoutSeconds: ScriptTimeout.listAlbums,
            operationName: "list albums"
        )
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { row -> AlbumSummary? in
                let columns = row.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count >= 2 else { return nil }
                let id = String(columns[0])
                let name = String(columns[1])
                let count = columns.count >= 3 ? (Int(columns[2]) ?? -1) : -1
                return AlbumSummary(id: id, name: name, itemCount: count)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func makeExistingMetadata(captionRaw: String, keywordsRaw: String) -> ExistingMetadataState {
        let caption = captionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = keywordsRaw
            .split(separator: Character(UnicodeScalar(31)), omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("missing value") != .orderedSame }

        let ownershipTag = OwnershipTagCodec.extract(from: keywords)
        let hasMeaningfulCaption = !caption.isEmpty && caption.caseInsensitiveCompare("missing value") != .orderedSame
        let hasKeywords = !keywords.isEmpty
        let isExternal = ownershipTag == nil && (hasMeaningfulCaption || hasKeywords)

        return ExistingMetadataState(
            caption: hasMeaningfulCaption ? caption : nil,
            keywords: keywords,
            ownershipTag: ownershipTag,
            isExternal: isExternal
        )
    }

    private func parseEnumeratedAssets(from output: String) async -> [MediaAsset] {
        var assets: [MediaAsset] = []
        assets.reserveCapacity(256)
        var missingDateIDs: [String] = []

        for row in output.split(whereSeparator: \.isNewline) {
            let columns = row.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }

            let id = String(columns[0])
            let filename = String(columns[1])
            let dateString = String(columns[2])
            let captureDate = parseDate(dateString)
            let kind = inferMediaKind(from: filename)
            assets.append(MediaAsset(id: id, filename: filename, captureDate: captureDate, kind: kind))
            if captureDate == nil {
                missingDateIDs.append(id)
            }
        }

        guard !missingDateIDs.isEmpty else {
            return assets
        }

        let fallbackDates = resolveModificationDates(for: missingDateIDs)
        guard !fallbackDates.isEmpty else {
            return assets
        }

        for index in assets.indices {
            guard assets[index].captureDate == nil else { continue }
            guard let fallbackDate = fallbackDates[assets[index].id] else { continue }
            let current = assets[index]
            assets[index] = MediaAsset(
                id: current.id,
                filename: current.filename,
                captureDate: fallbackDate,
                kind: current.kind
            )
        }

        return assets
    }

    private func photoIdentifierCandidates(from id: String) -> [String] {
        var candidates: [String] = []
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            candidates.append(trimmed)
        }
        let base = baseIdentifier(from: trimmed)
        if !base.isEmpty, !candidates.contains(base) {
            candidates.append(base)
        }
        return candidates
    }

    private func resolveAsset(
        identifierCandidates: [String],
        mediaType: PHAssetMediaType? = nil
    ) -> PHAsset? {
        guard !identifierCandidates.isEmpty else {
            return nil
        }

        let directFetch = PHAsset.fetchAssets(withLocalIdentifiers: identifierCandidates, options: nil)
        if let directMatch = firstMatchingAsset(in: directFetch, mediaType: mediaType) {
            return directMatch
        }

        for candidate in identifierCandidates where !candidate.contains("/") {
            let options = PHFetchOptions()
            options.fetchLimit = 5
            options.predicate = NSPredicate(format: "localIdentifier BEGINSWITH %@", "\(candidate)/")
            let prefixFetch = PHAsset.fetchAssets(with: options)
            if let prefixMatch = firstMatchingAsset(in: prefixFetch, mediaType: mediaType) {
                return prefixMatch
            }
        }

        return nil
    }

    private func resolveModificationDates(for ids: [String]) -> [String: Date] {
        var datesByID: [String: Date] = [:]
        var seen: Set<String> = []

        for rawID in ids {
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            guard seen.insert(id).inserted else { continue }

            let candidates = photoIdentifierCandidates(from: id)
            guard let asset = resolveAsset(identifierCandidates: candidates),
                  let modificationDate = asset.modificationDate
            else {
                continue
            }
            datesByID[id] = modificationDate
        }

        return datesByID
    }

    private func firstMatchingAsset(
        in result: PHFetchResult<PHAsset>,
        mediaType: PHAssetMediaType?
    ) -> PHAsset? {
        guard let mediaType else {
            return result.firstObject
        }

        var matched: PHAsset?
        result.enumerateObjects { asset, _, stop in
            guard asset.mediaType == mediaType else {
                return
            }
            matched = asset
            stop.pointee = true
        }
        return matched
    }

    enum PreviewRequestDecision: Equatable {
        case wait
        case returnImage
        case returnNil
    }

    static func previewRequestDecision(
        imagePresent: Bool,
        info: [AnyHashable: Any]?
    ) -> PreviewRequestDecision {
        let isCancelled = ((info?[PHImageCancelledKey] as? NSNumber)?.boolValue) ?? false
        if isCancelled {
            return .returnNil
        }

        if (info?[PHImageErrorKey] as? Error) != nil {
            return .returnNil
        }

        let isInCloud = ((info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue) ?? false
        if isInCloud {
            return .returnNil
        }

        let isDegraded = ((info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue) ?? false
        if imagePresent {
            return isDegraded ? .wait : .returnImage
        }

        return isDegraded ? .wait : .returnNil
    }

    static func exportAssetTimeout(for kind: MediaKind) -> TimeInterval {
        switch kind {
        case .photo:
            ScriptTimeout.exportPhotoAsset
        case .video:
            ScriptTimeout.exportVideoAsset
        }
    }

    static func preferredVideoExportFileType(from supportedTypes: [AVFileType]) -> AVFileType? {
        for candidate in [AVFileType.mov, .mp4, .m4v] where supportedTypes.contains(candidate) {
            return candidate
        }
        return supportedTypes.first
    }

    static func shouldFallbackToAppleScriptAfterFrameworkVideoAcquireFailure(_ error: Error) -> Bool {
        guard let photosError = error as? PhotosAppleScriptError else {
            return true
        }

        switch photosError {
        case let .scriptTimedOut(operation, _):
            let normalizedOperation = operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ![
                "download video asset",
                "prepare video export session",
                "export video asset"
            ].contains(normalizedOperation)
        case .scriptFailed, .noExportedFileFound:
            return true
        }
    }

    private func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        options: PHImageRequestOptions
    ) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let manager = PHImageManager.default()
            let lock = NSLock()
            var didResume = false
            var requestID: PHImageRequestID = PHInvalidImageRequestID

            func resumeOnce(_ image: NSImage?) {
                lock.lock()
                guard !didResume else {
                    lock.unlock()
                    return
                }
                didResume = true
                let activeRequestID = requestID
                lock.unlock()

                if activeRequestID != PHInvalidImageRequestID {
                    manager.cancelImageRequest(activeRequestID)
                }
                continuation.resume(returning: image)
            }

            let timeoutWork = DispatchWorkItem {
                resumeOnce(nil)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + ScriptTimeout.previewImageRequestGuard,
                execute: timeoutWork
            )

            requestID = manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                switch Self.previewRequestDecision(imagePresent: image != nil, info: info) {
                case .wait:
                    return
                case .returnImage:
                    timeoutWork.cancel()
                    resumeOnce(image)
                case .returnNil:
                    timeoutWork.cancel()
                    resumeOnce(nil)
                }
            }
        }
    }

    private func requestVideoAsset(
        for asset: PHAsset,
        options: PHVideoRequestOptions,
        timeoutSeconds: TimeInterval
    ) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let manager = PHImageManager.default()
            let lock = NSLock()
            var didResume = false
            var requestID: PHImageRequestID = PHInvalidImageRequestID

            func resumeOnce(with result: Result<AVAsset, Error>) {
                lock.lock()
                guard !didResume else {
                    lock.unlock()
                    return
                }
                didResume = true
                let activeRequestID = requestID
                lock.unlock()

                if activeRequestID != PHInvalidImageRequestID {
                    manager.cancelImageRequest(activeRequestID)
                }

                switch result {
                case let .success(asset):
                    continuation.resume(returning: asset)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            let timeoutWork = DispatchWorkItem {
                resumeOnce(
                    with: .failure(
                        PhotosAppleScriptError.scriptTimedOut(
                            operation: "download video asset",
                            timeoutSeconds: Int(timeoutSeconds.rounded())
                        )
                    )
                )
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + max(1, timeoutSeconds),
                execute: timeoutWork
            )

            requestID = manager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if ((info?[PHImageCancelledKey] as? NSNumber)?.boolValue) == true {
                    timeoutWork.cancel()
                    resumeOnce(
                        with: .failure(
                            PhotosAppleScriptError.scriptFailed(message: "Video request was cancelled.")
                        )
                    )
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    timeoutWork.cancel()
                    resumeOnce(with: .failure(error))
                    return
                }

                guard let avAsset else {
                    timeoutWork.cancel()
                    let isInCloud = ((info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue) ?? false
                    let message = isInCloud
                        ? "Video is still in iCloud after requesting a download."
                        : "Photos did not provide a video asset."
                    resumeOnce(with: .failure(PhotosAppleScriptError.scriptFailed(message: message)))
                    return
                }

                timeoutWork.cancel()
                resumeOnce(with: .success(avAsset))
            }
        }
    }

    private func exportRequestedVideoAsset(
        _ asset: PHAsset,
        options: PHVideoRequestOptions,
        assetID: String
    ) async throws -> URL {
        for presetName in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
            guard let exportSession = try await requestVideoExportSession(
                for: asset,
                options: options,
                presetName: presetName,
                timeoutSeconds: ScriptTimeout.prepareVideoExportSession
            ) else {
                continue
            }

            guard let outputFileType = Self.preferredVideoExportFileType(from: exportSession.rawValue.supportedFileTypes) else {
                continue
            }

            let outputURL = try makeTemporaryVideoOutputURL(
                assetID: assetID,
                fileExtension: Self.fileExtension(for: outputFileType)
            )

            do {
                return try await exportVideoAsset(
                    using: exportSession,
                    outputURL: outputURL,
                    outputFileType: outputFileType,
                    timeoutSeconds: ScriptTimeout.exportPreparedVideoAsset
                )
            } catch {
                try? fileManager.removeItem(at: outputURL.deletingLastPathComponent())
                throw error
            }
        }

        throw PhotosAppleScriptError.scriptFailed(message: "Photos could not prepare a compatible video export session.")
    }

    private func requestVideoExportSession(
        for asset: PHAsset,
        options: PHVideoRequestOptions,
        presetName: String,
        timeoutSeconds: TimeInterval
    ) async throws -> UncheckedExportSession? {
        try await withCheckedThrowingContinuation { continuation in
            let manager = PHImageManager.default()
            let lock = NSLock()
            var didResume = false
            var requestID: PHImageRequestID = PHInvalidImageRequestID

            func resumeOnce(with result: Result<UncheckedExportSession?, Error>) {
                lock.lock()
                guard !didResume else {
                    lock.unlock()
                    return
                }
                didResume = true
                let activeRequestID = requestID
                lock.unlock()

                if activeRequestID != PHInvalidImageRequestID {
                    manager.cancelImageRequest(activeRequestID)
                }

                switch result {
                case let .success(exportSession):
                    continuation.resume(returning: exportSession)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            let timeoutWork = DispatchWorkItem {
                resumeOnce(
                    with: .failure(
                        PhotosAppleScriptError.scriptTimedOut(
                            operation: "prepare video export session",
                            timeoutSeconds: Int(timeoutSeconds.rounded())
                        )
                    )
                )
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + max(1, timeoutSeconds),
                execute: timeoutWork
            )

            requestID = manager.requestExportSession(
                forVideo: asset,
                options: options,
                exportPreset: presetName
            ) { exportSession, info in
                if ((info?[PHImageCancelledKey] as? NSNumber)?.boolValue) == true {
                    timeoutWork.cancel()
                    resumeOnce(
                        with: .failure(
                            PhotosAppleScriptError.scriptFailed(message: "Video export-session request was cancelled.")
                        )
                    )
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    timeoutWork.cancel()
                    resumeOnce(with: .failure(error))
                    return
                }

                timeoutWork.cancel()
                let wrappedSession = exportSession.map { UncheckedExportSession(rawValue: $0) }
                resumeOnce(with: .success(wrappedSession))
            }
        }
    }

    private func exportVideoAsset(
        using exportSession: UncheckedExportSession,
        outputURL: URL,
        outputFileType: AVFileType,
        timeoutSeconds: TimeInterval
    ) async throws -> URL {
        let sendableSession = exportSession
        sendableSession.rawValue.shouldOptimizeForNetworkUse = false

        let timeoutNanoseconds = UInt64(max(1, (timeoutSeconds * 1_000_000_000).rounded()))

        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await withTaskCancellationHandler(operation: {
                    try await sendableSession.rawValue.export(to: outputURL, as: outputFileType)
                    return outputURL
                }, onCancel: {
                    sendableSession.rawValue.cancelExport()
                })
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw PhotosAppleScriptError.scriptTimedOut(
                    operation: "export video asset",
                    timeoutSeconds: Int(timeoutSeconds.rounded())
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func stageVideoAssetFile(from sourceURL: URL, assetID: String) throws -> URL {
        let pathExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let outputURL = try makeTemporaryVideoOutputURL(assetID: assetID, fileExtension: pathExtension)
        do {
            try fileManager.copyItem(at: sourceURL, to: outputURL)
            return outputURL
        } catch {
            try? fileManager.removeItem(at: outputURL.deletingLastPathComponent())
            throw error
        }
    }

    private func makeTemporaryVideoOutputURL(assetID: String, fileExtension: String) throws -> URL {
        let exportRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoDescriptionCreatorVideoExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        let sanitizedID = assetID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let basename = sanitizedID.isEmpty ? "video" : sanitizedID
        let normalizedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = normalizedExtension.isEmpty ? basename : "\(basename).\(normalizedExtension)"
        return exportRoot.appendingPathComponent(filename)
    }

    private static func fileExtension(for fileType: AVFileType) -> String {
        switch fileType {
        case .mov:
            return "mov"
        case .mp4:
            return "mp4"
        case .m4v:
            return "m4v"
        default:
            return "mov"
        }
    }

    private func writePreviewImageToTemporaryURL(_ image: NSImage, assetID: String) -> URL? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else {
            return nil
        }

        let previewRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoDescriptionCreatorPreviews", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: previewRoot, withIntermediateDirectories: true)
            let safeID = assetID
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            let filename = safeID.isEmpty ? "preview.jpg" : "\(safeID).jpg"
            let outputURL = previewRoot.appendingPathComponent(filename)
            try jpegData.write(to: outputURL, options: [.atomic])
            return outputURL
        } catch {
            return nil
        }
    }

    private func baseIdentifier(from targetID: String) -> String {
        guard let slash = targetID.firstIndex(of: "/") else {
            return targetID
        }
        return String(targetID[..<slash])
    }

    private var baseIdentifierHelperAppleScript: String {
        """
        on baseIdentifier(targetID)
            if targetID contains \"/\" then
                set AppleScript's text item delimiters to \"/\"
                set idParts to text items of targetID
                set AppleScript's text item delimiters to \"\"
                if (count of idParts) > 0 then
                    return item 1 of idParts
                end if
            end if
            return targetID
        end baseIdentifier
        """
    }

    private func makeScopeTargetItemsAssignment(scope: ScopeSource) -> String {
        switch scope {
        case .library:
            return "set targetItems to media items"
        case let .album(id):
            return "set targetAlbum to first album whose id is \"\(escapeAppleScriptString(id))\"\nset targetItems to media items of targetAlbum"
        case let .picker(ids):
            let idList = makeAppleScriptListLiteral(ids)
            return """
            set targetItems to {}
            repeat with pickerID in \(idList)
                set normalizedPickerID to pickerID as text
                set basePickerID to my baseIdentifier(normalizedPickerID)
                try
                    set end of targetItems to (first media item whose id is normalizedPickerID)
                end try
                if basePickerID is not equal to normalizedPickerID then
                    try
                        set end of targetItems to (first media item whose id is basePickerID)
                    end try
                end if
            end repeat
            """
        case .captionWorkflow:
            return "set targetItems to {}"
        }
    }

    private func makeEnumerationScript(scope: ScopeSource) -> String {
        let assignment = makeScopeTargetItemsAssignment(scope: scope)

        return """
        \(baseIdentifierHelperAppleScript)

        tell application \"Photos\"
            \(assignment)
            set rows to {}
            repeat with targetItem in targetItems
                set itemID to id of targetItem
                set itemFilename to filename of targetItem
                set itemDate to date of targetItem
                set itemDateText to \"\"
                try
                    set itemDateText to itemDate as string
                on error
                    set itemDateText to \"\"
                end try
                set end of rows to itemID & tab & itemFilename & tab & itemDateText
            end repeat
            set AppleScript's text item delimiters to linefeed
            set outputText to rows as text
            set AppleScript's text item delimiters to \"\"
            return outputText
        end tell
        """
    }

    private func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        if let epochSeconds = TimeInterval(trimmed) {
            return Date(timeIntervalSince1970: epochSeconds)
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        if let date = fallback.date(from: trimmed) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent

        let stylePairs: [(DateFormatter.Style, DateFormatter.Style)] = [
            (.full, .full),
            (.full, .long),
            (.long, .long),
            (.long, .medium),
            (.medium, .medium),
            (.short, .short)
        ]

        for (dateStyle, timeStyle) in stylePairs {
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
            if let parsed = formatter.date(from: trimmed) {
                return parsed
            }
        }

        return nil
    }

    private func inferMediaKind(from filename: String) -> MediaKind {
        let ext = (filename as NSString).pathExtension.lowercased()
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "hevc", "mts", "m2ts"]
        return videoExtensions.contains(ext) ? .video : .photo
    }

    private func firstRegularFile(in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }

        for case let candidate as URL in enumerator {
            guard
                let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey]),
                values.isRegularFile == true
            else {
                continue
            }
            return candidate
        }
        return nil
    }

    private var mediaItemResolverAppleScript: String {
        """
        on baseIdentifier(targetID)
            if targetID contains \"/\" then
                set AppleScript's text item delimiters to \"/\"
                set idParts to text items of targetID
                set AppleScript's text item delimiters to \"\"
                if (count of idParts) > 0 then
                    return item 1 of idParts
                end if
            end if
            return targetID
        end baseIdentifier

        on resolveMediaItem(targetID)
            set normalizedID to targetID as text
            set baseID to my baseIdentifier(normalizedID)

            tell application \"Photos\"
                try
                    return first media item whose id is normalizedID
                end try
                if baseID is not equal to normalizedID then
                    try
                        return first media item whose id is baseID
                    end try
                end if
            end tell

            error \"No media item found for id: \" & normalizedID
        end resolveMediaItem
        """
    }

    private func runAppleScript(
        _ source: String,
        arguments: [String] = [],
        timeoutSeconds: TimeInterval = 30,
        operationName: String = "AppleScript"
    ) throws -> String {
        let result = try runCommandWithResult(
            executablePath: "/usr/bin/osascript",
            arguments: ["-l", "AppleScript", "-e", source, "--"] + arguments,
            timeoutSeconds: timeoutSeconds,
            timeoutOperationName: operationName
        )

        guard result.status == 0 else {
            let rawMessage = result.error.isEmpty ? "Unknown AppleScript failure" : result.error
            let enrichedMessage = enrichScriptErrorMessage(rawMessage, source: source)
            throw PhotosAppleScriptError.scriptFailed(message: enrichedMessage)
        }

        return result.output
    }

    private func runCommand(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) throws -> String {
        let result = try runCommandWithResult(
            executablePath: executablePath,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )

        guard result.status == 0 else {
            let rawMessage = result.error.isEmpty ? "Command failed: \(executablePath)" : result.error
            throw PhotosAppleScriptError.scriptFailed(message: rawMessage)
        }

        return result.output
    }

    private func runCommandWithResult(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval,
        timeoutOperationName: String? = nil
    ) throws -> (status: Int32, output: String, error: String) {
        let totalArgumentBytes = executablePath.lengthOfBytes(using: .utf8)
            + arguments.reduce(0) { partialResult, argument in
                partialResult + argument.lengthOfBytes(using: .utf8) + 1
            }
        if totalArgumentBytes > ScriptTimeout.maximumCommandArgumentBytes {
            throw PhotosAppleScriptError.scriptFailed(
                message: "Command arguments exceeded safe launch limit (\(totalArgumentBytes) bytes)."
            )
        }

        return try autoreleasepool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let outputCollector = DataCollector()
            let errorCollector = DataCollector()
            let outputReadHandle = outputPipe.fileHandleForReading
            let errorReadHandle = errorPipe.fileHandleForReading
            let outputWriteHandle = outputPipe.fileHandleForWriting
            let errorWriteHandle = errorPipe.fileHandleForWriting
            var didCloseWriteHandles = false

            outputReadHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                outputCollector.append(chunk)
            }
            errorReadHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                errorCollector.append(chunk)
            }

            defer {
                outputReadHandle.readabilityHandler = nil
                errorReadHandle.readabilityHandler = nil
                outputReadHandle.closeFile()
                errorReadHandle.closeFile()
                if !didCloseWriteHandles {
                    outputWriteHandle.closeFile()
                    errorWriteHandle.closeFile()
                }
            }

            let terminationGroup = DispatchGroup()
            terminationGroup.enter()
            process.terminationHandler = { _ in
                terminationGroup.leave()
            }

            try process.run()
            // Close parent write handles immediately so the read side can reliably see EOF.
            outputWriteHandle.closeFile()
            errorWriteHandle.closeFile()
            didCloseWriteHandles = true

            let waitResult = terminationGroup.wait(timeout: .now() + max(1, timeoutSeconds))
            if waitResult == .timedOut {
                if process.isRunning {
                    process.terminate()
                    if terminationGroup.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                        _ = terminationGroup.wait(timeout: .now() + 1)
                    }
                }
                throw PhotosAppleScriptError.scriptTimedOut(
                    operation: timeoutOperationName ?? executablePath,
                    timeoutSeconds: Int(timeoutSeconds.rounded())
                )
            }

            outputCollector.append(outputReadHandle.readDataToEndOfFile())
            errorCollector.append(errorReadHandle.readDataToEndOfFile())

            let output = String(data: outputCollector.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(data: errorCollector.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return (process.terminationStatus, output, errorOutput)
        }
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func makeAppleScriptListLiteral(_ values: [String]) -> String {
        if values.isEmpty {
            return "{}"
        }

        let serialized = values
            .map { "\"\(escapeAppleScriptString($0))\"" }
            .joined(separator: ", ")
        return "{\(serialized)}"
    }

    private func enrichScriptErrorMessage(_ message: String, source: String) -> String {
        guard message.localizedCaseInsensitiveContains("syntax error") else {
            return message
        }

        guard
            let matchRange = message.range(of: #"\b(\d+):(\d+):"#, options: .regularExpression)
        else {
            return message
        }

        let token = String(message[matchRange]).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let parts = token.split(separator: ":", omittingEmptySubsequences: true)
        guard let startOffset = parts.first.flatMap({ Int($0) }) else {
            return message
        }

        let sourceNSString = source as NSString
        let normalizedStart = max(0, min(sourceNSString.length, startOffset))
        let contextRadius = 80
        let contextStart = max(0, normalizedStart - contextRadius)
        let contextLength = min(sourceNSString.length - contextStart, contextRadius * 2)
        guard contextLength > 0 else {
            return message
        }

        let excerpt = sourceNSString.substring(with: NSRange(location: contextStart, length: contextLength))
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\(message) [script excerpt: \(excerpt)]"
    }
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }
}

public enum PhotosAppleScriptError: Error, LocalizedError {
    case scriptFailed(message: String)
    case scriptTimedOut(operation: String, timeoutSeconds: Int)
    case noExportedFileFound

    public var errorDescription: String? {
        switch self {
        case let .scriptFailed(message):
            return "AppleScript failed: \(message)"
        case let .scriptTimedOut(operation, timeoutSeconds):
            return "\(operation) timed out after \(timeoutSeconds)s."
        case .noExportedFileFound:
            return "Photos export succeeded but no file was found in the export folder."
        }
    }
}
