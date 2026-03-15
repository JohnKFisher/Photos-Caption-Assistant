# Photo Description Creator

Current version/build: 2.2 (2)
Current description logic version: 2.5.0

Current overall status:
Version 2.2 build 2 with description logic 2.5.0 is the current known-good release as of March 15, 2026. We are treating this as the forward baseline for future work after earlier rollback history became unreliable.

What is working now:
- Local photo and video analysis through Ollama with the `qwen2.5vl:7b` model.
- Apple Photos metadata reads and writes, including captions, keywords, and app ownership tags.
- Library, album, and picker-based runs with overwrite policy checks.
- Incremental processing, pending-item tracking, and per-item completion previews.
- Batched metadata reads and batched metadata writes in the current source tree.
- Resilient enumerate-page retry behavior for large fast-order runs.
- Safety prompts for checkpoints, long ordered runs, and high Photos memory usage.
- Future builds from this source baseline now embed the current prompt files and use prompt logic 2.5.0.
- Video analysis now selects three ordered key frames from a larger candidate set using time coverage plus lightweight visual-difference scoring.
- The run pipeline now defaults to one in-flight LLM analysis with bounded prepare-ahead overlap so the next asset can be readied without competing model calls.
- Analyzer-ready payloads are now prepared ahead of the LLM handoff when the analyzer supports it, so image encoding and video frame packaging can overlap with the current analysis.
- Completion preview rendering is now deferred off the metadata-write critical path with a small bounded backlog.

What is partially implemented:
- Long-run resilience is improved, but still depends on AppleScript and Photos staying responsive.
- Prompt management exists in source text files and embedded analyzer constants, but there is no dedicated in-app prompt/version switcher.
- Recovery from interrupted or historical rollback states is only partially addressed; repo history before this baseline should not be treated as authoritative.

What is not implemented yet:
- No dedicated prompt comparison or prompt selection UI.
- No formal migration or repair tooling for previously lost git history.
- No fully isolated packaging flow that keeps build artifacts out of version control automatically.

Known limitations and trust warnings:
- The app depends on Apple Photos automation and local Ollama availability.
- Prompt quality and throughput can vary with model readiness and local machine performance.
- Video-analysis throughput may vary modestly with clip format because key-frame selection now evaluates a larger candidate set before sending frames to the model.
- Metadata writes still happen after each analyzed window, so the pipeline is only partially streamed end to end even though preview generation now overlaps later writes.
- The internal metadata ownership logic version in code is currently separate from the app marketing version.
- This repo started a fresh baseline on March 14, 2026; earlier rollback points should be treated cautiously.

Setup/runtime requirements:
- macOS 15 or later.
- Photos.app installed and open before starting a write run.
- Ollama running locally on `http://127.0.0.1:11434`.
- The `qwen2.5vl:7b` model installed locally.
- User approval for Photos library access and Apple Events automation when macOS prompts.

Important operational risks:
- Large runs can still be slow or brittle if Photos becomes unresponsive.
- Local model inference may time out on first run or under heavy load.
- Build artifacts are currently present in the repo history and should not be treated as source-of-truth outputs.

Recommended next priorities:
- Add a cleaner artifact management strategy so builds do not muddy repo state.
- Add more explicit diagnostics around prompt version, model readiness, and fallback behavior.
- Add a small, repeatable smoke-test workflow for known-good verification before future anchors.

Most recent durable known-good anchor:
- `known-good/20260315-v2-2-logic-2-5-0`
