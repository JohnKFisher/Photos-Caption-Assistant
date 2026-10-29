# Photos Caption Assistant

Current version/build: 4.6.6 (27)
Current description logic version: 3.0.0

## Current status

Photos Caption Assistant is a local-first macOS captioning workbench. On macOS 27 and later, normal Photos workflows use PhotoKit for library and album enumeration, selected-asset resolution, metadata reads and writes, preview media acquisition, and post-write verification. macOS 15–26 continue to use the established AppleScript compatibility backend. The app's minimum deployment target remains macOS 15; CI uses the Xcode 27 SDK to compile the newer symbols.

Caption and keyword generation remains local through Ollama and `qwen2.5vl:7b`. The app retains its run confirmations, overwrite policies, ownership tags, resumable state, cancellation, queued albums, retry reporting, and completed-item preview.

## Photos integration and metadata safety

- PhotoKit is selected at runtime on macOS 27+. It always operates on the System Photo Library; opening another library in Photos.app does not redirect native scans or writes. The app requests full Photos library access; denied, restricted, or limited access blocks runs that require the complete configured scope. Native runs do not require Photos.app to be open and do not use its quit/relaunch cycle. Preflight and run confirmation identify the target library.
- The AppleScript backend remains for macOS 15–26. It still requires Photos.app and Apple Events automation. There is no silent fallback from a failed native write to AppleScript.
- Asset lookup prefers exact Photos local identifiers. Legacy identifiers are accepted only when their old prefix resolves uniquely; filenames are never used as identity.
- Existing metadata is captured before analysis and passed to the native writer as a stale-change guard. Caption and keyword changes are submitted in one `performChanges` transaction. Keywords are reconciled as exact canonical values (Unicode NFC); replace behavior removes values outside the requested target, while merge/preserve/skip decisions remain in the existing run policy.
- The app reads metadata back after a PhotoKit change and reports the observed result. If an operation's completion is ambiguous, it checks the actual target and baseline state rather than guessing or blindly repeating a partial mutation. PhotoKit does not provide a rollback guarantee for partially applied changes.
- Normal albums, PhotoKit-exposed smart albums, and queued album enumeration use bounded pages and stable enumeration snapshots where available. macOS-only custom smart-album parity has not been verified against a real library. PhotoKit reads and previews support photos and videos, including hidden assets; this does not imply that every iCloud-only original is already locally available. Filenames use `PHAssetResource` lookup during enumeration to avoid an extra extended-metadata fetch per asset.
- AppleScript remains for the older-OS compatibility backend and the explicitly invoked legacy identity write/restore diagnostic. The scan benchmark compares readers and is opt-in; it does not perform metadata writes.

## Working product behavior

- Library, album, picker, and queued-album runs are available. Whole-library runs require explicit confirmation; no-prompt overwrites of metadata created outside the app require confirmation.
- Overwrite policy and app ownership tags distinguish app-generated metadata from user-authored metadata. Resume state and queued albums remain in Application Support.
- Normal PhotoKit runs queue every ID from the selected-scope snapshot before the first write. The existing pending-ID save is best effort, so durable recovery depends on that save succeeding. AppleScript library/album scans and queued-album runs retain discovered pending IDs; canceling during discovery may require a fresh run with the original scope to find items that were not yet queued. Explicit picker IDs remain queued during ordered preparation, then are replaced with canonical IDs before writes.
- The UI remains a toolbar-first run workbench with dedicated Settings, Preview, Data & Storage, and Diagnostics windows. Preview can show completed photo/video items during a run.
- Ollama setup and model download are explicit user actions. The app does not install Ollama, run remote installation scripts, upload media, or use cloud inference.
- The build script produces a universal `arm64` + `x86_64` app. GitHub Actions build/test and release jobs use an Xcode 27 runner; release publishing remains driven by a checked-in Info.plist version change and is not triggered by this modernization.

## Verification and known limits

- The implementation was compiled against the locally installed Xcode 27.0 / macOS 27.0 SDK on a macOS 27.2 host. The reviewed macOS 27.2 release notes add no further caption/keyword API used by this app; they deprecate `PHAssetResource.originalFilename` in favor of nullable `filename`, which the macOS 27+ enumerator uses.
- Automated tests exercise metadata reconciliation, stale-baseline matching, identifiers, enumeration helpers, and the existing run-coordinator behavior with test doubles. These do not prove behavior against a real Photos library.
- No real Photos write test or performance benchmark has been run. The production library was not modified. Consequently, there are no measured throughput claims yet; the architecture removes AppleScript invocations and Photos lifecycle restarts from macOS 27+ normal runs, but end-to-end speed depends on library and asset availability.
- Before relying on native writes, perform one caption/keyword write and restoration using a specifically designated disposable asset in the System Photo Library. An alternate library opened in Photos.app does not isolate PhotoKit. Verify the final caption and complete keyword set in Photos after each step; do not use an unrelated production-library item.
- iCloud-only media may require downloading or can be temporarily unavailable. Limited Photos access is not sufficient for full-library or album runs. Compatibility behavior on macOS 15–26, Photos authorization/write behavior on macOS 27, and custom smart-album parity still need on-device acceptance.
- Local packaged apps are ad-hoc signed by default unless a Developer ID signing identity is supplied. GitHub release notarization still needs the configured Apple signing and notarization secrets.

## Setup/runtime requirements

- macOS 15 or later; macOS 27+ for the native PhotoKit metadata backend.
- Ollama and the `qwen2.5vl:7b` model installed locally, or confirmation to download the model through Ollama.
- Photos library access. Apple Events automation and an open Photos.app are additionally required only on the macOS 15–26 compatibility backend.
- The app bundle identifier is `com.jkfisher.PhotosCaptionAssistant`.

Most recent durable known-good anchor:
- `checkpoint/20260402-180116-known-good`
