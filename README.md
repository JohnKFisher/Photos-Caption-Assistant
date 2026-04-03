# Photos Caption Assistant

This is a personal hobby app built for my own Photos workflow. It is being published so the source is visible and recoverable, not because it is polished for general public use. Outside usefulness is incidental. No support commitment, stability guarantee, or warranty is implied beyond the repository's actual license situation.

Photos Caption Assistant generates captions and keywords for photos and videos in Apple Photos using a local Ollama model, then writes the generated metadata back into Photos.

## Current Operating Model

- Local-first only. The app talks to a local Ollama service on `http://127.0.0.1:11434`.
- Photos metadata writes still use Apple Photos automation plus AppleScript-backed write paths.
- The current production write path is intentionally conservative: Photos automation remains the source of truth for metadata reads and writes, overwrite gating, picker resolution, queued-albums stage resolution, and Photos lifecycle handling.
- The app can guide first-run Ollama setup by opening the official macOS download page after explicit confirmation. It does not install Ollama automatically.
- The app can start Ollama locally when needed after it is installed. If the required `qwen2.5vl:7b` model is missing, the app asks before downloading it.

## Requirements

- macOS 15 or later.
- Apple Photos installed.
- Photos.app open before starting a write run.
- Ollama is required before runs can start, but it does not have to be installed before first launch. The app can open the official macOS download page to guide setup.
- The app does not auto-install Ollama and does not run remote install scripts.
- The `qwen2.5vl:7b` model available locally, or willingness to let the app download it through Ollama after a separate confirmation.
- User approval for:
  - Photos library access
  - Apple Events / automation access to Photos

## Safety And Scope

- The default startup scope is `Album`, not whole library.
- Overwriting non-app metadata without per-item prompts is off by default.
- The app shows a visible run summary before starting.
- Whole-library runs require confirmation before any write work starts.
- Runs that overwrite non-app metadata without per-item prompts require confirmation.
- If Ollama is missing, the app blocks runs and offers to open the official download page after confirmation.
- If the model must actually be downloaded, the app asks before downloading it.

## Data And Storage

Persistent state lives here:

- `~/Library/Application Support/PhotosCaptionAssistant/run_resume_state.json`
- `~/Library/Application Support/PhotosCaptionAssistant/caption_workflow_configuration.json`

On first launch after the rename, the app copies forward known persistent state from the old `PhotoDescriptionCreator` Application Support folder if the new folder does not exist yet. The old files are left in place.

Temporary outputs are created under the current temp directory in folders such as:

- `PhotosCaptionAssistantBenchmarks`
- `PhotosCaptionAssistantLastCompleted`
- `PhotosCaptionAssistantExports`
- `PhotosCaptionAssistantVideoExports`
- `PhotosCaptionAssistantPreviews`

The app now includes menu-accessible `Data & Storage` and `Diagnostics` windows. `Data & Storage` shows these paths, can open the data folder, and can clear only the resumable run-state snapshot.

## Build

Local verification:

```bash
swift test
swift build -c release --triple arm64-apple-macosx15.0 --product PhotosCaptionAssistant
swift build -c release --triple x86_64-apple-macosx15.0 --product PhotosCaptionAssistant
./scripts/build_app.sh
```

`./scripts/build_app.sh` now:

- increments the patch version
- increments the build number
- builds separate `arm64` and `x86_64` release binaries
- merges them into one universal executable with `lipo`
- packages the app into `dist/Photos Caption Assistant.app`
- ad-hoc signs the bundle and verifies the signature

Build artifacts are kept out of git. This repo is source-first.

Because the bundle identifier is now `com.jkfisher.PhotosCaptionAssistant`, macOS will likely prompt again for Photos and Apple Events permissions even if you previously approved the old app name.

## Opening The App On macOS

The packaged app is ad-hoc signed for local use, but it is not notarized for public distribution. macOS may warn when you open it.

Preferred safe opening flow:

1. In Finder, locate `dist/Photos Caption Assistant.app`.
2. Control-click the app and choose `Open`.
3. Click `Open` again if macOS asks for confirmation.

If macOS still blocks launch:

1. Try opening it once from Finder.
2. Open `System Settings > Privacy & Security`.
3. Find the blocked-app message near the bottom and choose `Open Anyway`.

## Known Limits

- This app depends on Apple Photos automation, which can still be fragile on long runs.
- It depends on a local Ollama install, but the app now uses a manual browser handoff instead of requiring preinstall before first launch.
- It is optimized for a personal workflow, not for a broad compatibility matrix.
- It is not a cloud service, collaboration tool, or background agent.
- It is not notarized and should be treated as a local hobby build.
