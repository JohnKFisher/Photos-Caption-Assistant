# Photo Description Creator

Current version/build: 2.4 (4)
Current description logic version: 3.0.0

Current overall status:
The current source tree builds as version 2.4 build 4 with description logic 3.0.0. The current durable known-good anchor is the March 22, 2026 caption-workflow baseline listed below.

What is working now:
- Local photo and video analysis through Ollama with the `qwen2.5vl:7b` model.
- Apple Photos metadata reads and writes, including captions, keywords, and app ownership tags.
- Library, album, and picker-based runs with overwrite policy checks.
- A `Caption Workflow` source mode that stores album-ID mappings for these four stages and re-queries them in order: `0 - Priority Captioning`, then `1 - No Caption - New Photos`, then `2 - No Caption - All`, then `3 - Older Caption Logic`.
- Incremental processing, pending-item tracking, and per-item completion previews.
- Batched metadata reads and batched metadata writes in the current source tree.
- Resilient enumerate-page retry behavior for large fast-order runs.
- Caption-workflow stage handoffs now preflight the configured albums, tolerate album renames, and use bounded retry/wait behavior before concluding that the next stage is empty or failed.
- Caption-workflow fast runs now collect and freeze bounded smart-album chunks before processing, so large shrinking smart albums can start sooner without relying on stale offsets.
- Automatic Photos restart after every 500 changed items, plus the same restart path as a backup when Photos memory usage crosses the configured threshold.
- Future builds from this source baseline now embed the current prompt files and use prompt logic 3.0.0.
- Launch-time capability checks now surface denied Photos automation immediately so unattended restart runs are less likely to stall later on a hidden permission prompt.
- Video analysis now selects three ordered key frames from a larger candidate set using time coverage plus lightweight visual-difference scoring.
- The run pipeline now defaults to one in-flight LLM analysis with bounded prepare-ahead overlap so the next asset can be readied without competing model calls.
- Analyzer-ready payloads are now prepared ahead of the LLM handoff when the analyzer supports it, so image encoding and video frame packaging can overlap with the current analysis.
- Completion preview rendering is now deferred off the metadata-write critical path with a small bounded backlog.
- The immersive preview now shows the same run counters as the main progress view, includes source context for each completed item, and uses backlog-aware `30s / 10s / sampled` display timing without slowing the processing pipeline.
- The cancel button now switches to `Canceling` after a cancel request is acknowledged while the current stage drains safely.

What is partially implemented:
- Long-run resilience is improved, but still depends on AppleScript and Photos relaunching cleanly when the automatic restart cycle fires.
- Prompt management exists in source text files and embedded analyzer constants, but there is no dedicated in-app prompt/version switcher.
- Recovery from interrupted or historical rollback states is only partially addressed; repo history before this baseline should not be treated as authoritative.

What is not implemented yet:
- No dedicated prompt comparison or prompt selection UI.
- No formal migration or repair tooling for previously lost git history.
- No fully isolated packaging flow that keeps build artifacts out of version control automatically.

Known limitations and trust warnings:
- The app depends on Apple Photos automation and local Ollama availability.
- Prompt quality and throughput can vary with model readiness and local machine performance.
- The `Caption Workflow` source now depends on saved stage-to-album mappings; if a mapped album is deleted or recreated under a new ID, the mapping must be repaired in the setup UI before the run can start.
- The `Caption Workflow` source re-queries each configured stage and may briefly wait/retry when Photos is slow to update the next smart album, so stage handoffs are a little more defensive than the normal fast library/album modes.
- The `Caption Workflow` fast-start path now trades a little more stage-refresh overhead for earlier visible progress; ordered traversal modes still use the slower full-stage snapshot path.
- If the immersive preview backlog grows past 60 queued items, it samples the queue to stay reasonably current instead of showing every completed image in strict order.
- Video-analysis throughput may vary modestly with clip format because key-frame selection now evaluates a larger candidate set before sending frames to the model.
- Metadata writes still happen after each analyzed window, so the pipeline is only partially streamed end to end even though preview generation now overlaps later writes.
- The internal metadata ownership logic version in code is currently separate from the app marketing version.
- The logic version major bump to 3.0.0 will cause previously app-owned 2.x metadata to be treated as older and eligible for overwrite under the usual ownership rules.
- This repo started a fresh baseline on March 14, 2026; earlier rollback points should be treated cautiously.

Setup/runtime requirements:
- macOS 15 or later.
- Photos.app installed and open before starting a write run.
- Ollama running locally on `http://127.0.0.1:11434`.
- The `qwen2.5vl:7b` model installed locally.
- User approval for Photos library access and Apple Events automation when macOS prompts.

Important operational risks:
- Large runs now deliberately pause for about 90 seconds per 500 changed items to reduce Photos instability, and they can still fail if Photos does not relaunch into an automation-ready state.
- Local model inference may time out on first run or under heavy load.
- Build artifacts are currently present in the repo history and should not be treated as source-of-truth outputs.

Recommended next priorities:
- Add a cleaner artifact management strategy so builds do not muddy repo state.
- Add more explicit diagnostics around prompt version, model readiness, and fallback behavior.
- Add a small, repeatable smoke-test workflow for known-good verification before future anchors.

Most recent durable known-good anchor:
- `known-good/20260322-v2-4-caption-workflow-fast-start`
