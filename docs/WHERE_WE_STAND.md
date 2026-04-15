# Photos Caption Assistant

Current version/build: 3.5.10 (18)
Current description logic version: 3.0.0

Current overall status:
The current source tree builds locally as version 3.5.10 build 18 and now includes safer run preflight checks, menu-accessible storage and diagnostics windows, deterministic source-controlled versioning, a universal macOS packaging script, adaptive immersive playback cadence, per-stage item retries for the core caption pipeline, and a version-triggered GitHub release flow that publishes a DMG. The core local captioning workflow is working, but this is still a personal hobby app built around Apple Photos automation rather than a polished public-distribution product.

What is working now:
- Local photo and video analysis through Ollama with the `qwen2.5vl:7b` model.
- Apple Photos metadata reads and writes, including captions, keywords, and app ownership tags.
- Library, album, picker, and Queued Albums runs.
- Visible run-summary/preflight UI showing source scope, exact count where practical, overwrite behavior, model status, and local Ollama service status.
- The main screen now uses a denser two-column workbench layout: card-based setup controls on the left and a compact preview-forward run summary/result pane on the right.
- Album names now surface before PhotoKit finishes resolving counts, so album-mode controls stop feeling dead on cold launch.
- The immersive completed-item view now uses a hybrid media layout: roomy landscape items keep the slim top HUD plus low-cover bottom dock, while tighter aspect ratios fall back to a dedicated bottom shelf so the chrome stays fully visible.
- The immersive completed-item view now buffers recent completed items even before full-screen opens, resumes any unseen backlog if you close and reopen it during a run, and suppresses same-asset replay inside that playback queue.
- Immersive playback cadence now learns from the rolling mean of the most recent completed-item intervals, aims to stay about two learned item-times behind the newest completion, and nudges preview holds up or down gradually instead of using the old fixed backlog-delay tiers.
- Aspect-fit immersive media now uses a restrained ambient matte instead of a flat black letterbox, and empty immersive state copy is centered until a completed preview exists.
- Capture dates now come across from AppleScript as stable local wall-clock timestamps so immersive timestamps match the Mac's local time instead of drifting through the earlier pseudo-epoch conversion.
- Run Summary now sits beside the main setup controls, while Data & Storage and Diagnostics live in separate windows opened from the menu bar.
- Safer startup defaults: `Album` is selected by default, and no-prompt overwrite of non-app metadata is off by default.
- Whole-library runs require explicit confirmation before write work starts.
- Runs that overwrite non-app metadata without per-item prompts require explicit confirmation.
- Core per-item stages now retry once automatically after a short pause when asset acquisition, caption generation/JSON decode, or Photos metadata write fails transiently.
- If Ollama is missing, the app now shows a setup card and can open the official macOS download page after explicit confirmation.
- Missing model downloads still require explicit confirmation, while ordinary local Ollama startup does not.
- Resume-state and queued-albums files are stored under Application Support and surfaced in the Data & Storage window.
- The build script now creates a universal `arm64` + `x86_64` app bundle in `dist/`.
- GitHub Actions now separate ordinary build/test verification from version-triggered release publishing, and releases package a DMG from committed source.
- Existing long-run progress, cancellation, resume-state persistence, diagnostics, and restart safeguards remain in place.

What is partially implemented:
- Long-run resilience is improved, but still depends on AppleScript and Photos relaunching cleanly when the automatic restart cycle fires.
- The guarded PhotoKit rollout still covers only the safe scan/count scopes already documented elsewhere; metadata writes remain AppleScript-backed.
- If Ollama is installed but not already running, the app cannot know model presence until it starts the local service and checks.

What is not implemented yet:
- No dedicated prompt comparison or prompt selection UI.
- No notarized public-distribution flow.

Known limitations and trust warnings:
- The packaged app is ad-hoc signed for local use but not notarized.
- The app depends on Apple Photos automation and local Ollama availability.
- Photos.app must be open before starting a write run.
- The bundle identifier is now `com.jkfisher.PhotosCaptionAssistant`, so macOS will likely prompt again for Photos and Apple Events permissions after the rename.
- The core production write path still relies on AppleScript and Photos automation for metadata reads, writes, overwrite gating, picker resolution, queued-albums resolution, and Photos lifecycle handling.
- The app does not install Ollama itself. It uses a manual browser handoff to the official download page when Ollama is missing.
- The app is still distributed as an ad-hoc-signed, non-notarized build, so Gatekeeper may still require Finder `Open` or `Privacy & Security -> Open Anyway`.
- This repo is source-first. Built app bundles and temp outputs should not be treated as source-of-truth artifacts.

Setup/runtime requirements:
- macOS 15 or later.
- Photos.app installed and open before starting a write run.
- Ollama required before runs can start, but not required before first launch; the app can open the official macOS download page to guide setup.
- The app does not auto-install Ollama or run remote install scripts.
- The `qwen2.5vl:7b` model installed locally, or willingness to let the app download it through Ollama after a separate confirmation.
- User approval for Photos library access and Apple Events automation when macOS prompts.
- First launch after the rename should be treated like a new app for macOS permission prompts.

Important operational risks:
- Large runs can still fail if Photos does not relaunch into an automation-ready state.
- First-time Ollama setup is still manual after the browser handoff.
- First-run model download can take several minutes.
- If Ollama is missing entirely, the run cannot start until the user installs it and clicks Re-check Setup.
- Whole-library runs and no-prompt overwrite modes are intentionally possible, but they still deserve caution even with the new confirmations.

Recommended next priorities:
- Decide whether this project will stay source-first and local-only, or gain a real notarized distribution path.
- Add a small, repeatable smoke-test checklist for future known-good anchors and releases.

Most recent durable known-good anchor:
- `checkpoint/20260402-180116-known-good`
