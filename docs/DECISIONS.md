# Photos Caption Assistant Decision Log

## 2026-04-14 — Keep captioning local-first through Ollama
Status: approved
Rationale: Caption and keyword generation stays on the local Mac through Ollama running on `127.0.0.1`. This preserves the project's privacy-first, personal-use operating model and avoids silent cloud inference.

## 2026-04-14 — Keep Apple Photos automation as the production write path
Status: superseded by the 2026-10-28 PhotoKit modernization decision
Rationale: This was the safe architecture before PhotoKit exposed the required extended metadata and mutation APIs. The older macOS compatibility implementation remains active where those APIs are unavailable.

## 2026-10-28 — Prefer PhotoKit for normal Photos workflows on macOS 27+
Status: approved
Rationale: On macOS 27 and later, the app uses PhotoKit for asset enumeration, album and picker resolution, caption/keyword reads, caption and keyword writes, media acquisition, and post-write verification. PhotoKit always addresses the System Photo Library, regardless of which library Photos.app currently displays; the preflight and confirmation must make that target visible. The macOS 15–26 compatibility backend remains AppleScript-based and addresses the library open in Photos.app. PhotoKit writes carry the pre-analysis metadata snapshot, reject stale assets, reconcile keyword additions/removals to the requested target, and verify the result after `performChanges`. Caption and keyword mutations share one PhotoKit change block; Photos does not offer rollback guarantees if a framework change partially applies, so the app reports and re-reads actual state instead of guessing or silently retrying a partial result. Normal PhotoKit runs queue all IDs from the selected scope before the first write, without changing the saved-state format; durable recovery still depends on the existing best-effort save succeeding. Native PhotoKit runs do not require Photos.app to be open or use the AppleScript restart cycle. CI must build with an SDK containing the macOS 27 APIs while the app's minimum deployment target remains macOS 15.

## 2026-04-14 — Keep app identity on `com.jkfisher.PhotosCaptionAssistant`
Status: approved
Rationale: The bundle identifier is a durable app identity and should not be casually renamed again after the existing permission prompts, saved state, and distribution expectations have already moved to this name.

## 2026-04-14 — Use checked-in Info.plist versioning as release source of truth
Status: approved
Rationale: `Sources/PhotosCaptionAssistant/Resources/Info.plist` is the canonical source for marketing version and build number. Local or CI packaging must not auto-bump or derive version/build from generated artifacts.

## 2026-04-14 — Keep distribution ad-hoc signed and non-notarized for now
Status: superseded by the 2026-07-04 Developer ID release workflow decision
Rationale: This repo previously distributed personal-use, ad-hoc-signed macOS builds and did not use Developer ID signing or notarization. README and release notes had to describe the Gatekeeper implications honestly.

## 2026-04-14 — Publish GitHub releases from version changes on main
Status: approved
Rationale: A checked-in version/build change on `main` is the publish signal. CI should create or update the corresponding GitHub Release using the existing `vX.Y.Z` tag shape and attach a DMG built from committed source.

## 2026-07-04 — Use Developer ID signing and notarization for GitHub release DMGs
Status: approved
Rationale: Version-triggered GitHub releases now import a Developer ID certificate from repository secrets, sign the app with hardened runtime and timestamping, sign the DMG, notarize and staple the DMG, and run Gatekeeper assessment before upload. Local builds may still fall back to ad-hoc signing unless a Developer ID signing identity is provided.

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
