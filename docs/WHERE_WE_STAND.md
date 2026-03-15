# Photo Description Creator

Current version/build: 2.1 (1)

Current overall status:
This is the new forward baseline as of March 14, 2026. We are treating this as the restart point for future work after earlier rollback history became unreliable.

What is working now:
- Local photo and video analysis through Ollama with the `qwen2.5vl:7b` model.
- Apple Photos metadata reads and writes, including captions, keywords, and app ownership tags.
- Library, album, and picker-based runs with overwrite policy checks.
- Incremental processing, pending-item tracking, and per-item completion previews.
- Batched metadata reads and batched metadata writes in the current source tree.
- Resilient enumerate-page retry behavior for large fast-order runs.
- Safety prompts for checkpoints, long ordered runs, and high Photos memory usage.
- Future builds from this source baseline now use the V3 prompt family.

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
- `known-good/20260314-v2-1-baseline`
