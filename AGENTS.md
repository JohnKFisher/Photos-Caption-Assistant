# Photos Caption Assistant — Project Instructions

Follow the global Codex instructions and conditional rules from the active `$CODEX_HOME`.

## Project purpose

Photos Caption Assistant is a personal macOS utility that analyzes photos and videos with a local AI model and writes generated captions and keywords into Apple Photos.

Privacy, metadata safety, and predictable long-running behavior are core product requirements.

## Core invariants

- AI inference is local-first through Ollama. Do not introduce cloud inference, remote media upload, telemetry, analytics, or background sync without an explicit product decision.
- User photos and videos are source data and must never be modified.
- Treat Photos metadata writes as consequential user-data changes. Preserve overwrite gating, run summaries, confirmations, resumability, and recovery behavior.
- Whole-library operations require explicit confirmation before write work begins.
- Preserve app-owned resume state so interrupted long runs can continue safely where possible.
- Malformed model output must never be converted into guessed semantic content. Formatting-only recovery and recovery of a later complete valid JSON object are acceptable; otherwise fail safely.
- Raw malformed model responses may be stored only in app-scoped local diagnostics for troubleshooting.

## Photos integration

Apple Photos automation is currently the production metadata read/write path.

PhotoKit may be used for proven-safe read/scan operations, but do not migrate production metadata writes, overwrite decisions, picker/album resolution, or Photos lifecycle behavior away from the established automation path unless the replacement is demonstrably safer and the architectural change is intentional.

Photos automation can be fragile during long runs. Preserve retry, restart, cancellation, resume, and failure-reporting behavior when changing this area.

## Product and UX direction

- Keep the app a focused personal captioning workbench rather than turning it into a general media-management system.
- Preserve the run-centric hybrid Mac workbench model; do not force a document/sidebar architecture without an intentional product change.
- Keep durable defaults in the Settings scene and completed-item viewing in the dedicated Preview window.
- Keep potentially destructive scope and overwrite behavior visible before a run begins.
- Prefer clear Mac-native controls and progressive disclosure over exposing implementation details.

## External AI/tooling

Ollama is a user-managed local dependency. The app may guide setup and, with confirmation, request required model downloads through Ollama, but it should not silently install external software or execute remote installation scripts.

The currently supported model and other changeable runtime requirements belong in project status/documentation rather than being permanent invariants here.

## Project documentation

Treat `DECISIONS.md` as the record of durable product and architecture decisions and `WHERE_WE_STAND.md` as current implementation/status context.

When an approved decision is intentionally replaced, update or supersede the decision rather than leaving contradictory rules in force.

The existing Info.plist-based version/build decision predates the current global `VERSION` + `BUILD_NUMBER` convention and should be superseded when this repository is retrofitted to that convention.