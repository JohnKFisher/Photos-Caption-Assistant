# Photos Caption Assistant Decision Log

## 2026-04-14 — Keep captioning local-first through Ollama
Status: approved
Rationale: Caption and keyword generation stays on the local Mac through Ollama running on `127.0.0.1`. This preserves the project's privacy-first, personal-use operating model and avoids silent cloud inference.

## 2026-04-14 — Keep Apple Photos automation as the production write path
Status: approved
Rationale: The app may expand guarded PhotoKit reads over time, but production metadata reads, writes, overwrite gating, and Photos lifecycle control remain AppleScript/automation-backed until a safer replacement is proven.

## 2026-04-14 — Keep app identity on `com.jkfisher.PhotosCaptionAssistant`
Status: approved
Rationale: The bundle identifier is a durable app identity and should not be casually renamed again after the existing permission prompts, saved state, and distribution expectations have already moved to this name.

## 2026-04-14 — Use checked-in Info.plist versioning as release source of truth
Status: approved
Rationale: `Sources/PhotosCaptionAssistant/Resources/Info.plist` is the canonical source for marketing version and build number. Local or CI packaging must not auto-bump or derive version/build from generated artifacts.

## 2026-04-14 — Keep distribution ad-hoc signed and non-notarized for now
Status: approved
Rationale: This repo distributes personal-use, ad-hoc-signed macOS builds and does not currently use Developer ID signing or notarization. README and release notes must describe the Gatekeeper implications honestly.

## 2026-04-14 — Publish GitHub releases from version changes on main
Status: approved
Rationale: A checked-in version/build change on `main` is the publish signal. CI should create or update the corresponding GitHub Release using the existing `vX.Y.Z` tag shape and attach a DMG built from committed source.

## 2026-04-15 — Keep the main app as a hybrid workbench, not a sidebar-first redesign
Status: approved
Rationale: The app’s core job is still a run-centric setup and monitoring workflow, so the modernization pass keeps that workbench model while making it feel more Mac-native through better scenes, menus, toolbars, and window behavior instead of forcing a document/sidebar architecture.

## 2026-04-15 — Use a dedicated Preview window and Settings scene for macOS defaults
Status: approved
Rationale: Completed-item preview now lives in its own macOS window, with optional full-screen behavior, and durable app-wide defaults now live in a proper Settings scene. This keeps the main workbench focused on the current run while matching standard Mac window and menu expectations.

## 2026-04-19 — Clamp the main workbench to the visible display and enable non-app overwrite by default
Status: approved
Rationale: The main window should open at a shorter Dock-respecting size on real Macs, and this personal workflow now prefers promptless overwrite of non-app metadata as the startup default while keeping the existing run-start confirmation.

## 2026-04-19 — Keep malformed Qwen diagnostics local and parser fallback formatting-only
Status: approved
Rationale: When Qwen returns malformed JSON, the app may save the raw model reply only to an app-scoped temporary diagnostics file on the local Mac so failures are diagnosable without adding any remote logging. Parser recovery stays limited to common formatting cleanup such as smart quotes and trailing commas rather than guessing missing fields or changing semantic content.

## 2026-04-19 — Prefer later complete JSON objects over broken Qwen prefixes
Status: approved
Rationale: Some malformed Qwen replies start a JSON object, truncate it, and then emit a second valid JSON object afterward. The analyzer may recover that later complete object, including fenced `json` blocks, but it should still reject outputs that never return to valid JSON.

## 2026-04-19 — Use an adaptive compact workbench on constrained windows
Status: approved
Rationale: The main run workbench should stay fully reachable on shorter and narrower Mac windows by switching from the roomy two-pane layout to a single-column compact mode with collapsible summary and progress sections. Run confirmation remains a native alert, but its message should stay intentionally brief because the full detail already lives in the visible Run Summary panel.
